-- Núcleo de estudo: sugestões só entram na agenda após decisão explícita.
-- Agenda mm-intervals-v1: intervalos determinísticos, não FSRS nem medida de domínio.
create table public.study_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  stage text not null check (stage in ('fundamental','medio','superior','autodidata')),
  daily_minutes smallint not null default 15 check (daily_minutes between 5 and 180),
  timezone text not null default 'America/Sao_Paulo' check (length(timezone) between 1 and 80),
  subject_ids uuid[] not null default '{}',
  goal text not null default '' check (length(goal) <= 240),
  exam_date date,
  reminders_enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  check (cardinality(subject_ids) <= 30)
);

create table public.review_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  concept_id uuid not null references public.concepts(id) on delete cascade,
  error_event_id uuid not null references public.error_events(id) on delete cascade,
  category text not null references public.error_types(name),
  active boolean not null default true,
  due_at timestamptz not null default now(),
  interval_days integer not null default 0 check (interval_days between 0 and 180),
  repetitions integer not null default 0 check (repetitions >= 0),
  lapses integer not null default 0 check (lapses >= 0),
  last_reviewed_at timestamptz,
  policy_version text not null default 'mm-intervals-v1',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, concept_id, category),
  unique (id, user_id)
);
create index review_items_due on public.review_items(user_id, due_at) where active;

create table public.study_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'active' check (status in ('active','completed')),
  planned_minutes smallint not null check (planned_minutes between 5 and 180),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (id, user_id)
);
create unique index study_one_active_session on public.study_sessions(user_id) where status='active';

-- Sem gabaritos na sessão. O enunciado é o da tentativa já pertencente ao aluno.
create table public.study_session_items (
  session_id uuid not null,
  item_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  position smallint not null check (position between 0 and 29),
  source_attempt_id uuid not null references public.attempts(id) on delete cascade,
  source_error_event_id uuid not null references public.error_events(id) on delete cascade,
  prompt_text text not null,
  evidence text not null,
  category text not null references public.error_types(name),
  primary key (session_id,item_id),
  unique (session_id,position),
  foreign key (session_id,user_id) references public.study_sessions(id,user_id) on delete cascade,
  foreign key (item_id,user_id) references public.review_items(id,user_id) on delete cascade
);

create table public.review_events (
  user_id uuid not null references auth.users(id) on delete cascade,
  event_id uuid not null,
  session_id uuid not null,
  item_id uuid not null,
  rating text not null check (rating in ('again','hard','good','easy')),
  evidence text not null default 'self_report' check (evidence='self_report'),
  answered_at timestamptz not null,
  received_at timestamptz not null default now(),
  elapsed_seconds integer not null check (elapsed_seconds between 0 and 1800),
  payload_hash text not null check (length(payload_hash)=64),
  next_due_at timestamptz not null,
  policy_version text not null default 'mm-intervals-v1',
  primary key (user_id,event_id),
  unique (session_id,item_id),
  foreign key (session_id,item_id) references public.study_session_items(session_id,item_id) on delete cascade,
  foreign key (item_id,user_id) references public.review_items(id,user_id) on delete cascade
);
create index review_events_user_date on public.review_events(user_id,answered_at desc);

create table public.error_event_decisions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  error_event_id uuid not null references public.error_events(id) on delete cascade,
  decision text not null check (decision in ('confirmed','rejected')),
  category text not null references public.error_types(name),
  importance numeric not null check (importance between 0.5 and 2),
  created_at timestamptz not null default now()
);
create index error_event_decisions_owner on public.error_event_decisions(user_id,error_event_id,created_at desc);

-- Escritas somente pelas Edge Functions, que verificam propriedade em cada operação.
-- Cliente pode consultar seu estado, sem poder fabricar eventos/agenda por REST.
alter table public.study_profiles enable row level security;
alter table public.review_items enable row level security;
alter table public.study_sessions enable row level security;
alter table public.study_session_items enable row level security;
alter table public.review_events enable row level security;
alter table public.error_event_decisions enable row level security;
create policy study_profiles_read on public.study_profiles for select to authenticated using(user_id=auth.uid());
create policy review_items_read on public.review_items for select to authenticated using(user_id=auth.uid());
create policy study_sessions_read on public.study_sessions for select to authenticated using(user_id=auth.uid());
create policy study_session_items_read on public.study_session_items for select to authenticated using(user_id=auth.uid());
create policy review_events_read on public.review_events for select to authenticated using(user_id=auth.uid());
create policy error_event_decisions_read on public.error_event_decisions for select to authenticated using(user_id=auth.uid());
revoke all on public.study_profiles, public.review_items, public.study_sessions, public.study_session_items,
  public.review_events, public.error_event_decisions from public, anon, authenticated;
grant select on public.study_profiles, public.review_items, public.study_sessions, public.study_session_items,
  public.review_events, public.error_event_decisions to authenticated;
grant all on public.study_profiles, public.review_items, public.study_sessions, public.study_session_items,
  public.review_events, public.error_event_decisions to service_role;

comment on table public.review_events is 'Autoavaliações explícitas. Não representam correção automática ou domínio comprovado.';
comment on column public.concepts.importance is 'Peso curricular definido pelo aluno/professor; padrão neutro 1. Não inferir por centralidade de grafo.';
