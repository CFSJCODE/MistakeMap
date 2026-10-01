-- PREPARATORY MIGRATION, 2026-09-29. Apply only after reviewing the remote
-- migration history. No API key or private credentials belong in this file.
begin;

alter table public.processing_runs add column if not exists lease_until timestamptz;
alter table public.processing_runs add column if not exists error_code text;

create table public.attempt_analyses (
  attempt_id uuid primary key references public.attempts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  analysis jsonb not null check(jsonb_typeof(analysis)='object'),
  model text not null,
  pipeline_version text not null,
  created_at timestamptz not null default now()
);
create index attempt_analyses_owner_subject_idx on public.attempt_analyses(user_id,subject_id,created_at desc);
alter table public.attempt_analyses enable row level security;
create policy attempt_analyses_owner_read on public.attempt_analyses for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.attempt_analyses from anon,authenticated;
grant select on public.attempt_analyses to authenticated;
grant all on public.attempt_analyses to service_role;

create table public.practice_sets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  source_attempt_ids uuid[] not null,
  exercise_count integer not null check(exercise_count between 3 and 5),
  model text not null,
  created_at timestamptz not null default now()
);
create index practice_sets_owner_idx on public.practice_sets(user_id,created_at desc);
alter table public.practice_sets enable row level security;
create policy practice_sets_owner_read on public.practice_sets for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.practice_sets from anon,authenticated;
grant select on public.practice_sets to authenticated;
grant all on public.practice_sets to service_role;

-- Deliberately no client policy/grant: generated answer keys must remain private
-- until an authenticated user submits a corresponding attempt for correction.
create table public.practice_answer_keys (
  exercise_id uuid primary key references public.exercises(id) on delete cascade,
  practice_set_id uuid not null references public.practice_sets(id) on delete cascade,
  correct_answer text not null,
  explanation text not null,
  focus_concept text not null
);
create index practice_answer_keys_set_idx on public.practice_answer_keys(practice_set_id);
alter table public.practice_answer_keys enable row level security;
revoke all on public.practice_answer_keys from public,anon,authenticated;
grant all on public.practice_answer_keys to service_role;

create table public.ai_daily_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check(kind in ('analysis','practice')),
  usage_day date not null,
  requests integer not null check(requests>0),
  primary key(user_id,kind,usage_day)
);
alter table public.ai_daily_usage enable row level security;
revoke all on public.ai_daily_usage from public,anon,authenticated;
grant all on public.ai_daily_usage to service_role;

insert into public.error_types(name,category,description,ontology_version)
values
  ('calculo','calculo','Erro em operação ou cálculo.','openai-analysis-v1'),
  ('conceito','conceito','Aplicação incorreta de um conceito.','openai-analysis-v1'),
  ('sinal','sinal','Troca ou omissão de sinal.','openai-analysis-v1'),
  ('interpretacao','interpretacao','Interpretação incorreta do enunciado.','openai-analysis-v1'),
  ('procedimento','procedimento','Etapa ou método inadequado.','openai-analysis-v1'),
  ('unidade','unidade','Uso ou conversão incorreta de unidade.','openai-analysis-v1'),
  ('outro','outro','Outro erro acompanhado de evidência.','openai-analysis-v1')
on conflict(name) do nothing;

-- Protect cross-user foreign-key relationships before privileged processing.
drop policy if exists attempts_owner_all on public.attempts;
create policy attempts_owner_all on public.attempts for all to authenticated
using(user_id=(select auth.uid()))
with check(user_id=(select auth.uid()) and exists(
  select 1 from public.exercises e join public.subjects s on s.id=e.subject_id
  where e.id=attempts.exercise_id and s.user_id=(select auth.uid())
));

drop policy if exists concept_edges_owner_all on public.concept_edges;
create policy concept_edges_owner_all on public.concept_edges for all to authenticated
using(exists(select 1 from public.concepts c join public.subjects s on s.id=c.subject_id where c.id=concept_edges.from_concept_id and s.user_id=(select auth.uid())))
with check(
  exists(select 1 from public.concepts c join public.subjects s on s.id=c.subject_id where c.id=concept_edges.from_concept_id and s.user_id=(select auth.uid()))
  and exists(select 1 from public.concepts c join public.subjects s on s.id=c.subject_id where c.id=concept_edges.to_concept_id and s.user_id=(select auth.uid()))
);
drop policy if exists exercise_concepts_owner_all on public.exercise_concepts;
create policy exercise_concepts_owner_all on public.exercise_concepts for all to authenticated
using(exists(select 1 from public.exercises e join public.subjects s on s.id=e.subject_id where e.id=exercise_concepts.exercise_id and s.user_id=(select auth.uid())))
with check(
  exists(select 1 from public.exercises e join public.subjects s on s.id=e.subject_id where e.id=exercise_concepts.exercise_id and s.user_id=(select auth.uid()))
  and exists(select 1 from public.concepts c join public.subjects s on s.id=c.subject_id where c.id=exercise_concepts.concept_id and s.user_id=(select auth.uid()))
);

drop policy if exists attempt_assets_owner_insert on public.attempt_assets;
create policy attempt_assets_owner_insert on public.attempt_assets for insert to authenticated
with check(exists(select 1 from public.attempts a where a.id=attempt_assets.attempt_id and a.user_id=(select auth.uid()) and a.status='uploading')
  and object_path like 'uploads/' || (select auth.uid())::text || '/%'
  and object_path ~ '^uploads/[0-9a-f-]+/[0-9a-f-]+\.(jpg|jpeg|png|webp)$'
  and sha256 ~ '^[0-9a-f]{64}$');

-- Client can create a submission and finish uploading, never forge analysis state.
create or replace function public.guard_attempt_ai_state() returns trigger
language plpgsql set search_path=public as $$
begin
  if auth.uid() is null then return new; end if;
  if tg_op='INSERT' then
    if new.status not in ('uploading','pending') or new.version<>1 then
      raise exception 'invalid submission state' using errcode='42501';
    end if;
  else
    if new.user_id<>old.user_id or new.exercise_id<>old.exercise_id then
      raise exception 'submission ownership cannot change' using errcode='42501';
    end if;
    if old.status not in ('uploading','pending') or new.status not in ('uploading','pending') or new.version<>old.version then
      raise exception 'analysis state is server controlled' using errcode='42501';
    end if;
    new.version=old.version+1;
  end if;
  return new;
end;
$$;
revoke execute on function public.guard_attempt_ai_state() from public,anon,authenticated;
create trigger guard_attempt_ai_state before insert or update on public.attempts for each row execute function public.guard_attempt_ai_state();

-- A diagnosis belongs to an immutable exercise prompt. Editing a prompt after
-- submission must create another exercise, otherwise the cached result lies.
create or replace function public.guard_analyzed_exercise() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if (new.prompt_text is distinct from old.prompt_text or new.subject_id is distinct from old.subject_id)
    and (exists(select 1 from public.attempts a where a.exercise_id=old.id)
      or exists(select 1 from public.practice_answer_keys k where k.exercise_id=old.id)) then
    raise exception 'create a new exercise to change a submitted prompt' using errcode='42501';
  end if;
  return new;
end;
$$;
revoke execute on function public.guard_analyzed_exercise() from public,anon,authenticated;
create trigger guard_analyzed_exercise before update on public.exercises for each row execute function public.guard_analyzed_exercise();

-- Results remain suggestions until a dedicated, audited review flow is added.
drop policy if exists corrections_owner_all on public.corrections;
create policy corrections_owner_read on public.corrections for select to authenticated
using(exists(select 1 from public.attempts a where a.id=corrections.attempt_id and a.user_id=(select auth.uid())));
drop policy if exists error_events_owner_all on public.error_events;
create policy error_events_owner_read on public.error_events for select to authenticated
using(exists(select 1 from public.attempts a where a.id=error_events.attempt_id and a.user_id=(select auth.uid())));
drop policy if exists mastery_events_owner_all on public.mastery_events;
create policy mastery_events_owner_read on public.mastery_events for select to authenticated
using(exists(select 1 from public.attempts a where a.id=mastery_events.attempt_id and a.user_id=(select auth.uid())));
revoke insert,update,delete on public.corrections,public.error_events,public.mastery_events from anon,authenticated;
grant select on public.corrections,public.error_events,public.mastery_events to authenticated;
grant all on public.corrections,public.error_events,public.mastery_events,public.processing_runs,public.ocr_artifacts to service_role;

commit;
