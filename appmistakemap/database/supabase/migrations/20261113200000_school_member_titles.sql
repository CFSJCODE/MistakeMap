-- Cargo e área de cada pessoa na escola (organograma real de uma rede).
--
-- O papel (owner, coordinator, it_admin, finance, teacher, student, guardian)
-- continua sendo o que dá acesso. O cargo e a área são só rótulos: mostram que
-- a "Diretora Regional" e o "Diretor da Unidade" são donos em níveis
-- diferentes, que a "Orientadora Educacional" está na coordenação etc.
--
-- * school_members.job_title / department: o mesmo valor em todas as linhas da
--   pessoa na escola (uma pessoa, um cargo por escola).
-- * set_school_member_title: a gestão (dono, coordenação, TI) define o cargo
--   de quem é da escola. O trigger school_members_guard já deixa UPDATE de
--   colunas que não sejam escola, usuário, papel e convite.
-- * school_staff: lista de quem trabalha na escola (sem estudantes e
--   responsáveis), com nome, e-mail, papéis, cargo e área, para gestão e
--   financeiro.

alter table public.school_members
  add column job_title text check (job_title is null or char_length(job_title) between 1 and 80),
  add column department text check (department is null or char_length(department) between 1 and 60);

create or replace function public.set_school_member_title(
  p_school uuid,
  p_user uuid,
  p_job_title text,
  p_department text default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_title text := nullif(btrim(coalesce(p_job_title, '')), '');
  v_dept text := nullif(btrim(coalesce(p_department, '')), '');
begin
  if not public.is_school_member(p_school, array['owner','coordinator','it_admin']) then
    raise exception 'school_forbidden' using errcode = 'MM403',
      hint = 'Só dono, coordenação e TI definem cargos.';
  end if;
  if char_length(v_title) > 80 or char_length(v_dept) > 60 then
    raise exception 'school_title_too_long' using errcode = '22001',
      hint = 'Cargo até 80 caracteres e área até 60.';
  end if;
  update public.school_members
     set job_title = v_title, department = v_dept
   where school_id = p_school and user_id = p_user;
  if not found then
    raise exception 'school_member_not_found' using errcode = 'MM404';
  end if;
end;
$$;
revoke all on function public.set_school_member_title(uuid, uuid, text, text) from public, anon;
grant execute on function public.set_school_member_title(uuid, uuid, text, text) to authenticated, service_role;

create or replace function public.school_staff(p_school uuid)
returns table(
  user_id uuid,
  full_name text,
  email text,
  roles text[],
  job_title text,
  department text)
language sql stable security definer set search_path = '' as $$
  select m.user_id,
         nullif(btrim(u.raw_user_meta_data->>'full_name'), ''),
         u.email::text,
         array_agg(m.role order by array_position(
           array['owner','coordinator','it_admin','finance','teacher','guardian','student'], m.role)),
         max(m.job_title),
         max(m.department)
    from public.school_members m
    join auth.users u on u.id = m.user_id
   where m.school_id = p_school
     and m.status = 'active'
     and public.is_school_member(p_school, array['owner','coordinator','it_admin','finance'])
   group by m.user_id, u.raw_user_meta_data, u.email
  having bool_or(m.role in ('owner','coordinator','it_admin','finance','teacher'))
   order by min(array_position(
     array['owner','coordinator','it_admin','finance','teacher'], m.role)),
     max(m.department) nulls last, max(m.job_title) nulls last, u.email;
$$;
revoke all on function public.school_staff(uuid) from public, anon;
grant execute on function public.school_staff(uuid) to authenticated, service_role;
