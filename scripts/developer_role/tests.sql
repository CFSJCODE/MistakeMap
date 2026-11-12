-- Casos do papel developer (migration 20261111233000), como o PostgREST faz:
-- role authenticated + request.jwt.claim.sub.
\set admin '''e0000000-0000-4000-8000-000000000001'''
\set dev   '''e0000000-0000-4000-8000-000000000002'''
\set aluno '''e0000000-0000-4000-8000-000000000003'''

insert into auth.users(id, email) values
  (:admin, 'admin@equipe.dev'), (:dev, 'dev@equipe.dev'), (:aluno, 'aluno@escola.dev');
update public.profiles set role = 'admin' where id = :admin;

do $$ begin
  begin
    update public.profiles set role = 'chefe' where id = 'e0000000-0000-4000-8000-000000000003';
    raise exception 'FALHOU: papel desconhecido foi aceito';
  exception when check_violation then raise notice 'ok: papel desconhecido recusado';
  end;
end $$;

-- O aluno não se promove a developer.
set role authenticated;
select set_config('request.jwt.claim.sub', :aluno, false);
do $$ begin
  begin
    update public.profiles set role = 'developer' where id = auth.uid();
    if (select role from public.profiles where id = auth.uid()) = 'developer' then
      raise exception 'FALHOU: aluno se promoveu';
    end if;
  exception when insufficient_privilege then null;
  end;
  if public.is_team_member() then raise exception 'FALHOU: aluno é da equipe'; end if;
  raise notice 'ok: aluno não se promove e não é da equipe';
end $$;

-- O admin promove o dev pelo painel.
select set_config('request.jwt.claim.sub', :admin, false);
update public.profiles set role = 'developer' where id = :dev;
do $$ begin
  if (select role from public.profiles where id = 'e0000000-0000-4000-8000-000000000002') <> 'developer' then
    raise exception 'FALHOU: admin não promoveu';
  end if;
  if not public.is_team_member() then raise exception 'FALHOU: admin fora da equipe'; end if;
  raise notice 'ok: admin promove developer e é da equipe';
end $$;

-- O dev é da equipe, mas não é admin e não se promove a admin.
select set_config('request.jwt.claim.sub', :dev, false);
do $$ begin
  if not public.is_team_member() then raise exception 'FALHOU: dev fora da equipe'; end if;
  if public.is_admin() then raise exception 'FALHOU: dev virou admin'; end if;
  begin
    update public.profiles set role = 'admin' where id = auth.uid();
  exception when insufficient_privilege then null;
  end;
  if public.is_admin() then raise exception 'FALHOU: dev se promoveu a admin'; end if;
  raise notice 'ok: dev é da equipe, não é admin e não se promove';
end $$;
reset role;
