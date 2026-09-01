create table if not exists public.storage_alert_state (
  id boolean primary key default true,
  alert_sent_at timestamptz,
  constraint storage_alert_state_singleton check (id)
);

insert into public.storage_alert_state (id) values (true)
on conflict (id) do nothing;

alter table public.storage_alert_state enable row level security;