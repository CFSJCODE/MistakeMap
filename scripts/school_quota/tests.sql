-- Casos de planos, cota coletiva e aluno ativo (migration 20261111210000).
-- Trechos com "set role authenticated" imitam o PostgREST; o resto roda como
-- o backend (Edge Function conectada ao banco).
\set owner_a   '''a0000000-0000-4000-8000-000000000001'''
\set s1        '''a0000000-0000-4000-8000-000000000011'''
\set s2        '''a0000000-0000-4000-8000-000000000012'''
\set s3        '''a0000000-0000-4000-8000-000000000013'''
\set s4        '''a0000000-0000-4000-8000-000000000014'''
\set s5        '''a0000000-0000-4000-8000-000000000015'''
\set owner_b   '''b0000000-0000-4000-8000-000000000001'''
\set it_b      '''b0000000-0000-4000-8000-000000000002'''
\set teacher_b '''b0000000-0000-4000-8000-000000000003'''
\set sb1       '''b0000000-0000-4000-8000-000000000011'''
\set sb2       '''b0000000-0000-4000-8000-000000000012'''
\set sb3       '''b0000000-0000-4000-8000-000000000013'''
\set sb4       '''b0000000-0000-4000-8000-000000000014'''
\set outsider  '''c0000000-0000-4000-8000-000000000001'''

insert into auth.users(id, email) values
  (:owner_a, 'dono@a.dev'), (:s1, 's1@a.dev'), (:s2, 's2@a.dev'), (:s3, 's3@a.dev'),
  (:s4, 's4@a.dev'), (:s5, 's5@a.dev'), (:owner_b, 'dono@b.dev'), (:it_b, 'ti@b.dev'),
  (:teacher_b, 'prof@b.dev'), (:sb1, 'sb1@b.dev'), (:sb2, 'sb2@b.dev'),
  (:sb3, 'sb3@b.dev'), (:sb4, 'sb4@b.dev'), (:outsider, 'fora@c.dev');

create temporary table t(k text primary key, v text);
grant all on t to authenticated, service_role;

create function pg_temp.ok(cond boolean, msg text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'FALHOU: %', msg; end if;
  raise notice 'ok: %', msg;
end $$;
create function pg_temp.fails(stmt text, state text, msg text) returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    if sqlstate = state then raise notice 'ok: %', msg; return; end if;
    raise exception 'FALHOU: % (esperava %, veio % %)', msg, state, sqlstate, sqlerrm;
  end;
  raise exception 'FALHOU: % (não deu erro)', msg;
end $$;
-- Consome n vezes e devolve quantas vezes saiu cada status.
create function pg_temp.consume(p_user uuid, p_kind text, n int) returns jsonb language plpgsql as $$
declare r jsonb := '{}'; st text;
begin
  for i in 1..n loop
    select status into st from public.consume_school_ai(p_user, p_kind);
    r := jsonb_set(r, array[st], to_jsonb(coalesce((r->>st)::int, 0) + 1));
  end loop;
  return r;
end $$;
create function pg_temp.attempt(p_user uuid) returns void language plpgsql as $$
declare v_subject uuid; v_exercise uuid;
begin
  insert into public.subjects(user_id, name) values (p_user, 'Robótica') returning id into v_subject;
  insert into public.exercises(subject_id, prompt_text)
    values (v_subject, 'Um motor de 12 V consome 2 A. Qual a potência?') returning id into v_exercise;
  insert into public.attempts(exercise_id, user_id, answer) values (v_exercise, p_user, '6 W');
end $$;

-- ---------------------------------------------------------------- montagem
set role authenticated;
select set_config('request.jwt.claim.sub', :owner_a, false);
insert into t values ('school_a', public.create_school('Clube de Robótica A')::text);
insert into t select 'inv_a', code from public.create_school_invite((select v::uuid from t where k='school_a'), 'student', null, 30, 7);
select set_config('request.jwt.claim.sub', :owner_b, false);
insert into t values ('school_b', public.create_school('Escola de Eletrônica B')::text);
insert into t select 'inv_b', code from public.create_school_invite((select v::uuid from t where k='school_b'), 'student', null, 30, 7);
insert into t select 'inv_b_it', code from public.create_school_invite((select v::uuid from t where k='school_b'), 'it_admin');
insert into t select 'inv_b_teacher', code from public.create_school_invite((select v::uuid from t where k='school_b'), 'teacher');
reset role;
-- A escola B contrata o plano Escola (no futuro, pelo item D).
update public.schools set plan = 'escola' where id = (select v::uuid from t where k='school_b');
set role authenticated;

-- ------------------------------------------- 1. plano Grátis: 5 usuários, 1 turma
select set_config('request.jwt.claim.sub', :s1, false);
select * from public.redeem_school_invite((select v from t where k='inv_a'));
select set_config('request.jwt.claim.sub', :s2, false);
select * from public.redeem_school_invite((select v from t where k='inv_a'));
select set_config('request.jwt.claim.sub', :s3, false);
select * from public.redeem_school_invite((select v from t where k='inv_a'));
select set_config('request.jwt.claim.sub', :s4, false);
select * from public.redeem_school_invite((select v from t where k='inv_a'));
select set_config('request.jwt.claim.sub', :s5, false);
select pg_temp.fails(format($s$select * from public.redeem_school_invite(%L)$s$, (select v from t where k='inv_a')),
  'MM402', 'Grátis recusa o 6º usuário');
reset role;
select pg_temp.ok((select uses from public.school_invites where school_id=(select v::uuid from t where k='school_a')) = 4,
  'convite recusado pelo limite não gasta uso');

insert into public.platform_classes(teacher_id, title, school_id)
  values (:owner_a, 'Robótica 1', (select v::uuid from t where k='school_a'));
select pg_temp.fails(format($s$insert into public.platform_classes(teacher_id,title,school_id) values (%L,'Robótica 2',%L)$s$,
  :owner_a, (select v from t where k='school_a')), 'MM402', 'Grátis recusa a 2ª turma');

-- ------------------------------------------- 2. aluno ativo
select pg_temp.attempt(:s1);
select pg_temp.attempt(:s1);
insert into public.platform_sessions(user_id, request_id, request_payload, mode, title, total)
  values (:s1, gen_random_uuid(), '{}', 'practice', 'Lei de Ohm', 3);
select pg_temp.ok((select active_students from public.school_usage_months
  where school_id=(select v::uuid from t where k='school_a') and month=public.school_usage_month()) = 1,
  'mesmo aluno com várias atividades conta 1 ativo');
insert into public.platform_sessions(user_id, request_id, request_payload, mode, title, total)
  values (:s2, gen_random_uuid(), '{}', 'practice', 'Diodos', 3);
select pg_temp.attempt(:owner_a);
select pg_temp.ok((select active_students from public.school_usage_months
  where school_id=(select v::uuid from t where k='school_a') and month=public.school_usage_month()) = 2,
  'segundo aluno conta; o dono (não aluno) não conta');
select pg_temp.ok((select first_activity from public.school_active_students where user_id=:s2) = 'practice_session',
  'registro guarda a primeira atividade do mês');
select pg_temp.attempt(:outsider);
select pg_temp.ok(not exists(select 1 from public.school_active_students where user_id=:outsider),
  'usuário sem escola não vira ativo de escola nenhuma');

-- ------------------------------------------- 3. pote do Grátis: 20 × ativos, sem extra
select pg_temp.ok(pg_temp.consume(:s1, 'analysis', 41) = '{"ok": 40, "exhausted": 1}',
  'Grátis com 2 ativos libera 40 análises e recusa a 41ª');
select pg_temp.ok((select status from public.consume_school_ai(:s3, 'analysis')) = 'ok',
  'aluno novo no mês aumenta o pote (+20) e já pode usar');
select pg_temp.ok((select active_students from public.school_usage_months
  where school_id=(select v::uuid from t where k='school_a')) = 3, 'pedido de IA também marca o aluno como ativo');
select pg_temp.ok(pg_temp.consume(:s2, 'practice', 13) = '{"ok": 12, "exhausted": 1}',
  'treinos do Grátis: 4 × 3 ativos = 12');

-- ------------------------------------------- 4. plano Escola: 60 × ativos, extra cobrável
select set_config('request.jwt.claim.sub', :sb1, false);
set role authenticated;
select * from public.redeem_school_invite((select v from t where k='inv_b'));
select set_config('request.jwt.claim.sub', :it_b, false);
select * from public.redeem_school_invite((select v from t where k='inv_b_it'));
select set_config('request.jwt.claim.sub', :teacher_b, false);
select * from public.redeem_school_invite((select v from t where k='inv_b_teacher'));
select set_config('request.jwt.claim.sub', :sb2, false);
select * from public.redeem_school_invite((select v from t where k='inv_b'));
select set_config('request.jwt.claim.sub', :sb3, false);
select * from public.redeem_school_invite((select v from t where k='inv_b'));
select pg_temp.ok(true, 'plano Escola aceita mais de 5 usuários');
reset role;

select pg_temp.ok(pg_temp.consume(:sb1, 'analysis', 62) = '{"ok": 60, "extra": 2}',
  'Escola com 1 ativo: 60 do pote e depois análise extra');
select pg_temp.ok((select extra_analyses from public.school_usage_months
  where school_id=(select v::uuid from t where k='school_b')) = 2, 'extras ficam contados para a fatura');
select public.release_school_ai((select v::uuid from t where k='school_b'), public.school_usage_month(), 'analysis', true);
select pg_temp.ok((select extra_analyses from public.school_usage_months
  where school_id=(select v::uuid from t where k='school_b')) = 1, 'falha da IA devolve a análise extra');
select pg_temp.ok(pg_temp.consume(:sb1, 'practice', 16) = '{"ok": 15, "exhausted": 1}',
  'treinos do Escola: 15 por ativo, sem extra');

-- ------------------------------------------- 5. nível de IA por plano
select pg_temp.ok((select ai_tier from public.consume_school_ai(:sb1, 'none')) = 'standard',
  'aluno do plano Escola usa IA standard (Gemini)');
select pg_temp.ok((select ai_tier from public.consume_school_ai(:outsider, 'none')) = 'standard'
  and (select status from public.consume_school_ai(:outsider, 'analysis')) = 'no_school',
  'sem escola: cota individual e IA standard');
update public.schools set plan = 'plus' where id = (select v::uuid from t where k='school_b');
select pg_temp.ok((select ai_tier from public.consume_school_ai(:sb1, 'analysis')) = 'premium',
  'aluno do Plus usa IA premium (Claude)');
select pg_temp.ok((select status || '/' || ai_tier from public.consume_school_ai(:teacher_b, 'analysis')) = 'no_school/premium',
  'professor do Plus usa a cota individual com IA premium (não gasta o pote)');
select pg_temp.ok((select plan_label from public.user_school_plan(:sb2)) = 'Escola Plus',
  'plano efetivo do aluno vem da escola');

-- ------------------------------------------- 6. troca de plano respeita limites
select pg_temp.fails(format($s$update public.schools set plan='free' where id=%L$s$, (select v from t where k='school_b')),
  'MM402', 'escola com 6 usuários não volta para o Grátis');

-- ------------------------------------------- 7. escola suspensa não usa o pote
update public.schools set status = 'suspended' where id = (select v::uuid from t where k='school_b');
select pg_temp.ok((select status || '/' || ai_tier from public.consume_school_ai(:sb1, 'analysis')) = 'no_school/standard',
  'escola suspensa: aluno volta à cota individual e IA standard');
update public.schools set status = 'active' where id = (select v::uuid from t where k='school_b');

-- ------------------------------------------- 8. RLS e permissões
set role authenticated;
select set_config('request.jwt.claim.sub', :sb1, false);
select pg_temp.ok((select count(*) from public.school_usage_months) = 0, 'aluno não vê o uso da escola');
select pg_temp.ok((select count(*) from public.school_active_students) = 0, 'aluno não vê quem está ativo');
select pg_temp.ok((select count(*) from public.school_plan_limits) = 3, 'qualquer usuário logado vê a tabela de planos');
select pg_temp.fails(format($s$select * from public.school_quota(%L)$s$, (select v from t where k='school_b')),
  'MM403', 'aluno não lê o resumo do pote');
select pg_temp.fails(format($s$select * from public.consume_school_ai(%L,'analysis')$s$, :sb1),
  '42501', 'app não consome cota direto');
select pg_temp.fails(format($s$select public.release_school_ai(%L,current_date,'analysis',false)$s$, (select v from t where k='school_b')),
  '42501', 'app não devolve cota');
select pg_temp.fails($s$update public.school_plan_limits set analyses_per_active = 1000$s$,
  '42501', 'app não altera a tabela de planos');
select pg_temp.fails(format($s$select * from public.user_school_plan(%L)$s$, :sb1),
  '42501', 'app não consulta plano de outra pessoa');

select set_config('request.jwt.claim.sub', :it_b, false);
select pg_temp.ok((select count(*) from public.school_usage_months) = 1, 'TI vê o uso da própria escola');
select pg_temp.ok((select count(*) from public.school_active_students) = 1, 'TI vê os ativos da própria escola');
select pg_temp.ok((select analyses_pot from public.school_quota((select v::uuid from t where k='school_b'))) = 100,
  'resumo do pote do Plus com 1 ativo = 100');
select pg_temp.ok((select count(*) from public.attempts) = 0, 'TI continua sem ver tentativas');

select set_config('request.jwt.claim.sub', :owner_a, false);
select pg_temp.ok((select count(*) from public.school_usage_months) = 1
  and (select school_id from public.school_usage_months) = (select v::uuid from t where k='school_a'),
  'dono A vê só o uso da escola A');
select pg_temp.fails(format($s$select * from public.school_quota(%L)$s$, (select v from t where k='school_b')),
  'MM403', 'dono A não lê o pote da escola B');
select pg_temp.ok((select extra_analyses_brl from public.school_quota((select v::uuid from t where k='school_a'))) = 0,
  'Grátis não gera valor de extra');
reset role;
