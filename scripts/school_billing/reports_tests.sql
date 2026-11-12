-- Casos dos relatórios da escola (migration 20261112210000), depois de
-- tests.sql no mesmo banco. Só agregados: nada por aluno.
\set owner_r '''c0000000-0000-4000-8000-000000000001'''
\set coord_r '''c0000000-0000-4000-8000-000000000002'''
\set fin_r   '''c0000000-0000-4000-8000-000000000003'''
\set it_r    '''c0000000-0000-4000-8000-000000000004'''
\set outro   '''c0000000-0000-4000-8000-000000000005'''

insert into auth.users(id, email) values
  (:owner_r, 'dono@r.dev'), (:coord_r, 'coord@r.dev'), (:fin_r, 'compras@r.dev'),
  (:it_r, 'ti@r.dev'), (:outro, 'outro@r.dev');
insert into auth.users(id, email)
select ('c1000000-0000-4000-8000-00000000000' || k)::uuid, 'aluno' || k || '@r.dev'
from generate_series(1, 6) k;

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
create function pg_temp.as_user(u uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u::text, false);
$$;

-- ------------------------------------------------------------- montagem
set role authenticated;
select pg_temp.as_user(:owner_r);
insert into t values ('s', public.create_school('Escola Relatórios (teste)')::text);
reset role;
update public.schools set plan = 'escola', billing_cycle = 'monthly' where id = (select v::uuid from t where k = 's');
set role authenticated;
select pg_temp.as_user(:owner_r);
insert into t select 'inv_coord', code from public.create_school_invite((select v::uuid from t where k = 's'), 'coordinator');
insert into t select 'inv_it', code from public.create_school_invite((select v::uuid from t where k = 's'), 'it_admin');
insert into t select 'inv_fin', code from public.create_school_invite((select v::uuid from t where k = 's'), 'finance', 'compras@r.dev');
insert into t select 'inv_st', code from public.create_school_invite((select v::uuid from t where k = 's'), 'student', null, 10, 7);
select pg_temp.as_user(:coord_r);
select * from public.redeem_school_invite((select v from t where k = 'inv_coord'));
select pg_temp.as_user(:it_r);
select * from public.redeem_school_invite((select v from t where k = 'inv_it'));
select pg_temp.as_user(:fin_r);
select * from public.redeem_school_invite((select v from t where k = 'inv_fin'));
select pg_temp.as_user(('c1000000-0000-4000-8000-00000000000' || k)::uuid),
       public.redeem_school_invite((select v from t where k = 'inv_st'))
from generate_series(1, 4) k;
reset role;

-- Turma da escola com 3 alunos.
insert into public.platform_classes(id, teacher_id, title, school_id)
values ('c2000000-0000-4000-8000-000000000001', :owner_r, 'Robótica — 2º ano', (select v::uuid from t where k = 's'));
insert into public.platform_memberships(class_id, user_id)
select 'c2000000-0000-4000-8000-000000000001', ('c1000000-0000-4000-8000-00000000000' || k)::uuid
from generate_series(1, 3) k;

-- Erros: cada aluno erra "Lei de Ohm" (cálculo); 3 deles também "Divisor de
-- tensão" (sinal).
create function pg_temp.erra(u uuid, conceito text, tipo text) returns void language plpgsql as $$
declare v_sub uuid; v_con uuid; v_ex uuid; v_at uuid;
begin
  insert into public.subjects(user_id, name) values (u, 'Eletrônica') returning id into v_sub;
  insert into public.concepts(subject_id, name) values (v_sub, conceito) returning id into v_con;
  insert into public.exercises(subject_id, prompt_text) values (v_sub, 'Exercício') returning id into v_ex;
  insert into public.attempts(exercise_id, user_id) values (v_ex, u) returning id into v_at;
  insert into public.error_events(attempt_id, concept_id, error_type_id)
  values (v_at, v_con, (select id from public.error_types where name = tipo));
end $$;
select pg_temp.erra(('c1000000-0000-4000-8000-00000000000' || k)::uuid, 'Lei de Ohm', 'calculo')
from generate_series(1, 4) k;
select pg_temp.erra(('c1000000-0000-4000-8000-00000000000' || k)::uuid, ' divisor de tensão', 'sinal')
from generate_series(1, 3) k;

-- Uso e faturas.
insert into public.school_usage_months(school_id, month, plan, active_students, analyses, practices)
values ((select v::uuid from t where k = 's'), (public.school_usage_month() - interval '1 month')::date, 'escola', 50, 900, 120)
on conflict (school_id, month) do update set active_students = 50, analyses = 900, practices = 120;
insert into public.school_invoices(school_id, kind, reference_month, plan, cycle, students,
  price_per_student, gross, total, method, status, due_date, paid_at)
values
  ((select v::uuid from t where k = 's'), 'monthly', (public.school_usage_month() - interval '1 month')::date,
   'escola', 'monthly', 50, 12, 600, 600, 'pix', 'paid', current_date, now()),
  ((select v::uuid from t where k = 's'), 'checkout', public.school_usage_month(),
   'escola', 'monthly', 40, 12, 480, 480, 'boleto', 'pending', current_date + 5, null);

-- ------------------------------------------------------------- permissões
set role authenticated;
select pg_temp.as_user(:owner_r);
insert into t values ('r_owner', public.school_reports((select v::uuid from t where k = 's'))::text);
select pg_temp.ok((select (v::jsonb->'pedagogical') is not null and (v::jsonb->'financial') is not null
  from t where k = 'r_owner'), 'dono vê relatório pedagógico e financeiro');
select pg_temp.as_user(:coord_r);
insert into t values ('r_coord', public.school_reports((select v::uuid from t where k = 's'))::text);
select pg_temp.ok((select v::jsonb->'financial' = 'null'::jsonb and v::jsonb->'pedagogical' <> 'null'::jsonb
  from t where k = 'r_coord'), 'coordenação vê só o pedagógico');
select pg_temp.as_user(:fin_r);
insert into t values ('r_fin', public.school_reports((select v::uuid from t where k = 's'))::text);
select pg_temp.ok((select v::jsonb->'pedagogical' = 'null'::jsonb and v::jsonb->'financial' <> 'null'::jsonb
  from t where k = 'r_fin'), 'financeiro vê só o financeiro');
select pg_temp.as_user(:it_r);
select pg_temp.fails($$select public.school_reports((select v::uuid from t where k = 's'))$$, '42501',
  'TI não vê relatórios');
select pg_temp.as_user(:outro);
select pg_temp.fails($$select public.school_reports((select v::uuid from t where k = 's'))$$, '42501',
  'quem é de fora não vê relatórios');
select pg_temp.as_user('c1000000-0000-4000-8000-000000000001');
select pg_temp.fails($$select public.school_reports((select v::uuid from t where k = 's'))$$, '42501',
  'aluno não vê relatórios');
reset role;

-- ------------------------------------------------------------- pedagógico
select pg_temp.ok((select (v::jsonb#>>'{pedagogical,error_students}')::int = 4 from t where k = 'r_owner'),
  'conta 4 alunos com erro');
select pg_temp.ok((select v::jsonb#>'{pedagogical,errors_by_type}' = '[]'::jsonb from t where k = 'r_owner'),
  'mapa de erros escondido com menos de 5 alunos');
select pg_temp.ok((select jsonb_array_length(v::jsonb#>'{pedagogical,classes}') = 1
    and (v::jsonb#>>'{pedagogical,classes,0,students}')::int = 3
    and (v::jsonb#>>'{pedagogical,classes,0,active_28d}')::int = 3
  from t where k = 'r_owner'), 'turma com 3 alunos, 3 ativos em 28 dias');
select pg_temp.ok((select v::jsonb#>'{pedagogical,usage}' @> '[{"active_students": 50, "practices": 120}]'
  from t where k = 'r_owner'), 'uso do mês no relatório');

-- Quinto aluno: o mapa aparece, mas só conceito com 3+ alunos.
set role authenticated;
select pg_temp.as_user('c1000000-0000-4000-8000-000000000005');
select * from public.redeem_school_invite((select v from t where k = 'inv_st'));
reset role;
select pg_temp.erra('c1000000-0000-4000-8000-000000000005', 'Lei de Ohm', 'conceito');
select pg_temp.erra('c1000000-0000-4000-8000-000000000005', 'Potência', 'calculo');
set role authenticated;
select pg_temp.as_user(:coord_r);
insert into t values ('r5', public.school_reports((select v::uuid from t where k = 's'))::text);
reset role;
select pg_temp.ok((select v::jsonb#>'{pedagogical,errors_by_type}'
    @> '[{"error_type": "calculo", "errors": 5, "students": 5}, {"error_type": "sinal", "errors": 3, "students": 3}]'
  from t where k = 'r5'), 'com 5 alunos: erros por tipo');
select pg_temp.ok((select jsonb_agg(c->>'concept' order by c->>'concept')
    = '["divisor de tensão", "lei de ohm"]'::jsonb
  from t, jsonb_array_elements(v::jsonb#>'{pedagogical,concepts}') c where k = 'r5'),
  'conceito com menos de 3 alunos (Potência) fica de fora; nomes juntam caixa e espaços');
select pg_temp.ok((select c->'by_type' = '{"calculo": 4, "conceito": 1}'::jsonb
  from t, jsonb_array_elements(v::jsonb#>'{pedagogical,concepts}') c
  where k = 'r5' and c->>'concept' = 'lei de ohm'), 'mapa conceito × tipo de erro');
select pg_temp.ok((select position('c1000000' in v) = 0 and position('@r.dev' in v) = 0 from t where k = 'r5'),
  'nenhum id ou e-mail de aluno no relatório');

-- ------------------------------------------------------------- financeiro
select pg_temp.ok((select v::jsonb#>'{financial,by_method}' = '[{"method": "pix", "count": 1, "total": 600.00}]'::jsonb
  from t where k = 'r_fin'), 'forma de pagamento conta só o que foi pago');
select pg_temp.ok((select v::jsonb#>'{financial,by_status}'
    @> '[{"status": "paid", "count": 1}, {"status": "pending", "count": 1}]'
  from t where k = 'r_fin'), 'faturas por situação');
select pg_temp.ok((select v::jsonb#>'{financial,invoices_by_month}'
    @> '[{"paid": 600.00, "open": 0}, {"paid": 0, "open": 480.00}]'
  from t where k = 'r_fin'), 'pago e em aberto por mês');
select pg_temp.ok((select v::jsonb#>'{financial,cost_by_month}' @> '[{"active_students": 50, "total": 600.00}]'
  from t where k = 'r_fin'), 'custo pelo uso usa a fórmula da fatura (50 × R$ 12)');
select pg_temp.ok((select jsonb_array_length(v::jsonb#>'{financial,invoices}') = 2
    and (v::jsonb#>>'{financial,sample}')::boolean = false
  from t where k = 'r_fin'), 'lista de faturas reais, sem amostra');

-- ------------------------------------------------------- amostra de demonstração
-- Amostra só vale para escola com demo = true; escola real nunca a lê.
insert into public.school_demo_report(school_id, payload)
values ((select v::uuid from t where k = 's'), '{"by_method": [{"method": "boleto", "count": 99, "total": 1}]}');
set role authenticated;
select pg_temp.as_user(:owner_r);
select pg_temp.ok((public.school_reports((select v::uuid from t where k = 's'))#>'{financial,by_method}')
  = '[{"method": "pix", "count": 1, "total": 600.00}]'::jsonb, 'escola real ignora a amostra');
select pg_temp.as_user(null);
select pg_temp.fails($$select public.school_reports((select v::uuid from t where k = 's'))$$, '42501',
  'sem login não há relatório');
reset role;
