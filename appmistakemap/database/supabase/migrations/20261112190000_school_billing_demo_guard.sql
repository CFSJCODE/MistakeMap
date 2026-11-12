-- Escola de demonstração comercial (school_billing_settings.demo): o uso do
-- mês fecha normalmente, mas nunca vira fatura. Corrige school_close_month
-- da migration 20261112170000 (migrations são imutáveis).
create or replace function public.school_close_month(p_month date default null)
returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_month date := coalesce(p_month,
    (public.school_usage_month() - interval '1 month')::date);
  v_count integer := 0;
  r record;
  q record;
  v_credit numeric;
  v_settings public.school_billing_settings%rowtype;
  v_total numeric;
begin
  if v_month <> date_trunc('month', v_month)::date then
    raise exception 'invalid_month' using errcode = '22023';
  end if;
  if v_month >= public.school_usage_month() then
    raise exception 'month_not_finished' using errcode = '22023';
  end if;
  for r in
    select u.school_id, u.plan, u.active_students, u.extra_analyses, s.billing_cycle
    from public.school_usage_months u
    join public.schools s on s.id = u.school_id
    where u.month = v_month and u.closed_at is null
    for update of u
  loop
    update public.school_usage_months set closed_at = now(), updated_at = now()
      where school_id = r.school_id and month = v_month;
    -- Escola de demonstração comercial: o uso fecha, mas nunca vira cobrança.
    if r.plan not in ('escola','plus')
       or exists(select 1 from public.school_billing_settings b
                 where b.school_id = r.school_id and b.demo)
       or exists(select 1 from public.school_invoices i
                 where i.school_id = r.school_id and i.reference_month = v_month and i.kind = 'monthly') then
      continue;
    end if;
    select * into q from public.school_billing_quote(r.plan, r.billing_cycle, r.active_students, r.extra_analyses);
    select coalesce(sum(i.total), 0) into v_credit from public.school_invoices i
      where i.school_id = r.school_id and i.reference_month = v_month
        and i.kind = 'checkout' and i.status = 'paid';
    select * into v_settings from public.school_billing_settings b where b.school_id = r.school_id;
    v_total := greatest(q.total - v_credit, 0);
    insert into public.school_invoices(
      school_id, kind, reference_month, plan, cycle, students, price_per_student, gross,
      volume_discount_percent, discount, minimum_applied, extra_analyses, extra_amount,
      credit, total, method, status, due_date, purchase_order, cost_center, provider, demo,
      paid_at)
    values (
      r.school_id, 'monthly', v_month, r.plan, r.billing_cycle, r.active_students,
      q.price_per_student, q.gross, q.volume_discount_percent, q.discount, q.minimum_applied,
      q.extra_analyses, q.extra_amount, least(v_credit, q.total), v_total,
      -- Cartão só com token salvo; sem ele, Pix.
      case when v_settings.default_method = 'credit_card' and v_settings.card_token is null then 'pix'
           else coalesce(v_settings.default_method, 'pix') end,
      case when v_total = 0 then 'paid' else 'pending' end,
      (now() at time zone 'America/Sao_Paulo')::date + coalesce(v_settings.due_days, 5),
      v_settings.purchase_order, v_settings.cost_center, 'asaas',
      coalesce(v_settings.demo, false),
      case when v_total = 0 then now() end);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke all on function public.school_close_month(date) from public, anon, authenticated;
grant execute on function public.school_close_month(date) to service_role;
