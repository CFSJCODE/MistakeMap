-- Escolas de demonstração comercial e acadêmica do MistakeMap (2026-11-13).
--
-- Rodar DEPOIS de criar as contas de contas.json (criar_contas.ps1) e ANTES de
-- seed_alunos.sql. Tudo é fictício (nomes de escola, rede, pessoas e números)
-- e toda escola daqui leva school_billing_settings.demo = true: o fechamento
-- do mês e a Edge Function school-billing nunca cobram no Asaas.
--
-- 1. Oficina Volt — escola pequena. O dono faz quase tudo: é dono,
--    coordenação e professor da turma de sábado; paga por Pix; plano Escola
--    mensal; 1 professora auxiliar, 5 alunos, 1 responsável, equipe FLL.
-- 2. Rede Nexo de Educação Tecnológica — rede grande no modo de operação de
--    SESI/SENAI/FIEMG e redes confessionais: diretoria regional dona de duas
--    unidades, coordenação, TI e Financeiro/Compras separados; quem paga é o
--    Financeiro, por boleto em 30 dias com pedido de compra, centro de custo e
--    NFS-e; contrato anual.
--    * Unidade Vale do Ferro: unidade grande já contratada (~1.900 alunos
--      ativos, só números agregados e relatório de amostra).
--    * Unidade Centro: piloto de 30 dias do plano Plus com 2 turmas reais
--      (10 alunos com conta, 2 professores, equipe OBR, 1 responsável).
--
-- Papéis entram como no app: convite pessoal por e-mail criado por quem pode
-- convidar e resgatado pela própria conta (o trigger school_members_guard
-- confere). As respostas das tarefas seguem o caminho do question_bank_service
-- (tentativa + análise + resposta com assignment_id).
-- Idempotente: escola, papel, turma, tarefa e fatura que já existem não são
-- duplicados.
begin;

create temporary table demo_contas(chave text primary key, email text not null) on commit drop;
insert into demo_contas values
  ('VOLT_DONO','dono.volt.demo@mistakemap.dev'),
  ('VOLT_PROFESSORA','professora.volt.demo@mistakemap.dev'),
  ('VOLT_ALUNO1','aluno1.volt.demo@mistakemap.dev'),
  ('VOLT_ALUNO2','aluno2.volt.demo@mistakemap.dev'),
  ('VOLT_ALUNO3','aluno3.volt.demo@mistakemap.dev'),
  ('VOLT_ALUNO4','aluno4.volt.demo@mistakemap.dev'),
  ('VOLT_ALUNO5','aluno5.volt.demo@mistakemap.dev'),
  ('VOLT_RESPONSAVEL','responsavel.volt.demo@mistakemap.dev'),
  ('NEXO_DIRETORIA','diretoria.nexo.demo@mistakemap.dev'),
  ('NEXO_COORDENACAO','coordenacao.nexo.demo@mistakemap.dev'),
  ('NEXO_TI','ti.nexo.demo@mistakemap.dev'),
  ('NEXO_FINANCEIRO','financeiro.nexo.demo@mistakemap.dev'),
  ('NEXO_PROF_ELETRONICA','prof.eletronica.nexo.demo@mistakemap.dev'),
  ('NEXO_PROF_ROBOTICA','prof.robotica.nexo.demo@mistakemap.dev'),
  ('NEXO_ALUNO01','aluno01.nexo.demo@mistakemap.dev'),
  ('NEXO_ALUNO02','aluno02.nexo.demo@mistakemap.dev'),
  ('NEXO_ALUNO03','aluno03.nexo.demo@mistakemap.dev'),
  ('NEXO_ALUNO04','aluno04.nexo.demo@mistakemap.dev'),
  ('NEXO_ALUNO05','aluno05.nexo.demo@mistakemap.dev'),
  ('NEXO_ALUNO06','aluno06.nexo.demo@mistakemap.dev'),
  ('NEXO_ALUNO07','aluno07.nexo.demo@mistakemap.dev'),
  ('NEXO_ALUNO08','aluno08.nexo.demo@mistakemap.dev'),
  ('NEXO_ALUNO09','aluno09.nexo.demo@mistakemap.dev'),
  ('NEXO_ALUNO10','aluno10.nexo.demo@mistakemap.dev'),
  ('NEXO_RESPONSAVEL','responsavel.nexo.demo@mistakemap.dev'),
  ('EQUIPE_ADMIN','admin.demo@mistakemap.dev'),
  ('EQUIPE_DEV','dev.demo@mistakemap.dev'),
  ('INDIVIDUAL','teste@mistakemap.dev');

create function pg_temp.u(p_chave text) returns uuid language sql stable as $f$
  select u.id from auth.users u join demo_contas c on lower(u.email) = c.email where c.chave = p_chave
$f$;

-- auth.uid() lê request.jwt.claim.sub; nulo = servidor.
create function pg_temp.como(p_user uuid) returns void language sql as $f$
  select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true),
         set_config('request.jwt.claims', case when p_user is null then ''
           else json_build_object('sub', p_user, 'role', 'authenticated')::text end, true);
$f$;

create function pg_temp.mes(k integer) returns date language sql stable as $f$
  select (public.school_usage_month() - make_interval(months => k))::date
$f$;

-- Papel por convite pessoal: quem convida cria, a conta convidada resgata.
create function pg_temp.papel(p_school uuid, p_por uuid, p_user uuid, p_role text)
returns void language plpgsql as $f$
declare v_code text;
begin
  if exists(select 1 from public.school_members m
            where m.school_id = p_school and m.user_id = p_user and m.role = p_role) then
    return;
  end if;
  perform pg_temp.como(p_por);
  select i.code into v_code from public.create_school_invite(
    p_school, p_role, (select email from auth.users where id = p_user), 1, 7) i;
  perform pg_temp.como(p_user);
  perform public.redeem_school_invite(v_code);
  perform pg_temp.como(null);
end;
$f$;

create function pg_temp.escola(p_dono uuid, p_nome text) returns uuid language plpgsql as $f$
declare v uuid;
begin
  select id into v from public.schools where name = p_nome;
  if v is null then
    perform pg_temp.como(p_dono);
    v := public.create_school(p_nome);
    perform pg_temp.como(null);
  end if;
  return v;
end;
$f$;

create function pg_temp.uso(p_school uuid, p_month date, p_plan text, p_active integer,
  p_analyses integer, p_practices integer, p_closed boolean)
returns void language sql as $f$
  insert into public.school_usage_months(school_id, month, plan, active_students, analyses, practices, closed_at)
  values (p_school, p_month, p_plan, p_active, p_analyses, p_practices,
          case when p_closed then (p_month + interval '1 month' + interval '2 hours')::timestamptz end)
  on conflict (school_id, month) do update set
    plan = excluded.plan,
    active_students = greatest(public.school_usage_months.active_students, excluded.active_students),
    analyses = greatest(public.school_usage_months.analyses, excluded.analyses),
    practices = greatest(public.school_usage_months.practices, excluded.practices),
    closed_at = coalesce(public.school_usage_months.closed_at, excluded.closed_at),
    updated_at = now();
$f$;

-- Fatura de demonstração (demo = true, sem id do Asaas): valor sempre pelo
-- school_billing_quote, como no fechamento de verdade.
create function pg_temp.fatura(p_school uuid, p_kind text, p_month date, p_plan text, p_cycle text,
  p_students integer, p_method text, p_status text, p_due date, p_paid timestamptz,
  p_po text default null, p_cc text default null, p_nfse text default null)
returns void language sql as $f$
  insert into public.school_invoices(
    school_id, kind, reference_month, plan, cycle, students, price_per_student, gross,
    volume_discount_percent, discount, minimum_applied, extra_analyses, extra_amount, total,
    method, status, due_date, purchase_order, cost_center, provider, demo,
    nfse_status, nfse_number, created_at, issued_at, paid_at)
  select p_school, p_kind, p_month, p_plan, p_cycle, p_students, q.price_per_student, q.gross,
    q.volume_discount_percent, q.discount, q.minimum_applied, 0, 0, q.total,
    p_method, p_status, p_due, p_po, p_cc, 'asaas', true,
    case when p_nfse is not null then 'issued' end, p_nfse,
    least(now(), (p_month + interval '1 month' + interval '3 hours')::timestamptz),
    least(now(), (p_month + interval '1 month' + interval '3 hours')::timestamptz), p_paid
  from public.school_billing_quote(p_plan, p_cycle, p_students, 0) q
  where not exists(select 1 from public.school_invoices i
                   where i.school_id = p_school and i.reference_month = p_month and i.kind = p_kind);
$f$;

-- Resposta a uma questão objetiva do banco, no mesmo formato do app
-- (question_bank_service.saveObjective), ligada a uma tarefa da turma.
create function pg_temp.responder(p_user uuid, p_slug text, p_choice text, p_hours numeric, p_assignment uuid)
returns void language plpgsql as $f$
declare
  q record; subj uuid; ex uuid; conc uuid; aid uuid; ans text; ok boolean; diag jsonb; an jsonb;
  v_at timestamptz := now() - make_interval(secs => p_hours * 3600);
  k text := p_user::text || ':tarefa:' || coalesce(p_assignment::text, '') || ':' || p_slug;
begin
  select b.*, kk.answer as key_answer, kk.correct_answer, kk.explanation into q
    from public.question_bank b join public.question_bank_keys kk on kk.question_id = b.id where b.slug = p_slug;
  if q.id is null then return; end if;
  aid := md5(k || ':att')::uuid;
  if exists(select 1 from public.attempts where id = aid) then return; end if;
  perform pg_temp.como(p_user);
  select id into subj from public.subjects where user_id = p_user and lower(btrim(name)) = lower(q.subject) order by created_at limit 1;
  if subj is null then
    insert into public.subjects(id, user_id, name, description, created_at)
    values (md5(p_user::text || ':qbsubj:' || q.subject)::uuid, p_user, q.subject, 'Histórico de demonstração (mmdemo)', v_at - interval '1 hour')
    returning id into subj;
  end if;
  select e.id into ex from public.exercises e where e.subject_id = subj and e.question_id = q.id order by e.created_at limit 1;
  if ex is null then
    insert into public.exercises(id, subject_id, source, prompt_text, difficulty, focus_concept, question_id, created_at)
    values (md5(k || ':ex')::uuid, subj, 'question_bank',
      q.prompt_text || E'\n\nAlternativas:' || (select string_agg(E'\n' || (o->>'id') || ') ' || (o->>'text'), '' order by n)
        from jsonb_array_elements(q.payload->'options') with ordinality t(o, n)),
      q.difficulty, q.theme, q.id, v_at - interval '5 minutes')
    returning id into ex;
  end if;
  select (o->>'id') || ') ' || (o->>'text') into ans from jsonb_array_elements(q.payload->'options') o where o->>'id' = p_choice;
  ok := p_choice = q.key_answer->>'correct';
  diag := q.key_answer->'diagnosis'->p_choice;
  an := jsonb_build_object('is_correct', ok, 'correct_answer', q.correct_answer, 'explanation', q.explanation,
    'transcribed_prompt', (select prompt_text from public.exercises where id = ex), 'transcribed_answer', ans,
    'concepts', jsonb_build_array(left(btrim(q.theme), 120)),
    'errors', case when ok then '[]'::jsonb else jsonb_build_array(jsonb_build_object(
      'category', coalesce(diag->>'category', q.error_category), 'concept', left(btrim(q.theme), 120),
      'evidence', coalesce(diag->>'feedback', 'Resposta dada: ' || ans || '. Resposta correta: ' || q.correct_answer || '.'),
      'confidence', case when diag ? 'feedback' then 0.7 else 0.5 end)) end);
  perform pg_temp.como(null);  -- guard_attempt_ai_state só aceita 'completed' sem JWT
  insert into public.attempts(id, exercise_id, user_id, answer, solution_text, attempted_at, status)
  values (aid, ex, p_user, ans, ans, v_at, 'completed');
  perform pg_temp.como(p_user);
  insert into public.attempt_analyses(attempt_id, user_id, subject_id, analysis, model, pipeline_version, created_at)
  values (aid, p_user, subj, an, 'gabarito-revisado', 'question-bank-v1', v_at);
  insert into public.corrections(attempt_id, reference_text, created_at)
  values (aid, q.correct_answer || E'\n\n' || q.explanation, v_at);
  select id into conc from public.concepts where subject_id = subj and lower(name) = lower(left(btrim(q.theme), 120)) order by created_at limit 1;
  if conc is null then
    insert into public.concepts(id, subject_id, name, created_at)
    values (md5(p_user::text || ':qbconc:' || q.theme)::uuid, subj, left(btrim(q.theme), 120), v_at)
    returning id into conc;
  end if;
  insert into public.exercise_concepts(exercise_id, concept_id) values (ex, conc) on conflict do nothing;
  if not ok then
    insert into public.error_events(id, attempt_id, error_type_id, concept_id, evidence_ref, confidence, status, created_at)
    select md5(k || ':ee')::uuid, aid, et.id, conc, an->'errors'->0->>'evidence',
           (an->'errors'->0->>'confidence')::numeric, 'pending', v_at
    from public.error_types et where et.name = an->'errors'->0->>'category';
  else
    insert into public.mastery_events(id, concept_id, attempt_id, outcome, created_at)
    values (md5(k || ':me')::uuid, conc, aid, 'question_bank_correct', v_at);
  end if;
  insert into public.question_responses(id, user_id, question_id, attempt_id, response, is_correct, score, created_at, assignment_id)
  values (md5(k || ':qr')::uuid, p_user, q.id, aid, jsonb_build_object('choice', p_choice), ok,
          case when ok then 1 else 0 end, v_at, p_assignment);
  perform pg_temp.como(null);
end;
$f$;

-- Alternativa escolhida por um aluno: ~60% de acerto, determinística.
create function pg_temp.escolha(p_user uuid, p_slug text, p_assignment uuid) returns text language sql stable as $f$
  with q as (
    select (k.answer->>'correct') as certa,
           array(select o->>'id' from jsonb_array_elements(b.payload->'options') o
                 where o->>'id' <> k.answer->>'correct' order by o->>'id') as erradas
    from public.question_bank b join public.question_bank_keys k on k.question_id = b.id where b.slug = p_slug),
  h as (select decode(md5(p_user::text || p_slug || p_assignment::text), 'hex') as d)
  select case when get_byte(h.d, 0) % 10 < 6 then q.certa
              else q.erradas[1 + get_byte(h.d, 1) % cardinality(q.erradas)] end
  from q, h;
$f$;

create function pg_temp.turma(p_school uuid, p_teacher uuid, p_title text, p_days integer) returns uuid
language plpgsql as $f$
declare v uuid;
begin
  select id into v from public.platform_classes where school_id = p_school and title = p_title;
  if v is null then
    insert into public.platform_classes(teacher_id, title, school_id, created_at)
    values (p_teacher, p_title, p_school, now() - make_interval(days => p_days)) returning id into v;
    insert into public.platform_class_invites(class_id) values (v) on conflict do nothing;
  end if;
  return v;
end;
$f$;

create function pg_temp.membro_turma(p_class uuid, p_user uuid, p_share boolean, p_days integer) returns void
language sql as $f$
  insert into public.platform_memberships(class_id, user_id, share_progress, share_answers, share_notes, joined_at, consent_updated_at)
  values (p_class, p_user, p_share, p_share, false, now() - make_interval(days => p_days), now() - make_interval(days => p_days))
  on conflict (class_id, user_id) do nothing;
$f$;

create function pg_temp.tarefa(p_class uuid, p_title text, p_slugs text[], p_concept text,
  p_created_days numeric, p_due_days numeric) returns uuid
language plpgsql as $f$
declare v uuid;
begin
  select id into v from public.platform_assignments where class_id = p_class and title = p_title;
  if v is null then
    insert into public.platform_assignments(class_id, title, due_at, catalog_ids, question_ids, source_concept, created_at)
    values (p_class, p_title, now() + make_interval(secs => p_due_days * 86400), '{}',
      array(select b.id from unnest(p_slugs) with ordinality s(slug, n) join public.question_bank b on b.slug = s.slug order by s.n),
      p_concept, now() - make_interval(secs => p_created_days * 86400))
    returning id into v;
  end if;
  return v;
end;
$f$;

create function pg_temp.responder_tarefa(p_assignment uuid, p_users uuid[], p_hours numeric) returns void
language plpgsql as $f$
declare u uuid; s text; i integer := 0;
begin
  foreach u in array p_users loop
    i := i + 1;
    foreach s in array (select array_agg(b.slug order by b.slug)
                          from public.platform_assignments a join public.question_bank b on b.id = any(a.question_ids)
                         where a.id = p_assignment) loop
      perform pg_temp.responder(u, s, pg_temp.escolha(u, s, p_assignment), p_hours - i * 0.7, p_assignment);
    end loop;
  end loop;
end;
$f$;

create function pg_temp.equipe(p_school uuid, p_por uuid, p_nome text, p_comp text) returns uuid
language plpgsql as $f$
declare v uuid;
begin
  select id into v from public.school_teams where school_id = p_school and name = p_nome;
  if v is null then
    insert into public.school_teams(school_id, name, competition, code_hash, created_by, created_at)
    values (p_school, p_nome, p_comp, public.code_digest(replace(gen_random_uuid()::text, '-', '')), p_por, now() - interval '40 days')
    returning id into v;
  end if;
  return v;
end;
$f$;

do $seed$
declare
  volt uuid; vf uuid; centro uuid; t uuid;
  r record; k integer;
  staff text[] := array['VOLT_DONO','VOLT_PROFESSORA','VOLT_RESPONSAVEL','NEXO_DIRETORIA','NEXO_COORDENACAO',
                        'NEXO_TI','NEXO_FINANCEIRO','NEXO_PROF_ELETRONICA','NEXO_PROF_ROBOTICA','NEXO_RESPONSAVEL'];
  nascimentos jsonb := '{
    "VOLT_ALUNO1":"2012-03-18","VOLT_ALUNO2":"2011-08-02","VOLT_ALUNO3":"2010-11-25","VOLT_ALUNO4":"2011-01-14",
    "VOLT_ALUNO5":"2009-06-30","NEXO_ALUNO01":"2010-04-09","NEXO_ALUNO02":"2009-12-01","NEXO_ALUNO03":"2009-07-21",
    "NEXO_ALUNO04":"2009-10-15","NEXO_ALUNO05":"2010-02-27","NEXO_ALUNO06":"2009-05-06","NEXO_ALUNO07":"2008-09-19",
    "NEXO_ALUNO08":"2008-12-11","NEXO_ALUNO09":"2008-03-03","NEXO_ALUNO10":"2008-07-28","INDIVIDUAL":"2005-05-20"}';
  personas jsonb := '{
    "VOLT_DONO":"owner","VOLT_PROFESSORA":"teacher","VOLT_RESPONSAVEL":"guardian","NEXO_DIRETORIA":"owner",
    "NEXO_COORDENACAO":"coordinator","NEXO_TI":"it_admin","NEXO_FINANCEIRO":"finance",
    "NEXO_PROF_ELETRONICA":"teacher","NEXO_PROF_ROBOTICA":"teacher","NEXO_RESPONSAVEL":"guardian",
    "VOLT_ALUNO2":"student_team","VOLT_ALUNO4":"student_team","NEXO_ALUNO03":"student_team",
    "NEXO_ALUNO06":"student_team","NEXO_ALUNO07":"student_team","NEXO_ALUNO09":"student_team"}';
begin
  if exists(select 1 from demo_contas c where pg_temp.u(c.chave) is null) then
    raise exception 'faltam contas: %', (select string_agg(email, ', ') from demo_contas c where pg_temp.u(c.chave) is null);
  end if;
  perform pg_temp.como(null);

  -- Perfis: equipe do MistakeMap e formação de quem trabalha na escola.
  update public.profiles set role = 'admin' where id = pg_temp.u('EQUIPE_ADMIN');
  update public.profiles set role = 'developer' where id = pg_temp.u('EQUIPE_DEV');
  update public.profiles set education_level = 'ensino_superior', higher_education_type = 'graduacao'
   where id in (select pg_temp.u(x) from unnest(staff || array['EQUIPE_ADMIN','EQUIPE_DEV']) x);
  update public.profiles set education_level = 'ensino_fundamental_2', institution_name = 'Oficina Volt'
   where id in (pg_temp.u('VOLT_ALUNO1'), pg_temp.u('VOLT_ALUNO2'), pg_temp.u('VOLT_ALUNO4'));
  update public.profiles set institution_name = 'Oficina Volt'
   where id in (pg_temp.u('VOLT_ALUNO3'), pg_temp.u('VOLT_ALUNO5'));
  update public.profiles set institution_name = 'Colégio Nexo — Unidade Centro', course = 'Técnico em Eletrônica integrado'
   where id in (select pg_temp.u(c.chave) from demo_contas c where c.chave like 'NEXO_ALUNO%');
  update public.profiles set education_level = 'ensino_superior', higher_education_type = 'graduacao',
         institution_name = 'Conta de desenvolvimento/teste', course = 'Engenharia de Computação'
   where id = pg_temp.u('INDIVIDUAL');

  -- "Quem é você?" de cada conta (como no cadastro do app).
  for r in select c.chave from demo_contas c where c.chave not in ('EQUIPE_ADMIN','EQUIPE_DEV') loop
    if not exists(select 1 from public.user_signups where user_id = pg_temp.u(r.chave)) then
      perform pg_temp.como(pg_temp.u(r.chave));
      perform public.save_signup_profile(coalesce(personas->>r.chave, 'student'), (nascimentos->>r.chave)::date);
      perform pg_temp.como(null);
    end if;
  end loop;

  -- ── Escolas ───────────────────────────────────────────────────────────────
  volt := pg_temp.escola(pg_temp.u('VOLT_DONO'), 'Oficina Volt — Robótica e Eletrônica (demonstração)');
  vf := pg_temp.escola(pg_temp.u('NEXO_DIRETORIA'), 'Colégio Nexo — Unidade Vale do Ferro (demonstração)');
  centro := pg_temp.escola(pg_temp.u('NEXO_DIRETORIA'), 'Colégio Nexo — Unidade Centro (demonstração)');
  update public.schools set plan = 'escola', billing_cycle = 'monthly', status = 'active',
         created_at = least(created_at, now() - interval '7 months') where id = volt;
  update public.schools set plan = 'escola', billing_cycle = 'annual', status = 'active',
         created_at = least(created_at, now() - interval '13 months') where id = vf;
  update public.schools set plan = 'plus', billing_cycle = 'annual', status = 'pilot',
         created_at = least(created_at, now() - interval '24 days') where id = centro;

  insert into public.school_billing_settings(school_id, payer_role, default_method, due_days, legal_name,
    billing_email, demo, postal_code, address_number, phone)
  values
    (volt, 'owner', 'pix', 5, 'Oficina Volt Educação Tecnológica ME (demonstração)',
     'dono.volt.demo@mistakemap.dev', true, '30130000', '120', '31990000001'),
    (vf, 'owner', 'boleto', 30, 'Rede Nexo de Educação Tecnológica — Unidade Vale do Ferro (demonstração)',
     'financeiro.nexo.demo@mistakemap.dev', true, '30640000', '2500', '3133330000'),
    (centro, 'owner', 'boleto', 30, 'Rede Nexo de Educação Tecnológica — Unidade Centro (demonstração)',
     'financeiro.nexo.demo@mistakemap.dev', true, '30110000', '800', '3133330001')
  on conflict (school_id) do update set demo = true, legal_name = excluded.legal_name,
    default_method = excluded.default_method, due_days = excluded.due_days,
    billing_email = excluded.billing_email, updated_at = now();

  -- ── Papéis: Oficina Volt (o dono acumula coordenação e aula) ─────────────
  perform pg_temp.papel(volt, pg_temp.u('VOLT_DONO'), pg_temp.u('VOLT_DONO'), 'coordinator');
  perform pg_temp.papel(volt, pg_temp.u('VOLT_DONO'), pg_temp.u('VOLT_DONO'), 'teacher');
  perform pg_temp.papel(volt, pg_temp.u('VOLT_DONO'), pg_temp.u('VOLT_PROFESSORA'), 'teacher');
  for k in 1..5 loop
    perform pg_temp.papel(volt, pg_temp.u('VOLT_DONO'), pg_temp.u('VOLT_ALUNO' || k), 'student');
  end loop;
  perform pg_temp.papel(volt, pg_temp.u('VOLT_DONO'), pg_temp.u('VOLT_RESPONSAVEL'), 'guardian');

  -- ── Papéis: Rede Nexo (gestão nas duas unidades; sala de aula no Centro) ──
  foreach t in array array[vf, centro] loop
    perform pg_temp.papel(t, pg_temp.u('NEXO_DIRETORIA'), pg_temp.u('NEXO_COORDENACAO'), 'coordinator');
    perform pg_temp.papel(t, pg_temp.u('NEXO_DIRETORIA'), pg_temp.u('NEXO_TI'), 'it_admin');
    perform pg_temp.papel(t, pg_temp.u('NEXO_DIRETORIA'), pg_temp.u('NEXO_FINANCEIRO'), 'finance');
  end loop;
  perform pg_temp.papel(centro, pg_temp.u('NEXO_COORDENACAO'), pg_temp.u('NEXO_PROF_ELETRONICA'), 'teacher');
  perform pg_temp.papel(centro, pg_temp.u('NEXO_COORDENACAO'), pg_temp.u('NEXO_PROF_ROBOTICA'), 'teacher');
  for k in 1..10 loop
    perform pg_temp.papel(centro, pg_temp.u('NEXO_TI'), pg_temp.u('NEXO_ALUNO' || lpad(k::text, 2, '0')), 'student');
  end loop;
  perform pg_temp.papel(centro, pg_temp.u('NEXO_COORDENACAO'), pg_temp.u('NEXO_RESPONSAVEL'), 'guardian');
  -- Na rede, quem paga é o Financeiro/Compras.
  update public.school_billing_settings set payer_role = 'finance',
         purchase_order = case when school_id = vf then 'PC-2026-0417' else 'PC-2026-0533' end,
         cost_center = case when school_id = vf then 'CC-EDU-VF-0210' else 'CC-EDU-CT-0115' end,
         updated_at = now()
   where school_id in (vf, centro);

  -- ── Contas da equipe do MistakeMap: todos os papéis nas três escolas ─────
  foreach t in array array[volt, vf, centro] loop
    for r in select x as chave from unnest(array['EQUIPE_ADMIN','EQUIPE_DEV']) x loop
      perform pg_temp.papel(t, (select m.user_id from public.school_members m where m.school_id = t and m.role = 'owner'
                                  and m.user_id not in (pg_temp.u('EQUIPE_ADMIN'), pg_temp.u('EQUIPE_DEV')) limit 1),
                            pg_temp.u(r.chave), 'owner');
    end loop;
  end loop;
end
$seed$;

-- Segunda parte: papéis da equipe, turmas, tarefas, equipes, responsáveis e faturas.
do $seed2$
declare
  volt uuid := (select id from public.schools where name = 'Oficina Volt — Robótica e Eletrônica (demonstração)');
  vf uuid := (select id from public.schools where name = 'Colégio Nexo — Unidade Vale do Ferro (demonstração)');
  centro uuid := (select id from public.schools where name = 'Colégio Nexo — Unidade Centro (demonstração)');
  t uuid; p text; eq text;
  c_sab uuid; c_qua uuid; c_2a uuid; c_3b uuid; a uuid; team uuid;
  volt_alunos uuid[]; a2 uuid[]; b3 uuid[];
  k integer; v_active integer; v_teste uuid;
begin
  foreach t in array array[volt, vf, centro] loop
    foreach eq in array array['EQUIPE_ADMIN','EQUIPE_DEV'] loop
      foreach p in array array['coordinator','it_admin','finance','teacher','student','guardian'] loop
        perform pg_temp.papel(t, pg_temp.u(eq), pg_temp.u(eq), p);
      end loop;
    end loop;
  end loop;

  -- Escola de TESTE REAL de cobrança (não é demo): volta a ter dono, o da Volt.
  select id into v_teste from public.schools where cnpj = '54497959000103';
  if v_teste is not null and not exists(select 1 from public.school_members where school_id = v_teste and role = 'owner') then
    update public.schools set created_by = pg_temp.u('VOLT_DONO') where id = v_teste;
    insert into public.school_members(school_id, user_id, role) values (v_teste, pg_temp.u('VOLT_DONO'), 'owner');
  end if;

  -- Professores aprovados na plataforma de turmas.
  insert into public.platform_teachers(user_id, approved_by)
  select pg_temp.u(x), pg_temp.u('EQUIPE_ADMIN')
  from unnest(array['VOLT_DONO','VOLT_PROFESSORA','NEXO_PROF_ELETRONICA','NEXO_PROF_ROBOTICA',
                    'NEXO_COORDENACAO','EQUIPE_ADMIN','EQUIPE_DEV']) x
  on conflict (user_id) do nothing;

  -- ── Turmas ────────────────────────────────────────────────────────────────
  volt_alunos := array(select pg_temp.u('VOLT_ALUNO' || k) from generate_series(1, 5) k);
  a2 := array(select pg_temp.u('NEXO_ALUNO' || lpad(k::text, 2, '0')) from generate_series(1, 5) k);
  b3 := array(select pg_temp.u('NEXO_ALUNO' || lpad(k::text, 2, '0')) from generate_series(6, 10) k);

  c_sab := pg_temp.turma(volt, pg_temp.u('VOLT_DONO'), 'Robótica com Arduino — Turma de Sábado', 150);
  c_qua := pg_temp.turma(volt, pg_temp.u('VOLT_PROFESSORA'), 'Eletrônica Básica — Turma de Quarta', 120);
  c_2a := pg_temp.turma(centro, pg_temp.u('NEXO_PROF_ELETRONICA'), '2º ano A — Eletrônica e Sistemas Embarcados', 22);
  c_3b := pg_temp.turma(centro, pg_temp.u('NEXO_PROF_ROBOTICA'), '3º ano B — Robótica Móvel', 22);
  for k in 1..5 loop
    perform pg_temp.membro_turma(c_sab, volt_alunos[k], k <> 5, 140 - k);
    perform pg_temp.membro_turma(c_qua, volt_alunos[k], k <> 5, 110 - k);
    perform pg_temp.membro_turma(c_2a, a2[k], true, 21);
    perform pg_temp.membro_turma(c_3b, b3[k], k <> 5, 21);
  end loop;

  -- ── Tarefas (questões do banco) e respostas ──────────────────────────────
  a := pg_temp.tarefa(c_sab, 'Desafio do LED: resistor e conversão binária',
         array['me-ohm-led','me-byte-decimal'], 'Lei de Ohm', 9, -6);
  perform pg_temp.responder_tarefa(a, volt_alunos, 190);
  a := pg_temp.tarefa(c_qua, 'Bateria do drone: porcentagem e MRUV',
         array['me-servidor-porcentagem','me-drone-mruv'], 'Porcentagem', 2, 4);
  perform pg_temp.responder_tarefa(a, volt_alunos[1:2], 30);
  a := pg_temp.tarefa(c_2a, 'Lei de Ohm e conversões — revisão para a prova',
         array['me-ohm-led','me-byte-decimal','me-servidor-porcentagem'], 'Lei de Ohm', 10, -3);
  perform pg_temp.responder_tarefa(a, a2, 220);
  perform pg_temp.tarefa(c_2a, 'Treino: frenagem do robô seguidor (MRUV)',
         array['me-drone-mruv'], 'MRUV', 1, 6);
  a := pg_temp.tarefa(c_3b, 'Cinemática do drone e corrente do motor',
         array['me-drone-mruv','me-ohm-led'], 'MRUV', 6, -1);
  perform pg_temp.responder_tarefa(a, b3[1:4], 120);

  -- ── Equipes de robótica ──────────────────────────────────────────────────
  team := pg_temp.equipe(volt, pg_temp.u('VOLT_DONO'), 'Volt Lego Masters', 'fll');
  insert into public.school_team_members(team_id, user_id, team_role) values
    (team, pg_temp.u('VOLT_ALUNO2'), 'programacao'), (team, pg_temp.u('VOLT_ALUNO4'), 'mecanica')
  on conflict do nothing;
  team := pg_temp.equipe(centro, pg_temp.u('NEXO_PROF_ROBOTICA'), 'Nexo Bots', 'obr');
  insert into public.school_team_members(team_id, user_id, team_role) values
    (team, pg_temp.u('NEXO_ALUNO03'), 'eletronica'), (team, pg_temp.u('NEXO_ALUNO06'), 'programacao'),
    (team, pg_temp.u('NEXO_ALUNO07'), 'mecanica'), (team, pg_temp.u('NEXO_ALUNO09'), 'estrategia')
  on conflict do nothing;

  -- ── Responsáveis ─────────────────────────────────────────────────────────
  insert into public.guardian_links(guardian_id, student_id, consent_version, consented_at) values
    (pg_temp.u('VOLT_RESPONSAVEL'), pg_temp.u('VOLT_ALUNO1'), 'termo-responsavel-v1', now() - interval '140 days'),
    (pg_temp.u('NEXO_RESPONSAVEL'), pg_temp.u('NEXO_ALUNO01'), 'termo-responsavel-v1', now() - interval '21 days'),
    (pg_temp.u('NEXO_RESPONSAVEL'), pg_temp.u('NEXO_ALUNO06'), 'termo-responsavel-v1', now() - interval '21 days')
  on conflict do nothing;

  -- ── Uso mensal e faturas de demonstração ─────────────────────────────────
  -- Oficina Volt: abriu há 7 meses com contratação por Pix; cresce de 14 a 26
  -- alunos ativos; o último mês fechado está aguardando o Pix.
  perform pg_temp.fatura(volt, 'checkout', pg_temp.mes(7), 'escola', 'monthly', 12, 'pix', 'paid',
    (pg_temp.mes(7) + 3), (pg_temp.mes(7) + interval '1 day 2 hours'));
  for k in 1..7 loop
    v_active := 12 + (8 - k) * 2;
    perform pg_temp.uso(volt, pg_temp.mes(k), 'escola', v_active, v_active * 18, v_active * 6, true);
    perform pg_temp.fatura(volt, 'monthly', pg_temp.mes(k), 'escola', 'monthly', v_active, 'pix',
      case when k = 1 then 'awaiting_payment' else 'paid' end,
      case when k = 1 then current_date + 3 else pg_temp.mes(k - 1) + 5 end,
      case when k = 1 then null else (pg_temp.mes(k - 1) + interval '2 days 10 hours') end,
      null, null, case when k = 1 then null else 'VOLT-' || to_char(pg_temp.mes(k), 'YYYYMM') end);
  end loop;
  perform pg_temp.uso(volt, pg_temp.mes(0), 'escola', 21, 21 * 9, 21 * 3, false);

  -- Unidade Vale do Ferro: 12 meses fechados (queda de julho nas férias),
  -- boleto 30 dias com pedido de compra/centro de custo e NFS-e emitida;
  -- o último mês ainda está em aberto no prazo do boleto.
  for k in 1..12 loop
    v_active := case when extract(month from pg_temp.mes(k)) = 7 then 1180 else 1640 + (12 - k) * 25 end;
    perform pg_temp.uso(vf, pg_temp.mes(k), 'escola', v_active,
      v_active * case when extract(month from pg_temp.mes(k)) = 7 then 11 else 31 end, v_active * 14, true);
    perform pg_temp.fatura(vf, 'monthly', pg_temp.mes(k), 'escola', 'annual', v_active, 'boleto',
      case when k = 1 then 'awaiting_payment' else 'paid' end,
      (pg_temp.mes(k - 1) + 29),
      case when k = 1 then null else (pg_temp.mes(k - 1) + interval '21 days 14 hours') end,
      'PC-2026-0417', 'CC-EDU-VF-0210',
      case when k = 1 then null else 'NX' || to_char(pg_temp.mes(k), 'YYYYMM') || '-0' || (100 + k) end);
  end loop;
  perform pg_temp.uso(vf, pg_temp.mes(0), 'escola', 1935, 1935 * 12, 1935 * 6, false);

  -- Unidade Centro: piloto de 30 dias do Plus (sem fatura até virar contrato);
  -- o uso do mês vem dos próprios alunos (school_mark_active).
  perform pg_temp.uso(centro, pg_temp.mes(1), 'plus', 10, 10 * 14, 10 * 5, true);

  -- Relatório de amostra só da unidade grande (que não tem turma com conta):
  -- aparece marcado como demonstração.
  insert into public.school_demo_report(school_id, payload)
  values (vf, jsonb_build_object(
    'classes', '[
      {"title": "1º ano A — Eletrônica básica", "students": 248, "active_28d": 231, "assignments": 14},
      {"title": "1º ano B — Eletrônica básica", "students": 245, "active_28d": 219, "assignments": 12},
      {"title": "2º ano A — Robótica móvel", "students": 241, "active_28d": 228, "assignments": 16},
      {"title": "2º ano B — Sistemas embarcados", "students": 238, "active_28d": 210, "assignments": 11},
      {"title": "3º ano A — Redes e IoT", "students": 236, "active_28d": 214, "assignments": 13},
      {"title": "3º ano B — Programação", "students": 240, "active_28d": 226, "assignments": 15},
      {"title": "Técnico — Automação industrial", "students": 252, "active_28d": 239, "assignments": 18},
      {"title": "Equipe de robótica — OBR/FLL", "students": 235, "active_28d": 222, "assignments": 9}
    ]'::jsonb,
    'error_students', 1612,
    'errors_by_type', '[
      {"error_type": "calculo", "errors": 4820, "students": 1188},
      {"error_type": "conceito", "errors": 3915, "students": 1043},
      {"error_type": "unidade", "errors": 2760, "students": 902},
      {"error_type": "sinal", "errors": 2140, "students": 761},
      {"error_type": "interpretacao", "errors": 1985, "students": 694},
      {"error_type": "procedimento", "errors": 1430, "students": 512},
      {"error_type": "outro", "errors": 410, "students": 188}
    ]'::jsonb,
    'concepts', '[
      {"concept": "lei de ohm", "errors": 2310, "students": 884, "by_type": {"calculo": 1120, "unidade": 610, "conceito": 380, "sinal": 200}},
      {"concept": "divisor de tensão", "errors": 1780, "students": 702, "by_type": {"calculo": 760, "conceito": 540, "interpretacao": 300, "unidade": 180}},
      {"concept": "controle pid", "errors": 1540, "students": 561, "by_type": {"conceito": 720, "procedimento": 430, "interpretacao": 390}},
      {"concept": "pwm e duty cycle", "errors": 1320, "students": 590, "by_type": {"calculo": 520, "unidade": 470, "conceito": 330}},
      {"concept": "potência elétrica", "errors": 1210, "students": 633, "by_type": {"calculo": 610, "unidade": 420, "sinal": 180}},
      {"concept": "lógica booleana", "errors": 980, "students": 470, "by_type": {"conceito": 410, "procedimento": 330, "interpretacao": 240}},
      {"concept": "comunicação i2c", "errors": 860, "students": 388, "by_type": {"procedimento": 400, "conceito": 300, "interpretacao": 160}},
      {"concept": "cinemática diferencial", "errors": 790, "students": 341, "by_type": {"calculo": 330, "sinal": 290, "conceito": 170}}
    ]'::jsonb))
  on conflict (school_id) do update set payload = excluded.payload, updated_at = now();
end
$seed2$;

-- Resumo para conferência.
select s.name, s.plan, s.billing_cycle, s.status,
  (select count(*) from public.school_members m where m.school_id = s.id) as papeis,
  (select count(*) from public.platform_classes c where c.school_id = s.id) as turmas,
  (select count(*) from public.school_usage_months u where u.school_id = s.id) as meses,
  (select count(*) from public.school_invoices i where i.school_id = s.id) as faturas
from public.schools s order by s.created_at;

commit;
