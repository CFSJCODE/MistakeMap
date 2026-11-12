-- Planos da escola, cota coletiva de IA e aluno ativo (onda 1, item C do
-- plano consolidado por perfil). Depende de 20261111050000_schools_and_roles.
--
-- Regras:
-- * Aluno ativo = aluno (papel student, ativo) que usou o app no mês. "Usou" é
--   gravado no servidor: tentativa nova, sessão do catálogo, resposta no banco
--   de questões ou pedido de IA. Abrir o app só para ler não conta.
-- * O mês é o do calendário de Brasília (America/Sao_Paulo).
-- * O pote da escola é coletivo: análises_por_ativo × alunos ativos do mês
--   (Grátis 20, Escola 60, Plus 100). Nos planos pagos a análise além do pote
--   é liberada e contada como extra (R$ 0,15); no Grátis, o pote acaba.
-- * Treinos gerados por IA também saem de um pote (4, 15, 25 por ativo), sem
--   extra. Exercícios do catálogo revisado não gastam pote.
-- * Plano Grátis: até 5 usuários e 1 turma por escola.
-- * IA: Grátis e Escola usam o nível standard (Gemini); só o Plus tem premium
--   (Claude). Quem decide é o backend (model_router.ts), nunca o app.
-- * Nenhuma cobrança acontece aqui: o fechamento do mês e a fatura são o item D.
-- * Nada de HTTP em trigger: tudo aqui é SQL na mesma transação.

-- ---------------------------------------------------------------------------
-- Limites por plano (tabela de referência, editável só pelo backend)
-- ---------------------------------------------------------------------------

create table public.school_plan_limits (
  plan text primary key check (plan in ('free','escola','plus')),
  label text not null,
  max_users integer check (max_users is null or max_users > 0),
  max_classes integer check (max_classes is null or max_classes > 0),
  analyses_per_active integer not null check (analyses_per_active > 0),
  practices_per_active integer not null check (practices_per_active > 0),
  -- null = sem análise extra: o pote acaba e a IA para até o mês virar.
  extra_analysis_brl numeric(8,2) check (extra_analysis_brl is null or extra_analysis_brl >= 0),
  ai_tier text not null check (ai_tier in ('standard','premium')),
  updated_at timestamptz not null default now()
);

insert into public.school_plan_limits
  (plan, label, max_users, max_classes, analyses_per_active, practices_per_active, extra_analysis_brl, ai_tier)
values
  ('free',   'Grátis',       5,    1,    20,  4,  null, 'standard'),
  ('escola', 'Escola',       null, null, 60,  15, 0.15, 'standard'),
  ('plus',   'Escola Plus',  null, null, 100, 25, 0.15, 'premium');

-- ---------------------------------------------------------------------------
-- Uso do mês e registro de aluno ativo
-- ---------------------------------------------------------------------------

create or replace function public.school_usage_month(p_at timestamptz default now())
returns date
language sql stable set search_path = '' as $$
  select date_trunc('month', p_at at time zone 'America/Sao_Paulo')::date;
$$;
revoke all on function public.school_usage_month(timestamptz) from public, anon;
grant execute on function public.school_usage_month(timestamptz) to authenticated, service_role;

create table public.school_usage_months (
  school_id uuid not null references public.schools(id) on delete cascade,
  month date not null check (month = date_trunc('month', month)::date),
  -- Plano vigente no último uso do mês; o fechamento (item D) congela o valor.
  plan text not null check (plan in ('free','escola','plus')),
  active_students integer not null default 0 check (active_students >= 0),
  analyses integer not null default 0 check (analyses >= 0),
  extra_analyses integer not null default 0 check (extra_analyses >= 0),
  practices integer not null default 0 check (practices >= 0),
  -- Custo estimado de IA; preenchido quando houver medição por pedido (item F).
  ai_cost_usd numeric(12,6) not null default 0 check (ai_cost_usd >= 0),
  closed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (school_id, month)
);

-- Quem contou como ativo no mês (evita contar a mesma pessoa duas vezes).
-- O total cobrado é school_usage_months.active_students, que não diminui se a
-- conta for apagada depois.
create table public.school_active_students (
  school_id uuid not null,
  month date not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  first_activity text not null check (first_activity in ('attempt','practice_session','question','ai')),
  first_seen_at timestamptz not null default now(),
  primary key (school_id, month, user_id),
  foreign key (school_id, month) references public.school_usage_months(school_id, month) on delete cascade
);
create index school_active_students_user on public.school_active_students(user_id);

-- Marca o aluno como ativo no mês em toda escola onde ele é estudante.
create or replace function public.school_mark_active(p_user uuid, p_source text)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_month date := public.school_usage_month();
  r record;
begin
  if p_user is null then
    return;
  end if;
  for r in
    select m.school_id, s.plan
    from public.school_members m
    join public.schools s on s.id = m.school_id
    where m.user_id = p_user and m.role = 'student' and m.status = 'active'
      and s.status in ('pilot','active')
  loop
    insert into public.school_usage_months(school_id, month, plan)
      values (r.school_id, v_month, r.plan)
      on conflict (school_id, month) do nothing;
    insert into public.school_active_students(school_id, month, user_id, first_activity)
      values (r.school_id, v_month, p_user, p_source)
      on conflict (school_id, month, user_id) do nothing;
    if found then
      update public.school_usage_months
        set active_students = active_students + 1, plan = r.plan, updated_at = now()
        where school_id = r.school_id and month = v_month;
    end if;
  end loop;
end;
$$;
revoke all on function public.school_mark_active(uuid, text) from public, anon, authenticated;
grant execute on function public.school_mark_active(uuid, text) to service_role;

create or replace function public.school_activity_trigger()
returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.school_mark_active(new.user_id, tg_argv[0]);
  return null;
end;
$$;
revoke all on function public.school_activity_trigger() from public, anon, authenticated;

create trigger school_activity_attempt
  after insert on public.attempts
  for each row execute function public.school_activity_trigger('attempt');
create trigger school_activity_session
  after insert on public.platform_sessions
  for each row execute function public.school_activity_trigger('practice_session');
create trigger school_activity_question
  after insert on public.question_responses
  for each row execute function public.school_activity_trigger('question');

-- ---------------------------------------------------------------------------
-- Plano efetivo de quem usa a IA (platform_entitlements deriva daqui)
-- ---------------------------------------------------------------------------

-- Escola de melhor plano em que a pessoa é membro ativo (qualquer papel).
-- Sem escola, devolve nenhuma linha e vale o plano individual.
create or replace function public.user_school_plan(p_user uuid)
returns table(school_id uuid, school_name text, role text, plan text, plan_label text,
              ai_tier text, school_status text)
language sql stable security definer set search_path = '' as $$
  select s.id, s.name, m.role, s.plan, l.label, l.ai_tier, s.status
  from public.school_members m
  join public.schools s on s.id = m.school_id
  join public.school_plan_limits l on l.plan = s.plan
  where m.user_id = p_user and m.status = 'active' and s.status in ('pilot','active')
  order by case s.plan when 'plus' then 3 when 'escola' then 2 else 1 end desc,
           case m.role when 'student' then 0 else 1 end, m.joined_at
  limit 1;
$$;
revoke all on function public.user_school_plan(uuid) from public, anon, authenticated;
grant execute on function public.user_school_plan(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- Cota coletiva (chamada pelas Edge Functions, na transação do pedido de IA)
-- ---------------------------------------------------------------------------

-- p_kind: 'analysis', 'practice' ou 'none' (só marca o ativo e informa o nível
-- de IA, para materiais de estudo).
-- status: 'no_school' (vale a cota individual), 'ok' (saiu do pote),
-- 'extra' (pote esgotado; análise extra cobrável) ou 'exhausted' (recusar).
create or replace function public.consume_school_ai(p_user uuid, p_kind text)
returns table(status text, school_id uuid, plan text, ai_tier text, month date,
              pot integer, used integer)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_month date := public.school_usage_month();
  v_school uuid;
  v_plan text;
  v_limits public.school_plan_limits%rowtype;
  v_usage public.school_usage_months%rowtype;
  v_pot integer;
begin
  if p_kind not in ('analysis','practice','none') then
    raise exception 'invalid_kind' using errcode = '22023';
  end if;
  -- Pote é do estudante; professor e gestão usam a cota individual, mas com o
  -- nível de IA do plano da escola.
  select s.id, s.plan into v_school, v_plan
  from public.school_members m
  join public.schools s on s.id = m.school_id
  where m.user_id = p_user and m.role = 'student' and m.status = 'active'
    and s.status in ('pilot','active')
  order by case s.plan when 'plus' then 3 when 'escola' then 2 else 1 end desc, m.joined_at
  limit 1;
  if v_school is null then
    return query
      select 'no_school'::text, p.school_id, p.plan, coalesce(p.ai_tier, 'standard'), null::date,
             null::integer, null::integer
      from (select 1) one left join public.user_school_plan(p_user) p on true;
    return;
  end if;

  perform public.school_mark_active(p_user, 'ai');
  select * into v_limits from public.school_plan_limits l where l.plan = v_plan;
  select * into v_usage from public.school_usage_months u
    where u.school_id = v_school and u.month = v_month for update;

  if p_kind = 'none' then
    return query select 'ok'::text, v_school, v_plan, v_limits.ai_tier, v_month,
      null::integer, null::integer;
    return;
  end if;

  if p_kind = 'analysis' then
    v_pot := v_limits.analyses_per_active * v_usage.active_students;
    if v_usage.analyses < v_pot then
      update public.school_usage_months set analyses = analyses + 1, plan = v_plan, updated_at = now()
        where school_id = v_school and month = v_month;
      return query select 'ok'::text, v_school, v_plan, v_limits.ai_tier, v_month, v_pot, v_usage.analyses + 1;
    elsif v_limits.extra_analysis_brl is not null then
      update public.school_usage_months set extra_analyses = extra_analyses + 1, plan = v_plan, updated_at = now()
        where school_id = v_school and month = v_month;
      return query select 'extra'::text, v_school, v_plan, v_limits.ai_tier, v_month, v_pot, v_usage.analyses;
    else
      return query select 'exhausted'::text, v_school, v_plan, v_limits.ai_tier, v_month, v_pot, v_usage.analyses;
    end if;
    return;
  end if;

  v_pot := v_limits.practices_per_active * v_usage.active_students;
  if v_usage.practices < v_pot then
    update public.school_usage_months set practices = practices + 1, plan = v_plan, updated_at = now()
      where school_id = v_school and month = v_month;
    return query select 'ok'::text, v_school, v_plan, v_limits.ai_tier, v_month, v_pot, v_usage.practices + 1;
  else
    return query select 'exhausted'::text, v_school, v_plan, v_limits.ai_tier, v_month, v_pot, v_usage.practices;
  end if;
end;
$$;
revoke all on function public.consume_school_ai(uuid, text) from public, anon, authenticated;
grant execute on function public.consume_school_ai(uuid, text) to service_role;

-- Devolve ao pote um pedido que falhou (a IA não entregou resultado).
create or replace function public.release_school_ai(p_school uuid, p_month date, p_kind text, p_extra boolean)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_kind = 'analysis' and p_extra then
    update public.school_usage_months set extra_analyses = greatest(extra_analyses - 1, 0), updated_at = now()
      where school_id = p_school and month = p_month and closed_at is null;
  elsif p_kind = 'analysis' then
    update public.school_usage_months set analyses = greatest(analyses - 1, 0), updated_at = now()
      where school_id = p_school and month = p_month and closed_at is null;
  elsif p_kind = 'practice' then
    update public.school_usage_months set practices = greatest(practices - 1, 0), updated_at = now()
      where school_id = p_school and month = p_month and closed_at is null;
  end if;
end;
$$;
revoke all on function public.release_school_ai(uuid, date, text, boolean) from public, anon, authenticated;
grant execute on function public.release_school_ai(uuid, date, text, boolean) to service_role;

-- Resumo do pote para o painel do dono e da TI (item F). Sem dado pedagógico.
create or replace function public.school_quota(p_school uuid)
returns table(month date, plan text, plan_label text, active_students integer,
              analyses_pot integer, analyses_used integer, extra_analyses integer,
              extra_analyses_brl numeric, practices_pot integer, practices_used integer)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_month date := public.school_usage_month();
begin
  if not public.is_school_member(p_school, array['owner','coordinator','it_admin']) then
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
revoke all on function public.school_quota(uuid) from public, anon;
grant execute on function public.school_quota(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Limites do plano Grátis: 5 usuários e 1 turma
-- ---------------------------------------------------------------------------

create or replace function public.school_members_plan_limit()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_max integer;
begin
  if new.status <> 'active'
     or (tg_op = 'UPDATE' and old.status = 'active') then
    return new;
  end if;
  -- Trava a escola para dois convites simultâneos não passarem do limite.
  select l.max_users into v_max
  from public.schools s join public.school_plan_limits l on l.plan = s.plan
  where s.id = new.school_id for update of s;
  if v_max is not null
     and not exists(select 1 from public.school_members m
                    where m.school_id = new.school_id and m.user_id = new.user_id
                      and m.status = 'active')
     and (select count(distinct m.user_id) from public.school_members m
          where m.school_id = new.school_id and m.status = 'active') >= v_max then
    raise exception 'school_plan_user_limit' using errcode = 'MM402',
      hint = 'O plano Grátis vai até ' || v_max || ' usuários. Mude para o plano Escola.';
  end if;
  return new;
end;
$$;
revoke all on function public.school_members_plan_limit() from public, anon, authenticated;

create trigger school_members_plan_limit
  before insert or update of status on public.school_members
  for each row execute function public.school_members_plan_limit();

create or replace function public.platform_classes_plan_limit()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_max integer;
begin
  if new.school_id is null
     or (tg_op = 'UPDATE' and new.school_id is not distinct from old.school_id) then
    return new;
  end if;
  select l.max_classes into v_max
  from public.schools s join public.school_plan_limits l on l.plan = s.plan
  where s.id = new.school_id for update of s;
  if v_max is not null
     and (select count(*) from public.platform_classes c
          where c.school_id = new.school_id and c.id <> new.id) >= v_max then
    raise exception 'school_plan_class_limit' using errcode = 'MM402',
      hint = 'O plano Grátis tem ' || v_max || ' turma. Mude para o plano Escola.';
  end if;
  return new;
end;
$$;
revoke all on function public.platform_classes_plan_limit() from public, anon, authenticated;

create trigger platform_classes_plan_limit
  before insert or update of school_id on public.platform_classes
  for each row execute function public.platform_classes_plan_limit();

-- Voltar para o Grátis só cabe se a escola estiver dentro dos limites.
create or replace function public.schools_plan_change_guard()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_limits public.school_plan_limits%rowtype;
begin
  if new.plan is not distinct from old.plan then
    return new;
  end if;
  select * into v_limits from public.school_plan_limits l where l.plan = new.plan;
  if v_limits.max_users is not null
     and (select count(distinct m.user_id) from public.school_members m
          where m.school_id = new.id and m.status = 'active') > v_limits.max_users then
    raise exception 'school_plan_user_limit' using errcode = 'MM402',
      hint = 'A escola tem mais usuários do que o plano ' || v_limits.label || ' permite.';
  end if;
  if v_limits.max_classes is not null
     and (select count(*) from public.platform_classes c where c.school_id = new.id) > v_limits.max_classes then
    raise exception 'school_plan_class_limit' using errcode = 'MM402',
      hint = 'A escola tem mais turmas do que o plano ' || v_limits.label || ' permite.';
  end if;
  return new;
end;
$$;
revoke all on function public.schools_plan_change_guard() from public, anon, authenticated;

create trigger schools_plan_change_guard
  before update of plan on public.schools
  for each row execute function public.schools_plan_change_guard();

-- ---------------------------------------------------------------------------
-- RLS: o cliente só lê; toda escrita é do backend
-- ---------------------------------------------------------------------------

alter table public.school_plan_limits enable row level security;
alter table public.school_usage_months enable row level security;
alter table public.school_active_students enable row level security;
revoke all on public.school_plan_limits, public.school_usage_months, public.school_active_students
  from public, anon, authenticated;
grant all on public.school_plan_limits, public.school_usage_months, public.school_active_students
  to service_role;

-- Tabela de preços e limites é pública para quem está logado.
create policy school_plan_limits_read on public.school_plan_limits for select to authenticated
  using (true);
grant select on public.school_plan_limits to authenticated;

-- Uso e ativos: dono, coordenador e TI da escola (consumo, não desempenho).
create policy school_usage_months_staff_read on public.school_usage_months for select to authenticated
  using (public.is_school_member(school_id, array['owner','coordinator','it_admin']));
grant select on public.school_usage_months to authenticated;

create policy school_active_students_staff_read on public.school_active_students for select to authenticated
  using (public.is_school_member(school_id, array['owner','coordinator','it_admin']));
grant select on public.school_active_students to authenticated;
