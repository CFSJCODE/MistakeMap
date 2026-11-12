-- Plataforma: sessões persistentes com gabarito privado, planejamento,
-- colaboração por consentimento e solicitações de privacidade.
-- Nenhum plano pago é ativado e nenhuma cobrança é efetuada nesta migration.

create table public.platform_entitlements (
  user_id uuid primary key references auth.users(id) on delete cascade,
  plan text not null default 'free' check (plan in ('free','pilot','pro')),
  sessions_per_day integer not null default 10 check (sessions_per_day between 1 and 100),
  expires_at timestamptz,
  updated_at timestamptz not null default now()
);

create table public.platform_teachers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz not null default now()
);

create table public.platform_goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 160),
  exam_date date,
  minutes_per_day integer not null check (minutes_per_day between 5 and 180),
  subjects text[] not null default '{}',
  weekly_plan jsonb not null default '[]' check (jsonb_typeof(weekly_plan) = 'array'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.platform_classes (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 160),
  created_at timestamptz not null default now()
);

-- O código de ingresso não fica na tabela legível pelos membros da turma.
create table public.platform_class_invites (
  class_id uuid primary key references public.platform_classes(id) on delete cascade,
  code text not null unique default replace(gen_random_uuid()::text,'-',''),
  created_at timestamptz not null default now()
);

create table public.platform_memberships (
  class_id uuid not null references public.platform_classes(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  share_progress boolean not null default false,
  share_answers boolean not null default false,
  share_notes boolean not null default false,
  joined_at timestamptz not null default now(),
  consent_updated_at timestamptz not null default now(),
  primary key(class_id,user_id)
);

create table public.platform_assignments (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.platform_classes(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 160),
  due_at timestamptz,
  catalog_ids uuid[] not null check (cardinality(catalog_ids) between 1 and 10),
  created_at timestamptz not null default now()
);

create table public.platform_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  request_payload jsonb not null,
  goal_id uuid references public.platform_goals(id) on delete set null,
  assignment_id uuid references public.platform_assignments(id) on delete set null,
  mode text not null check (mode in ('practice','exam')),
  title text not null,
  status text not null default 'active' check (status in ('active','completed')),
  total integer not null check (total between 1 and 10),
  correct_count integer check (correct_count between 0 and total),
  assisted boolean not null default false,
  results jsonb,
  created_at timestamptz not null default now(),
  finished_at timestamptz,
  unique(user_id,request_id),
  check ((status = 'active' and results is null and finished_at is null)
    or (status = 'completed' and results is not null and finished_at is not null))
);
create index platform_sessions_owner_created on public.platform_sessions(user_id,created_at desc);

create table public.platform_session_items (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.platform_sessions(id) on delete cascade,
  catalog_exercise_id uuid references public.catalog_exercises(id) on delete set null,
  position integer not null,
  prompt text not null,
  subject text not null,
  theme text not null,
  difficulty text not null,
  answer text not null default '' check (char_length(answer) <= 2000),
  hint_level integer not null default 0 check (hint_level between 0 and 3),
  updated_at timestamptz not null default now(),
  unique(session_id,position)
);

-- Snapshot: alterações futuras no catálogo não mudam a correção de uma sessão.
create table public.platform_session_keys (
  item_id uuid primary key references public.platform_session_items(id) on delete cascade,
  correct_answer text not null,
  explanation text not null
);

create table public.platform_materials (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 160),
  url text not null check (char_length(url) <= 2000 and url like 'https://%'),
  notes text not null default '' check (char_length(notes) <= 3000),
  page_number integer check (page_number between 1 and 100000),
  rights_confirmed_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table public.platform_connected_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 160),
  body text not null check (char_length(body) between 1 and 5000),
  concept text not null default '' check (char_length(concept) <= 160),
  attempt_id uuid references public.attempts(id) on delete set null,
  catalog_exercise_id uuid references public.catalog_exercises(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.platform_privacy_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind = 'account_deletion'),
  status text not null default 'pending' check (status in ('pending','processing','completed','cancelled')),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  -- Conclusão exige operador/integração verificar dados, arquivos R2 e Auth.
  check ((status = 'completed') = (completed_at is not null))
);
create unique index platform_privacy_pending on public.platform_privacy_requests(user_id,kind)
  where status in ('pending','processing');

create or replace function public.platform_owns_class(p_class uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.platform_classes c
    where c.id = p_class and c.teacher_id = (select auth.uid()));
$$;
create or replace function public.platform_reads_class(p_class uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.platform_owns_class(p_class) or exists(
    select 1 from public.platform_memberships m
    where m.class_id = p_class and m.user_id = (select auth.uid()));
$$;
revoke all on function public.platform_owns_class(uuid),public.platform_reads_class(uuid) from public,anon;
grant execute on function public.platform_owns_class(uuid),public.platform_reads_class(uuid) to authenticated;

-- Toda mutação passa por study-platform, que autentica, valida ownership e
-- executa transações. O cliente não pode alterar plano, professor ou resultado.
do $rls$
declare t text;
begin
  foreach t in array array['platform_entitlements','platform_teachers','platform_goals',
    'platform_classes','platform_class_invites','platform_memberships','platform_assignments',
    'platform_sessions','platform_session_items','platform_session_keys','platform_materials',
    'platform_connected_notes','platform_privacy_requests'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public,anon,authenticated', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
  foreach t in array array['platform_entitlements','platform_teachers','platform_goals',
    'platform_sessions','platform_materials','platform_connected_notes','platform_privacy_requests'] loop
    execute format('create policy %I on public.%I for select to authenticated using (user_id=(select auth.uid()))',t || '_owner_read',t);
    execute format('grant select on public.%I to authenticated',t);
  end loop;
end;
$rls$;

create policy platform_class_read on public.platform_classes for select to authenticated
  using (public.platform_reads_class(id));
create policy platform_membership_read on public.platform_memberships for select to authenticated
  using (user_id=(select auth.uid()) or public.platform_owns_class(class_id));
create policy platform_assignment_read on public.platform_assignments for select to authenticated
  using (public.platform_reads_class(class_id));
create policy platform_item_read on public.platform_session_items for select to authenticated
  using (exists(select 1 from public.platform_sessions s where s.id=session_id and s.user_id=(select auth.uid())));
grant select on public.platform_classes,public.platform_memberships,public.platform_assignments,
  public.platform_session_items to authenticated;

-- Intencionalmente sem SELECT/policy para invites e keys, nem políticas que
-- deem ao professor acesso direto a respostas/notas dos alunos. Relatórios
-- consultam os consentimentos atuais a cada chamada e somem após revogação.
