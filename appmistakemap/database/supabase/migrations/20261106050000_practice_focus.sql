-- Public practice metadata survives reloading a round. Answers and their
-- explanations stay in practice_answer_keys, which remains server-only.
begin;

alter table public.exercises
  add column if not exists focus_concept text not null default '';

comment on column public.exercises.focus_concept is
  'Conceito focal da prática, visível apenas conforme as políticas de acesso do exercício. Não contém gabarito.';

update public.exercises e
set focus_concept = k.focus_concept
from public.practice_answer_keys k
where k.exercise_id = e.id
  and e.source in ('ai_practice', 'catalog')
  and e.focus_concept = ''
  and k.focus_concept <> '';

commit;
