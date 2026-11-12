-- Escola de demonstração comercial "Colégio Nexo — Unidade Vale do Ferro".
--
-- Escola fictícia (nome, rede e números inventados para apresentação; não
-- representa nenhuma escola real). Só dados AGREGADOS de uso: 12 meses de
-- alunos ativos (~1.935 no mês mais recente), análises e práticas. Nenhuma
-- conta de aluno, nenhuma resposta, nenhuma fatura: school_billing_settings
-- .demo = true faz o fechamento do mês e a Edge Function nunca cobrarem
-- esta escola no Asaas.
--
-- Uso (no banco do projeto, depois da migration 20261112170000):
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

select s.id as school_id, count(u.*) as meses
from seed_school s join public.school_usage_months u on u.school_id = s.id
group by s.id;

commit;
