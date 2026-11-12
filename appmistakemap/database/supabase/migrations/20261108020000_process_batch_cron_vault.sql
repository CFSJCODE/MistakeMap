-- Move o segredo do cron do process-batch para o Vault.
--
-- Antes: o job 'process-batch-every-minute' trazia o x-cron-secret em texto
-- dentro de cron.job.command (legível por quem consulta cron.job e nos logs).
-- Depois: o job chama public.invoke_process_batch(), que lê URL e segredo do
-- Vault a cada execução. Nenhum valor sensível fica nesta migration.
--
-- Transição sem parada: se o Vault ainda não tem 'process_batch_cron_secret',
-- o valor atual é copiado do comando do job antigo para o Vault. Se não houver
-- segredo em nenhum dos dois lugares, o job antigo fica como está e a migration
-- só avisa (NOTICE), para o lote de análises não parar.
--
-- Rotação depois do deploy (mesmo valor nos dois lugares):
--   supabase secrets set WORKER_CRON_SECRET=<novo>
--   select vault.update_secret(
--     (select id from vault.secrets where name = 'process_batch_cron_secret'), '<novo>');

create or replace function public.invoke_process_batch()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
begin
  select s.decrypted_secret into v_url
    from vault.decrypted_secrets s where s.name = 'mistakemap_project_url';
  select s.decrypted_secret into v_secret
    from vault.decrypted_secrets s where s.name = 'process_batch_cron_secret';
  if coalesce(v_url, '') = '' or coalesce(length(v_secret), 0) < 24 then
    return null;
  end if;

  return net.http_post(
    url := rtrim(v_url, '/') || '/functions/v1/process-batch',
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', v_secret),
    timeout_milliseconds := 10000
  );
end;
$$;

revoke all on function public.invoke_process_batch() from public, anon, authenticated;
grant execute on function public.invoke_process_batch() to service_role;

comment on function public.invoke_process_batch() is
  'Chamado pelo pg_cron. Lê URL e segredo do Vault; não faz nada sem os dois.';

do $$
declare
  v_command text;
  v_legacy text;
  v_has_secret boolean;
  v_has_url boolean;
begin
  select exists(select 1 from vault.secrets where name = 'process_batch_cron_secret')
    into v_has_secret;
  select exists(select 1 from vault.secrets where name = 'mistakemap_project_url')
    into v_has_url;

  if not v_has_secret then
    select command into v_command from cron.job
      where jobname = 'process-batch-every-minute';
    v_legacy := substring(v_command from '''x-cron-secret''\s*,\s*''([^'']+)''');
    if coalesce(length(v_legacy), 0) >= 24 then
      perform vault.create_secret(v_legacy, 'process_batch_cron_secret',
        'x-cron-secret do process-batch (copiado do job antigo do pg_cron)');
      v_has_secret := true;
    end if;
  end if;

  if not (v_has_secret and v_has_url) then
    raise notice 'process-batch: Vault sem process_batch_cron_secret ou mistakemap_project_url; job antigo mantido.';
    return;
  end if;

  if exists (select 1 from cron.job where jobname = 'process-batch-every-minute') then
    perform cron.unschedule('process-batch-every-minute');
  end if;
  perform cron.schedule(
    'process-batch-every-minute',
    '* * * * *',
    'select public.invoke_process_batch();'
  );
end;
$$;
