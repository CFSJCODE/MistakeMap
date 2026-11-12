-- Cadastro por perfil "Quem é você?" (onda 1, item B do plano consolidado).
--
-- Depende de 20261111050000_schools_and_roles (escola, papéis e convites).
--
-- O que entra aqui:
-- * user_signups: o perfil escolhido no cadastro e a data de nascimento do
--   estudante. O perfil é só um pedido: papel de escola continua vindo apenas
--   de convite (trigger school_members_guard).
-- * guardian_consent_requests e guardian_links: menor de 18 anos sem escola
--   só usa a IA depois do aceite do responsável (LGPD, art. 14).
-- * school_teams e school_team_members: equipe de robótica com código e função.
-- * guardian_consent_pending(): conferida pelas Edge Functions de IA.
--
-- Regras de sempre: o cliente só lê (RLS); toda escrita passa por funções
-- security definer com search_path vazio, chamadas pela Edge Function
-- school-admin; códigos ficam só como hash SHA-256.

-- ---------------------------------------------------------------------------
-- Perfil escolhido no cadastro
-- ---------------------------------------------------------------------------

create table public.user_signups (
  user_id uuid primary key references auth.users(id) on delete cascade,
  persona text not null check (persona in
    ('student','student_team','teacher','guardian','owner','coordinator','it_admin')),
  birth_date date check (birth_date is null or birth_date >= date '1900-01-01'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Estudante sempre informa a data de nascimento.
  check (persona not in ('student','student_team') or birth_date is not null)
);

-- ---------------------------------------------------------------------------
-- Consentimento do responsável (menor sem escola)
-- ---------------------------------------------------------------------------

-- Código que o estudante mostra ao responsável. Uso único, vale 7 dias.
create table public.guardian_consent_requests (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references auth.users(id) on delete cascade,
  code_hash text not null unique check (code_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz,
  used_by uuid references auth.users(id) on delete set null,
  check (expires_at > created_at)
);
create index guardian_consent_requests_student
  on public.guardian_consent_requests(student_id, created_at desc);

-- Vínculo responsável → estudante com a versão do termo aceito.
create table public.guardian_links (
  guardian_id uuid not null references auth.users(id) on delete cascade,
  student_id uuid not null references auth.users(id) on delete cascade,
  consent_version text not null check (char_length(consent_version) between 1 and 40),
  consented_at timestamptz not null default now(),
  revoked_at timestamptz,
  primary key (guardian_id, student_id),
  check (guardian_id <> student_id)
);
create index guardian_links_student on public.guardian_links(student_id);

-- ---------------------------------------------------------------------------
-- Equipes de robótica
-- ---------------------------------------------------------------------------

create table public.school_teams (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 2 and 120),
  competition text not null default 'projeto'
    check (competition in ('obr','fll','ftc','frc','projeto','outra')),
  code_hash text not null unique check (code_hash ~ '^[0-9a-f]{64}$'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  archived_at timestamptz
);
create index school_teams_school on public.school_teams(school_id);

create table public.school_team_members (
  team_id uuid not null references public.school_teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  team_role text not null check (team_role in ('programacao','mecanica','eletronica','estrategia')),
  joined_at timestamptz not null default now(),
  primary key (team_id, user_id)
);
create index school_team_members_user on public.school_team_members(user_id);

-- ---------------------------------------------------------------------------
-- Conferências (security definer, search_path vazio: sem recursão de RLS)
-- ---------------------------------------------------------------------------

create or replace function public.code_digest(p_code text)
returns text
language sql immutable set search_path = '' as $$
  select encode(sha256(convert_to(upper(btrim(coalesce(p_code, ''))), 'UTF8')), 'hex');
$$;
revoke all on function public.code_digest(text) from public, anon;
grant execute on function public.code_digest(text) to authenticated, service_role;

-- Código curto, legível e sem caracteres ambíguos (0/O, 1/I).
create or replace function public.new_short_code()
returns text
language sql volatile set search_path = '' as $$
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
           1 + (get_byte(b, i) % 32), 1), '' order by i)
  from (select decode(replace(gen_random_uuid()::text, '-', ''), 'hex') as b) r,
       generate_series(0, 11) as i;
$$;
revoke all on function public.new_short_code() from public, anon, authenticated;
grant execute on function public.new_short_code() to service_role;

create or replace function public.is_team_member(p_team uuid)
returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.school_team_members m
                where m.team_id = p_team and m.user_id = (select auth.uid()));
$$;
revoke all on function public.is_team_member(uuid) from public, anon;
grant execute on function public.is_team_member(uuid) to authenticated, service_role;

-- Menor de 18 anos, estudante, sem escola e sem aceite do responsável.
-- Conta antiga sem data de nascimento não é bloqueada.
create or replace function public.guardian_consent_pending(p_user uuid)
returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(
      select 1 from public.user_signups s
      where s.user_id = p_user
        and s.persona in ('student','student_team')
        and s.birth_date is not null
        and s.birth_date > (current_date - interval '18 years')::date)
    and not exists(
      select 1 from public.school_members m
      where m.user_id = p_user and m.role = 'student' and m.status = 'active')
    and not exists(
      select 1 from public.platform_memberships pm
      join public.platform_classes c on c.id = pm.class_id
      where pm.user_id = p_user and c.school_id is not null)
    and not exists(
      select 1 from public.guardian_links g
      where g.student_id = p_user and g.revoked_at is null);
$$;
revoke all on function public.guardian_consent_pending(uuid) from public, anon, authenticated;
grant execute on function public.guardian_consent_pending(uuid) to service_role;

create or replace function public.my_guardian_consent_pending()
returns boolean
language sql stable security definer set search_path = '' as $$
  select public.guardian_consent_pending((select auth.uid()));
$$;
revoke all on function public.my_guardian_consent_pending() from public, anon;
grant execute on function public.my_guardian_consent_pending() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Operações
-- ---------------------------------------------------------------------------

-- Grava (ou troca) o perfil escolhido. Não concede papel nenhum.
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
     ('student','student_team','teacher','guardian','owner','coordinator','it_admin') then
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

-- O estudante pede um código para o responsável. Apaga os pedidos abertos.
create or replace function public.request_guardian_consent()
returns table(code text, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_code text := public.new_short_code();
  v_expires timestamptz := now() + interval '7 days';
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'MM401';
  end if;
  if not public.guardian_consent_pending(v_uid) then
    raise exception 'consent_not_required' using errcode = 'MM409';
  end if;
  if (select count(*) from public.guardian_consent_requests r
      where r.student_id = v_uid and r.created_at > now() - interval '1 day') >= 10 then
    raise exception 'too_many_requests' using errcode = 'MM429';
  end if;
  delete from public.guardian_consent_requests r
    where r.student_id = v_uid and r.used_at is null;
  insert into public.guardian_consent_requests(student_id, code_hash, expires_at)
    values (v_uid, public.code_digest(v_code), v_expires);
  return query select v_code, v_expires;
end;
$$;

-- O responsável, na própria conta, aceita o termo com o código do estudante.
create or replace function public.grant_guardian_consent(p_code text, p_version text)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_req public.guardian_consent_requests%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'MM401';
  end if;
  if p_version is null or char_length(btrim(p_version)) not between 1 and 40 then
    raise exception 'invalid_version' using errcode = '22023';
  end if;
  select * into v_req from public.guardian_consent_requests r
    where r.code_hash = public.code_digest(p_code) for update;
  if not found or v_req.used_at is not null or v_req.expires_at <= now() then
    raise exception 'consent_code_invalid' using errcode = 'MM404';
  end if;
  if v_req.student_id = v_uid then
    raise exception 'guardian_is_student' using errcode = 'MM403',
      hint = 'O aceite precisa ser feito na conta do responsável.';
  end if;
  -- Responsável que informou nascimento precisa ser maior de idade.
  if exists(select 1 from public.user_signups s
            where s.user_id = v_uid and s.birth_date is not null
              and s.birth_date > (current_date - interval '18 years')::date) then
    raise exception 'guardian_minor' using errcode = 'MM403';
  end if;
  update public.guardian_consent_requests
    set used_at = now(), used_by = v_uid where id = v_req.id;
  insert into public.guardian_links(guardian_id, student_id, consent_version)
    values (v_uid, v_req.student_id, btrim(p_version))
  on conflict (guardian_id, student_id) do update
    set consent_version = excluded.consent_version,
        consented_at = now(), revoked_at = null;
  return v_req.student_id;
end;
$$;

create or replace function public.revoke_guardian_consent(p_student uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'MM401';
  end if;
  update public.guardian_links set revoked_at = coalesce(revoked_at, now())
    where guardian_id = v_uid and student_id = p_student;
  if not found then
    raise exception 'not_found' using errcode = 'MM404';
  end if;
end;
$$;

-- Filhos que o responsável acompanha (e-mail do estudante para reconhecer).
create or replace function public.my_guardian_children()
returns table(student_id uuid, email text, consent_version text,
              consented_at timestamptz, revoked_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select g.student_id, u.email::text, g.consent_version, g.consented_at, g.revoked_at
  from public.guardian_links g
  join auth.users u on u.id = g.student_id
  where g.guardian_id = (select auth.uid())
  order by g.consented_at desc;
$$;

-- Equipe nova: dono, coordenador ou professor da escola. Código só aqui.
create or replace function public.create_school_team(p_school uuid, p_name text, p_competition text default 'projeto')
returns table(team_id uuid, code text)
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_code text := public.new_short_code();
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'MM401';
  end if;
  if not public.is_school_member(p_school, array['owner','coordinator','teacher']) then
    raise exception 'forbidden' using errcode = 'MM403';
  end if;
  if (select count(*) from public.school_teams t
      where t.school_id = p_school and t.archived_at is null) >= 50 then
    raise exception 'team_limit_reached' using errcode = 'MM429';
  end if;
  insert into public.school_teams(school_id, name, competition, code_hash, created_by)
    values (p_school, btrim(p_name), coalesce(p_competition, 'projeto'),
            public.code_digest(v_code), v_uid)
    returning id into v_id;
  return query select v_id, v_code;
end;
$$;

-- Entra na equipe pelo código (ou troca a própria função nela).
create or replace function public.join_school_team(p_code text, p_team_role text)
returns table(team_id uuid, team_name text, school_id uuid)
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_team public.school_teams%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'MM401';
  end if;
  if p_team_role is null or p_team_role not in ('programacao','mecanica','eletronica','estrategia') then
    raise exception 'invalid_team_role' using errcode = '22023';
  end if;
  select * into v_team from public.school_teams t
    where t.code_hash = public.code_digest(p_code) and t.archived_at is null;
  if not found then
    raise exception 'team_code_invalid' using errcode = 'MM404';
  end if;
  if (select count(*) from public.school_team_members m where m.team_id = v_team.id) >= 60
     and not exists(select 1 from public.school_team_members m
                    where m.team_id = v_team.id and m.user_id = v_uid) then
    raise exception 'team_full' using errcode = 'MM429';
  end if;
  insert into public.school_team_members(team_id, user_id, team_role)
    values (v_team.id, v_uid, p_team_role)
  on conflict on constraint school_team_members_pkey
    do update set team_role = excluded.team_role;
  return query select v_team.id, v_team.name, v_team.school_id;
end;
$$;

create or replace function public.leave_school_team(p_team uuid)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = 'MM401';
  end if;
  delete from public.school_team_members m
    where m.team_id = p_team and m.user_id = (select auth.uid());
end;
$$;

revoke all on function public.save_signup_profile(text, date),
  public.request_guardian_consent(),
  public.grant_guardian_consent(text, text),
  public.revoke_guardian_consent(uuid),
  public.my_guardian_children(),
  public.create_school_team(uuid, text, text),
  public.join_school_team(text, text),
  public.leave_school_team(uuid) from public, anon;
grant execute on function public.save_signup_profile(text, date),
  public.request_guardian_consent(),
  public.grant_guardian_consent(text, text),
  public.revoke_guardian_consent(uuid),
  public.my_guardian_children(),
  public.create_school_team(uuid, text, text),
  public.join_school_team(text, text),
  public.leave_school_team(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- RLS: o cliente só lê
-- ---------------------------------------------------------------------------

alter table public.user_signups enable row level security;
alter table public.guardian_consent_requests enable row level security;
alter table public.guardian_links enable row level security;
alter table public.school_teams enable row level security;
alter table public.school_team_members enable row level security;
revoke all on public.user_signups, public.guardian_consent_requests, public.guardian_links,
  public.school_teams, public.school_team_members from public, anon, authenticated;
grant all on public.user_signups, public.guardian_consent_requests, public.guardian_links,
  public.school_teams, public.school_team_members to service_role;

create policy user_signups_owner_read on public.user_signups for select to authenticated
  using (user_id = (select auth.uid()));
grant select on public.user_signups to authenticated;

-- Pedidos de consentimento: o estudante vê os próprios (sem o hash).
create policy guardian_consent_requests_owner_read on public.guardian_consent_requests
  for select to authenticated using (student_id = (select auth.uid()));
grant select (id, student_id, created_at, expires_at, used_at)
  on public.guardian_consent_requests to authenticated;

-- Vínculo: responsável e estudante veem o deles.
create policy guardian_links_party_read on public.guardian_links for select to authenticated
  using (guardian_id = (select auth.uid()) or student_id = (select auth.uid()));
grant select on public.guardian_links to authenticated;

-- Equipe: membros e a escola (dono, coordenação, professores e TI) veem; nunca o hash.
create policy school_teams_read on public.school_teams for select to authenticated
  using (public.is_team_member(id)
         or public.is_school_member(school_id, array['owner','coordinator','it_admin','teacher']));
grant select (id, school_id, name, competition, created_by, created_at, archived_at)
  on public.school_teams to authenticated;

create policy school_team_members_read on public.school_team_members for select to authenticated
  using (user_id = (select auth.uid())
         or public.is_team_member(team_id)
         or exists(select 1 from public.school_teams t
                   where t.id = team_id
                     and public.is_school_member(t.school_id,
                           array['owner','coordinator','it_admin','teacher'])));
grant select on public.school_team_members to authenticated;
