-- Mapa da turma, tarefa pelo mapa e resultado da tarefa (onda 1, item G).
--
-- - O mapa da turma é calculado na Edge Function study-platform a partir dos
--   eventos de erro que já existem; não há tabela nova para ele. O agregado só
--   sai com 5 alunos ou mais e nunca traz identificador de aluno.
-- - "Treinar este conceito" cria uma tarefa da turma com questões do banco
--   (question_bank), e não do catálogo antigo. Uma tarefa usa um dos dois.
-- - Cada resposta a uma questão de tarefa guarda a tarefa, para o resultado
--   (quem fez, acerto por questão e erros mais comuns).
-- Usa as turmas que já existem (platform_classes), sem depender de escola.

alter table public.platform_assignments
  add column question_ids uuid[] not null default '{}',
  add column source_concept text
    check (source_concept is null or char_length(btrim(source_concept)) between 1 and 160);

-- A restrição antiga exigia de 1 a 10 questões do catálogo. Agora a tarefa tem
-- de 1 a 10 questões de uma única origem: catálogo ou banco de questões.
do $constraint$
declare c record;
begin
  for c in
    select con.conname from pg_constraint con
    where con.conrelid = 'public.platform_assignments'::regclass
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%cardinality(catalog_ids)%'
  loop
    execute format('alter table public.platform_assignments drop constraint %I', c.conname);
  end loop;
end;
$constraint$;

alter table public.platform_assignments
  add constraint platform_assignments_one_source check (
    (cardinality(catalog_ids) between 1 and 10 and cardinality(question_ids) = 0)
    or (cardinality(catalog_ids) = 0 and cardinality(question_ids) between 1 and 10)
  );

alter table public.question_responses
  add column assignment_id uuid references public.platform_assignments(id) on delete set null;

create index question_responses_assignment_idx
  on public.question_responses (assignment_id, user_id, question_id, created_at desc)
  where assignment_id is not null;

-- O mapa da turma lê as tentativas das últimas 4 semanas de cada aluno.
create index if not exists attempts_user_attempted_idx
  on public.attempts (user_id, attempted_at desc);

comment on column public.platform_assignments.question_ids is
  'Questões do banco (question_bank) quando a tarefa veio do mapa da turma; vazio para listas do catálogo.';
comment on column public.platform_assignments.source_concept is
  'Conceito do mapa da turma que originou a tarefa ("Treinar este conceito").';
comment on column public.question_responses.assignment_id is
  'Tarefa da turma respondida; nulo na prática livre da aba Exercícios.';
