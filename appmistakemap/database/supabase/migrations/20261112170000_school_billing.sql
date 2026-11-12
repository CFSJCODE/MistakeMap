-- Cobrança da escola (onda 1, item D do plano consolidado por perfil).
-- Depende de 20261111050000_schools_and_roles e 20261111210000_school_plans_quota.
--
-- Regras:
-- * Papel novo 'finance' (Financeiro/Compras), só por convite pessoal do dono.
--   Serve para redes como a FIEMG, em que o setor de compras/financeiro
--   contrata e paga. Em escola pequena quem paga é o próprio dono.
-- * Cada escola diz quem paga (school_billing_settings.payer_role): 'owner'
--   (padrão) ou 'finance'. Só quem tem o papel que paga escolhe o plano e gera
--   cobrança; o dono sempre acompanha as faturas. Só o dono troca quem paga.
-- * O valor é calculado aqui (school_billing_quote), nunca no app: preço por
--   aluno ativo, desconto por volume, mínimo mensal e análises extras.
-- * O gateway é o Asaas (API v3), atrás da Edge Function school-billing e de
--   uma interface PaymentProvider trocável. O banco guarda o id do pagamento
--   no Asaas, o Pix copia e cola, a linha digitável e, no cartão, só o token
--   (creditCardToken), a bandeira e os 4 últimos dígitos. Número do cartão e
--   CVV nunca chegam ao banco. A chave da API nunca passa pelo banco nem pelo app.
-- * Fechamento do mês no dia 1 (pg_cron): congela o uso do mês anterior, gera
--   a fatura por aluno ativo (descontando o que já foi pago na contratação) e
--   chama a Edge Function por pg_net para emitir a cobrança. Nada de HTTP em
--   trigger.
-- * O cliente só lê (RLS). Toda escrita passa pelas funções abaixo ou pela
--   Edge Function com service_role.

-- ---------------------------------------------------------------------------
-- Papel Financeiro/Compras
-- ---------------------------------------------------------------------------

do $$
declare
  v_nome text;
begin
  -- As restrições de papel foram criadas sem nome em 20261111050000.
  for v_nome in
    select c.conname from pg_constraint c
     where c.conrelid in ('public.school_members'::regclass, 'public.school_invites'::regclass)
       and c.contype = 'c'
       and pg_get_constraintdef(c.oid) ilike '%role%'
  loop
    execute format('alter table %s drop constraint %I',
      (select c.conrelid::regclass from pg_constraint c where c.conname = v_nome limit 1), v_nome);
  end loop;
  for v_nome in
    select c.conname from pg_constraint c
     where c.conrelid = 'public.user_signups'::regclass
       and c.contype = 'c'
       and pg_get_constraintdef(c.oid) ilike '%persona%'
       and pg_get_constraintdef(c.oid) not ilike '%birth_date%'
  loop
    execute format('alter table public.user_signups drop constraint %I', v_nome);
  end loop;
end
$$;

alter table public.school_members
  add constraint school_members_role_check
  check (role in ('owner','coordinator','it_admin','finance','teacher','student','guardian'));
alter table public.school_invites
  add constraint school_invites_role_check
  check (role in ('owner','coordinator','it_admin','finance','teacher','student','guardian'));
-- Convite de gestão é pessoal: serve para uma pessoa só.
alter table public.school_invites
  add constraint school_invites_management_single_use
  check (role not in ('owner','coordinator','it_admin','finance') or max_uses = 1);
alter table public.user_signups
  add constraint user_signups_persona_check
  check (persona in ('student','student_team','teacher','guardian','owner','coordinator','it_admin','finance'));

create or replace function public.save_signup_profile(p_persona text, p_birth_date date default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'MM401';
  end if;
  if p_persona is null or p_persona not in
     ('student','student_team','teacher','guardian','owner','coordinator','it_admin','finance') then
    raise exception 'invalid_persona' using errcode = '22023';
  end if;
  if p_persona in ('student','student_team') and p_birth_date is null then
    raise exception 'birth_date_required' using errcode = '22023';
  end if;
  if p_birth_date is not null
     and (p_birth_date > current_date or p_birth_date < current_date - interval '120 years') then
    raise exception 'invalid_birth_date' using errcode = '22023';
  end if;
  insert into public.user_signups(user_id, persona, birth_date)
    values (v_uid, p_persona, p_birth_date)
  on conflict (user_id) do update
    set persona = excluded.persona,
        birth_date = coalesce(excluded.birth_date, public.user_signups.birth_date),
        updated_at = now();
end;
$$;

-- Dono convida qualquer papel (gestão e financeiro só ele); coordenador e TI
-- convidam professor, estudante e responsável.
create or replace function public.create_school_invite(
  p_school uuid,
  p_role text,
  p_email text default null,
  p_max_uses integer default 1,
  p_valid_days integer default 7)
returns table(invite_id uuid, code text, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_code text := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
  v_id uuid;
  v_expires timestamptz := now() + make_interval(days => p_valid_days);
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'MM401';
  end if;
  if p_role in ('owner','coordinator','it_admin','finance') then
    if not public.is_school_member(p_school, array['owner']) then
      raise exception 'forbidden' using errcode = 'MM403';
    end if;
  elsif p_role in ('teacher','student','guardian') then
    if not public.is_school_member(p_school, array['owner','coordinator','it_admin']) then
      raise exception 'forbidden' using errcode = 'MM403';
    end if;
  else
    raise exception 'invalid_role' using errcode = '22023';
  end if;
  if p_valid_days is null or p_valid_days not between 1 and 90 then
    raise exception 'invalid_valid_days' using errcode = '22023';
  end if;
  insert into public.school_invites(school_id, role, code_hash, email, max_uses, created_by, expires_at)
    values (p_school, p_role,
            encode(sha256(convert_to(v_code, 'UTF8')), 'hex'),
            nullif(lower(btrim(coalesce(p_email, ''))), ''),
            coalesce(p_max_uses, 1), v_uid, v_expires)
    returning id into v_id;
  return query select v_id, v_code, v_expires;
end;
$$;

create or replace function public.revoke_school_invite(p_invite uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_invite public.school_invites%rowtype;
begin
  select * into v_invite from public.school_invites i where i.id = p_invite;
  if not found then
    raise exception 'not_found' using errcode = 'MM404';
  end if;
  if not public.is_school_member(v_invite.school_id,
       case when v_invite.role in ('owner','coordinator','it_admin','finance')
            then array['owner'] else array['owner','coordinator','it_admin'] end) then
    raise exception 'forbidden' using errcode = 'MM403';
  end if;
  update public.school_invites set revoked_at = coalesce(revoked_at, now()) where id = p_invite;
end;
$$;

-- O financeiro também acompanha o consumo do mês (sem dado pedagógico).
create or replace function public.school_quota(p_school uuid)
returns table(month date, plan text, plan_label text, active_students integer,
              analyses_pot integer, analyses_used integer, extra_analyses integer,
              extra_analyses_brl numeric, practices_pot integer, practices_used integer)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_month date := public.school_usage_month();
begin
  if not public.is_school_member(p_school, array['owner','coordinator','it_admin','finance']) then
    raise exception 'forbidden' using errcode = 'MM403';
  end if;
  return query
    select v_month, s.plan, l.label,
           coalesce(u.active_students, 0),
           l.analyses_per_active * coalesce(u.active_students, 0),
           coalesce(u.analyses, 0),
           coalesce(u.extra_analyses, 0),
           coalesce(u.extra_analyses, 0) * coalesce(l.extra_analysis_brl, 0),
           l.practices_per_active * coalesce(u.active_students, 0),
           coalesce(u.practices, 0)
    from public.schools s
    join public.school_plan_limits l on l.plan = s.plan
    left join public.school_usage_months u on u.school_id = s.id and u.month = v_month
    where s.id = p_school;
end;
$$;

create policy school_usage_months_finance_read on public.school_usage_months for select to authenticated
  using (public.is_school_member(school_id, array['finance']));

-- ---------------------------------------------------------------------------
-- Preços (tabela de referência; para mudar, crie uma migration com update)
-- ---------------------------------------------------------------------------

create table public.school_plan_prices (
  plan text primary key references public.school_plan_limits(plan),
  monthly_brl numeric(8,2) not null check (monthly_brl >= 0),
  -- Anual: fidelidade de 12 meses, cobrada mês a mês com o preço menor.
  annual_brl numeric(8,2) not null check (annual_brl >= 0),
  minimum_brl numeric(8,2) not null default 0 check (minimum_brl >= 0),
  updated_at timestamptz not null default now()
);
insert into public.school_plan_prices(plan, monthly_brl, annual_brl, minimum_brl) values
  ('free',   0,     0,     0),
  ('escola', 12.00, 9.90,  99.00),
  ('plus',   16.00, 13.90, 99.00);

create table public.school_volume_discounts (
  min_students integer primary key check (min_students > 0),
  percent integer not null check (percent between 0 and 90)
);
insert into public.school_volume_discounts(min_students, percent) values
  (101, 10),
  (301, 20);

-- Orçamento: a única conta de preço do sistema. O app e a Edge Function leem
-- daqui. Arredonda em centavos.
create or replace function public.school_billing_quote(
  p_plan text, p_cycle text, p_students integer, p_extra_analyses integer default 0)
returns table(plan text, cycle text, students integer, price_per_student numeric,
              gross numeric, volume_discount_percent integer, discount numeric,
              minimum_applied boolean, extra_analyses integer, extra_amount numeric,
              total numeric)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_price public.school_plan_prices%rowtype;
  v_extra_unit numeric;
  v_unit numeric;
  v_gross numeric;
  v_pct integer;
  v_discount numeric;
  v_net numeric;
  v_extra numeric;
  v_min boolean := false;
begin
  if p_cycle not in ('monthly','annual') then
    raise exception 'invalid_cycle' using errcode = '22023';
  end if;
  if p_students is null or p_students < 0 or p_students > 200000 then
    raise exception 'invalid_students' using errcode = '22023';
  end if;
  select * into v_price from public.school_plan_prices pp where pp.plan = p_plan;
  if not found then
    raise exception 'invalid_plan' using errcode = '22023';
  end if;
  select l.extra_analysis_brl into v_extra_unit from public.school_plan_limits l where l.plan = p_plan;
  v_unit := case p_cycle when 'annual' then v_price.annual_brl else v_price.monthly_brl end;
  v_gross := round(v_unit * p_students, 2);
  select coalesce(max(d.percent), 0) into v_pct
    from public.school_volume_discounts d where p_students >= d.min_students;
  if v_price.monthly_brl = 0 then
    v_pct := 0;
  end if;
  v_discount := round(v_gross * v_pct / 100.0, 2);
  v_net := v_gross - v_discount;
  if v_price.minimum_brl > 0 and v_net < v_price.minimum_brl then
    v_net := v_price.minimum_brl;
    v_min := true;
  end if;
  v_extra := round(coalesce(v_extra_unit, 0) * greatest(coalesce(p_extra_analyses, 0), 0), 2);
  return query select p_plan, p_cycle, p_students, v_unit, v_gross, v_pct, v_discount,
    v_min, greatest(coalesce(p_extra_analyses, 0), 0), v_extra, v_net + v_extra;
end;
$$;
revoke all on function public.school_billing_quote(text, text, integer, integer) from public, anon;
grant execute on function public.school_billing_quote(text, text, integer, integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Quem paga e dados de cobrança
-- ---------------------------------------------------------------------------

create table public.school_billing_settings (
  school_id uuid primary key references public.schools(id) on delete cascade,
  payer_role text not null default 'owner' check (payer_role in ('owner','finance')),
  default_method text not null default 'pix' check (default_method in ('pix','boleto','credit_card')),
  -- Prazo do boleto/Pix gerado no fechamento. Compras de rede costuma pedir 30.
  due_days integer not null default 5 check (due_days between 1 and 60),
  legal_name text check (legal_name is null or char_length(btrim(legal_name)) between 2 and 160),
  billing_email text check (billing_email is null or billing_email = lower(btrim(billing_email))),
  -- Número do pedido de compra e centro de custo que o setor de compras exige
  -- na nota fiscal (modelo FIEMG). Livres; vão na descrição da cobrança.
  purchase_order text check (purchase_order is null or char_length(purchase_order) <= 60),
  cost_center text check (cost_center is null or char_length(cost_center) <= 60),
  -- Endereço e telefone do titular: o Asaas exige no pagamento com cartão.
  postal_code text check (postal_code is null or postal_code ~ '^[0-9]{8}$'),
  address_number text check (address_number is null or char_length(address_number) <= 20),
  phone text check (phone is null or phone ~ '^[0-9]{10,11}$'),
  provider text not null default 'asaas' check (provider in ('asaas')),
  provider_customer_id text,
  -- Cartão salvo para as próximas faturas: só o token do Asaas.
  card_token text,
  card_brand text,
  card_last4 text check (card_last4 is null or card_last4 ~ '^[0-9]{4}$'),
  -- Escola de demonstração comercial (dados de uso agregados, não reais).
  demo boolean not null default false,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

-- Quem paga é sempre um papel ativo. Sem configuração, paga o dono.
create or replace function public.school_is_payer(p_school uuid)
returns boolean
language sql stable security definer set search_path = '' as $$
  select public.is_school_member(p_school, array[
    coalesce((select b.payer_role from public.school_billing_settings b where b.school_id = p_school),
             'owner')]);
$$;
revoke all on function public.school_is_payer(uuid) from public, anon;
grant execute on function public.school_is_payer(uuid) to authenticated, service_role;

-- Grava quem paga e os dados de cobrança. Só o dono troca quem paga; o
-- pagante atual edita o resto. Texto vazio apaga o campo opcional.
create or replace function public.save_school_billing_settings(
  p_school uuid,
  p_payer_role text default null,
  p_default_method text default null,
  p_due_days integer default null,
  p_legal_name text default null,
  p_billing_email text default null,
  p_purchase_order text default null,
  p_cost_center text default null,
  p_postal_code text default null,
  p_address_number text default null,
  p_phone text default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_owner boolean := public.is_school_member(p_school, array['owner']);
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'MM401';
  end if;
  if not (v_owner or public.school_is_payer(p_school)) then
    raise exception 'forbidden' using errcode = 'MM403';
  end if;
  if p_payer_role is not null and not v_owner then
    raise exception 'payer_owner_only' using errcode = 'MM403';
  end if;
  if p_payer_role = 'finance'
     and not exists(select 1 from public.school_members m
                    where m.school_id = p_school and m.role = 'finance' and m.status = 'active') then
    raise exception 'finance_member_required' using errcode = 'MM409';
  end if;
  insert into public.school_billing_settings(school_id, updated_by)
    values (p_school, v_uid)
    on conflict (school_id) do nothing;
  update public.school_billing_settings b set
    payer_role = coalesce(p_payer_role, b.payer_role),
    default_method = coalesce(p_default_method, b.default_method),
    due_days = coalesce(p_due_days, b.due_days),
    legal_name = coalesce(nullif(btrim(p_legal_name), ''), b.legal_name),
    billing_email = coalesce(nullif(lower(btrim(p_billing_email)), ''), b.billing_email),
    purchase_order = case when p_purchase_order is null then b.purchase_order
                          else nullif(btrim(p_purchase_order), '') end,
    cost_center = case when p_cost_center is null then b.cost_center
                       else nullif(btrim(p_cost_center), '') end,
    postal_code = case when p_postal_code is null then b.postal_code
                       else nullif(regexp_replace(p_postal_code, '[^0-9]', '', 'g'), '') end,
    address_number = case when p_address_number is null then b.address_number
                          else nullif(btrim(p_address_number), '') end,
    phone = case when p_phone is null then b.phone
                 else nullif(regexp_replace(p_phone, '[^0-9]', '', 'g'), '') end,
    updated_by = v_uid,
    updated_at = now()
  where b.school_id = p_school;
end;
$$;
revoke all on function public.save_school_billing_settings(uuid, text, text, integer, text, text, text, text, text, text, text)
  from public, anon;
grant execute on function public.save_school_billing_settings(uuid, text, text, integer, text, text, text, text, text, text, text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Faturas e eventos do gateway
-- ---------------------------------------------------------------------------

create table public.school_invoices (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  -- checkout: contratação/troca de plano, paga adiantada pelo número de alunos
  -- estimado; monthly: fechamento do mês pelos alunos ativos de verdade.
  kind text not null check (kind in ('checkout','monthly')),
  reference_month date not null check (reference_month = date_trunc('month', reference_month)::date),
  plan text not null check (plan in ('escola','plus')),
  cycle text not null check (cycle in ('monthly','annual')),
  students integer not null check (students >= 0),
  price_per_student numeric(8,2) not null,
  gross numeric(12,2) not null,
  volume_discount_percent integer not null default 0,
  discount numeric(12,2) not null default 0,
  minimum_applied boolean not null default false,
  extra_analyses integer not null default 0,
  extra_amount numeric(12,2) not null default 0,
  -- Já pago na contratação do mesmo mês (abatido no fechamento).
  credit numeric(12,2) not null default 0,
  total numeric(12,2) not null check (total >= 0),
  method text not null check (method in ('pix','boleto','credit_card')),
  status text not null default 'pending'
    check (status in ('pending','awaiting_payment','paid','overdue','canceled','failed')),
  due_date date not null,
  purchase_order text,
  cost_center text,
  provider text not null default 'asaas' check (provider in ('asaas')),
  provider_payment_id text,
  pix_payload text,
  pix_qr_image text check (pix_qr_image is null or length(pix_qr_image) <= 200000),
  pix_expires_at timestamptz,
  boleto_line text,
  invoice_url text,
  bank_slip_url text,
  card_brand text,
  card_last4 text,
  -- NFS-e agendada no Asaas depois do pagamento (POST /v3/invoices).
  nfse_provider_id text,
  nfse_status text check (nfse_status is null or nfse_status in ('scheduled','issued','error','canceled','not_configured')),
  nfse_number text,
  nfse_url text,
  receipt_number text,
  transaction_id text,
  failure_reason text,
  demo boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  issued_at timestamptz,
  paid_at timestamptz,
  updated_at timestamptz not null default now()
);
create unique index school_invoices_monthly_unique
  on public.school_invoices(school_id, reference_month) where kind = 'monthly';
create unique index school_invoices_provider_payment
  on public.school_invoices(provider, provider_payment_id) where provider_payment_id is not null;
create index school_invoices_school on public.school_invoices(school_id, created_at desc);
create index school_invoices_pending on public.school_invoices(status) where status = 'pending';

-- Webhooks recebidos: idempotência (o Asaas reenvia) e trilha de auditoria.
create table public.school_payment_events (
  id bigint generated always as identity primary key,
  provider text not null,
  event_id text not null,
  event text not null,
  provider_payment_id text,
  invoice_id uuid references public.school_invoices(id) on delete set null,
  payload jsonb not null,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  error text,
  unique (provider, event_id)
);

create or replace function public.school_invoices_touch()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger school_invoices_touch before update on public.school_invoices
  for each row execute function public.school_invoices_touch();

-- Pagamento confirmado pelo gateway. Idempotente. Na contratação, o plano da
-- escola muda aqui, na mesma transação.
create or replace function public.school_invoice_paid(
  p_invoice uuid, p_paid_at timestamptz default now(), p_transaction text default null)
returns public.school_invoices
language plpgsql security definer set search_path = '' as $$
declare
  v_inv public.school_invoices%rowtype;
begin
  select * into v_inv from public.school_invoices i where i.id = p_invoice for update;
  if not found then
    raise exception 'not_found' using errcode = 'MM404';
  end if;
  if v_inv.status = 'paid' then
    return v_inv;
  end if;
  if v_inv.status = 'canceled' then
    raise exception 'invoice_canceled' using errcode = 'MM409';
  end if;
  update public.school_invoices set
    status = 'paid',
    paid_at = coalesce(p_paid_at, now()),
    transaction_id = coalesce(p_transaction, transaction_id),
    receipt_number = coalesce(receipt_number,
      'MM-' || to_char(coalesce(p_paid_at, now()) at time zone 'America/Sao_Paulo', 'YYYY') || '-'
        || upper(substr(replace(id::text, '-', ''), 1, 8)))
  where id = p_invoice
  returning * into v_inv;
  if v_inv.kind = 'checkout' then
    update public.schools set plan = v_inv.plan, billing_cycle = v_inv.cycle,
      status = case when status in ('suspended','closed') then status else 'active' end
    where id = v_inv.school_id;
  end if;
  return v_inv;
end;
$$;
revoke all on function public.school_invoice_paid(uuid, timestamptz, text) from public, anon, authenticated;
grant execute on function public.school_invoice_paid(uuid, timestamptz, text) to service_role;

-- ---------------------------------------------------------------------------
-- Fechamento do mês
-- ---------------------------------------------------------------------------

-- Fecha o mês de todas as escolas pagas: congela o uso e cria a fatura
-- 'pending' (a Edge Function emite a cobrança depois). Idempotente.
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
    if r.plan not in ('escola','plus')
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

-- Chamado pelo pg_cron: avisa a Edge Function para emitir as cobranças
-- 'pending'. URL e segredo vêm do Vault; sem os dois, não faz nada.
create or replace function public.invoke_school_billing()
returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v_url text;
  v_secret text;
begin
  select s.decrypted_secret into v_url
    from vault.decrypted_secrets s where s.name = 'mistakemap_project_url';
  select s.decrypted_secret into v_secret
    from vault.decrypted_secrets s where s.name = 'school_billing_cron_secret';
  if coalesce(v_url, '') = '' or coalesce(length(v_secret), 0) < 24 then
    return null;
  end if;
  return net.http_post(
    url := rtrim(v_url, '/') || '/functions/v1/billing-webhook',
    body := '{"action":"issue_pending"}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', v_secret),
    timeout_milliseconds := 30000
  );
end;
$$;
revoke all on function public.invoke_school_billing() from public, anon, authenticated;
grant execute on function public.invoke_school_billing() to service_role;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'school-billing: pg_cron ausente; fechamento do mês não agendado.';
    return;
  end if;
  if exists (select 1 from cron.job where jobname = 'school-billing-close-month') then
    perform cron.unschedule('school-billing-close-month');
  end if;
  -- Dia 1, 06:00 de Brasília (09:00 UTC): fecha o mês anterior e emite.
  perform cron.schedule(
    'school-billing-close-month',
    '0 9 1 * *',
    'select public.school_close_month(); select public.invoke_school_billing();'
  );
  if exists (select 1 from cron.job where jobname = 'school-billing-retry') then
    perform cron.unschedule('school-billing-retry');
  end if;
  -- De hora em hora: reemite cobranças que ficaram 'pending' (gateway fora).
  perform cron.schedule(
    'school-billing-retry',
    '17 * * * *',
    'select public.invoke_school_billing() where exists (select 1 from public.school_invoices where status = ''pending'');'
  );
end
$$;

-- ---------------------------------------------------------------------------
-- RLS: o cliente só lê; toda escrita é do backend
-- ---------------------------------------------------------------------------

alter table public.school_plan_prices enable row level security;
alter table public.school_volume_discounts enable row level security;
alter table public.school_billing_settings enable row level security;
alter table public.school_invoices enable row level security;
alter table public.school_payment_events enable row level security;
revoke all on public.school_plan_prices, public.school_volume_discounts,
  public.school_billing_settings, public.school_invoices, public.school_payment_events
  from public, anon, authenticated;
grant all on public.school_plan_prices, public.school_volume_discounts,
  public.school_billing_settings, public.school_invoices, public.school_payment_events
  to service_role;

create policy school_plan_prices_read on public.school_plan_prices for select to authenticated
  using (true);
grant select on public.school_plan_prices to authenticated;
create policy school_volume_discounts_read on public.school_volume_discounts for select to authenticated
  using (true);
grant select on public.school_volume_discounts to authenticated;

-- Dono e financeiro veem quem paga e os dados de cobrança; coordenação vê só
-- quem paga (para saber a quem pedir). O token do cartão nunca vai ao app.
create policy school_billing_settings_read on public.school_billing_settings for select to authenticated
  using (public.is_school_member(school_id, array['owner','finance','coordinator']));
grant select (school_id, payer_role, default_method, due_days, legal_name, billing_email,
  purchase_order, cost_center, postal_code, address_number, phone, provider, card_brand,
  card_last4, demo, updated_by, updated_at)
  on public.school_billing_settings to authenticated;

-- Faturas: dono e financeiro. TI e coordenação não veem valores.
create policy school_invoices_read on public.school_invoices for select to authenticated
  using (public.is_school_member(school_id, array['owner','finance']));
grant select on public.school_invoices to authenticated;
-- school_payment_events: só o backend.
