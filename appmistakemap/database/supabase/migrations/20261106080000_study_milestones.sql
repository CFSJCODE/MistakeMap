-- Pausa explícita da sequência; não registra atividade pedagógica e não gera conquista.
create table public.study_streak_freezes (
  user_id uuid not null references auth.users(id) on delete cascade,
  frozen_date date not null,
  week_start date not null,
  timezone text not null check(length(timezone) between 1 and 80),
  created_at timestamptz not null default now(),
  primary key(user_id,frozen_date),
  unique(user_id,week_start),
  check(extract(isodow from week_start)=1 and frozen_date between week_start and week_start+6)
);
alter table public.study_streak_freezes enable row level security;
create policy study_streak_freezes_read on public.study_streak_freezes for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.study_streak_freezes from public,anon,authenticated;
grant select on public.study_streak_freezes to authenticated;
grant all on public.study_streak_freezes to service_role;

create index study_sessions_owner_completed on public.study_sessions(user_id,completed_at desc) where status='completed';
create index platform_sessions_owner_finished on public.platform_sessions(user_id,finished_at desc) where status='completed';
create index platform_session_items_catalog_history on public.platform_session_items(catalog_exercise_id,session_id) where catalog_exercise_id is not null;
