-- Pending approval: technical telemetry only, no prompts, responses or identities.
create table public.ai_api_events (
  id uuid primary key default gen_random_uuid(),
  requested_model text not null,
  model text not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  elapsed_ms integer,
  status_code integer,
  input_tokens integer,
  output_tokens integer,
  total_tokens integer,
  error_code text,
  check(elapsed_ms is null or elapsed_ms >= 0),
  check(input_tokens is null or input_tokens >= 0),
  check(output_tokens is null or output_tokens >= 0),
  check(total_tokens is null or total_tokens >= 0)
);
create index ai_api_events_time_idx on public.ai_api_events(started_at desc);
alter table public.ai_api_events enable row level security;
revoke all on public.ai_api_events from public,anon,authenticated;
grant all on public.ai_api_events to service_role;

create or replace function public.admin_ai_api_metrics()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrative access required' using errcode='42501';
  end if;
  select jsonb_build_object(
    'captured_at',now(),
    'observed_since',(select min(started_at) from public.ai_api_events),
    'last_http_success',(select max(finished_at) from public.ai_api_events where status_code between 200 and 299),
    'last_failure',(select max(finished_at) from public.ai_api_events where status_code=0 or status_code>=400),
    'models',(select coalesce(jsonb_agg(row_to_json(m)),'[]'::jsonb) from (
      select model,
        count(*) filter(where started_at>=now()-interval '1 minute') as rpm,
        sum(input_tokens) filter(where started_at>=now()-interval '1 minute') as tpm,
        count(*) filter(where started_at >= date_trunc('day',now() at time zone 'America/Los_Angeles') at time zone 'America/Los_Angeles') as rpd,
        count(*) filter(where started_at>=now()-interval '24 hours' and (status_code=0 or status_code>=400)) as failures_24h,
        count(*) filter(where started_at>=now()-interval '24 hours' and status_code=429) as throttled_24h,
        percentile_cont(0.5) within group(order by elapsed_ms) filter(where started_at>=now()-interval '24 hours') as median_ms,
        count(*) filter(where started_at>=now()-interval '1 minute' and input_tokens is null) as unknown_tokens
      from public.ai_api_events group by model
    ) m)
  ) into result;
  return result;
end;
$$;
revoke all on function public.admin_ai_api_metrics() from public,anon;
grant execute on function public.admin_ai_api_metrics() to authenticated;
