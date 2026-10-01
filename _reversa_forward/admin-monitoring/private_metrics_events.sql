-- Private invalidation signal for the authorized administrative monitor.
-- No student record, identifier, prompt or answer is sent over Realtime.
create policy admin_metrics_receive on realtime.messages for select to authenticated
  using(realtime.topic()='admin-metrics' and public.is_admin());
create policy admin_metrics_guard on realtime.messages as restrictive for select to public
  using((topic<>'admin-metrics' and coalesce(realtime.topic(),'')<>'admin-metrics') or public.is_admin());

create or replace function public.notify_admin_metrics()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform realtime.send('{"refresh":true}'::jsonb,'metrics_changed','admin-metrics',true);
  return null;
exception when others then
  -- Monitoring must never block a student's save or analysis transaction.
  raise warning 'Administrative metrics notification unavailable';
  return null;
end;
$$;
revoke all on function public.notify_admin_metrics() from public,anon,authenticated;
do $$ declare t text; begin
  foreach t in array array['profiles','exercises','attempts','processing_runs','practice_sets','ai_daily_usage','r2_quota_usage','ai_api_events'] loop
    execute format('create trigger admin_metrics_changed after insert or update or delete on public.%I for each statement execute function public.notify_admin_metrics()',t);
  end loop;
end $$;
