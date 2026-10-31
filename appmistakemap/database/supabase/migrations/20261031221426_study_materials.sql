-- Material de estudo gerado pela IA (resumo, cartões e quiz) a partir dos
-- exercícios e erros de uma matéria. Escrito só pela Edge Function
-- study-material (service_role); o aluno lê as próprias linhas.
create table public.study_materials (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  summary jsonb not null check (jsonb_typeof(summary) = 'object'),
  flashcards jsonb not null check (jsonb_typeof(flashcards) = 'array'),
  -- Questões sem gabarito: id, enunciado, alternativas e conceito.
  quiz jsonb not null check (jsonb_typeof(quiz) = 'array'),
  source_count integer not null default 0 check (source_count >= 0),
  model text not null,
  created_at timestamptz not null default now()
);

create index study_materials_owner_idx
  on public.study_materials(user_id, subject_id, created_at desc);

alter table public.study_materials enable row level security;

create policy study_materials_owner_read on public.study_materials
  for select to authenticated using (user_id = (select auth.uid()));

revoke all on public.study_materials from anon, authenticated;
grant select on public.study_materials to authenticated;
grant all on public.study_materials to service_role;

-- Gabarito do quiz: nunca exposto ao cliente; volta só na correção.
create table public.study_quiz_keys (
  material_id uuid primary key references public.study_materials(id) on delete cascade,
  answers jsonb not null check (jsonb_typeof(answers) = 'array')
);

alter table public.study_quiz_keys enable row level security;
revoke all on public.study_quiz_keys from public, anon, authenticated;
grant all on public.study_quiz_keys to service_role;

-- Cada rodada corrigida do quiz, para métricas de desempenho do aluno.
create table public.study_quiz_rounds (
  id uuid primary key default gen_random_uuid(),
  material_id uuid not null references public.study_materials(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  answers jsonb not null check (jsonb_typeof(answers) = 'array'),
  correct_count integer not null check (correct_count >= 0),
  total integer not null check (total > 0 and correct_count <= total),
  created_at timestamptz not null default now()
);

create index study_quiz_rounds_owner_idx
  on public.study_quiz_rounds(user_id, created_at desc);

alter table public.study_quiz_rounds enable row level security;

create policy study_quiz_rounds_owner_read on public.study_quiz_rounds
  for select to authenticated using (user_id = (select auth.uid()));

revoke all on public.study_quiz_rounds from anon, authenticated;
grant select on public.study_quiz_rounds to authenticated;
grant all on public.study_quiz_rounds to service_role;
