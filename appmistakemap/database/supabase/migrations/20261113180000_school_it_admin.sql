-- Funções do perfil TI da escola (it_admin).
--
-- A TI administra contas e acessos, nunca dado pedagógico nem financeiro:
-- * diretório de pessoas da escola (e-mail, nome, papéis, situação, último
--   acesso, aparelhos conectados) e exportação em CSV pelo app;
-- * suspender, reativar e remover um papel; encerrar as sessões de uma conta
--   em todos os aparelhos; pedir o e-mail de redefinição de senha;
-- * convites em lote (planilha colada) e renovação de convite;
-- * uso de licenças do plano (usuários, turmas, alunos ativos, pote de IA),
--   sem valores em reais;
-- * registro de auditoria de tudo que muda papéis e convites.
--
-- Regras:
-- * O cliente só lê o que as funções devolvem. Toda escrita passa por funções
--   security definer chamadas pela Edge Function school-admin como o usuário
--   (role authenticated + sub do JWT), igual às migrations anteriores.
-- * Dono e TI administram professor, estudante e responsável. Papéis de gestão
--   (dono, coordenação, TI, Financeiro) só o dono administra, e o papel de
--   dono não é suspenso nem removido por aqui. Ninguém age sobre si mesmo.
-- * Ações na conta inteira (sessões, senha) exigem que a pessoa não tenha papel
--   de gestão em outra escola nem seja da equipe MistakeMap (profiles.role
--   admin/developer): a TI de uma escola não derruba a conta de outra.
-- * Auditoria gravada por trigger na mesma transação (sem HTTP em trigger).

-- ---------------------------------------------------------------------------
-- Registro de auditoria
-- ---------------------------------------------------------------------------

create table public.school_audit_log (
  id bigint generated always as identity primary key,
  school_id uuid not null references public.schools(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null check (action in (
    'member_joined','member_suspended','member_reactivated','member_removed',
    'invite_created','invite_revoked','invites_imported','invite_renewed',
    'sessions_revoked','password_reset_sent')),
  target_user uuid references auth.users(id) on delete set null,
  target_role text,
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default now()
);
create index school_audit_log_school on public.school_audit_log(school_id, created_at desc, id desc);
create index school_audit_log_actor on public.school_audit_log(actor_id) where actor_id is not null;
create index school_audit_log_target on public.school_audit_log(target_user) where target_user is not null;

alter table public.school_audit_log enable row level security;
revoke all on public.school_audit_log from public, anon, authenticated;
grant all on public.school_audit_log to service_role;
create policy school_audit_log_read on public.school_audit_log for select to authenticated
  using (public.is_school_member(school_id, array['owner','it_admin']));
grant select on public.school_audit_log to authenticated;

create or replace function public.school_audit_write(
  p_school uuid, p_action text, p_target uuid, p_role text, p_details jsonb default '{}'::jsonb)
returns void
language sql security definer set search_path = '' as $$
  insert into public.school_audit_log(school_id, actor_id, action, target_user, target_role, details)
  values (p_school, (select auth.uid()), p_action, p_target, p_role, coalesce(p_details, '{}'::jsonb));
$$;
revoke all on function public.school_audit_write(uuid, text, uuid, text, jsonb) from public, anon, authenticated;

create or replace function public.school_members_audit()
returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    perform public.school_audit_write(new.school_id, 'member_joined', new.user_id, new.role,
      jsonb_build_object('invite_id', new.invite_id));
  elsif tg_op = 'UPDATE' then
    if new.status is distinct from old.status then
      perform public.school_audit_write(new.school_id,
        case when new.status = 'suspended' then 'member_suspended' else 'member_reactivated' end,
        new.user_id, new.role, '{}'::jsonb);
    end if;
  elsif tg_op = 'DELETE' then
    -- Escola ou conta apagada: o registro iria contra uma chave que já não
    -- existe (e travaria a exclusão da conta). Só grava remoção de papel.
    if exists(select 1 from public.schools s where s.id = old.school_id)
       and exists(select 1 from auth.users u where u.id = old.user_id) then
      perform public.school_audit_write(old.school_id, 'member_removed', old.user_id, old.role, '{}'::jsonb);
    end if;
    return old;
  end if;
  return new;
end;
$$;
revoke all on function public.school_members_audit() from public, anon, authenticated;

create trigger school_members_audit
  after insert or update of status or delete on public.school_members
  for each row execute function public.school_members_audit();

create or replace function public.school_invites_audit()
returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    perform public.school_audit_write(new.school_id, 'invite_created', null, new.role,
      jsonb_build_object('invite_id', new.id, 'email', new.email, 'max_uses', new.max_uses));
  elsif new.revoked_at is not null and old.revoked_at is null then
    perform public.school_audit_write(new.school_id, 'invite_revoked', null, new.role,
      jsonb_build_object('invite_id', new.id, 'email', new.email));
  end if;
  return new;
end;
$$;
revoke all on function public.school_invites_audit() from public, anon, authenticated;

create trigger school_invites_audit
  after insert or update of revoked_at on public.school_invites
  for each row execute function public.school_invites_audit();

-- ---------------------------------------------------------------------------
-- Conferência de permissão
-- ---------------------------------------------------------------------------

-- Quem chamou pode administrar este papel nesta escola?
create or replace function public.school_can_manage_role(p_school uuid, p_role text)
returns boolean
language sql stable security definer set search_path = '' as $$
  select case
    when p_role = 'owner' then false
    when p_role in ('coordinator','it_admin','finance')
      then public.is_school_member(p_school, array['owner'])
    when p_role in ('teacher','student','guardian')
      then public.is_school_member(p_school, array['owner','it_admin'])
    else false end;
$$;
revoke all on function public.school_can_manage_role(uuid, text) from public, anon;
grant execute on function public.school_can_manage_role(uuid, text) to authenticated, service_role;

-- Ação na conta inteira (sessões, senha): a pessoa é da escola, não é quem
-- chamou, todos os papéis dela aqui são administráveis por quem chamou, não
-- tem gestão em outra escola e não é da equipe MistakeMap.
create or replace function public.school_can_manage_account(p_school uuid, p_user uuid)
returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  if p_user is null or p_user = (select auth.uid()) then
    return false;
  end if;
  if not exists(select 1 from public.school_members m
                where m.school_id = p_school and m.user_id = p_user) then
    return false;
  end if;
  if exists(select 1 from public.school_members m
            where m.school_id = p_school and m.user_id = p_user
              and not public.school_can_manage_role(p_school, m.role)) then
    return false;
  end if;
  if exists(select 1 from public.school_members m
            where m.user_id = p_user and m.school_id <> p_school
              and m.role in ('owner','coordinator','it_admin','finance')) then
    return false;
  end if;
  if exists(select 1 from public.profiles p
            where p.id = p_user and p.role in ('admin','developer')) then
    return false;
  end if;
  return true;
end;
$$;
revoke all on function public.school_can_manage_account(uuid, uuid) from public, anon;
grant execute on function public.school_can_manage_account(uuid, uuid) to authenticated, service_role;

create or replace function public.school_it_require(p_school uuid)
returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = 'MM401';
  end if;
  if not public.is_school_member(p_school, array['owner','it_admin']) then
    raise exception 'forbidden' using errcode = 'MM403';
  end if;
end;
$$;
revoke all on function public.school_it_require(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Diretório de pessoas (sem nenhum dado pedagógico)
-- ---------------------------------------------------------------------------

create or replace function public.school_it_directory(p_school uuid)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_people jsonb;
begin
  perform public.school_it_require(p_school);
  select coalesce(jsonb_agg(p order by p->>'email'), '[]'::jsonb) into v_people
  from (
    select jsonb_build_object(
      'user_id', m.user_id,
      'email', u.email,
      'name', nullif(btrim(coalesce(u.raw_user_meta_data->>'full_name',
                                    u.raw_user_meta_data->>'name', '')), ''),
      'roles', jsonb_agg(jsonb_build_object(
          'role', m.role, 'status', m.status, 'joined_at', m.joined_at,
          'manageable', public.school_can_manage_role(p_school, m.role))
        order by m.joined_at),
      'joined_at', min(m.joined_at),
      'last_sign_in_at', u.last_sign_in_at,
      'sessions', (select count(*) from auth.sessions s
                   where s.user_id = m.user_id
                     and (s.not_after is null or s.not_after > now())),
      'account_manageable', public.school_can_manage_account(p_school, m.user_id),
      'is_me', m.user_id = (select auth.uid())) as p
    from public.school_members m
    join auth.users u on u.id = m.user_id
    where m.school_id = p_school
    group by m.user_id, u.email, u.raw_user_meta_data, u.last_sign_in_at
    limit 5000
  ) x;
  return jsonb_build_object('people', v_people);
end;
$$;
revoke all on function public.school_it_directory(uuid) from public, anon;
grant execute on function public.school_it_directory(uuid) to authenticated, service_role;

-- Aparelhos conectados de uma pessoa (sessões abertas). Sem IP completo:
-- só os dois primeiros blocos, para a TI reconhecer a rede da escola.
create or replace function public.school_member_sessions(p_school uuid, p_user uuid)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.school_it_require(p_school);
  if not public.school_can_manage_account(p_school, p_user) then
    raise exception 'forbidden' using errcode = 'MM403';
  end if;
  return jsonb_build_object('sessions', coalesce((
    select jsonb_agg(jsonb_build_object(
        'created_at', s.created_at,
        'last_seen_at', coalesce(s.refreshed_at::timestamptz, s.updated_at, s.created_at),
        'user_agent', left(coalesce(s.user_agent, ''), 300),
        'network', case
          when s.ip is null then null
          when family(s.ip) = 4 then split_part(host(s.ip), '.', 1) || '.' || split_part(host(s.ip), '.', 2) || '.x.x'
          else split_part(host(s.ip), ':', 1) || ':' || split_part(host(s.ip), ':', 2) || ':…' end)
      order by coalesce(s.refreshed_at::timestamptz, s.updated_at, s.created_at) desc)
    from auth.sessions s
    where s.user_id = p_user and (s.not_after is null or s.not_after > now())), '[]'::jsonb));
end;
$$;
revoke all on function public.school_member_sessions(uuid, uuid) from public, anon;
grant execute on function public.school_member_sessions(uuid, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Suspender, reativar e remover papel
-- ---------------------------------------------------------------------------

create or replace function public.set_school_member_status(
  p_school uuid, p_user uuid, p_role text, p_status text)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.school_it_require(p_school);
  if p_status not in ('active','suspended') then
    raise exception 'invalid_status' using errcode = '22023';
  end if;
  if p_user = (select auth.uid()) or not public.school_can_manage_role(p_school, p_role) then
    raise exception 'forbidden' using errcode = 'MM403';
  end if;
  -- Reativar passa de novo pelo limite do plano (trigger school_members_plan_limit).
  update public.school_members set status = p_status
    where school_id = p_school and user_id = p_user and role = p_role;
  if not found then
    raise exception 'not_found' using errcode = 'MM404';
  end if;
end;
$$;

create or replace function public.remove_school_member(p_school uuid, p_user uuid, p_role text)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.school_it_require(p_school);
  if p_user = (select auth.uid()) or not public.school_can_manage_role(p_school, p_role) then
    raise exception 'forbidden' using errcode = 'MM403';
  end if;
  delete from public.school_members
    where school_id = p_school and user_id = p_user and role = p_role;
  if not found then
    raise exception 'not_found' using errcode = 'MM404';
  end if;
end;
$$;

-- Encerra todas as sessões da conta (os aparelhos pedem login de novo quando
-- o token atual vencer, em até uma hora).
create or replace function public.revoke_school_member_sessions(p_school uuid, p_user uuid)
returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_total integer;
begin
  perform public.school_it_require(p_school);
  if not public.school_can_manage_account(p_school, p_user) then
    raise exception 'forbidden' using errcode = 'MM403';
  end if;
  delete from auth.sessions s where s.user_id = p_user;
  get diagnostics v_total = row_count;
  perform public.school_audit_write(p_school, 'sessions_revoked', p_user, null,
    jsonb_build_object('sessions', v_total));
  return v_total;
end;
$$;

-- Devolve o e-mail para a Edge Function pedir a redefinição de senha ao Auth
-- (o mesmo e-mail do "Esqueci minha senha"; a TI nunca vê nem define a senha).
create or replace function public.school_member_password_reset(p_school uuid, p_user uuid)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_email text;
begin
  perform public.school_it_require(p_school);
  if not public.school_can_manage_account(p_school, p_user) then
    raise exception 'forbidden' using errcode = 'MM403';
  end if;
  if (select count(*) from public.school_audit_log a
      where a.school_id = p_school and a.action = 'password_reset_sent'
        and a.target_user = p_user and a.created_at > now() - interval '10 minutes') > 0 then
    raise exception 'password_reset_recent' using errcode = 'MM429';
  end if;
  select u.email into v_email from auth.users u where u.id = p_user;
  if v_email is null then
    raise exception 'not_found' using errcode = 'MM404';
  end if;
  perform public.school_audit_write(p_school, 'password_reset_sent', p_user, null, '{}'::jsonb);
  return v_email;
end;
$$;

revoke all on function public.set_school_member_status(uuid, uuid, text, text),
  public.remove_school_member(uuid, uuid, text),
  public.revoke_school_member_sessions(uuid, uuid),
  public.school_member_password_reset(uuid, uuid) from public, anon;
grant execute on function public.set_school_member_status(uuid, uuid, text, text),
  public.remove_school_member(uuid, uuid, text),
  public.revoke_school_member_sessions(uuid, uuid),
  public.school_member_password_reset(uuid, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Convites em lote e renovação
-- ---------------------------------------------------------------------------

-- p_rows: [{"email": "...", "role": "teacher|student|guardian"}], até 500.
-- Cada linha vira um convite pessoal (uso único, preso ao e-mail). Devolve o
-- código de cada um (única vez) ou o motivo de não ter criado.
create or replace function public.create_school_invites_batch(
  p_school uuid, p_rows jsonb, p_valid_days integer default 30)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_row jsonb;
  v_email text;
  v_role text;
  v_seen text[] := '{}';
  v_out jsonb := '[]'::jsonb;
  v_inv record;
  v_created integer := 0;
begin
  perform public.school_it_require(p_school);
  if jsonb_typeof(p_rows) is distinct from 'array'
     or jsonb_array_length(p_rows) not between 1 and 500 then
    raise exception 'invalid_rows' using errcode = '22023';
  end if;
  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_email := lower(btrim(coalesce(v_row->>'email', '')));
    v_role := lower(btrim(coalesce(v_row->>'role', '')));
    if v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' or length(v_email) > 254 then
      v_out := v_out || jsonb_build_object('email', v_email, 'role', v_role, 'status', 'invalid_email');
    elsif v_role not in ('teacher','student','guardian') then
      v_out := v_out || jsonb_build_object('email', v_email, 'role', v_role, 'status', 'invalid_role');
    elsif (v_email || '|' || v_role) = any(v_seen) then
      v_out := v_out || jsonb_build_object('email', v_email, 'role', v_role, 'status', 'duplicate');
    elsif exists(select 1 from public.school_members m join auth.users u on u.id = m.user_id
                 where m.school_id = p_school and m.role = v_role and lower(u.email) = v_email) then
      v_out := v_out || jsonb_build_object('email', v_email, 'role', v_role, 'status', 'already_member');
    else
      select * into v_inv from public.create_school_invite(p_school, v_role, v_email, 1, p_valid_days);
      v_created := v_created + 1;
      v_out := v_out || jsonb_build_object('email', v_email, 'role', v_role, 'status', 'created',
        'code', v_inv.code, 'expires_at', v_inv.expires_at);
    end if;
    v_seen := v_seen || (v_email || '|' || v_role);
  end loop;
  perform public.school_audit_write(p_school, 'invites_imported', null, null,
    jsonb_build_object('rows', jsonb_array_length(p_rows), 'created', v_created));
  return jsonb_build_object('rows', v_out, 'created', v_created);
end;
$$;

-- Revoga o convite e cria outro igual (mesmo papel, e-mail e usos restantes).
create or replace function public.renew_school_invite(p_invite uuid, p_valid_days integer default null)
returns table(invite_id uuid, code text, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare
  v_old public.school_invites%rowtype;
  v_days integer;
  v_uses integer;
begin
  select * into v_old from public.school_invites i where i.id = p_invite;
  if not found then
    raise exception 'not_found' using errcode = 'MM404';
  end if;
  v_days := coalesce(p_valid_days,
    case when v_old.role in ('owner','coordinator','it_admin','finance') then 7 else 30 end);
  v_uses := greatest(v_old.max_uses - v_old.uses, 1);
  -- As duas funções conferem quem pode revogar e criar este papel.
  perform public.revoke_school_invite(p_invite);
  return query select * from public.create_school_invite(
    v_old.school_id, v_old.role, v_old.email, v_uses, v_days) c;
  perform public.school_audit_write(v_old.school_id, 'invite_renewed', null, v_old.role,
    jsonb_build_object('old_invite_id', p_invite, 'email', v_old.email));
end;
$$;

revoke all on function public.create_school_invites_batch(uuid, jsonb, integer),
  public.renew_school_invite(uuid, integer) from public, anon;
grant execute on function public.create_school_invites_batch(uuid, jsonb, integer),
  public.renew_school_invite(uuid, integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Licenças e uso do plano (sem valores em reais)
-- ---------------------------------------------------------------------------

create or replace function public.school_it_licenses(p_school uuid)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_month date := public.school_usage_month();
  v_out jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = 'MM401';
  end if;
  if not public.is_school_member(p_school, array['owner','coordinator','it_admin','finance']) then
    raise exception 'forbidden' using errcode = 'MM403';
  end if;
  select jsonb_build_object(
    'month', v_month,
    'plan', s.plan,
    'plan_label', l.label,
    'max_users', l.max_users,
    'users_active', (select count(distinct m.user_id) from public.school_members m
                     where m.school_id = s.id and m.status = 'active'),
    'users_suspended', (select count(distinct m.user_id) from public.school_members m
                        where m.school_id = s.id and m.status = 'suspended'
                          and not exists(select 1 from public.school_members a
                                         where a.school_id = s.id and a.user_id = m.user_id
                                           and a.status = 'active')),
    'by_role', coalesce((select jsonb_object_agg(r.role, r.total) from (
        select m.role, count(*) as total from public.school_members m
        where m.school_id = s.id and m.status = 'active' group by m.role) r), '{}'::jsonb),
    'max_classes', l.max_classes,
    'classes', (select count(*) from public.platform_classes c where c.school_id = s.id),
    'open_invites', (select count(*) from public.school_invites i
                     where i.school_id = s.id and i.revoked_at is null
                       and i.expires_at > now() and i.uses < i.max_uses),
    'active_students', coalesce(u.active_students, 0),
    'analyses_pot', l.analyses_per_active * coalesce(u.active_students, 0),
    'analyses_used', coalesce(u.analyses, 0),
    'extra_analyses', coalesce(u.extra_analyses, 0),
    'practices_pot', l.practices_per_active * coalesce(u.active_students, 0),
    'practices_used', coalesce(u.practices, 0))
  into v_out
  from public.schools s
  join public.school_plan_limits l on l.plan = s.plan
  left join public.school_usage_months u on u.school_id = s.id and u.month = v_month
  where s.id = p_school;
  return v_out;
end;
$$;
revoke all on function public.school_it_licenses(uuid) from public, anon;
grant execute on function public.school_it_licenses(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Leitura da auditoria (com e-mails de quem fez e de quem sofreu a ação)
-- ---------------------------------------------------------------------------

create or replace function public.school_audit(
  p_school uuid, p_limit integer default 100, p_before bigint default null)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.school_it_require(p_school);
  return jsonb_build_object('entries', coalesce((
    select jsonb_agg(jsonb_build_object(
        'id', a.id, 'action', a.action, 'created_at', a.created_at,
        'actor_email', ua.email, 'target_email', ut.email,
        'target_role', a.target_role, 'details', a.details) order by a.id desc)
    from (select * from public.school_audit_log a
          where a.school_id = p_school and (p_before is null or a.id < p_before)
          order by a.id desc
          limit least(greatest(coalesce(p_limit, 100), 1), 500)) a
    left join auth.users ua on ua.id = a.actor_id
    left join auth.users ut on ut.id = a.target_user), '[]'::jsonb));
end;
$$;
revoke all on function public.school_audit(uuid, integer, bigint) from public, anon;
grant execute on function public.school_audit(uuid, integer, bigint) to authenticated, service_role;
