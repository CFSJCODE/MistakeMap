-- Escola de demonstração comercial "Colégio Nexo — Unidade Vale do Ferro".
--
-- Escola fictícia (nome, rede e números inventados para apresentação; não
-- representa nenhuma escola real). Só dados AGREGADOS de uso: 12 meses de
-- alunos ativos (~1.935 no mês mais recente), análises e práticas. Nenhuma
-- conta de aluno, nenhuma resposta, nenhuma fatura: school_billing_settings
-- .demo = true faz o fechamento do mês e a Edge Function nunca cobrarem
-- esta escola no Asaas. A amostra dos relatórios (school_demo_report) fica
-- numa tabela à parte e só aparece marcada como demonstração.
--
-- Uso (no banco do projeto, depois das migrations 20261112170000, 20261112190000
-- e 20261112210000):
--   psql "$DB_URL" -v owner_email=dono.demo@... -f scripts/school_billing/seed_demo_nexo.sql
-- Idempotente: rodar de novo só atualiza os números.
\set ON_ERROR_STOP on

begin;

create temporary table seed_ctx on commit drop as
select u.id as owner_id
from auth.users u
where lower(u.email) = lower(:'owner_email');

do $$
begin
  if (select count(*) from seed_ctx) <> 1 then
    raise exception 'Conta do dono de demonstração não encontrada.';
  end if;
end $$;

-- A escola nasce pelo create_school como o dono (o guarda de school_members
-- só aceita o dono assim), e depois ganha o plano de demonstração.
select set_config('request.jwt.claim.sub', owner_id::text, true),
       set_config('request.jwt.claims',
         json_build_object('sub', owner_id, 'role', 'authenticated')::text, true)
from seed_ctx;
set local role authenticated;
select public.create_school('Colégio Nexo — Unidade Vale do Ferro (demonstração)')
where not exists (
  select 1 from public.schools
  where name = 'Colégio Nexo — Unidade Vale do Ferro (demonstração)'
);
reset role;

create temporary table seed_school on commit drop as
select id from public.schools
where name = 'Colégio Nexo — Unidade Vale do Ferro (demonstração)';

update public.schools set plan = 'escola', billing_cycle = 'annual', status = 'active'
where id = (select id from seed_school);

insert into public.school_billing_settings(
  school_id, payer_role, default_method, due_days, legal_name, purchase_order,
  cost_center, demo)
select id, 'owner', 'boleto', 30,
  'Rede Nexo de Educação Tecnológica (demonstração)', 'PC-DEMO-0001',
  'CC-EDU-DEMO', true
from seed_school
on conflict (school_id) do update set demo = true,
  legal_name = excluded.legal_name, purchase_order = excluded.purchase_order,
  cost_center = excluded.cost_center, updated_at = now();

-- 12 meses fechados: matrículas crescendo até ~1.935 ativos, com a queda
-- de julho (férias) que um colégio real tem.
insert into public.school_usage_months(
  school_id, month, plan, active_students, analyses, extra_analyses, practices,
  closed_at)
select s.id, m.month, 'escola', m.active,
  m.active * m.per_student, 0, m.active * 14,
  (m.month + interval '1 month')::timestamptz
from seed_school s
cross join lateral (
  select (public.school_usage_month() - make_interval(months => k))::date as month,
         case when extract(month from public.school_usage_month() - make_interval(months => k)) = 7
              then 1180
              else 1640 + (12 - k) * 25 end as active,
         case when extract(month from public.school_usage_month() - make_interval(months => k)) = 7
              then 11 else 31 end as per_student
  from generate_series(1, 12) as k
) m
on conflict (school_id, month) do update set
  active_students = excluded.active_students, analyses = excluded.analyses,
  practices = excluded.practices, closed_at = excluded.closed_at,
  updated_at = now();

-- Mês corrente em andamento.
insert into public.school_usage_months(school_id, month, plan, active_students, analyses, practices)
select id, public.school_usage_month(), 'escola', 1935, 1935 * 12, 1935 * 6 from seed_school
on conflict (school_id, month) do update set
  active_students = excluded.active_students, analyses = excluded.analyses,
  practices = excluded.practices, updated_at = now();

-- Amostra dos relatórios (só lida porque a escola é demo = true): turmas,
-- mapa de erros e faturas fictícias, sempre exibidas como demonstração.
-- As faturas de amostra seguem o custo do uso de cada mês fechado.
insert into public.school_demo_report(school_id, payload)
select s.id, jsonb_build_object(
  'classes', '[
    {"title": "1º ano A — Eletrônica básica", "students": 248, "active_28d": 231, "assignments": 14},
    {"title": "1º ano B — Eletrônica básica", "students": 245, "active_28d": 219, "assignments": 12},
    {"title": "2º ano A — Robótica móvel", "students": 241, "active_28d": 228, "assignments": 16},
    {"title": "2º ano B — Sistemas embarcados", "students": 238, "active_28d": 210, "assignments": 11},
    {"title": "3º ano A — Redes e IoT", "students": 236, "active_28d": 214, "assignments": 13},
    {"title": "3º ano B — Programação", "students": 240, "active_28d": 226, "assignments": 15},
    {"title": "Técnico — Automação industrial", "students": 252, "active_28d": 239, "assignments": 18},
    {"title": "Equipe de robótica — OBR/FLL", "students": 235, "active_28d": 222, "assignments": 9}
  ]'::jsonb,
  'error_students', 1612,
  'errors_by_type', '[
    {"error_type": "calculo", "errors": 4820, "students": 1188},
    {"error_type": "conceito", "errors": 3915, "students": 1043},
    {"error_type": "unidade", "errors": 2760, "students": 902},
    {"error_type": "sinal", "errors": 2140, "students": 761},
    {"error_type": "interpretacao", "errors": 1985, "students": 694},
    {"error_type": "procedimento", "errors": 1430, "students": 512},
    {"error_type": "outro", "errors": 410, "students": 188}
  ]'::jsonb,
  'concepts', '[
    {"concept": "lei de ohm", "errors": 2310, "students": 884, "by_type": {"calculo": 1120, "unidade": 610, "conceito": 380, "sinal": 200}},
    {"concept": "divisor de tensão", "errors": 1780, "students": 702, "by_type": {"calculo": 760, "conceito": 540, "interpretacao": 300, "unidade": 180}},
    {"concept": "controle pid", "errors": 1540, "students": 561, "by_type": {"conceito": 720, "procedimento": 430, "interpretacao": 390}},
    {"concept": "pwm e duty cycle", "errors": 1320, "students": 590, "by_type": {"calculo": 520, "unidade": 470, "conceito": 330}},
    {"concept": "potência elétrica", "errors": 1210, "students": 633, "by_type": {"calculo": 610, "unidade": 420, "sinal": 180}},
    {"concept": "lógica booleana", "errors": 980, "students": 470, "by_type": {"conceito": 410, "procedimento": 330, "interpretacao": 240}},
    {"concept": "comunicação i2c", "errors": 860, "students": 388, "by_type": {"procedimento": 400, "conceito": 300, "interpretacao": 160}},
    {"concept": "cinemática diferencial", "errors": 790, "students": 341, "by_type": {"calculo": 330, "sinal": 290, "conceito": 170}}
  ]'::jsonb,
  'invoices_by_month', coalesce((
    select jsonb_agg(jsonb_build_object('month', u.month, 'billed', q.total, 'paid', q.total, 'open', 0)
      order by u.month)
    from public.school_usage_months u
    cross join lateral public.school_billing_quote('escola', 'annual', u.active_students) q
    where u.school_id = s.id and u.closed_at is not null), '[]'::jsonb),
  'by_method', (
    select jsonb_build_array(
      jsonb_build_object('method', 'boleto', 'count', 9, 'total', round(sum(q.total) * 0.74, 2)),
      jsonb_build_object('method', 'pix', 'count', 2, 'total', round(sum(q.total) * 0.17, 2)),
      jsonb_build_object('method', 'credit_card', 'count', 1, 'total', round(sum(q.total) * 0.09, 2)))
    from public.school_usage_months u
    cross join lateral public.school_billing_quote('escola', 'annual', u.active_students) q
    where u.school_id = s.id and u.closed_at is not null),
  'by_status', (
    select jsonb_build_array(jsonb_build_object('status', 'paid', 'count', count(*), 'total', sum(q.total)))
    from public.school_usage_months u
    cross join lateral public.school_billing_quote('escola', 'annual', u.active_students) q
    where u.school_id = s.id and u.closed_at is not null),
  'invoices', coalesce((
    select jsonb_agg(jsonb_build_object(
        'reference_month', u.month, 'kind', 'monthly', 'plan', 'escola',
        'students', u.active_students,
        'method', case when extract(month from u.month) in (3, 9) then 'pix'
                       when extract(month from u.month) = 12 then 'credit_card' else 'boleto' end,
        'status', 'paid', 'total', q.total,
        'due_date', (u.month + interval '1 month' + interval '29 days')::date,
        'paid_at', (u.month + interval '1 month' + interval '20 days')::timestamptz,
        'purchase_order', 'PC-DEMO-0001', 'cost_center', 'CC-EDU-DEMO',
        'nfse_number', null, 'created_at', (u.month + interval '1 month')::timestamptz)
      order by u.month desc)
    from public.school_usage_months u
    cross join lateral public.school_billing_quote('escola', 'annual', u.active_students) q
    where u.school_id = s.id and u.closed_at is not null), '[]'::jsonb))
from seed_school s
on conflict (school_id) do update set payload = excluded.payload, updated_at = now();

select s.id as school_id, count(u.*) as meses
from seed_school s join public.school_usage_months u on u.school_id = s.id
group by s.id;

commit;
