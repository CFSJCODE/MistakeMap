-- Exercícios de exemplo para conta vazia.
--
-- A Lista mostra só exercícios do próprio aluno, então uma conta nova abre
-- vazia. seed_example_exercises() copia do catálogo revisado um exercício
-- (o de posição 1, o mais fácil) de cada tema, criando a matéria do aluno
-- quando ainda não existe uma com o mesmo nome. Os exercícios copiados
-- guardam catalog_exercise_id, como os que o generate-practice serve.
--
-- Só age quando o aluno ainda não tem nenhum exercício: chamar de novo (dois
-- toques, dois aparelhos) não duplica nada. Devolve quantos foram criados.

create or replace function public.seed_example_exercises()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  item record;
  materia uuid;
  criados integer := 0;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Serializa chamadas simultâneas do mesmo aluno.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('seed_example_exercises:' || uid::text, 0)
  );

  if exists (
    select 1
    from public.exercises e
    join public.subjects s on s.id = e.subject_id
    where s.user_id = uid
  ) then
    return 0;
  end if;

  for item in
    select c.id, c.subject, c.prompt_text, c.difficulty
    from public.catalog_exercises c
    where c.position = 1
    order by c.subject, c.topic, c.theme
  loop
    select s.id into materia
    from public.subjects s
    where s.user_id = uid
      and pg_catalog.lower(pg_catalog.btrim(s.name))
        = pg_catalog.lower(pg_catalog.btrim(item.subject))
    order by s.created_at
    limit 1;

    if materia is null then
      insert into public.subjects (user_id, name)
      values (uid, item.subject)
      returning id into materia;
    end if;

    insert into public.exercises (
      subject_id, source, prompt_text, difficulty, catalog_exercise_id
    ) values (materia, 'catalog', item.prompt_text, item.difficulty, item.id);
    criados := criados + 1;
  end loop;

  return criados;
end;
$$;

revoke execute on function public.seed_example_exercises() from public, anon;
grant execute on function public.seed_example_exercises() to authenticated;
