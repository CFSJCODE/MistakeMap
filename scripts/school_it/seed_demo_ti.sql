-- Dados de demonstração do Painel de TI na "Colégio Nexo — Unidade Centro
-- (demonstração)" (escola demo, nunca cobrada). Idempotente: apaga e recria
-- só o que marcou (details.demo = 'ti' e convites @convite.nexo.demo).
-- Roda como o backend (postgres), depois de scripts/demo_escolas/seed_escolas.sql.
-- Não manda e-mail, não mexe em senha nem em sessão de ninguém.
do $$
declare
  v_school uuid := (select id from public.schools
                    where name = 'Colégio Nexo — Unidade Centro (demonstração)');
  v_ti uuid := (select id from auth.users where email = 'ti.nexo.demo@mistakemap.dev');
  v_dir uuid := (select id from auth.users where email = 'diretoria.nexo.demo@mistakemap.dev');
  v_inv uuid;
  r record;
begin
  if v_school is null then
    raise notice 'escola demo Unidade Centro não existe; nada a fazer';
    return;
  end if;

  -- Limpa a rodada anterior.
  delete from public.school_audit_log a
    where a.school_id = v_school and a.details->>'demo' = 'ti';
  delete from public.school_invites i
    where i.school_id = v_school and i.email like '%@convite.nexo.demo';
  delete from public.school_audit_log a
    where a.school_id = v_school and a.action in ('invite_created','invite_revoked')
      and a.details->>'email' like '%@convite.nexo.demo';

  -- Histórico de entrada de quem já está na escola (antes da auditoria existir).
  insert into public.school_audit_log(school_id, actor_id, action, target_user, target_role, details, created_at)
  select v_school, null, 'member_joined', m.user_id, m.role,
         jsonb_build_object('demo', 'ti', 'backfill', true), m.joined_at
  from public.school_members m
  where m.school_id = v_school
    and not exists(select 1 from public.school_audit_log a
                   where a.school_id = v_school and a.action = 'member_joined'
                     and a.target_user = m.user_id and a.target_role = m.role);

  -- Convites em aberto, como se a TI tivesse importado uma planilha.
  for r in select * from (values
      ('marina.alves@convite.nexo.demo', 'teacher', 2),
      ('joao.pedro@convite.nexo.demo', 'student', 2),
      ('ana.clara@convite.nexo.demo', 'student', 2),
      ('rafael.nunes@convite.nexo.demo', 'student', 2),
      ('beatriz.souza@convite.nexo.demo', 'guardian', 2),
      ('lucas.ferreira@convite.nexo.demo', 'student', 6)) v(email, role, dias) loop
    insert into public.school_invites(school_id, role, code_hash, email, max_uses, created_by, created_at, expires_at)
      values (v_school, r.role,
              encode(sha256(convert_to(gen_random_uuid()::text, 'UTF8')), 'hex'),
              r.email, 1, v_ti, now() - make_interval(days => r.dias),
              now() - make_interval(days => r.dias) + interval '30 days')
      returning id into v_inv;
    if r.email = 'lucas.ferreira@convite.nexo.demo' then
      update public.school_invites set revoked_at = now() - interval '5 days' where id = v_inv;
    end if;
  end loop;
  -- Os triggers gravaram os convites sem autor (rodou como backend): a demo
  -- mostra a TI como autora, com as datas da importação.
  update public.school_audit_log a
     set actor_id = v_ti,
         details = a.details || jsonb_build_object('demo', 'ti'),
         created_at = coalesce((select case when a.action = 'invite_revoked' then i.revoked_at
                                       else i.created_at end
                                from public.school_invites i
                                where i.id = (a.details->>'invite_id')::uuid), a.created_at)
   where a.school_id = v_school and a.details->>'email' like '%@convite.nexo.demo';

  insert into public.school_audit_log(school_id, actor_id, action, target_user, target_role, details, created_at)
  values
    (v_school, v_ti, 'invites_imported', null, null,
     jsonb_build_object('demo', 'ti', 'rows', 7, 'created', 6), now() - interval '6 days 2 hours'),
    (v_school, v_ti, 'invites_imported', null, null,
     jsonb_build_object('demo', 'ti', 'rows', 5, 'created', 5), now() - interval '2 days 3 hours'),
    (v_school, v_ti, 'password_reset_sent',
     (select id from auth.users where email = 'aluno04.nexo.demo@mistakemap.dev'), null,
     jsonb_build_object('demo', 'ti'), now() - interval '1 day 4 hours'),
    (v_school, v_ti, 'sessions_revoked',
     (select id from auth.users where email = 'aluno02.nexo.demo@mistakemap.dev'), null,
     jsonb_build_object('demo', 'ti', 'sessions', 3), now() - interval '20 hours'),
    (v_school, coalesce(v_dir, v_ti), 'invite_renewed', null, 'teacher',
     jsonb_build_object('demo', 'ti', 'email', 'marina.alves@convite.nexo.demo'), now() - interval '3 hours');
end $$;
