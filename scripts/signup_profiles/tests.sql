-- Casos do cadastro por perfil (migration 20261111223000).
-- Cada trecho roda como um usuário: role authenticated + request.jwt.claim.sub.
\set owner    '''a1000000-0000-4000-8000-000000000001'''
\set teacher  '''a1000000-0000-4000-8000-000000000002'''
\set it       '''a1000000-0000-4000-8000-000000000003'''
\set minor    '''a1000000-0000-4000-8000-000000000004'''
\set minor_sc '''a1000000-0000-4000-8000-000000000005'''
\set adult    '''a1000000-0000-4000-8000-000000000006'''
\set guardian '''a1000000-0000-4000-8000-000000000007'''
\set legacy   '''a1000000-0000-4000-8000-000000000008'''
\set outsider '''a1000000-0000-4000-8000-000000000009'''
\set teen_g   '''a1000000-0000-4000-8000-00000000000a'''

insert into auth.users(id, email) values
  (:owner, 'dono@escola.dev'), (:teacher, 'prof@escola.dev'), (:it, 'ti@escola.dev'),
  (:minor, 'menor@casa.dev'), (:minor_sc, 'menor@escola.dev'), (:adult, 'adulto@casa.dev'),
  (:guardian, 'mae@casa.dev'), (:legacy, 'antigo@casa.dev'), (:outsider, 'intruso@fora.dev'),
  (:teen_g, 'irmao@casa.dev');

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

set role authenticated;

-- ------------------------------------------------ escola, professor e TI
select set_config('request.jwt.claim.sub', :owner, false);
select public.save_signup_profile('owner');
insert into t values ('school', public.create_school('Escola de Robótica')::text);
insert into t select 'inv_teacher', code from public.create_school_invite((select v::uuid from t where k='school'), 'teacher');
insert into t select 'inv_it', code from public.create_school_invite((select v::uuid from t where k='school'), 'it_admin');
insert into t select 'inv_student', code from public.create_school_invite((select v::uuid from t where k='school'), 'student', null, 30, 7);
select set_config('request.jwt.claim.sub', :teacher, false);
select * from public.redeem_school_invite((select v from t where k='inv_teacher'));
select public.save_signup_profile('teacher');
select set_config('request.jwt.claim.sub', :it, false);
select * from public.redeem_school_invite((select v from t where k='inv_it'));
select public.save_signup_profile('it_admin');

-- ---------------------------------------- 1. o perfil escolhido é só um pedido
select set_config('request.jwt.claim.sub', :outsider, false);
select public.save_signup_profile('coordinator');
select pg_temp.ok((select persona from public.user_signups) = 'coordinator', 'perfil de coordenador fica gravado como pedido');
select pg_temp.ok(not public.is_school_member((select v::uuid from t where k='school')),
  'marcar coordenador não dá papel na escola');
select pg_temp.ok((select count(*) from public.schools) = 0, 'quem só marcou o perfil não vê escola');
select pg_temp.fails($s$insert into public.user_signups(user_id, persona) values (auth.uid(), 'owner')$s$,
  '42501', 'cliente não grava o perfil direto na tabela');
select pg_temp.fails($s$select public.save_signup_profile('student')$s$, '22023', 'estudante sem data de nascimento é recusado');
select pg_temp.fails($s$select public.save_signup_profile('student', current_date + 1)$s$, '22023', 'nascimento no futuro é recusado');
select pg_temp.fails($s$select public.save_signup_profile('admin')$s$, '22023', 'perfil fora da lista é recusado');
select pg_temp.ok((select count(*) from public.user_signups) = 1, 'cada um vê só o próprio perfil');

-- ---------------------------------- 2. menor sem escola precisa do responsável
select set_config('request.jwt.claim.sub', :minor, false);
select public.save_signup_profile('student', (current_date - interval '13 years')::date);
select pg_temp.ok(public.my_guardian_consent_pending(), 'menor de 13 anos sem escola fica pendente');
select pg_temp.fails(format($s$select public.guardian_consent_pending(%L)$s$, :adult), '42501',
  'app não consulta a pendência de outra pessoa');
insert into t select 'consent', code from public.request_guardian_consent();
select pg_temp.ok((select count(*) from public.guardian_consent_requests) = 1, 'estudante vê o próprio pedido');
select pg_temp.fails('select code_hash from public.guardian_consent_requests', '42501', 'ninguém lê o hash do código');
select pg_temp.fails(format($s$select public.grant_guardian_consent(%L, 'termo-2026-11')$s$, (select v from t where k='consent')),
  'MM403', 'o próprio estudante não consente por si');

select set_config('request.jwt.claim.sub', :teen_g, false);
select public.save_signup_profile('student', (current_date - interval '15 years')::date);
select pg_temp.fails(format($s$select public.grant_guardian_consent(%L, 'termo-2026-11')$s$, (select v from t where k='consent')),
  'MM403', 'responsável menor de idade é recusado');

select set_config('request.jwt.claim.sub', :guardian, false);
select public.save_signup_profile('guardian');
select pg_temp.fails($s$select public.grant_guardian_consent('CODIGOFALSO1', 'termo-2026-11')$s$, 'MM404', 'código inexistente é recusado');
select pg_temp.ok(public.grant_guardian_consent(lower((select v from t where k='consent')), 'termo-2026-11') = :minor,
  'responsável aceita com o código do filho (maiúsculas ignoradas)');
select pg_temp.ok((select count(*) from public.my_guardian_children()) = 1
  and (select email from public.my_guardian_children()) = 'menor@casa.dev', 'responsável vê o filho que acompanha');
select pg_temp.fails(format($s$select public.grant_guardian_consent(%L, 'termo-2026-11')$s$, (select v from t where k='consent')),
  'MM404', 'código de consentimento é de uso único');

select set_config('request.jwt.claim.sub', :minor, false);
select pg_temp.ok(not public.my_guardian_consent_pending(), 'depois do aceite o menor usa a IA');
select pg_temp.ok((select count(*) from public.guardian_links) = 1, 'estudante vê o vínculo com o responsável');
select pg_temp.fails('select * from public.request_guardian_consent()', 'MM409', 'sem pendência não se pede código novo');

select set_config('request.jwt.claim.sub', :outsider, false);
select pg_temp.ok((select count(*) from public.guardian_links) = 0, 'terceiro não vê vínculo de responsável');
select pg_temp.ok((select count(*) from public.my_guardian_children()) = 0, 'terceiro não vê filhos de ninguém');
select pg_temp.fails(format($s$select public.revoke_guardian_consent(%L)$s$, :minor), 'MM404', 'terceiro não revoga consentimento alheio');

select set_config('request.jwt.claim.sub', :guardian, false);
select public.revoke_guardian_consent(:minor);
select set_config('request.jwt.claim.sub', :minor, false);
select pg_temp.ok(public.my_guardian_consent_pending(), 'consentimento revogado volta a bloquear a IA');

-- ------------------------------------ 3. menor da escola, adulto e conta antiga
select set_config('request.jwt.claim.sub', :minor_sc, false);
select public.save_signup_profile('student', (current_date - interval '12 years')::date);
select pg_temp.ok(public.my_guardian_consent_pending(), 'menor antes de entrar na escola fica pendente');
select * from public.redeem_school_invite((select v from t where k='inv_student'));
select pg_temp.ok(not public.my_guardian_consent_pending(), 'menor que entra pela escola não precisa do aceite individual');

select set_config('request.jwt.claim.sub', :adult, false);
select public.save_signup_profile('student', (current_date - interval '19 years')::date);
select pg_temp.ok(not public.my_guardian_consent_pending(), 'maior de 18 não precisa de responsável');

select set_config('request.jwt.claim.sub', :legacy, false);
select pg_temp.ok(not public.my_guardian_consent_pending(), 'conta antiga sem cadastro de perfil não é bloqueada');

-- ---------------------------------------------------- 4. equipe de robótica
select set_config('request.jwt.claim.sub', :outsider, false);
select pg_temp.fails(format($s$select * from public.create_school_team(%L, 'Equipe pirata')$s$, (select v from t where k='school')),
  'MM403', 'quem não é da escola não cria equipe');
select set_config('request.jwt.claim.sub', :it, false);
select pg_temp.fails(format($s$select * from public.create_school_team(%L, 'Equipe da TI')$s$, (select v from t where k='school')),
  'MM403', 'TI não cria equipe');

select set_config('request.jwt.claim.sub', :teacher, false);
insert into t select 'team', code from public.create_school_team((select v::uuid from t where k='school'), 'Robôs do Norte', 'obr');
select pg_temp.ok((select count(*) from public.school_teams) = 1, 'professor vê a equipe que criou');

select set_config('request.jwt.claim.sub', :adult, false);
select public.save_signup_profile('student_team', (current_date - interval '19 years')::date);
select pg_temp.ok((select team_name from public.join_school_team((select v from t where k='team'), 'eletronica')) = 'Robôs do Norte',
  'estudante entra na equipe pelo código com a função');
select * from public.join_school_team((select v from t where k='team'), 'programacao');
select pg_temp.ok((select team_role from public.school_team_members) = 'programacao', 'repetir o código troca a função');
select pg_temp.fails(format($s$select * from public.join_school_team(%L, 'pilotagem')$s$, (select v from t where k='team')),
  '22023', 'função fora da lista é recusada');
select pg_temp.fails($s$select * from public.join_school_team('CODIGOFALSO1', 'mecanica')$s$, 'MM404', 'código de equipe inválido');
select pg_temp.ok((select count(*) from public.school_teams) = 1, 'membro vê a equipe');
select pg_temp.fails('select code_hash from public.school_teams', '42501', 'ninguém lê o hash do código da equipe');

select set_config('request.jwt.claim.sub', :it, false);
select pg_temp.ok((select count(*) from public.school_team_members) = 1, 'TI vê quem está na equipe (sem dado pedagógico)');
select set_config('request.jwt.claim.sub', :outsider, false);
select pg_temp.ok((select count(*) from public.school_teams) = 0
  and (select count(*) from public.school_team_members) = 0, 'quem não é da escola nem da equipe não vê nada');
select pg_temp.fails(format($s$insert into public.school_team_members(team_id,user_id,team_role)
  select id, auth.uid(), 'mecanica' from public.school_teams$s$), '42501', 'cliente não entra na equipe direto');

select set_config('request.jwt.claim.sub', :adult, false);
select public.leave_school_team((select id from public.school_teams));
select pg_temp.ok((select count(*) from public.school_teams) = 0, 'quem saiu da equipe deixa de vê-la');

reset role;
