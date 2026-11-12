-- Orçamento do MistakeMap, conservador em qualquer janela móvel de 31 dias.
-- Reservas sem confirmação permanecem contabilizadas até sair da janela.
create table public.ai_budget_reservations (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  model text not null,
  reserved_usd numeric(12,6) not null check (reserved_usd > 0),
  settled_usd numeric(12,6) check (settled_usd >= 0 and settled_usd <= reserved_usd),
  settled_at timestamptz,
  check ((settled_usd is null) = (settled_at is null))
);
create index ai_budget_reservations_created_idx on public.ai_budget_reservations(created_at);
alter table public.ai_budget_reservations enable row level security;
revoke all on public.ai_budget_reservations from public, anon, authenticated;
grant select, insert, update on public.ai_budget_reservations to service_role;

create function public.reserve_claude_budget(p_model text, p_reservation numeric)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare used_amount numeric; reservation_id uuid;
begin
  if p_model <> 'claude-sonnet-5-5' or p_reservation <> 1 then
    raise exception 'invalid budget request';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(387722883, 100);
  select coalesce(sum(coalesce(settled_usd, reserved_usd)), 0) into used_amount
    from public.ai_budget_reservations where created_at > pg_catalog.now() - interval '31 days';
  if used_amount + p_reservation > 100 then return null; end if;
  insert into public.ai_budget_reservations(model, reserved_usd)
    values (p_model, p_reservation) returning id into reservation_id;
  return reservation_id;
end;
$$;
revoke all on function public.reserve_claude_budget(text, numeric) from public, anon, authenticated;
grant execute on function public.reserve_claude_budget(text, numeric) to service_role;
