-- Applied to MistakeMap Supabase with explicit user authorization on 2026-09-30.
-- Aggregates only: no prompts, answers, identities, secrets or answer keys.
create or replace function public.admin_metrics_snapshot()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb; today date := (now() at time zone 'UTC')::date;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrative access required' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'captured_at', now(), 'scope', 'global',
    'profiles', (select count(*) from public.profiles),
    'exercises', (select count(*) from public.exercises),
    'attempts', (select count(*) from public.attempts),
    'processing', (select count(*) from public.processing_runs where status='processing' and lease_until > now()),
    'analysis_requests_today', (select coalesce(sum(requests),0) from public.ai_daily_usage where usage_day=today and kind='analysis'),
    'practice_requests_today', (select coalesce(sum(requests),0) from public.ai_daily_usage where usage_day=today and kind='practice'),
    'analyses_today', (select count(*) from public.attempt_analyses where created_at >= today::timestamp at time zone 'UTC'),
    'last_analysis_at', (select max(created_at) from public.attempt_analyses),
    'last_model', (select model from public.attempt_analyses order by created_at desc limit 1),
    'failures_24h', (select count(*) from public.processing_runs where updated_at >= now()-interval '24 hours' and status in ('retryable_failed','dead_letter')),
    'rate_limited_24h', (select count(*) from public.processing_runs where updated_at >= now()-interval '24 hours' and error_code='ai_rate_limited'),
    'r2_class_a', (select class_a_ops from public.r2_quota_usage where period=to_char(now() at time zone 'UTC','YYYY-MM')),
    'r2_class_b', (select class_b_ops from public.r2_quota_usage where period=to_char(now() at time zone 'UTC','YYYY-MM')),
    'r2_storage_estimate', (select sum(storage_bytes_estimate) from public.r2_quota_usage),
    'storage_bytes', public.storage_usage_bytes()
  ) into result;
  return result;
end;
$$;
revoke all on function public.admin_metrics_snapshot() from public, anon;
grant execute on function public.admin_metrics_snapshot() to authenticated;
