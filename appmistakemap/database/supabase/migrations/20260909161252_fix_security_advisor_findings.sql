-- Corrige achados do Security Advisor do Supabase:
--
-- 1. "Function Search Path Mutable" em storage_usage_bytes() e
--    enforce_storage_cap() — nenhuma delas fixava search_path, diferente
--    das demais funções já corrigidas desde o início.
-- 2. "Public/Signed-In Users Can Execute SECURITY DEFINER Function" — toda
--    função criada nesta base ficou com o GRANT EXECUTE padrão do Postgres
--    para PUBLIC (o que inclui anon e authenticated). Funções de uso
--    puramente interno (chamadas só por triggers ou pelo pg_cron) não devem
--    ser invocáveis via RPC por nenhum usuário. check_rate_limit() é a
--    única exceção: continua liberada para "authenticated", que é o uso
--    pretendido (chamada futura pelo backend/worker).
--
-- Os 3 achados "RLS Enabled No Policy" (r2_alert_state, rate_limits,
-- storage_alert_state) são intencionais — essas tabelas só devem ser
-- acessadas pelas funções security definer, nunca diretamente — por isso
-- não têm nenhuma policy. Não é um bug.
--
-- "Leaked Password Protection Disabled" exige o plano pago do Supabase
-- (confirmado via API: HIBP password check é recurso Pro+); não é
-- corrigível no plano gratuito atual.

create or replace function public.storage_usage_bytes()
returns bigint
language sql
stable
set search_path = public
as $$
  select coalesce(sum((metadata->>'size')::bigint), 0)
  from storage.objects;
$$;

create or replace function public.enforce_storage_cap()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_cap bigint := 980 * 1024 * 1024;
begin
  if public.storage_usage_bytes() + coalesce((new.metadata->>'size')::bigint, 0) > v_cap then
    raise exception 'storage cap exceeded: limite de 980 MB atingido'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke execute on function public.storage_usage_bytes() from public, anon, authenticated;
revoke execute on function public.enforce_storage_cap() from public, anon, authenticated;
revoke execute on function public.enforce_rate_limit() from public, anon, authenticated;
revoke execute on function public.check_storage_and_alert() from public, anon, authenticated;
revoke execute on function public.request_r2_storage_usage(text) from public, anon, authenticated;
revoke execute on function public.process_r2_storage_usage(text) from public, anon, authenticated;

revoke execute on function public.check_rate_limit(text, integer, integer) from public, anon;
-- mantém: grant execute on function public.check_rate_limit(text, integer, integer) to authenticated;
