-- Casos da cobrança da escola (migration 20261112170000).
-- Trechos com "set role authenticated" imitam o PostgREST; o resto roda como
-- o backend (Edge Function conectada ao banco).
\set owner_a   '''a0000000-0000-4000-8000-000000000001'''
\set fin_a     '''a0000000-0000-4000-8000-000000000002'''
\set coord_a   '''a0000000-0000-4000-8000-000000000003'''
\set it_a      '''a0000000-0000-4000-8000-000000000004'''
\set s1        '''a0000000-0000-4000-8000-000000000011'''
\set owner_b   '''b0000000-0000-4000-8000-000000000001'''

insert into auth.users(id, email) values
  (:owner_a, 'dono@a.dev'), (:fin_a, 'compras@a.dev'), (:coord_a, 'coord@a.dev'),
  (:it_a, 'ti@a.dev'), (:s1, 's1@a.dev'), (:owner_b, 'dono@b.dev');

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

-- ------------------------------------------------------------- 1. orçamento
select pg_temp.ok((select total from public.school_billing_quote('escola','monthly',5)) = 99.00,
  'escola pequena paga o mínimo de R$ 99');
select pg_temp.ok((select minimum_applied from public.school_billing_quote('escola','monthly',5)),
  'mínimo marcado no orçamento');
select pg_temp.ok((select total from public.school_billing_quote('escola','monthly',50)) = 600.00,
  '50 alunos × R$ 12 = R$ 600');
select pg_temp.ok((select volume_discount_percent from public.school_billing_quote('escola','annual',200)) = 10,
  '101 a 300 alunos: −10%');
-- 1.935 × 9,90 = 19.156,50; −20% = 15.325,20
select pg_temp.ok((select total from public.school_billing_quote('escola','annual',1935)) = 15325.20,
  '1.935 alunos no Escola anual = R$ 15.325,20');
select pg_temp.ok((select total from public.school_billing_quote('plus','monthly',1935, 1000)) = round(16*1935*0.8, 2) + 150.00,
  'Plus com 1.000 análises extras soma R$ 150');
select pg_temp.ok((select total from public.school_billing_quote('free','monthly',4)) = 0,
  'Grátis não cobra');
select pg_temp.fails($$select * from public.school_billing_quote('ouro','monthly',10)$$, '22023', 'plano inválido recusado');

-- ------------------------------------------------- 2. papel Financeiro/Compras
set role authenticated;
select set_config('request.jwt.claim.sub', :owner_a, false);
insert into t values ('school_a', public.create_school('Colégio Nexo (teste)')::text);
insert into t select 'inv_fin', code from public.create_school_invite((select v::uuid from t where k='school_a'), 'finance', 'compras@a.dev');
insert into t select 'inv_coord', code from public.create_school_invite((select v::uuid from t where k='school_a'), 'coordinator');
insert into t select 'inv_it', code from public.create_school_invite((select v::uuid from t where k='school_a'), 'it_admin');
insert into t select 'inv_st', code from public.create_school_invite((select v::uuid from t where k='school_a'), 'student', null, 10, 7);
select pg_temp.fails($$select * from public.create_school_invite((select v::uuid from t where k='school_a'), 'finance', null, 5, 7)$$,
  '23514', 'convite do financeiro é de uso único');

select set_config('request.jwt.claim.sub', :coord_a, false);
select * from public.redeem_school_invite((select v from t where k='inv_coord'));
select pg_temp.fails($$select * from public.create_school_invite((select v::uuid from t where k='school_a'), 'finance')$$,
  'MM403', 'coordenação não convida o financeiro');
select set_config('request.jwt.claim.sub', :it_a, false);
select * from public.redeem_school_invite((select v from t where k='inv_it'));
select set_config('request.jwt.claim.sub', :s1, false);
select * from public.redeem_school_invite((select v from t where k='inv_st'));
select set_config('request.jwt.claim.sub', :fin_a, false);
select * from public.redeem_school_invite((select v from t where k='inv_fin'));
select pg_temp.ok(public.is_school_member((select v::uuid from t where k='school_a'), array['finance']),
  'financeiro entra com o convite');
select public.save_signup_profile('finance');
select pg_temp.ok((select persona from public.user_signups where user_id = :fin_a) = 'finance',
  'perfil Financeiro/Compras no cadastro');

-- --------------------------------------------------------- 3. quem paga
-- Sem configuração, paga o dono.
select pg_temp.ok(not public.school_is_payer((select v::uuid from t where k='school_a')),
  'financeiro não paga enquanto o dono for o pagante');
select pg_temp.fails($$select public.save_school_billing_settings((select v::uuid from t where k='school_a'), 'finance')$$,
  'MM403', 'só o dono troca quem paga');
select set_config('request.jwt.claim.sub', :owner_a, false);
select pg_temp.ok(public.school_is_payer((select v::uuid from t where k='school_a')), 'escola pequena: o dono paga');
select public.save_school_billing_settings((select v::uuid from t where k='school_a'), 'finance', 'boleto', 30,
  'Rede Nexo de Educação Tecnológica', 'Compras@A.dev', 'PC-2026-0042', 'CC-EDU-17');
select pg_temp.ok(not public.school_is_payer((select v::uuid from t where k='school_a')),
  'modelo rede: dono passa a só acompanhar');
select set_config('request.jwt.claim.sub', :fin_a, false);
select pg_temp.ok(public.school_is_payer((select v::uuid from t where k='school_a')), 'financeiro vira o pagante');
select pg_temp.ok((select billing_email from public.school_billing_settings) = 'compras@a.dev',
  'financeiro lê os dados de cobrança (e-mail em minúsculas)');
select public.save_school_billing_settings((select v::uuid from t where k='school_a'), null, null, null, null, null, 'PC-2026-0043');
select pg_temp.ok((select purchase_order from public.school_billing_settings) = 'PC-2026-0043',
  'financeiro atualiza o pedido de compra');
select set_config('request.jwt.claim.sub', :it_a, false);
select pg_temp.ok((select count(*) from public.school_billing_settings) = 0, 'TI não vê dados de cobrança');
select pg_temp.fails($$select public.save_school_billing_settings((select v::uuid from t where k='school_a'), null, 'pix')$$,
  'MM403', 'TI não altera a cobrança');
select set_config('request.jwt.claim.sub', :coord_a, false);
select pg_temp.ok((select payer_role from public.school_billing_settings) = 'finance',
  'coordenação sabe quem paga');
reset role;

-- ------------------------------------------------ 4. contratação e pagamento
insert into public.school_invoices(school_id, kind, reference_month, plan, cycle, students,
  price_per_student, gross, volume_discount_percent, discount, total, method, due_date, provider,
  provider_payment_id)
select (select v::uuid from t where k='school_a'), 'checkout', public.school_usage_month(), q.plan, q.cycle,
  q.students, q.price_per_student, q.gross, q.volume_discount_percent, q.discount, q.total,
  'boleto', current_date + 30, 'asaas', 'pay_teste_1'
from public.school_billing_quote('escola','annual',1935) q;
insert into t select 'inv_checkout', id::text from public.school_invoices;
select public.school_invoice_paid((select v::uuid from t where k='inv_checkout'), now(), 'E2E1');
select pg_temp.ok((select plan from public.schools where id = (select v::uuid from t where k='school_a')) = 'escola',
  'pagamento da contratação libera o plano Escola');
select pg_temp.ok((select billing_cycle from public.schools where id = (select v::uuid from t where k='school_a')) = 'annual',
  'ciclo anual gravado');
select pg_temp.ok((select receipt_number from public.school_invoices where id = (select v::uuid from t where k='inv_checkout')) like 'MM-%',
  'recibo numerado');
-- Webhook repetido não muda nada.
select public.school_invoice_paid((select v::uuid from t where k='inv_checkout'), now() + interval '1 hour', 'E2E2');
select pg_temp.ok((select transaction_id from public.school_invoices where id = (select v::uuid from t where k='inv_checkout')) = 'E2E1',
  'confirmação repetida é ignorada');

set role authenticated;
select set_config('request.jwt.claim.sub', :fin_a, false);
select pg_temp.ok((select count(*) from public.school_invoices) = 1, 'financeiro vê a fatura');
select set_config('request.jwt.claim.sub', :owner_a, false);
select pg_temp.ok((select count(*) from public.school_invoices) = 1, 'dono acompanha a fatura');
select set_config('request.jwt.claim.sub', :coord_a, false);
select pg_temp.ok((select count(*) from public.school_invoices) = 0, 'coordenação não vê valores');
select set_config('request.jwt.claim.sub', :s1, false);
select pg_temp.ok((select count(*) from public.school_invoices) = 0, 'aluno não vê fatura');
select set_config('request.jwt.claim.sub', :owner_b, false);
select pg_temp.ok((select count(*) from public.school_invoices) = 0, 'outra escola não vê fatura');
select pg_temp.fails($$select public.school_invoice_paid((select v::uuid from t where k='inv_checkout'))$$,
  '42501', 'app não confirma pagamento');
select pg_temp.fails($$insert into public.school_invoices(school_id, kind, reference_month, plan, cycle, students,
  price_per_student, gross, total, method, due_date, provider) values ((select v::uuid from t where k='school_a'),
  'checkout', date '2026-11-01', 'escola', 'monthly', 1, 12, 12, 0.01, 'pix', current_date, 'asaas')$$,
  '42501', 'app não cria fatura');
select set_config('request.jwt.claim.sub', :fin_a, false);
select pg_temp.ok((select count(*) from public.school_quota((select v::uuid from t where k='school_a'))) = 1,
  'financeiro acompanha o consumo do mês');
reset role;

-- ------------------------------------------------------ 5. fechamento do mês
-- Mês anterior com 1.940 ativos e 300 análises extras.
insert into public.school_usage_months(school_id, month, plan, active_students, analyses, extra_analyses)
values ((select v::uuid from t where k='school_a'), (public.school_usage_month() - interval '1 month')::date,
        'escola', 1940, 116400, 300);
-- Contratação paga no mês anterior abate a fatura.
update public.school_invoices set reference_month = (public.school_usage_month() - interval '1 month')::date
  where id = (select v::uuid from t where k='inv_checkout');
select pg_temp.ok(public.school_close_month() = 1, 'fechamento gera 1 fatura');
select pg_temp.ok(public.school_close_month() = 0, 'fechamento é idempotente');
select pg_temp.ok((select closed_at is not null from public.school_usage_months
  where month = (public.school_usage_month() - interval '1 month')::date), 'uso do mês congelado');
select pg_temp.ok((select total from public.school_invoices where kind = 'monthly')
  = round(9.90*1940*0.8, 2) + 45.00 - 15325.20, 'fatura = ativos reais + extras − contratação');
select pg_temp.ok((select method || '/' || purchase_order || '/' || status || '/' || (due_date - current_date)
  from public.school_invoices where kind = 'monthly') = 'boleto/PC-2026-0043/pending/30',
  'fatura usa boleto, pedido de compra e prazo de 30 dias do financeiro');
select pg_temp.fails($$select public.school_close_month(public.school_usage_month())$$, '22023',
  'mês corrente não fecha');

-- ------------------------------------------------------- 6. cartão com token
set role authenticated;
select set_config('request.jwt.claim.sub', :fin_a, false);
select public.save_school_billing_settings((select v::uuid from t where k='school_a'), null, 'credit_card',
  null, null, null, null, null, '30660-130', '126', '(31) 99999-0000');
select pg_temp.ok((select postal_code || '/' || phone from public.school_billing_settings) = '30660130/31999990000',
  'CEP e telefone do titular só com dígitos');
select pg_temp.fails($$select card_token from public.school_billing_settings$$, '42501',
  'token do cartão não chega ao app');
reset role;
-- Sem token salvo, o fechamento cai para Pix.
insert into public.school_usage_months(school_id, month, plan, active_students)
values ((select v::uuid from t where k='school_a'), (public.school_usage_month() - interval '2 month')::date, 'escola', 1900);
select public.school_close_month((public.school_usage_month() - interval '2 month')::date);
select pg_temp.ok((select method from public.school_invoices where kind = 'monthly'
  and reference_month = (public.school_usage_month() - interval '2 month')::date) = 'pix',
  'cartão sem token: fatura do mês sai em Pix');
