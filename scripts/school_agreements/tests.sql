-- Casos do contrato e LGPD da escola (migration 20261111074500).
-- Cada trecho roda como um usuário: role authenticated + request.jwt.claim.sub,
-- como o PostgREST faz no Supabase.
\set owner_a   '''a0000000-0000-4000-8000-000000000001'''
\set it_a      '''a0000000-0000-4000-8000-000000000002'''
\set coord_a   '''a0000000-0000-4000-8000-000000000003'''
\set teacher_a '''a0000000-0000-4000-8000-000000000004'''
\set student_a '''a0000000-0000-4000-8000-000000000005'''
\set owner_b   '''b0000000-0000-4000-8000-000000000001'''
\set outsider  '''c0000000-0000-4000-8000-000000000001'''
\set admin     '''e0000000-0000-4000-8000-000000000001'''

insert into auth.users(id, email) values
  (:owner_a, 'Dono@Escola-A.dev'), (:it_a, 'ti@escola-a.dev'),
  (:coord_a, 'coord@escola-a.dev'), (:teacher_a, 'prof@escola-a.dev'),
  (:student_a, 'aluno@escola-a.dev'), (:owner_b, 'dono@escola-b.dev'),
  (:outsider, 'intruso@fora.dev'), (:admin, 'admin@mistakemap.dev');

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

-- Documentos que a tela mostrou, no formato que o app envia.
create function pg_temp.shown() returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('document', document, 'version', version, 'sha256', sha256))
  from public.current_legal_documents() $$;
grant execute on function pg_temp.shown() to authenticated;

-- ------------------------------------------- 1. textos versionados no repo
set role authenticated;
select set_config('request.jwt.claim.sub', :outsider, false);
select pg_temp.ok((select count(*) from public.current_legal_documents()) = 3, 'há 3 documentos vigentes');
select pg_temp.ok((select sha256 from public.legal_document_versions where document='termos-de-uso' and version='1.0') = :sha_termos,
  'Termos de Uso 1.0 no banco = arquivo do repo');
select pg_temp.ok((select sha256 from public.legal_document_versions where document='contrato-saas' and version='1.0') = :sha_contrato,
  'Contrato SaaS 1.0 no banco = arquivo do repo');
select pg_temp.ok((select sha256 from public.legal_document_versions where document='acordo-tratamento-dados' and version='1.0') = :sha_dpa,
  'Acordo de Tratamento de Dados 1.0 no banco = arquivo do repo');
select pg_temp.ok((select title from public.legal_document_versions where document='acordo-tratamento-dados') like 'Acordo de Tratamento%',
  'título vem do cabeçalho do texto');
select pg_temp.fails($s$insert into public.legal_document_versions(document,version,title,body,sha256,effective_at)
  values ('termos-de-uso','9.9','Falso',repeat('x',200),repeat('0',64),now())$s$, '42501', 'cliente não publica texto legal');

-- ----------------------------- 2. escola nova fica bloqueada até o aceite
select set_config('request.jwt.claim.sub', :owner_a, false);
insert into t values ('school_a', public.create_school('Escola de Robótica A')::text);
select pg_temp.ok(not public.school_is_usable((select v::uuid from t where k='school_a')), 'escola nova começa bloqueada');
select pg_temp.ok((select count(*) from public.school_agreement_status((select v::uuid from t where k='school_a'))
                   where accepted_at is null and body is not null) = 3, 'dono vê os 3 textos pendentes');
select pg_temp.fails(format($s$select * from public.create_school_invite(%L,'teacher')$s$, (select v from t where k='school_a')),
  'MM428', 'sem aceite, a escola não cria convite');

select set_config('request.jwt.claim.sub', :outsider, false);
select pg_temp.fails(format($s$select * from public.school_agreement_status(%L)$s$, (select v from t where k='school_a')),
  'MM403', 'quem não é da escola não lê a situação do contrato');
select pg_temp.fails(format($s$select public.accept_school_agreements(%L, pg_temp.shown(), 'Intruso da Silva', 'Diretor')$s$,
  (select v from t where k='school_a')), 'MM403', 'quem não é dono não aceita');

select set_config('request.jwt.claim.sub', :owner_a, false);
select pg_temp.fails(format($s$select public.accept_school_agreements(%L, pg_temp.shown(), '', 'Diretora')$s$,
  (select v from t where k='school_a')), '22023', 'aceite exige o nome de quem assina');
select pg_temp.fails(format($s$select public.accept_school_agreements(%L,
    (select jsonb_agg(e || jsonb_build_object('sha256', repeat('0',64))) from jsonb_array_elements(pg_temp.shown()) e),
    'Ana Diretora', 'Diretora')$s$, (select v from t where k='school_a')),
  'MM409', 'texto diferente do vigente é recusado');
select pg_temp.fails(format($s$select public.accept_school_agreements(%L,
    (select jsonb_agg(e) from jsonb_array_elements(pg_temp.shown()) e where e->>'document' <> 'acordo-tratamento-dados'),
    'Ana Diretora', 'Diretora')$s$, (select v from t where k='school_a')),
  'MM409', 'faltando o acordo de dados, o aceite é recusado');
select pg_temp.ok(not public.school_is_usable((select v::uuid from t where k='school_a')), 'tentativas recusadas não liberam a escola');

-- ------------------------------------------------ 3. aceite libera a escola
select pg_temp.ok(public.accept_school_agreements((select v::uuid from t where k='school_a'), pg_temp.shown(),
  '  Ana Diretora  ', 'Diretora'), 'dono aceita os 3 documentos e a escola é liberada');
select pg_temp.ok(public.accept_school_agreements((select v::uuid from t where k='school_a'), pg_temp.shown(),
  'Ana Diretora', 'Diretora'), 'repetir o aceite não duplica nem dá erro');
select pg_temp.ok((select count(*) from public.school_agreements) = 3, 'ficam 3 aceites gravados');
select pg_temp.ok((select bool_and(signer_name = 'Ana Diretora' and signer_email = 'dono@escola-a.dev'
                                   and accepted_by = :owner_a and accepted_at is not null)
                   from public.school_agreements), 'aceite guarda quem assinou, e-mail, conta e data');
select pg_temp.ok((select count(*) from public.school_agreement_status((select v::uuid from t where k='school_a'))
                   where accepted_at is not null and version = '1.0') = 3, 'situação mostra versão e data do aceite');

insert into t select 'inv_coord', code from public.create_school_invite((select v::uuid from t where k='school_a'), 'coordinator');
insert into t select 'inv_it', code from public.create_school_invite((select v::uuid from t where k='school_a'), 'it_admin');
insert into t select 'inv_teacher', code from public.create_school_invite((select v::uuid from t where k='school_a'), 'teacher');
insert into t select 'inv_student', code from public.create_school_invite((select v::uuid from t where k='school_a'), 'student', null, 30, 30);
select pg_temp.ok(true, 'com o aceite, o dono cria convites');
select set_config('request.jwt.claim.sub', :coord_a, false);
select * from public.redeem_school_invite((select v from t where k='inv_coord'));
select set_config('request.jwt.claim.sub', :it_a, false);
select * from public.redeem_school_invite((select v from t where k='inv_it'));
select set_config('request.jwt.claim.sub', :teacher_a, false);
select * from public.redeem_school_invite((select v from t where k='inv_teacher'));
select pg_temp.ok(public.is_school_member((select v::uuid from t where k='school_a'), array['teacher']), 'professor entra pelo convite');

-- ------------------------------------- 4. quem vê o contrato (matriz de papéis)
select set_config('request.jwt.claim.sub', :coord_a, false);
select pg_temp.ok((select count(*) from public.school_agreements) = 3, 'coordenador vê os aceites');
select pg_temp.ok((select count(*) from public.school_agreement_status((select v::uuid from t where k='school_a'))) = 3,
  'coordenador vê a situação do contrato');
select pg_temp.fails(format($s$select public.accept_school_agreements(%L, pg_temp.shown(), 'Carla Coord', 'Coordenadora')$s$,
  (select v from t where k='school_a')), 'MM403', 'coordenador não aceita pelo dono');

select set_config('request.jwt.claim.sub', :it_a, false);
select pg_temp.ok((select count(*) from public.school_agreements) = 0, 'TI não vê os aceites');
select pg_temp.fails(format($s$select * from public.school_agreement_status(%L)$s$, (select v from t where k='school_a')),
  'MM403', 'TI não lê a situação do contrato');
select pg_temp.ok(public.school_is_usable((select v::uuid from t where k='school_a')), 'qualquer membro sabe se a escola está liberada');

select set_config('request.jwt.claim.sub', :teacher_a, false);
select pg_temp.ok((select count(*) from public.school_agreements) = 0, 'professor não vê os aceites');

select set_config('request.jwt.claim.sub', :admin, false);
select pg_temp.ok((select count(*) from public.school_agreements) = 3, 'admin do MistakeMap vê os aceites');

select set_config('request.jwt.claim.sub', :owner_a, false);
select pg_temp.fails($s$update public.school_agreements set version = '0.9'$s$, '42501', 'cliente não altera aceite');
select pg_temp.fails(format($s$insert into public.school_agreements(school_id,document,version,sha256,signer_name,signer_role)
  values (%L,'termos-de-uso','1.0',%L,'Falso','Falso')$s$, (select v from t where k='school_a'), :sha_termos),
  '42501', 'cliente não grava aceite direto');

-- ------------------------------------- 5. aceite e texto não mudam depois
reset role;
set role service_role;
select pg_temp.fails($s$update public.school_agreements set signer_name = 'Outra Pessoa'$s$, '42501', 'backend não tem permissão para alterar aceite');
select pg_temp.fails($s$delete from public.school_agreements$s$, '42501', 'backend não tem permissão para apagar aceite');
-- Mesmo com permissão total (dono do banco), o trigger barra.
reset role;
select pg_temp.fails($s$update public.school_agreements set signer_name = 'Outra Pessoa'$s$, 'MM403', 'nem o dono do banco altera aceite');
select pg_temp.fails($s$delete from public.school_agreements$s$, 'MM403', 'nem o dono do banco apaga aceite');
select pg_temp.fails($s$update public.legal_document_versions set body = body || ' ' where version = '1.0'$s$,
  'MM403', 'texto publicado não muda');
select pg_temp.fails($s$delete from public.legal_document_versions where version = '1.0'$s$,
  'MM403', 'texto publicado não é apagado');
set role service_role;
select pg_temp.fails($s$insert into public.legal_document_versions(document,version,title,body,sha256,effective_at)
  values ('termos-de-uso','1.1','Termos',repeat('x',200),repeat('0',64),now())$s$, '22023', 'hash errado é recusado');

-- ----------------------- 6. escola sem aceite não usa turma nem matrícula
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :owner_b, false);
insert into t values ('school_b', public.create_school('Escola de Eletrônica B')::text);
reset role;
set role service_role;
select pg_temp.fails(format($s$insert into public.platform_classes(teacher_id,title,school_id) values (%L,'Eletrônica 9º',%L)$s$,
  :owner_b, (select v from t where k='school_b')), 'MM428', 'escola sem aceite não vincula turma');
insert into public.platform_classes(id, teacher_id, title, school_id)
  values ('f0000000-0000-4000-8000-000000000001', :teacher_a, 'Robótica 8º ano', (select v::uuid from t where k='school_a'));
select pg_temp.ok(true, 'escola com aceite vincula turma');
insert into public.platform_classes(id, teacher_id, title)
  values ('f0000000-0000-4000-8000-000000000002', :owner_b, 'Turma avulsa');
select pg_temp.fails(format($s$update public.platform_classes set school_id = %L where id = 'f0000000-0000-4000-8000-000000000002'$s$,
  (select v from t where k='school_b')), 'MM428', 'turma avulsa não passa para escola sem aceite');
insert into public.platform_memberships(class_id, user_id) values ('f0000000-0000-4000-8000-000000000002', :outsider);
select pg_temp.ok(true, 'turma sem escola continua funcionando como antes');

-- ----------------------------- 7. versão nova bloqueia até o novo aceite
insert into public.legal_document_versions(document, version, title, body, sha256, effective_at)
  select 'termos-de-uso', '1.1', 'Termos de Uso do MistakeMap para Escolas', b,
         encode(sha256(convert_to(b, 'UTF8')), 'hex'), now() - interval '1 second'
  from (select '# Termos de Uso do MistakeMap para Escolas' || chr(10) || repeat('Texto da versão 1.1. ', 20) as b) x;
select pg_temp.ok(not public.school_is_usable((select v::uuid from t where k='school_a')), 'publicar versão nova bloqueia a escola');
select pg_temp.fails(format($s$insert into public.platform_memberships(class_id,user_id) values ('f0000000-0000-4000-8000-000000000001',%L)$s$,
  :student_a), 'MM428', 'escola bloqueada não aceita aluno novo na turma');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :student_a, false);
select pg_temp.fails(format($s$select * from public.redeem_school_invite(%L)$s$, (select v from t where k='inv_student')),
  'MM428', 'escola bloqueada não aceita resgate de convite');
select set_config('request.jwt.claim.sub', :owner_a, false);
select pg_temp.ok((select count(*) from public.school_agreement_status((select v::uuid from t where k='school_a'))
                   where accepted_at is null) = 1
  and (select version from public.school_agreement_status((select v::uuid from t where k='school_a'))
       where document = 'termos-de-uso') = '1.1', 'dono vê só os Termos 1.1 pendentes');
select pg_temp.ok(public.accept_school_agreements((select v::uuid from t where k='school_a'), pg_temp.shown(),
  'Ana Diretora', 'Diretora'), 'novo aceite libera a escola de novo');
select pg_temp.ok((select count(*) from public.school_agreements where document = 'termos-de-uso') = 2,
  'o aceite da versão antiga continua guardado');
select set_config('request.jwt.claim.sub', :student_a, false);
select pg_temp.ok((select role from public.redeem_school_invite((select v from t where k='inv_student'))) = 'student',
  'depois do novo aceite o aluno entra');

-- ------------------- 8. excluir a conta de quem assinou não apaga a prova
reset role;
delete from auth.users where id = :owner_a;
select pg_temp.ok((select count(*) from public.school_agreements where accepted_by is null) = 4
  and (select bool_and(signer_name = 'Ana Diretora') from public.school_agreements
       where school_id = (select v::uuid from t where k='school_a')),
  'conta do dono excluída: aceites ficam com nome e e-mail de quem assinou');
select pg_temp.fails(format($s$delete from public.schools where id = %L$s$, (select v from t where k='school_a')),
  '23503', 'escola com aceite não é apagada (encerrar = status closed)');
