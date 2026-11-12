-- Curadoria: professor habilitado redige; administrador revisa e publica.
-- Gabaritos de rascunhos nunca são legíveis por alunos comuns.
create table public.platform_content_drafts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  subject text not null check (char_length(btrim(subject)) between 1 and 120),
  topic text not null check (char_length(btrim(topic)) between 1 and 120),
  theme text not null check (char_length(btrim(theme)) between 1 and 120),
  position smallint not null check (position between 1 and 5),
  difficulty text not null check (difficulty in ('facil','media','dificil')),
  error_category text not null references public.error_types(name),
  prompt_text text not null check (char_length(btrim(prompt_text)) between 20 and 5000),
  correct_answer text not null check (char_length(btrim(correct_answer)) between 1 and 2000),
  explanation text not null check (char_length(btrim(explanation)) between 10 and 5000),
  technology_context text not null check (char_length(btrim(technology_context)) between 20 and 1000),
  source_url text check (source_url is null or (source_url like 'https://%' and char_length(source_url)<=2000)),
  rights_confirmed_at timestamptz not null default now(),
  status text not null default 'draft' check (status in ('draft','pending_review','rejected','published')),
  review_note text not null default '' check (char_length(review_note)<=2000),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  catalog_exercise_id uuid references public.catalog_exercises(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (status <> 'published' or (reviewed_at is not null and catalog_exercise_id is not null))
);
create index platform_drafts_author_updated on public.platform_content_drafts(author_id,updated_at desc);
create index platform_drafts_pending on public.platform_content_drafts(updated_at) where status='pending_review';
alter table public.platform_content_drafts enable row level security;
revoke all on public.platform_content_drafts from public,anon,authenticated;
grant all on public.platform_content_drafts to service_role;
grant select on public.platform_content_drafts to authenticated;
create policy platform_drafts_editor_read on public.platform_content_drafts for select to authenticated
  using (author_id=(select auth.uid()) or public.is_admin());

comment on table public.platform_content_drafts is
  'Rascunhos privados com gabarito; publicação transacional só pela Edge Function após revisão administrativa explícita.';
