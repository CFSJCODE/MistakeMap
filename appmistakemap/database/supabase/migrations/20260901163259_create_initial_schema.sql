-- MistakeMap: modelo de dados inicial (event-oriented)
-- subjects -> concepts -> concept_edges
-- exercises -> exercise_concepts -> attempts -> corrections
-- error_types -> error_events -> mastery_events

create extension if not exists "pgcrypto" with schema extensions;

-- ---------------------------------------------------------------------------
-- subjects
-- ---------------------------------------------------------------------------
create table if not exists public.subjects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  description text,
  created_at timestamptz not null default now()
);

create index if not exists subjects_user_id_idx on public.subjects (user_id);

-- ---------------------------------------------------------------------------
-- concepts
-- ---------------------------------------------------------------------------
create table if not exists public.concepts (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects (id) on delete cascade,
  name text not null,
  description text,
  importance numeric not null default 1,
  created_at timestamptz not null default now()
);

create index if not exists concepts_subject_id_idx on public.concepts (subject_id);

-- ---------------------------------------------------------------------------
-- concept_edges (grafo de pré-requisitos/relacionamentos)
-- ---------------------------------------------------------------------------
create table if not exists public.concept_edges (
  id uuid primary key default gen_random_uuid(),
  from_concept_id uuid not null references public.concepts (id) on delete cascade,
  to_concept_id uuid not null references public.concepts (id) on delete cascade,
  relation text not null,
  created_at timestamptz not null default now(),
  constraint concept_edges_no_self_loop check (from_concept_id <> to_concept_id),
  constraint concept_edges_unique unique (from_concept_id, to_concept_id, relation)
);

create index if not exists concept_edges_from_idx on public.concept_edges (from_concept_id);
create index if not exists concept_edges_to_idx on public.concept_edges (to_concept_id);

-- ---------------------------------------------------------------------------
-- exercises
-- ---------------------------------------------------------------------------
create table if not exists public.exercises (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects (id) on delete cascade,
  source text,
  prompt_text text not null,
  difficulty text,
  created_at timestamptz not null default now()
);

create index if not exists exercises_subject_id_idx on public.exercises (subject_id);

-- ---------------------------------------------------------------------------
-- exercise_concepts (N:N)
-- ---------------------------------------------------------------------------
create table if not exists public.exercise_concepts (
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  concept_id uuid not null references public.concepts (id) on delete cascade,
  weight numeric not null default 1,
  primary key (exercise_id, concept_id)
);

create index if not exists exercise_concepts_concept_id_idx on public.exercise_concepts (concept_id);

-- ---------------------------------------------------------------------------
-- attempts
-- ---------------------------------------------------------------------------
create table if not exists public.attempts (
  id uuid primary key default gen_random_uuid(),
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  solution_text text,
  answer text,
  attempted_at timestamptz not null default now()
);

create index if not exists attempts_exercise_id_idx on public.attempts (exercise_id);
create index if not exists attempts_user_id_idx on public.attempts (user_id);

-- ---------------------------------------------------------------------------
-- corrections
-- ---------------------------------------------------------------------------
create table if not exists public.corrections (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.attempts (id) on delete cascade,
  reference_text text,
  attachment_id uuid,
  reviewed_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists corrections_attempt_id_idx on public.corrections (attempt_id);

-- ---------------------------------------------------------------------------
-- error_types (taxonomia global)
-- ---------------------------------------------------------------------------
create table if not exists public.error_types (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  category text,
  description text
);

-- ---------------------------------------------------------------------------
-- error_events
-- ---------------------------------------------------------------------------
create table if not exists public.error_events (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.attempts (id) on delete cascade,
  error_type_id uuid references public.error_types (id) on delete set null,
  concept_id uuid references public.concepts (id) on delete set null,
  evidence_ref text,
  confidence numeric,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  constraint error_events_status_check
    check (status in ('pending', 'confirmed', 'rejected', 'superseded'))
);

create index if not exists error_events_attempt_id_idx on public.error_events (attempt_id);
create index if not exists error_events_concept_id_idx on public.error_events (concept_id);
create index if not exists error_events_status_idx on public.error_events (status);

-- ---------------------------------------------------------------------------
-- mastery_events (evidência de recuperação)
-- ---------------------------------------------------------------------------
create table if not exists public.mastery_events (
  id uuid primary key default gen_random_uuid(),
  concept_id uuid not null references public.concepts (id) on delete cascade,
  attempt_id uuid not null references public.attempts (id) on delete cascade,
  outcome text not null,
  created_at timestamptz not null default now()
);

create index if not exists mastery_events_concept_id_idx on public.mastery_events (concept_id);
create index if not exists mastery_events_attempt_id_idx on public.mastery_events (attempt_id);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- Propriedade dos dados sempre remonta a subjects.user_id ou attempts.user_id.
-- ---------------------------------------------------------------------------
alter table public.subjects enable row level security;
alter table public.concepts enable row level security;
alter table public.concept_edges enable row level security;
alter table public.exercises enable row level security;
alter table public.exercise_concepts enable row level security;
alter table public.attempts enable row level security;
alter table public.corrections enable row level security;
alter table public.error_events enable row level security;
alter table public.mastery_events enable row level security;
alter table public.error_types enable row level security;

-- subjects: dono direto
create policy "subjects_owner_all" on public.subjects
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- concepts: dono via subjects
create policy "concepts_owner_all" on public.concepts
  for all
  using (
    exists (
      select 1 from public.subjects s
      where s.id = concepts.subject_id and s.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.subjects s
      where s.id = concepts.subject_id and s.user_id = auth.uid()
    )
  );

-- concept_edges: dono via concepts -> subjects
create policy "concept_edges_owner_all" on public.concept_edges
  for all
  using (
    exists (
      select 1 from public.concepts c
      join public.subjects s on s.id = c.subject_id
      where c.id = concept_edges.from_concept_id and s.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.concepts c
      join public.subjects s on s.id = c.subject_id
      where c.id = concept_edges.from_concept_id and s.user_id = auth.uid()
    )
  );

-- exercises: dono via subjects
create policy "exercises_owner_all" on public.exercises
  for all
  using (
    exists (
      select 1 from public.subjects s
      where s.id = exercises.subject_id and s.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.subjects s
      where s.id = exercises.subject_id and s.user_id = auth.uid()
    )
  );

-- exercise_concepts: dono via exercises -> subjects
create policy "exercise_concepts_owner_all" on public.exercise_concepts
  for all
  using (
    exists (
      select 1 from public.exercises e
      join public.subjects s on s.id = e.subject_id
      where e.id = exercise_concepts.exercise_id and s.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.exercises e
      join public.subjects s on s.id = e.subject_id
      where e.id = exercise_concepts.exercise_id and s.user_id = auth.uid()
    )
  );

-- attempts: dono direto
create policy "attempts_owner_all" on public.attempts
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- corrections: dono via attempts
create policy "corrections_owner_all" on public.corrections
  for all
  using (
    exists (
      select 1 from public.attempts a
      where a.id = corrections.attempt_id and a.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.attempts a
      where a.id = corrections.attempt_id and a.user_id = auth.uid()
    )
  );

-- error_events: dono via attempts
create policy "error_events_owner_all" on public.error_events
  for all
  using (
    exists (
      select 1 from public.attempts a
      where a.id = error_events.attempt_id and a.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.attempts a
      where a.id = error_events.attempt_id and a.user_id = auth.uid()
    )
  );

-- mastery_events: dono via attempts
create policy "mastery_events_owner_all" on public.mastery_events
  for all
  using (
    exists (
      select 1 from public.attempts a
      where a.id = mastery_events.attempt_id and a.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.attempts a
      where a.id = mastery_events.attempt_id and a.user_id = auth.uid()
    )
  );

-- error_types: taxonomia global, leitura para qualquer usuário autenticado
create policy "error_types_read_all" on public.error_types
  for select
  using (auth.role() = 'authenticated');
