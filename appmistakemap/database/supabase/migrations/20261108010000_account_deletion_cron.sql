-- Agenda o worker account-data (exclusão de conta) com pg_cron + pg_net.
--
-- Segredo e URL ficam no Vault e são lidos a cada execução; nada sensível
-- entra nesta migration, em cron.job ou em logs. Sem os dois segredos a função
-- não faz nada, então aplicar a migration antes de configurar o Vault é seguro.
--
-- Segredos esperados no Vault (criar no SQL Editor, nunca versionar):
--   select vault.create_secret('<URL do projeto, ex. https://<ref>.supabase.co>', 'mistakemap_project_url');
--   select vault.create_secret('<mesmo valor de ACCOUNT_DELETION_CRON_SECRET>', 'account_deletion_cron_secret');
--
-- A chamada só acontece quando há trabalho: pedido pendente, job não concluído
-- ou job concluído há mais de 30 dias para expurgar. Assim o cron de minuto em
-- minuto não gera 43 mil invocações vazias por mês.

create or replace function public.invoke_account_deletion_worker()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
begin
  if not exists (
       select 1 from public.platform_privacy_requests r
       where r.kind = 'account_deletion' and r.status = 'pending')
     and not exists (
       select 1 from public.account_deletion_jobs j
       where j.status <> 'completed'
          or j.completed_at < now() - interval '30 days') then
    return null;
  end if;

  select s.decrypted_secret into v_url
    from vault.decrypted_secrets s where s.name = 'mistakemap_project_url';
  select s.decrypted_secret into v_secret
    from vault.decrypted_secrets s where s.name = 'account_deletion_cron_secret';
  if coalesce(v_url, '') = '' or coalesce(length(v_secret), 0) < 24 then
    return null;
  end if;

  -- Assíncrono: pg_net enfileira o POST e a resposta fica em net._http_response.
  return net.http_post(
    url := rtrim(v_url, '/') || '/functions/v1/account-data',
    body := jsonb_build_object('action', 'process_deletion'),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-account-deletion-secret', v_secret),
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.invoke_account_deletion_worker() from public, anon, authenticated;
grant execute on function public.invoke_account_deletion_worker() to service_role;

comment on function public.invoke_account_deletion_worker() is
  'Chamado pelo pg_cron. Lê URL e segredo do Vault; não faz nada sem trabalho pendente ou sem segredos.';

do $$
begin
  if exists (select 1 from cron.job where jobname = 'account-deletion-worker') then
    perform cron.unschedule('account-deletion-worker');
  end if;
end;
$$;

select cron.schedule(
  'account-deletion-worker',
  '* * * * *',
  'select public.invoke_account_deletion_worker();'
);
