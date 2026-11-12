-- Catálogo compartilhado e conteúdo editorial da comunidade.
create table public.learning_subjects (
  id uuid primary key default gen_random_uuid(),
  stage text not null check (stage in ('fundamental', 'medio', 'superior', 'autodidata')),
  grade smallint,
  course text,
  name text not null check (length(trim(name)) between 1 and 120),
  check (coalesce(
    (stage = 'fundamental' and grade between 7 and 9 and course is null)
    or (stage = 'medio' and grade between 1 and 3 and course is null)
    or (stage = 'superior' and grade is null and course is not null)
    or (stage = 'autodidata' and grade is null and course is null)
  , false)),
  unique nulls not distinct (stage, grade, course, name)
);

alter table public.learning_subjects enable row level security;
create policy learning_subjects_read on public.learning_subjects
  for select to authenticated using (true);
revoke all on public.learning_subjects from anon, authenticated;
grant select on public.learning_subjects to authenticated;
grant all on public.learning_subjects to service_role;

insert into public.learning_subjects(stage, grade, name)
select 'fundamental', grade, name
from generate_series(7, 9) as g(grade)
cross join unnest(array['Língua Portuguesa', 'Arte', 'Educação Física',
  'Língua Inglesa', 'Matemática', 'Ciências', 'Geografia', 'História',
  'Ensino Religioso']) as subjects(name);
insert into public.learning_subjects(stage, grade, name)
select 'medio', grade, name
from generate_series(1, 3) as g(grade)
cross join unnest(array['Língua Portuguesa', 'Arte', 'Educação Física',
  'Língua Inglesa', 'Matemática', 'Biologia', 'Física', 'Química',
  'Geografia', 'História', 'Filosofia', 'Sociologia']) as subjects(name);
insert into public.learning_subjects(stage, course, name)
select 'superior', 'Engenharia de Computação', name
from unnest(array['Cálculo', 'Álgebra Linear', 'Matemática Discreta',
  'Física', 'Probabilidade e Estatística', 'Programação', 'Estruturas de Dados',
  'Algoritmos', 'Arquitetura de Computadores', 'Sistemas Digitais',
  'Circuitos Elétricos', 'Eletrônica', 'Sistemas Embarcados', 'Robótica',
  'Sistemas Operacionais', 'Redes de Computadores', 'Banco de Dados',
  'Engenharia de Software', 'Inteligência Artificial', 'Segurança da Informação'])
  as subjects(name);
insert into public.learning_subjects(stage, name)
select 'autodidata', name from unnest(array['Computação', 'Eletrônica',
  'Robótica', 'Programação', 'Projetos de Tecnologia']) as subjects(name);

create table public.knowledge_posts (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(trim(title)) between 1 and 140),
  body text not null check (length(trim(body)) between 1 and 20000),
  category text not null check (category in ('eletronica', 'informatica', 'robotica', 'projetos', 'dicas')),
  link_url text check (link_url is null or link_url ~ '^https://[^[:space:]]+$'),
  author_id uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create function public.touch_knowledge_post_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger knowledge_post_updated_at
before update on public.knowledge_posts
for each row execute function public.touch_knowledge_post_updated_at();
alter table public.knowledge_posts enable row level security;
create policy knowledge_read on public.knowledge_posts for select to authenticated using (true);
create policy knowledge_insert on public.knowledge_posts for insert to authenticated
  with check (public.is_admin() and author_id = auth.uid());
create policy knowledge_update on public.knowledge_posts for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy knowledge_delete on public.knowledge_posts for delete to authenticated
  using (public.is_admin());
revoke all on public.knowledge_posts from anon, authenticated;
grant select, insert, update, delete on public.knowledge_posts to authenticated;
grant all on public.knowledge_posts to service_role;

