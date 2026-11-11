-- Papel "developer" em profiles.role, para o app MistakeMap Equipe.
--
-- O app da equipe (MISTAKEMAP_TEAM_BUILD=true) só aceita contas com papel
-- 'admin' ou 'developer'. O desenvolvedor usa o app inteiro como um usuário
-- comum: is_admin() continua exigindo 'admin', então nenhuma política de RLS
-- muda. Quem promove é um admin, pelo painel Admin (admin_update_any_profile);
-- o próprio usuário não troca o papel (user_manage_own_profile exige
-- role = current_user_role()).

do $$
declare
  v_nome text;
begin
  -- A restrição foi criada sem nome em 20260928194109; remove a que trata de role.
  for v_nome in
    select c.conname
      from pg_constraint c
     where c.conrelid = 'public.profiles'::regclass
       and c.contype = 'c'
       and pg_get_constraintdef(c.oid) ilike '%role%'
  loop
    execute format('alter table public.profiles drop constraint %I', v_nome);
  end loop;
end
$$;

alter table public.profiles
  add constraint profiles_role_check
  check (role in ('admin', 'developer', 'user'));

-- Papel da equipe de quem está logado; o app da equipe lê pelo próprio perfil,
-- esta função serve a políticas e funções futuras.
create or replace function public.is_team_member()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
     where id = auth.uid() and role in ('admin', 'developer')
  );
$$;

revoke all on function public.is_team_member() from public, anon;
grant execute on function public.is_team_member() to authenticated;
