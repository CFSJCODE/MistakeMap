-- Casos das funções da TI da escola (migration 20261113180000).
-- Trechos com "set role authenticated" imitam a Edge Function school-admin
-- (role authenticated + sub do JWT); o resto roda como o backend.
\set owner '''c0000000-0000-4000-8000-000000000001'''
\set ti    '''c0000000-0000-4000-8000-000000000002'''
\set coord '''c0000000-0000-4000-8000-000000000003'''
\set fin   '''c0000000-0000-4000-8000-000000000004'''
\set prof  '''c0000000-0000-4000-8000-000000000005'''
\set al1   '''c0000000-0000-4000-8000-000000000006'''
\set al2   '''c0000000-0000-4000-8000-000000000007'''
\set dev   '''c0000000-0000-4000-8000-000000000008'''
\set fora  '''c0000000-0000-4000-8000-000000000009'''
\set ti2   '''c0000000-0000-4000-8000-00000000000a'''

insert into auth.users(id, email, raw_user_meta_data, last_sign_in_at) values
  (:owner, 'dono@c.dev', '{"full_name":"Dona C"}', now()),
  (:ti, 'ti@c.dev', null, now()), (:coord, 'coord@c.dev', null, null),
  (:fin, 'fin@c.dev', null, null), (:prof, 'prof@c.dev', '{"name":"Prof C"}', now()),
  (:al1, 'al1@c.dev', null, now()), (:al2, 'al2@c.dev', null, null),
  (:dev, 'dev@c.dev', null, null), (:fora, 'fora@c.dev', null, null),
  (:ti2, 'ti2@c.dev', null, null);
insert into public.profiles(id, role) values (:dev, 'developer') on conflict (id) do update set role = excluded.role;
insert into auth.sessions(user_id, user_agent, ip) values
  (:al1, 'Mozilla/5.0 (Linux; Android 15)', '177.10.20.30'),
  (:al1, 'Dart/3.9 (dart:io)', '2804:14c:abcd::1'),
  (:prof, 'Mozilla/5.0 (Windows NT 10.0)', '10.0.0.5');

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
create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u, false) $$;
create function pg_temp.join(u text, r text) returns void language plpgsql as $$
declare c text;
begin
  perform pg_temp.as_user((select v from t where k = 'owner'));
  select code into c from public.create_school_invite((select v::uuid from t where k='school'), r, null, 1, 7);
  perform pg_temp.as_user(u);
  perform public.redeem_school_invite(c);
end $$;
insert into t values ('owner', :owner);

-- ------------------------------------------------------------- 1. montagem
set role authenticated;
select pg_temp.as_user(:owner);
insert into t values ('school', public.create_school('Escola C (teste)')::text);
reset role;
update public.schools set plan = 'escola' where id = (select v::uuid from t where k='school');
set role authenticated;
select pg_temp.join(:ti, 'it_admin');
select pg_temp.join(:coord, 'coordinator');
select pg_temp.join(:fin, 'finance');
select pg_temp.join(:prof, 'teacher');
select pg_temp.join(:al1, 'student');
select pg_temp.join(:al2, 'student');
select pg_temp.join(:dev, 'student');
-- O professor também é dono de outra escola (gestão fora daqui).
select pg_temp.as_user(:prof);
insert into t values ('school2', public.create_school('Escola do Prof (teste)')::text);
-- Uma segunda escola, onde a TI de cá não manda.
select pg_temp.as_user(:fora);
insert into t values ('school3', public.create_school('Escola de Fora (teste)')::text);
reset role;

select pg_temp.ok((select count(*) from public.school_audit_log a
                   where a.school_id = (select v::uuid from t where k='school')
                     and a.action = 'member_joined') = 8,
  'cada entrada na escola gravou member_joined (dono + 7)');
select pg_temp.ok((select count(*) from public.school_audit_log a
                   where a.school_id = (select v::uuid from t where k='school')
                     and a.action = 'invite_created') = 7,
  'cada convite gravou invite_created');

-- ------------------------------------------------------------- 2. diretório
set role authenticated;
select pg_temp.as_user(:ti);
insert into t select 'dir', public.school_it_directory((select v::uuid from t where k='school'))::text;
select pg_temp.ok(jsonb_array_length((select v::jsonb->'people' from t where k='dir')) = 8,
  'TI vê as 8 pessoas da escola');
select pg_temp.ok((select p->>'name' from jsonb_array_elements((select v::jsonb->'people' from t where k='dir')) p
                   where p->>'email' = 'prof@c.dev') = 'Prof C', 'nome vem do cadastro');
select pg_temp.ok((select (p->>'sessions')::int from jsonb_array_elements((select v::jsonb->'people' from t where k='dir')) p
                   where p->>'email' = 'al1@c.dev') = 2, 'conta as sessões abertas');
select pg_temp.ok((select (p->>'account_manageable')::boolean from jsonb_array_elements((select v::jsonb->'people' from t where k='dir')) p
                   where p->>'email' = 'al1@c.dev'), 'aluno: TI administra a conta');
select pg_temp.ok(not (select (p->>'account_manageable')::boolean from jsonb_array_elements((select v::jsonb->'people' from t where k='dir')) p
                   where p->>'email' = 'prof@c.dev'), 'professor dono de outra escola: TI não mexe na conta');
select pg_temp.ok(not (select (p->>'account_manageable')::boolean from jsonb_array_elements((select v::jsonb->'people' from t where k='dir')) p
                   where p->>'email' = 'dev@c.dev'), 'equipe MistakeMap: TI não mexe na conta');
select pg_temp.ok(not (select (p->>'account_manageable')::boolean from jsonb_array_elements((select v::jsonb->'people' from t where k='dir')) p
                   where p->>'email' = 'coord@c.dev'), 'coordenação: só o dono administra');
select pg_temp.ok(not (select v::jsonb::text from t where k='dir') ~ 'attempt|analysis|invoice|total',
  'diretório não traz dado pedagógico nem financeiro');
select pg_temp.as_user(:coord);
select pg_temp.fails($$select public.school_it_directory((select v::uuid from t where k='school'))$$, 'MM403', 'coordenação não abre o diretório da TI');
select pg_temp.as_user(:al1);
select pg_temp.fails($$select public.school_it_directory((select v::uuid from t where k='school'))$$, 'MM403', 'aluno não abre o diretório');
select pg_temp.as_user(:ti);
select pg_temp.fails($$select public.school_it_directory((select v::uuid from t where k='school3'))$$, 'MM403', 'TI não abre escola alheia');

-- ------------------------------------------------------------- 3. sessões
insert into t select 'sess', public.school_member_sessions((select v::uuid from t where k='school'), :al1)::text;
select pg_temp.ok(jsonb_array_length((select v::jsonb->'sessions' from t where k='sess')) = 2, 'lista os aparelhos do aluno');
select pg_temp.ok((select v from t where k='sess') like '%177.10.x.x%'
                  and (select v from t where k='sess') not like '%177.10.20.30%', 'IP aparece só pela metade');
select pg_temp.fails($$select public.school_member_sessions((select v::uuid from t where k='school'), 'c0000000-0000-4000-8000-000000000005')$$,
  'MM403', 'TI não vê aparelhos do professor que é dono em outra escola');
select pg_temp.ok(public.revoke_school_member_sessions((select v::uuid from t where k='school'), :al1) = 2,
  'TI encerra as 2 sessões do aluno');
reset role;
select pg_temp.ok((select count(*) from auth.sessions where user_id = :al1) = 0, 'sessões apagadas no Auth');
select pg_temp.ok((select count(*) from auth.sessions where user_id = :prof) = 1, 'sessões de outros intactas');
set role authenticated;
select pg_temp.as_user(:ti);
select pg_temp.fails($$select public.revoke_school_member_sessions((select v::uuid from t where k='school'), 'c0000000-0000-4000-8000-000000000002')$$,
  'MM403', 'ninguém age na própria conta');
select pg_temp.fails($$select public.revoke_school_member_sessions((select v::uuid from t where k='school'), 'c0000000-0000-4000-8000-000000000008')$$,
  'MM403', 'TI não derruba conta da equipe MistakeMap');

-- ------------------------------------------------------------- 4. senha
select pg_temp.ok(public.school_member_password_reset((select v::uuid from t where k='school'), :al2) = 'al2@c.dev',
  'pedido de redefinição devolve o e-mail para a Edge Function');
select pg_temp.ok((select count(*) from public.school_audit_log where action = 'password_reset_sent') = 0,
  'conferir não registra envio (só depois que o Auth aceita)');
select public.school_member_password_reset_sent((select v::uuid from t where k='school'), :al2);
select pg_temp.fails($$select public.school_member_password_reset((select v::uuid from t where k='school'), 'c0000000-0000-4000-8000-000000000007')$$,
  'MM429', 'segundo pedido em 10 minutos é recusado');
select pg_temp.fails($$select public.school_member_password_reset((select v::uuid from t where k='school'), 'c0000000-0000-4000-8000-000000000001')$$,
  'MM403', 'TI não redefine a senha do dono');

-- ------------------------------------------------------------- 5. suspender
select public.set_school_member_status((select v::uuid from t where k='school'), :al2, 'student', 'suspended');
reset role;
select pg_temp.ok((select status from public.school_members where user_id = :al2 and school_id = (select v::uuid from t where k='school')) = 'suspended',
  'TI suspende aluno');
set role authenticated;
select pg_temp.as_user(:al2);
select pg_temp.ok(not public.is_school_member((select v::uuid from t where k='school')), 'aluno suspenso perde o acesso à escola');
select pg_temp.as_user(:ti);
select public.set_school_member_status((select v::uuid from t where k='school'), :al2, 'student', 'active');
select pg_temp.fails($$select public.set_school_member_status((select v::uuid from t where k='school'), 'c0000000-0000-4000-8000-000000000003', 'coordinator', 'suspended')$$,
  'MM403', 'TI não suspende coordenação');
select pg_temp.fails($$select public.set_school_member_status((select v::uuid from t where k='school'), 'c0000000-0000-4000-8000-000000000001', 'owner', 'suspended')$$,
  'MM403', 'ninguém suspende o dono');
select pg_temp.fails($$select public.set_school_member_status((select v::uuid from t where k='school'), 'c0000000-0000-4000-8000-000000000007', 'student', 'banido')$$,
  '22023', 'situação inválida recusada');
select pg_temp.as_user(:owner);
select public.set_school_member_status((select v::uuid from t where k='school'), :coord, 'coordinator', 'suspended');
select public.set_school_member_status((select v::uuid from t where k='school'), :coord, 'coordinator', 'active');
select pg_temp.as_user(:coord);
select pg_temp.ok(public.is_school_member((select v::uuid from t where k='school')), 'dono suspende e reativa a coordenação');
select pg_temp.fails($$select public.set_school_member_status((select v::uuid from t where k='school'), 'c0000000-0000-4000-8000-000000000007', 'student', 'suspended')$$,
  'MM403', 'coordenação não usa as funções da TI');

-- Professor suspenso perde a turma da escola; turma sem escola continua dele.
reset role;
with x as (insert into public.platform_classes(teacher_id, title, school_id)
  values (:prof, 'Turma da escola', (select v::uuid from t where k='school')) returning id)
insert into t select 'class_school', id::text from x;
with x as (insert into public.platform_classes(teacher_id, title)
  values (:prof, 'Turma particular') returning id)
insert into t select 'class_free', id::text from x;
set role authenticated;
select pg_temp.as_user(:prof);
select pg_temp.ok(public.platform_owns_class((select v::uuid from t where k='class_school')), 'professor ativo é dono da turma da escola');
select pg_temp.as_user(:ti);
select public.set_school_member_status((select v::uuid from t where k='school'), :prof, 'teacher', 'suspended');
select pg_temp.as_user(:prof);
select pg_temp.ok(not public.platform_owns_class((select v::uuid from t where k='class_school')), 'professor suspenso perde a turma da escola');
select pg_temp.ok(public.platform_owns_class((select v::uuid from t where k='class_free')), 'turma sem escola continua do professor');
select pg_temp.as_user(:ti);
select public.set_school_member_status((select v::uuid from t where k='school'), :prof, 'teacher', 'active');
select pg_temp.as_user(:prof);
select pg_temp.ok(public.platform_owns_class((select v::uuid from t where k='class_school')), 'reativado, recupera a turma');
select pg_temp.as_user(:ti);

-- ------------------------------------------------------------- 6. remover
select pg_temp.as_user(:ti);
select public.remove_school_member((select v::uuid from t where k='school'), :dev, 'student');
select pg_temp.fails($$select public.remove_school_member((select v::uuid from t where k='school'), 'c0000000-0000-4000-8000-000000000008', 'student')$$,
  'MM404', 'remover de novo: não encontrado');

-- ------------------------------------------------------------- 7. lote
insert into t select 'batch', public.create_school_invites_batch((select v::uuid from t where k='school'),
  '[{"email":"Novo1@C.dev","role":"student"},{"email":"novo1@c.dev","role":"student"},
    {"email":"novo2@c.dev","role":"teacher"},{"email":"al1@c.dev","role":"student"},
    {"email":"ruim","role":"student"},{"email":"x@c.dev","role":"coordinator"}]'::jsonb)::text;
select pg_temp.ok((select (v::jsonb->>'created')::int from t where k='batch') = 2, 'lote cria 2 convites');
select pg_temp.ok((select string_agg(r->>'status', ',') from jsonb_array_elements((select v::jsonb->'rows' from t where k='batch')) r)
  = 'created,duplicate,created,already_member,invalid_email,invalid_role', 'lote explica cada linha');
select pg_temp.ok((select count(*) from jsonb_array_elements((select v::jsonb->'rows' from t where k='batch')) r
                   where r->>'code' ~ '^[0-9A-F]{12}$') = 2, 'códigos aparecem uma vez no retorno');
reset role;
select pg_temp.ok((select count(*) from public.school_invites where email = 'novo1@c.dev' and max_uses = 1) = 1, 'convite pessoal preso ao e-mail');
set role authenticated;
select pg_temp.as_user(:ti);
select pg_temp.fails($$select public.create_school_invites_batch((select v::uuid from t where k='school'), '[]'::jsonb)$$,
  '22023', 'lote vazio recusado');
select pg_temp.as_user(:al1);
select pg_temp.fails($$select public.create_school_invites_batch((select v::uuid from t where k='school'), '[{"email":"a@b.dev","role":"student"}]'::jsonb)$$,
  'MM403', 'aluno não importa convites');

-- ------------------------------------------------------------- 8. renovar
select pg_temp.as_user(:ti);
insert into t select 'renew_old', id::text from public.school_invites where email = 'novo2@c.dev';
insert into t select 'renew', code from public.renew_school_invite((select v::uuid from t where k='renew_old'));
reset role;
select pg_temp.ok((select revoked_at is not null from public.school_invites where id = (select v::uuid from t where k='renew_old')),
  'renovar revoga o convite antigo');
select pg_temp.ok((select count(*) from public.school_invites where email = 'novo2@c.dev' and revoked_at is null) = 1,
  'renovar cria um convite novo para o mesmo e-mail');
set role authenticated;
select pg_temp.fails($$select * from public.renew_school_invite((select v::uuid from t where k='renew_old'))$$,
  'MM409', 'convite já renovado não gera segundo código');
insert into t select 'multi', code from public.create_school_invite((select v::uuid from t where k='school'), 'student', null, 30, 7);

-- ------------------------------------------------------------- 9. licenças
insert into t select 'lic', public.school_it_licenses((select v::uuid from t where k='school'))::text;
select pg_temp.ok((select (v::jsonb->>'users_active')::int from t where k='lic') = 7, 'licenças: 7 usuários ativos');
select pg_temp.ok((select (v::jsonb->>'open_invites')::int from t where k='lic') = 3, 'licenças: 3 convites em aberto');
select pg_temp.ok((select (v::jsonb->>'open_invite_seats')::int from t where k='lic') = 32, 'licenças: convites deixam entrar 32 pessoas');
select pg_temp.ok((select v::jsonb->>'plan' from t where k='lic') = 'escola', 'licenças: plano');
select pg_temp.ok(not (select v from t where k='lic') ~ 'brl|price|total', 'licenças sem valor em reais');
select pg_temp.as_user(:prof);
select pg_temp.fails($$select public.school_it_licenses((select v::uuid from t where k='school'))$$, 'MM403', 'professor não vê licenças');

-- ------------------------------------------------------------- 10. auditoria
select pg_temp.as_user(:ti);
insert into t select 'audit', public.school_audit((select v::uuid from t where k='school'), 200)::text;
select pg_temp.ok((select string_agg(distinct e->>'action', ',' order by e->>'action')
                   from jsonb_array_elements((select v::jsonb->'entries' from t where k='audit')) e)
  = 'invite_created,invite_renewed,invite_revoked,invites_imported,member_joined,member_reactivated,member_removed,member_suspended,password_reset_sent,sessions_revoked',
  'auditoria registra todas as ações');
select pg_temp.ok((select e->>'actor_email' from jsonb_array_elements((select v::jsonb->'entries' from t where k='audit')) e
                   where e->>'action' = 'sessions_revoked') = 'ti@c.dev', 'auditoria mostra quem fez');
select pg_temp.ok((select count(*) from public.school_audit_log) > 0
                  and (select count(*) from public.school_audit_log where school_id <> (select v::uuid from t where k='school')) = 0,
  'RLS: TI lê só a auditoria da própria escola');
select pg_temp.fails($$insert into public.school_audit_log(school_id, action) values ((select v::uuid from t where k='school'), 'member_joined')$$,
  '42501', 'app não escreve na auditoria');
select pg_temp.as_user(:coord);
select pg_temp.ok((select count(*) from public.school_audit_log) = 0, 'coordenação não lê a auditoria');
reset role;

-- ------------------------------------------------------------- 11. exclusões
delete from auth.users where id = :al2;
select pg_temp.ok(true, 'apagar conta de aluno não trava na auditoria');
delete from public.schools where id = (select v::uuid from t where k='school3');
select pg_temp.ok(true, 'apagar escola não trava na auditoria');

-- Escola demo para o seed da TI (mesmo nome da produção).
insert into auth.users(id, email) values
  ('d1000000-0000-4000-8000-000000000001', 'ti.nexo.demo@mistakemap.dev'),
  ('d1000000-0000-4000-8000-000000000002', 'aluno04.nexo.demo@mistakemap.dev');
insert into public.schools(id, name, plan, created_by) values
  ('d1000000-0000-4000-8000-0000000000aa', 'Colégio Nexo — Unidade Centro (demonstração)', 'plus', :owner);
