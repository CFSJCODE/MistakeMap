-- Casos de RLS da escola e papéis (migration 20261111050000).
-- Cada trecho roda como um usuário: role authenticated + request.jwt.claim.sub,
-- como o PostgREST faz no Supabase.
\set owner_a   '''a0000000-0000-4000-8000-000000000001'''
\set it_a      '''a0000000-0000-4000-8000-000000000002'''
\set coord_a   '''a0000000-0000-4000-8000-000000000003'''
\set teacher_a '''a0000000-0000-4000-8000-000000000004'''
\set student_a '''a0000000-0000-4000-8000-000000000005'''
\set owner_b   '''b0000000-0000-4000-8000-000000000001'''
\set student_b '''b0000000-0000-4000-8000-000000000005'''
\set outsider  '''c0000000-0000-4000-8000-000000000001'''

insert into auth.users(id, email) values
  (:owner_a, 'dono@escola-a.dev'), (:it_a, 'ti@escola-a.dev'),
  (:coord_a, 'coord@escola-a.dev'), (:teacher_a, 'prof@escola-a.dev'),
  (:student_a, 'aluno@escola-a.dev'), (:owner_b, 'dono@escola-b.dev'),
  (:student_b, 'aluno@escola-b.dev'), (:outsider, 'intruso@fora.dev');

-- Dado pedagógico do aluno A, gravado pelo backend.
insert into public.subjects(id, user_id, name)
  values ('d0000000-0000-4000-8000-000000000001', :student_a, 'Circuitos');
insert into public.exercises(id, subject_id, prompt_text)
  values ('d0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001',
          'Um sensor de 12 V puxa 0,5 A. Qual a resistência?');
insert into public.attempts(id, exercise_id, user_id, answer)
  values ('d0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000002',
          :student_a, '6 ohms');
insert into public.attempt_analyses(attempt_id, user_id, subject_id, analysis)
  values ('d0000000-0000-4000-8000-000000000003', :student_a,
          'd0000000-0000-4000-8000-000000000001', '{"erro":"inverteu V/I"}');

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

-- ---------------------------------------------------------------- montagem
set role authenticated;

select set_config('request.jwt.claim.sub', :owner_a, false);
insert into t values ('school_a', public.create_school('Escola de Robótica A', '12.345.678/0001-90')::text);
insert into t select 'inv_it', code from public.create_school_invite((select v::uuid from t where k='school_a'), 'it_admin', 'TI@escola-a.dev');
insert into t select 'inv_coord', code from public.create_school_invite((select v::uuid from t where k='school_a'), 'coordinator');
insert into t select 'inv_teacher', code from public.create_school_invite((select v::uuid from t where k='school_a'), 'teacher');
insert into t select 'inv_student', code from public.create_school_invite((select v::uuid from t where k='school_a'), 'student', null, 30, 7);

select set_config('request.jwt.claim.sub', :owner_b, false);
insert into t values ('school_b', public.create_school('Escola de Eletrônica B')::text);
insert into t select 'inv_student_b', code from public.create_school_invite((select v::uuid from t where k='school_b'), 'student', null, 30, 7);

select set_config('request.jwt.claim.sub', :it_a, false);
select pg_temp.ok((select role from public.redeem_school_invite((select v from t where k='inv_it'))) = 'it_admin',
  'TI resgata convite de TI com o e-mail certo (maiúsculas ignoradas)');
select set_config('request.jwt.claim.sub', :coord_a, false);
select * from public.redeem_school_invite((select v from t where k='inv_coord'));
select set_config('request.jwt.claim.sub', :teacher_a, false);
select * from public.redeem_school_invite(lower((select v from t where k='inv_teacher')));
select set_config('request.jwt.claim.sub', :student_a, false);
select * from public.redeem_school_invite((select v from t where k='inv_student'));
select pg_temp.ok((select count(*) from public.redeem_school_invite((select v from t where k='inv_student'))) = 1,
  'resgatar de novo o mesmo convite não duplica nem dá erro');
select set_config('request.jwt.claim.sub', :student_b, false);
select * from public.redeem_school_invite((select v from t where k='inv_student_b'));

-- Turma da escola A, criada pelo backend com o professor da escola.
reset role;
insert into public.platform_classes(id, teacher_id, title, school_id)
  values ('f0000000-0000-4000-8000-000000000001', :teacher_a, 'Robótica 8º ano',
          (select v::uuid from t where k='school_a'));
insert into public.platform_memberships(class_id, user_id, share_progress, share_answers)
  values ('f0000000-0000-4000-8000-000000000001', :student_a, true, true);
insert into public.platform_sessions(id, user_id, request_id, request_payload, mode, title, total)
  values ('f0000000-0000-4000-8000-000000000002', :student_a, gen_random_uuid(), '{}', 'practice', 'Lei de Ohm', 3);
set role authenticated;

-- ------------------------------------- 1. aluno de uma escola não vê outra escola
select set_config('request.jwt.claim.sub', :student_a, false);
select pg_temp.ok((select count(*) from public.schools) = 1, 'aluno A vê só a própria escola');
select pg_temp.ok(not exists(select 1 from public.schools where id = (select v::uuid from t where k='school_b')),
  'aluno A não vê a escola B');
select pg_temp.ok((select count(*) from public.school_members) = 1, 'aluno A vê só o próprio papel');
select pg_temp.ok((select count(*) from public.school_invites) = 0, 'aluno A não vê convites');
select pg_temp.ok(not public.is_school_member((select v::uuid from t where k='school_b')),
  'is_school_member(escola B) é falso para o aluno A');
select pg_temp.ok((select count(*) from public.platform_classes) = 1, 'aluno A vê a turma em que está matriculado');

select set_config('request.jwt.claim.sub', :student_b, false);
select pg_temp.ok((select count(*) from public.schools) = 1
  and (select id from public.schools) = (select v::uuid from t where k='school_b'), 'aluno B vê só a escola B');
select pg_temp.ok(not exists(select 1 from public.school_members where school_id = (select v::uuid from t where k='school_a')),
  'aluno B não vê membros da escola A');

select set_config('request.jwt.claim.sub', :owner_b, false);
select pg_temp.ok((select count(*) from public.school_members) = 2, 'dono B vê só os 2 membros da escola B');
select pg_temp.ok(not exists(select 1 from public.platform_classes), 'dono B não vê turma da escola A');

select set_config('request.jwt.claim.sub', :outsider, false);
select pg_temp.ok((select count(*) from public.schools) = 0, 'usuário sem escola não vê nenhuma escola');

-- ------------------------------------------- 2. TI não vê dado pedagógico
select set_config('request.jwt.claim.sub', :it_a, false);
select pg_temp.ok((select count(*) from public.school_members) = 5, 'TI vê os 5 membros da escola A (sem recursão de RLS)');
select pg_temp.ok((select count(*) from public.school_invites) = 4, 'TI vê os convites da escola');
select pg_temp.ok((select count(*) from public.platform_classes) = 1, 'TI vê a turma da escola (título e professor)');
select pg_temp.ok((select count(*) from public.attempts) = 0, 'TI não vê tentativas do aluno');
select pg_temp.ok((select count(*) from public.attempt_analyses) = 0, 'TI não vê análises do aluno');
select pg_temp.ok((select count(*) from public.subjects) = 0, 'TI não vê matérias do aluno');
select pg_temp.ok((select count(*) from public.platform_sessions) = 0, 'TI não vê sessões de estudo do aluno');
select pg_temp.ok((select count(*) from public.platform_memberships) = 0, 'TI não vê consentimentos de turma');
select pg_temp.fails('select code_hash from public.school_invites', '42501', 'TI não lê o hash do código do convite');

select set_config('request.jwt.claim.sub', :coord_a, false);
select pg_temp.ok((select count(*) from public.attempt_analyses) = 0, 'coordenador não vê análise individual sem consentimento');

select set_config('request.jwt.claim.sub', :student_a, false);
select pg_temp.ok((select count(*) from public.attempt_analyses) = 1, 'aluno continua vendo a própria análise');

-- ------------------------------- 3. papel de gestão sem convite é recusado
select set_config('request.jwt.claim.sub', :outsider, false);
select pg_temp.fails(format($s$insert into public.school_members(school_id,user_id,role) values (%L,%L,'coordinator')$s$,
  (select v from t where k='school_a'), :outsider), '42501', 'cliente não insere papel direto');
select pg_temp.fails(format($s$select * from public.redeem_school_invite(%L)$s$, (select v from t where k='inv_coord')),
  'MM404', 'convite de coordenador já usado não serve para outra pessoa');
select pg_temp.fails(format($s$select * from public.redeem_school_invite(%L)$s$, 'CODIGOFALSO1'),
  'MM404', 'código inexistente é recusado');
select pg_temp.fails(format($s$select * from public.create_school_invite(%L,'it_admin')$s$, (select v from t where k='school_a')),
  'MM403', 'quem não é da escola não cria convite');

select set_config('request.jwt.claim.sub', :it_a, false);
select pg_temp.fails(format($s$select * from public.create_school_invite(%L,'coordinator')$s$, (select v from t where k='school_a')),
  'MM403', 'TI não convida gestor');
insert into t select 'inv_teacher2', code from public.create_school_invite((select v::uuid from t where k='school_a'), 'teacher');
select pg_temp.ok(true, 'TI convida professor');

select set_config('request.jwt.claim.sub', :teacher_a, false);
select pg_temp.fails(format($s$select * from public.create_school_invite(%L,'student')$s$, (select v from t where k='school_a')),
  'MM403', 'professor não cria convite da escola');

select set_config('request.jwt.claim.sub', :owner_a, false);
insert into t select 'inv_owner_email', code from public.create_school_invite((select v::uuid from t where k='school_a'), 'it_admin', 'outra-pessoa@escola-a.dev');
select pg_temp.fails($s$select * from public.create_school_invite((select v::uuid from t where k='school_a'),'coordinator',null,5)$s$,
  '23514', 'convite de gestão não pode ser de vários usos');
select set_config('request.jwt.claim.sub', :outsider, false);
select pg_temp.fails(format($s$select * from public.redeem_school_invite(%L)$s$, (select v from t where k='inv_owner_email')),
  'MM404', 'convite com e-mail de outra pessoa é recusado');

select set_config('request.jwt.claim.sub', :owner_a, false);
select public.revoke_school_invite((select id from public.school_invites where role='teacher' and uses=0 limit 1));
select set_config('request.jwt.claim.sub', :outsider, false);
select pg_temp.fails(format($s$select * from public.redeem_school_invite(%L)$s$, (select v from t where k='inv_teacher2')),
  'MM404', 'convite revogado é recusado');

-- Mesmo o backend com service_role não pula o convite.
reset role;
set role service_role;
select pg_temp.fails(format($s$insert into public.school_members(school_id,user_id,role) values (%L,%L,'it_admin')$s$,
  (select v from t where k='school_a'), :outsider), 'MM403', 'service_role sem convite também é recusado');
select pg_temp.fails(format($s$insert into public.school_members(school_id,user_id,role) values (%L,%L,'owner')$s$,
  (select v from t where k='school_a'), :outsider), 'MM403', 'segundo dono sem convite é recusado');
select pg_temp.fails(format($s$update public.school_members set role='owner' where user_id=%L$s$, :student_a),
  'MM403', 'trocar o papel de um membro exige convite novo');
update public.school_invites set expires_at = created_at + interval '1 second', uses = 0
  where role = 'it_admin' and email = 'outra-pessoa@escola-a.dev';
select pg_temp.fails(format($s$insert into public.school_members(school_id,user_id,role,invite_id)
  select school_id,%L,role,id from public.school_invites where email='outra-pessoa@escola-a.dev'$s$, :outsider),
  'MM404', 'convite vencido é recusado');
select pg_temp.fails(format($s$insert into public.platform_classes(teacher_id,title,school_id) values (%L,'Turma pirata',%L)$s$,
  :outsider, (select v from t where k='school_a')), 'MM403', 'turma de escola exige professor da escola');
reset role;

select set_config('request.jwt.claim.sub', :it_a, false);
set role authenticated;
select pg_temp.ok((select uses from public.school_invites where role='student') = 1, 'convite de aluno contou 1 uso');
reset role;
