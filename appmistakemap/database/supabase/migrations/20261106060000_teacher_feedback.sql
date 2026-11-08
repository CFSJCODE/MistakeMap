-- Feedback de professor sobre respostas compartilhadas de uma tarefa.
-- Cada acesso/mutação no servidor consulta consentimento e vínculo atuais.
create table public.platform_teacher_feedback (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.platform_sessions(id) on delete cascade,
  student_id uuid not null references auth.users(id) on delete cascade,
  teacher_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 3000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(session_id,teacher_id)
);
create index platform_feedback_student on public.platform_teacher_feedback(student_id,updated_at desc);
alter table public.platform_teacher_feedback enable row level security;
revoke all on public.platform_teacher_feedback from public,anon,authenticated;
grant all on public.platform_teacher_feedback to service_role;
grant select on public.platform_teacher_feedback to authenticated;
create policy platform_feedback_student_read on public.platform_teacher_feedback for select to authenticated
  using (student_id=(select auth.uid()));
-- Professor recebe seus pareceres pelo relatório da turma somente enquanto o
-- aluno autorizar respostas. Não ganha SELECT direto dos dados dos estudantes.
