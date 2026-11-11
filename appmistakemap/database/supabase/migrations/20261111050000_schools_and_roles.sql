-- Escola e papéis (onda 1, item A do plano consolidado por perfil).
--
-- Base para cadastro por perfil, cota coletiva, cobrança, contrato e painéis.
-- Ainda sem telas e sem cobrança: aqui só existem a escola, quem participa dela
-- com qual papel e o convite que dá esse papel.
--
-- Regras:
-- * O cliente só lê (RLS). Toda escrita passa pelas funções abaixo
--   (security definer) ou pela Edge Function school-admin com service_role.
-- * Nenhum papel entra sem convite válido, exceto o dono fundador da escola.
--   Quem confere é o trigger de school_members, então nem uma Edge Function
--   com bug consegue pular o convite.
-- * is_school_member() é security definer com search_path fixo, para as
--   políticas não lerem school_members por dentro de uma política de
--   school_members (a recursão das migrations 20260929112200 e 20261109221500).
-- * O código do convite é mostrado uma vez a quem o cria; no banco fica só o
--   hash SHA-256.

create table public.schools (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 2 and 160),
  cnpj text check (cnpj ~ '^[0-9]{14}$'),
  plan text not null default 'free' check (plan in ('free','escola','plus')),
  billing_cycle text not null default 'monthly' check (billing_cycle in ('monthly','annual')),
  status text not null default 'active' check (status in ('pilot','active','suspended','closed')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index schools_cnpj_unique on public.schools(cnpj) where cnpj is not null;
create index schools_created_by on public.schools(created_by);

create table public.school_invites (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  role text not null check (role in ('owner','coordinator','it_admin','teacher','student','guardian')),
  code_hash text not null unique check (code_hash ~ '^[0-9a-f]{64}$'),
  email text check (email is null or email = lower(btrim(email))),
  max_uses integer not null default 1 check (max_uses between 1 and 1000),
  uses integer not null default 0 check (uses >= 0 and uses <= max_uses),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  check (expires_at > created_at),
  -- Convite de gestão é pessoal: serve para uma pessoa só.
  check (role not in ('owner','coordinator','it_admin') or max_uses = 1)
);
create index school_invites_school on public.school_invites(school_id, created_at desc);

create table public.school_members (
  school_id uuid not null references public.schools(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','coordinator','it_admin','teacher','student','guardian')),
  status text not null default 'active' check (status in ('active','suspended')),
  invite_id uuid references public.school_invites(id) on delete set null,
  invited_by uuid references auth.users(id) on delete set null,
  joined_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (school_id, user_id, role)
);
create index school_members_user on public.school_members(user_id);

-- Turmas passam a poder pertencer a uma escola. Turmas antigas ficam sem escola.
alter table public.platform_classes
  add column school_id uuid references public.schools(id) on delete set null;
create index platform_classes_school on public.platform_classes(school_id) where school_id is not null;

-- ---------------------------------------------------------------------------
-- Conferência de papel (usada pelas políticas e pelas funções)
-- ---------------------------------------------------------------------------

create or replace function public.is_school_member(p_school uuid, p_roles text[] default null)
returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(
    select 1 from public.school_members m
    where m.school_id = p_school
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and (p_roles is null or m.role = any(p_roles)));
$$;
revoke all on function public.is_school_member(uuid, text[]) from public, anon;
grant execute on function public.is_school_member(uuid, text[]) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Triggers de integridade
-- ---------------------------------------------------------------------------

create or replace function public.school_members_guard()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_invite public.school_invites%rowtype;
  v_email text;
begin
  if tg_op = 'UPDATE' then
    if new.school_id is distinct from old.school_id
       or new.user_id is distinct from old.user_id
       or new.role is distinct from old.role
       or (new.invite_id is distinct from old.invite_id and new.invite_id is not null) then
      raise exception 'school_member_immutable'
        using errcode = 'MM403', hint = 'Troca de papel exige um convite novo.';
    end if;
    new.updated_at := now();
    return new;
  end if;

  -- Dono fundador: quem criou a escola entra como dono sem convite, uma vez.
  if new.invite_id is null then
    if new.role = 'owner'
       and exists(select 1 from public.schools s
                  where s.id = new.school_id and s.created_by = new.user_id)
       and not exists(select 1 from public.school_members m
                      where m.school_id = new.school_id and m.role = 'owner') then
      return new;
    end if;
    raise exception 'school_invite_required'
      using errcode = 'MM403', hint = 'Papel ' || new.role || ' só entra com convite válido.';
  end if;

  select * into v_invite from public.school_invites i
    where i.id = new.invite_id for update;
  if not found
     or v_invite.school_id <> new.school_id
     or v_invite.role <> new.role
     or v_invite.revoked_at is not null
     or v_invite.expires_at <= now()
     or v_invite.uses >= v_invite.max_uses then
    raise exception 'school_invite_invalid' using errcode = 'MM404';
  end if;
  if v_invite.email is not null then
    select lower(u.email) into v_email from auth.users u where u.id = new.user_id;
    if v_email is distinct from v_invite.email then
      raise exception 'school_invite_invalid' using errcode = 'MM404',
        hint = 'Convite destinado a outro e-mail.';
    end if;
  end if;

  -- O convite é consumido aqui, por qualquer caminho de inserção.
  update public.school_invites set uses = uses + 1 where id = v_invite.id;
  new.invited_by := coalesce(new.invited_by, v_invite.created_by);
  return new;
end;
$$;
revoke all on function public.school_members_guard() from public, anon, authenticated;

create trigger school_members_guard
  before insert or update on public.school_members
  for each row execute function public.school_members_guard();

-- Turma de escola só pode ser de quem dá aula nela.
create or replace function public.platform_classes_school_guard()
returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.school_id is not null
     and (tg_op = 'INSERT'
          or new.school_id is distinct from old.school_id
          or new.teacher_id is distinct from old.teacher_id)
     and not exists(select 1 from public.school_members m
                    where m.school_id = new.school_id and m.user_id = new.teacher_id
                      and m.status = 'active'
                      and m.role in ('teacher','coordinator','owner')) then
    raise exception 'class_teacher_not_in_school' using errcode = 'MM403';
  end if;
  return new;
end;
$$;
revoke all on function public.platform_classes_school_guard() from public, anon, authenticated;

create trigger platform_classes_school_guard
  before insert or update of school_id, teacher_id on public.platform_classes
  for each row execute function public.platform_classes_school_guard();

create or replace function public.schools_touch()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger schools_touch before update on public.schools
  for each row execute function public.schools_touch();

-- ---------------------------------------------------------------------------
-- Operações (chamadas pelo app via RPC ou pela Edge Function school-admin)
-- ---------------------------------------------------------------------------

-- Cria a escola no plano Grátis com quem chamou como dono.
create or replace function public.create_school(p_name text, p_cnpj text default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_school uuid;
  v_cnpj text := nullif(regexp_replace(coalesce(p_cnpj, ''), '[^0-9]', '', 'g'), '');
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'MM401';
  end if;
  if (select count(*) from public.schools s where s.created_by = v_uid) >= 5 then
    raise exception 'school_limit_reached' using errcode = 'MM429';
  end if;
  insert into public.schools(name, cnpj, created_by)
    values (btrim(p_name), v_cnpj, v_uid)
    returning id into v_school;
  insert into public.school_members(school_id, user_id, role)
    values (v_school, v_uid, 'owner');
  return v_school;
end;
$$;

-- Cria um convite e devolve o código (única vez em que ele aparece).
-- Dono convida qualquer papel; coordenador e TI convidam professor,
-- estudante e responsável. Gestão (dono, coordenador, TI) só o dono convida.
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
  if p_role in ('owner','coordinator','it_admin') then
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

-- Resgata um convite: quem chamou ganha o papel na escola.
-- Se já tem esse papel, nada muda e o convite não é gasto.
create or replace function public.redeem_school_invite(p_code text)
returns table(school_id uuid, role text)
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_invite public.school_invites%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'MM401';
  end if;
  select * into v_invite from public.school_invites i
    where i.code_hash = encode(sha256(convert_to(upper(btrim(coalesce(p_code, ''))), 'UTF8')), 'hex');
  if not found then
    raise exception 'school_invite_invalid' using errcode = 'MM404';
  end if;
  if not exists(select 1 from public.school_members m
                where m.school_id = v_invite.school_id and m.user_id = v_uid
                  and m.role = v_invite.role) then
    -- Validade, e-mail e consumo do convite são conferidos no trigger.
    insert into public.school_members(school_id, user_id, role, invite_id)
      values (v_invite.school_id, v_uid, v_invite.role, v_invite.id);
  end if;
  return query select v_invite.school_id, v_invite.role;
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
       case when v_invite.role in ('owner','coordinator','it_admin')
            then array['owner'] else array['owner','coordinator','it_admin'] end) then
    raise exception 'forbidden' using errcode = 'MM403';
  end if;
  update public.school_invites set revoked_at = coalesce(revoked_at, now()) where id = p_invite;
end;
$$;

revoke all on function public.create_school(text, text),
  public.create_school_invite(uuid, text, text, integer, integer),
  public.redeem_school_invite(text),
  public.revoke_school_invite(uuid) from public, anon;
grant execute on function public.create_school(text, text),
  public.create_school_invite(uuid, text, text, integer, integer),
  public.redeem_school_invite(text),
  public.revoke_school_invite(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- RLS: o cliente só lê
-- ---------------------------------------------------------------------------

alter table public.schools enable row level security;
alter table public.school_members enable row level security;
alter table public.school_invites enable row level security;
revoke all on public.schools, public.school_members, public.school_invites
  from public, anon, authenticated;
grant all on public.schools, public.school_members, public.school_invites to service_role;

-- Qualquer membro ativo vê a escola dele; ninguém vê escola alheia.
create policy schools_member_read on public.schools for select to authenticated
  using (public.is_school_member(id));
grant select on public.schools to authenticated;

-- Cada um vê os próprios papéis; dono, coordenador e TI veem todos da escola.
create policy school_members_read on public.school_members for select to authenticated
  using (user_id = (select auth.uid())
         or public.is_school_member(school_id, array['owner','coordinator','it_admin']));
grant select on public.school_members to authenticated;

-- Convites: só a gestão vê, e nunca o hash do código.
create policy school_invites_staff_read on public.school_invites for select to authenticated
  using (public.is_school_member(school_id, array['owner','coordinator','it_admin']));
grant select (id, school_id, role, email, max_uses, uses, created_by, created_at, expires_at, revoked_at)
  on public.school_invites to authenticated;

-- A gestão da escola enxerga as turmas da escola (título e professor, sem
-- respostas nem mapa de aluno). As políticas antigas de turma continuam valendo.
create policy platform_class_school_staff_read on public.platform_classes for select to authenticated
  using (school_id is not null
         and public.is_school_member(school_id, array['owner','coordinator','it_admin']));
