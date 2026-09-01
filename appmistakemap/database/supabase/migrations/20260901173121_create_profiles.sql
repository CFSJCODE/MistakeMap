-- Perfil acadêmico do estudante: instituição de ensino, curso, nível de ensino
-- e, quando aplicável, tipo de ensino superior.

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  institution_name text,
  course text,
  education_level text not null,
  higher_education_type text,
  created_at timestamptz not null default now(),
  constraint profiles_education_level_check
    check (education_level in ('ensino_fundamental_2', 'ensino_medio', 'ensino_superior')),
  constraint profiles_higher_education_type_check
    check (
      (education_level = 'ensino_superior' and higher_education_type in ('graduacao', 'mestrado', 'doutorado'))
      or (education_level <> 'ensino_superior' and higher_education_type is null)
    )
);

alter table public.profiles enable row level security;

create policy "profiles_owner_all" on public.profiles
  for all
  using (id = auth.uid())
  with check (id = auth.uid());
