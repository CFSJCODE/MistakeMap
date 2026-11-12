-- Relatórios da escola (item F): pedagógico e financeiro, num único RPC.
--
-- * public.school_reports(p_school, p_months) devolve um jsonb com:
--   - school: nome, plano, ciclo, se é escola de demonstração;
--   - pedagogical (dono e coordenação): uso por mês, turmas e o mapa de erros
--     da escola (tipo de erro e conceito × tipo nos últimos 90 dias);
--   - financial (dono e financeiro): custo pelo uso de cada mês, faturas por
--     mês, forma de pagamento e situação, totais e as últimas faturas.
--   A seção sem permissão volta null. Quem não é dono, coordenação nem
--   financeiro recebe 42501.
-- * Privacidade igual ao mapa da turma: nada por aluno, mapa de erros só com
--   5+ alunos com erro no período e conceito só com 3+ alunos.
-- * public.school_demo_report: amostra fictícia só para escola com
--   school_billing_settings.demo. Preenche o que a escola demo não tem de
--   verdade (turmas, mapa de erros, faturas), sempre marcado sample = true.
--   Nunca é lida para escola real.

create table public.school_demo_report (
  school_id uuid primary key references public.schools(id) on delete cascade,
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  updated_at timestamptz not null default now()
);
alter table public.school_demo_report enable row level security;
revoke all on public.school_demo_report from public, anon, authenticated;

create index if not exists school_invoices_school_month
  on public.school_invoices(school_id, reference_month);

create or replace function public.school_reports(p_school uuid, p_months integer default 12)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_ped boolean := public.is_school_member(p_school, array['owner','coordinator']);
  v_fin boolean := public.is_school_member(p_school, array['owner','finance']);
  v_months integer := least(greatest(coalesce(p_months, 12), 1), 24);
  v_from date;
  v_school public.schools%rowtype;
  v_demo boolean := false;
  v_sample jsonb;
  v_usage jsonb;
  v_ped_out jsonb;
  v_fin_out jsonb;
  v_classes jsonb;
  v_types jsonb;
  v_concepts jsonb;
  v_error_students integer;
  v_by_month jsonb;
  v_by_method jsonb;
  v_by_status jsonb;
  v_invoices jsonb;
  v_cost jsonb;
  v_has_invoices boolean;
begin
  if p_school is null or not (v_ped or v_fin) then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  select * into v_school from public.schools s where s.id = p_school;
  if not found then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  v_from := (public.school_usage_month() - make_interval(months => v_months - 1))::date;
  select coalesce(b.demo, false) into v_demo
    from public.school_billing_settings b where b.school_id = p_school;
  v_demo := coalesce(v_demo, false);
  if v_demo then
    select d.payload into v_sample from public.school_demo_report d where d.school_id = p_school;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'month', u.month, 'plan', u.plan, 'active_students', u.active_students,
      'analyses', u.analyses, 'extra_analyses', u.extra_analyses,
      'practices', u.practices, 'closed', u.closed_at is not null)
    order by u.month), '[]'::jsonb)
  into v_usage
  from public.school_usage_months u
  where u.school_id = p_school and u.month >= v_from;

  -- ------------------------------------------------------------------ pedagógico
  if v_ped then
    select coalesce(jsonb_agg(c order by c->>'title'), '[]'::jsonb) into v_classes
    from (
      select jsonb_build_object(
        'title', pc.title,
        'students', (select count(*) from public.platform_memberships m
                      where m.class_id = pc.id and m.user_id <> pc.teacher_id),
        'active_28d', (select count(distinct a.user_id) from public.platform_memberships m
                        join public.attempts a on a.user_id = m.user_id
                         and a.attempted_at >= now() - interval '28 days'
                        where m.class_id = pc.id and m.user_id <> pc.teacher_id),
        'assignments', (select count(*) from public.platform_assignments pa
                         where pa.class_id = pc.id)) as c
      from public.platform_classes pc
      where pc.school_id = p_school
    ) t;

    -- Erros dos alunos da escola nos últimos 90 dias (só agregados).
    with e as (
      select a.user_id as student, lower(btrim(c.name)) as concept,
             coalesce(et.name, 'outro') as error_type
      from public.school_members sm
      join public.attempts a on a.user_id = sm.user_id
       and a.attempted_at >= now() - interval '90 days'
      join public.error_events ee on ee.attempt_id = a.id
       and ee.status in ('pending','confirmed')
      left join public.concepts c on c.id = ee.concept_id
      left join public.error_types et on et.id = ee.error_type_id
      where sm.school_id = p_school and sm.role = 'student' and sm.status = 'active'
      limit 200000
    ),
    types as (
      select error_type, count(*) as n, count(distinct student) as s
      from e group by error_type
    ),
    conc as (
      select concept, count(*) as n, count(distinct student) as s
      from e where concept is not null
      group by concept
      having count(distinct student) >= 3
      order by count(*) desc, concept
      limit 10
    ),
    conc_types as (
      select e.concept, jsonb_object_agg(e.error_type, e.k) as by_type
      from (select e.concept, e.error_type, count(*) as k
            from e join conc using (concept) group by e.concept, e.error_type) e
      group by e.concept
    )
    select (select count(distinct student) from e),
           (select coalesce(jsonb_agg(jsonb_build_object(
               'error_type', error_type, 'errors', n, 'students', s)
               order by n desc, error_type), '[]'::jsonb) from types),
           (select coalesce(jsonb_agg(jsonb_build_object(
               'concept', c.concept, 'errors', c.n, 'students', c.s,
               'by_type', coalesce(t.by_type, '{}'::jsonb))
               order by c.n desc, c.concept), '[]'::jsonb)
              from conc c left join conc_types t using (concept))
    into v_error_students, v_types, v_concepts;
    -- Mapa da escola só com 5+ alunos com erro (mesma regra do mapa da turma).
    if coalesce(v_error_students, 0) < 5 then
      v_types := '[]'::jsonb;
      v_concepts := '[]'::jsonb;
    end if;

    v_ped_out := jsonb_build_object(
      'usage', v_usage,
      'classes', v_classes,
      'error_students', coalesce(v_error_students, 0),
      'errors_by_type', coalesce(v_types, '[]'::jsonb),
      'concepts', coalesce(v_concepts, '[]'::jsonb),
      'sample', false);
    if v_sample is not null and jsonb_array_length(v_classes) = 0
       and coalesce(v_error_students, 0) < 5 then
      v_ped_out := v_ped_out || jsonb_build_object(
        'classes', coalesce(v_sample->'classes', '[]'::jsonb),
        'error_students', coalesce((v_sample->>'error_students')::integer, 0),
        'errors_by_type', coalesce(v_sample->'errors_by_type', '[]'::jsonb),
        'concepts', coalesce(v_sample->'concepts', '[]'::jsonb),
        'sample', true);
    end if;
  end if;

  -- ------------------------------------------------------------------ financeiro
  if v_fin then
    -- Custo de cada mês pelo uso, com a mesma fórmula da fatura.
    select coalesce(jsonb_agg(jsonb_build_object(
        'month', u.month, 'active_students', u.active_students,
        'total', coalesce(q.total, 0),
        'price_per_student', q.price_per_student,
        'volume_discount_percent', coalesce(q.volume_discount_percent, 0))
      order by u.month), '[]'::jsonb)
    into v_cost
    from public.school_usage_months u
    left join lateral (
      select * from public.school_billing_quote(u.plan, coalesce(v_school.billing_cycle, 'monthly'),
                                                u.active_students, u.extra_analyses)
      where u.plan in ('escola','plus')
    ) q on true
    where u.school_id = p_school and u.month >= v_from;

    select exists(select 1 from public.school_invoices i
                  where i.school_id = p_school and i.reference_month >= v_from)
      into v_has_invoices;

    select coalesce(jsonb_agg(jsonb_build_object(
        'month', m, 'billed', billed, 'paid', paid, 'open', open_amount)
      order by m), '[]'::jsonb)
    into v_by_month
    from (
      select i.reference_month as m,
             sum(i.total) filter (where i.status <> 'canceled') as billed,
             coalesce(sum(i.total) filter (where i.status = 'paid'), 0) as paid,
             coalesce(sum(i.total) filter (where i.status in ('pending','awaiting_payment','overdue','failed')), 0) as open_amount
      from public.school_invoices i
      where i.school_id = p_school and i.reference_month >= v_from
      group by i.reference_month
    ) t;

    select coalesce(jsonb_agg(jsonb_build_object('method', method, 'count', n, 'total', total)
      order by total desc, method), '[]'::jsonb)
    into v_by_method
    from (select i.method, count(*) as n, sum(i.total) as total
          from public.school_invoices i
          where i.school_id = p_school and i.reference_month >= v_from and i.status = 'paid'
          group by i.method) t;

    select coalesce(jsonb_agg(jsonb_build_object('status', status, 'count', n, 'total', total)
      order by n desc, status), '[]'::jsonb)
    into v_by_status
    from (select i.status, count(*) as n, sum(i.total) as total
          from public.school_invoices i
          where i.school_id = p_school and i.reference_month >= v_from
          group by i.status) t;

    select coalesce(jsonb_agg(x order by x->>'created_at' desc), '[]'::jsonb) into v_invoices
    from (
      select jsonb_build_object(
        'reference_month', i.reference_month, 'kind', i.kind, 'plan', i.plan,
        'students', i.students, 'method', i.method, 'status', i.status,
        'total', i.total, 'due_date', i.due_date, 'paid_at', i.paid_at,
        'purchase_order', i.purchase_order, 'cost_center', i.cost_center,
        'nfse_number', i.nfse_number, 'created_at', i.created_at) as x
      from public.school_invoices i
      where i.school_id = p_school and i.reference_month >= v_from
      order by i.created_at desc
      limit 36
    ) t;

    v_fin_out := jsonb_build_object(
      'cost_by_month', v_cost,
      'invoices_by_month', v_by_month,
      'by_method', v_by_method,
      'by_status', v_by_status,
      'invoices', v_invoices,
      'sample', false);
    if v_sample is not null and not v_has_invoices then
      v_fin_out := v_fin_out || jsonb_build_object(
        'invoices_by_month', coalesce(v_sample->'invoices_by_month', '[]'::jsonb),
        'by_method', coalesce(v_sample->'by_method', '[]'::jsonb),
        'by_status', coalesce(v_sample->'by_status', '[]'::jsonb),
        'invoices', coalesce(v_sample->'invoices', '[]'::jsonb),
        'sample', true);
    end if;
  end if;

  return jsonb_build_object(
    'school', jsonb_build_object(
      'name', v_school.name, 'plan', v_school.plan,
      'cycle', v_school.billing_cycle, 'demo', v_demo),
    'from', v_from,
    'months', v_months,
    'generated_at', now(),
    'pedagogical', v_ped_out,
    'financial', v_fin_out);
end;
$$;
revoke all on function public.school_reports(uuid, integer) from public, anon;
grant execute on function public.school_reports(uuid, integer) to authenticated, service_role;

-- A "Escola Demonstração MistakeMap" (contas demo comerciais de 2026-11-11)
-- também é de demonstração: nunca vira fatura no fechamento do mês.
insert into public.school_billing_settings(school_id, demo)
select s.id, true from public.schools s where s.name = 'Escola Demonstração MistakeMap'
on conflict (school_id) do update set demo = true, updated_at = now();
