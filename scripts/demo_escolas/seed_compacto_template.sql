-- Seed de demonstração (mmdemo), formato compacto: dados em jsonb, SQL genérico.
-- Gerado por gerar_compacto.py (scripts/demo_escolas). Ids = md5(conta || chave)::uuid.
-- Contas por e-mail; idempotente (pula conta já semeada).
do $seed$
declare
  d constant jsonb := $d$__DATA__$d$;
  uid uuid; v uuid; r jsonb; e jsonb; x jsonb; c text; aid uuid; eid uuid; s_id uuid;
  qrow record; ex uuid; subj uuid; conc uuid; diag jsonb; ans text; ok boolean; an jsonb; h numeric; keys jsonb; pub jsonb; res jsonb; mid uuid;
begin
  create temp table mm_map(k text primary key, id uuid not null) on commit drop;
  execute $f$create function pg_temp.i(k text) returns uuid language sql stable as 'select md5(current_setting(''mm.uid'')||k)::uuid'$f$;
  execute $f$create function pg_temp.m(k text) returns uuid language sql stable as 'select id from mm_map where mm_map.k=$1'$f$;
  execute $f$create function pg_temp.h(n numeric) returns timestamptz language sql stable as 'select now() - make_interval(secs => (n + current_setting(''mm.off'')::numeric)*3600)'$f$;
  if (select count(*) from auth.users where lower(email) = any(array[__USERS__])) <> cardinality(array[__USERS__]) then
    raise exception 'alguma conta de demonstração não existe';
  end if;
  foreach uid in array (select array_agg(id order by email) from auth.users where lower(email) = any(array[__USERS__])) loop
    truncate mm_map;
    perform set_config('mm.uid', uid::text, true);
    -- Cada aluno ganha um deslocamento de até 9 h e pula parte das tentativas
    -- opcionais, para o mapa da turma não ter todos os alunos iguais.
    perform set_config('mm.off', (get_byte(decode(md5(uid::text), 'hex'), 0) % 10)::text, true);
    if exists (select 1 from public.study_sessions where id = pg_temp.i('sess:S1')) then raise notice 'já aplicado em %', uid; continue; end if;
    perform set_config('request.jwt.claim.sub', uid::text, true);

    for r in select * from jsonb_array_elements(d->'subjects') loop
      select id into v from public.subjects where user_id = uid and lower(btrim(name)) = lower(r->>'name') order by created_at limit 1;
      if v is null then
        insert into public.subjects(id,user_id,name,description,created_at)
        values (pg_temp.i('subj:'||(r->>'k')), uid, r->>'name', d->>'mark', pg_temp.h(700)) returning id into v;
      end if;
      insert into mm_map values ('S:'||(r->>'k'), v);
    end loop;
    for r in select * from jsonb_array_elements(d->'concepts') loop
      select id into v from public.concepts where subject_id = pg_temp.m('S:'||(r->>'s')) and lower(name) = lower(r->>'name') order by created_at limit 1;
      if v is null then
        insert into public.concepts(id,subject_id,name,importance,created_at)
        values (pg_temp.i('conc:'||(r->>'k')), pg_temp.m('S:'||(r->>'s')), r->>'name', (r->>'imp')::numeric, pg_temp.h(690)) returning id into v;
      end if;
      insert into mm_map values ('C:'||(r->>'k'), v);
    end loop;
    for r in select * from jsonb_array_elements(d->'edges') loop
      insert into public.concept_edges(id,from_concept_id,to_concept_id,relation)
      values (pg_temp.i('edge:'||(r->>0)||(r->>1)), pg_temp.m('C:'||(r->>0)), pg_temp.m('C:'||(r->>1)), r->>2) on conflict do nothing;
    end loop;
    for r in select * from jsonb_array_elements(d->'exercises') loop
      insert into public.exercises(id,subject_id,source,prompt_text,difficulty,focus_concept,created_at)
      values (pg_temp.i('ex:'||(r->>'k')), pg_temp.m('S:'||(r->>'s')), 'manual', r->>'prompt', r->>'diff',
        (select name from public.concepts where id = pg_temp.m('C:'||(r->'concs'->>0))), pg_temp.h((r->>'h')::numeric));
      for c in select * from jsonb_array_elements_text(r->'concs') loop
        insert into public.exercise_concepts(exercise_id,concept_id) values (pg_temp.i('ex:'||(r->>'k')), pg_temp.m('C:'||c)) on conflict do nothing;
      end loop;
    end loop;

    -- tentativas + análise no formato do analyze-attempt
    for r in select * from jsonb_array_elements(d->'attempts') loop
      continue when coalesce((r->>'opt')::boolean, false)
        and get_byte(decode(md5(uid::text || (r->>'k')), 'hex'), 0) % 3 = 0;
      select x2 into e from jsonb_array_elements(d->'exercises') x2 where x2->>'k' = r->>'e';
      aid := pg_temp.i(r->>'k'); h := (r->>'h')::numeric;
      perform set_config('request.jwt.claim.sub', '', true);  -- guard_attempt_ai_state só aceita 'completed' sem JWT
      insert into public.attempts(id,exercise_id,user_id,answer,solution_text,attempted_at,status)
      values (aid, pg_temp.i('ex:'||(r->>'e')), uid, r->>'ans', r->>'ans', pg_temp.h(h), 'completed');
      perform set_config('request.jwt.claim.sub', uid::text, true);
      an := jsonb_build_object('is_correct', (r->>'ok')::boolean, 'correct_answer', e->>'gab', 'explanation', e->>'expl',
        'transcribed_prompt', e->>'prompt', 'transcribed_answer', r->>'ans',
        'errors', coalesce((select jsonb_agg(jsonb_build_object('category', x3->>'cat',
            'concept', (select name from public.concepts where id = pg_temp.m('C:'||(x3->>'c'))),
            'evidence', x3->>'ev', 'confidence', (x3->>'cf')::numeric)) from jsonb_array_elements(r->'errs') x3), '[]'::jsonb),
        'concepts', (select jsonb_agg(name order by n) from jsonb_array_elements_text(e->'concs') with ordinality t(ck,n)
                     join public.concepts cc on cc.id = pg_temp.m('C:'||ck)));
      insert into public.attempt_analyses(attempt_id,user_id,subject_id,analysis,model,pipeline_version,created_at)
      values (aid, uid, pg_temp.m('S:'||(e->>'s')), an, 'gemini-2.5-flash', 'gemini-analysis-v1', pg_temp.h(h-0.02));
      insert into public.corrections(attempt_id,reference_text,created_at)
      values (aid, (e->>'gab')||E'\n\n'||(e->>'expl'), pg_temp.h(h-0.02));
      for x, h in select y, (n - 1) from jsonb_array_elements(r->'errs') with ordinality t(y,n) loop
        eid := pg_temp.i('ee:'||(r->>'k')||':'||h::int);
        insert into public.error_events(id,attempt_id,error_type_id,concept_id,evidence_ref,confidence,status,created_at)
        values (eid, aid, (select id from public.error_types where name = x->>'cat'), pg_temp.m('C:'||(x->>'c')),
          x->>'ev', (x->>'cf')::numeric, x->>'st', pg_temp.h((r->>'h')::numeric - 0.02));
        if x->>'st' = 'confirmed' then
          insert into public.error_event_decisions(id,user_id,error_event_id,decision,category,importance,created_at)
          values (pg_temp.i('dec:'||eid::text), uid, eid, 'confirmed', x->>'cat',
            (select importance from public.concepts where id = pg_temp.m('C:'||(x->>'c'))), pg_temp.h((r->>'h')::numeric - 3));
        end if;
      end loop;
      if (r->>'ok')::boolean then
        for c in select * from jsonb_array_elements_text(e->'concs') loop
          insert into public.mastery_events(id,concept_id,attempt_id,outcome,created_at)
          values (pg_temp.i('me:'||(r->>'k')||c), pg_temp.m('C:'||c), aid, 'ai_suggested_correct', pg_temp.h((r->>'h')::numeric - 0.02));
        end loop;
      end if;
    end loop;

    -- agenda de revisão (mm-intervals-v1) e sessões concluídas
    for r in select * from jsonb_array_elements(d->'items') loop
      insert into public.review_items(id,user_id,subject_id,concept_id,error_event_id,category,due_at,interval_days,repetitions,lapses,last_reviewed_at,created_at,updated_at)
      values (pg_temp.i(r->>'k'), uid, (select subject_id from public.concepts where id = pg_temp.m('C:'||(r->>'c'))), pg_temp.m('C:'||(r->>'c')),
        pg_temp.i(r->>'ev'), r->>'cat', pg_temp.h((r->>'due_h')::numeric), (r->>'interval')::int, (r->>'reps')::int, (r->>'lapses')::int,
        case when r->>'last_h' is null then null else pg_temp.h((r->>'last_h')::numeric) end,
        pg_temp.h((r->>'created_h')::numeric), pg_temp.h(coalesce((r->>'last_h')::numeric, (r->>'created_h')::numeric)));
    end loop;
    for r in select * from jsonb_array_elements(d->'sessions') loop
      s_id := pg_temp.i(r->>'k');
      insert into public.study_sessions(id,user_id,status,planned_minutes,started_at,completed_at)
      values (s_id, uid, 'completed', (r->>'min')::int, pg_temp.h((r->>'h')::numeric), pg_temp.h((r->>'h')::numeric - 0.25));
      for x in select * from jsonb_array_elements(r->'items') loop
        insert into public.study_session_items(session_id,item_id,user_id,position,source_attempt_id,source_error_event_id,prompt_text,evidence,category)
        values (s_id, pg_temp.i(x->>'item'), uid, (x->>'pos')::int, pg_temp.i(x->>'att'), pg_temp.i(x->>'ev'),
          (select y->>'prompt' from jsonb_array_elements(d->'exercises') y where y->>'k' = x->>'e'), x->>'evidence', x->>'cat');
        insert into public.review_events(user_id,event_id,session_id,item_id,rating,answered_at,elapsed_seconds,payload_hash,next_due_at)
        values (uid, pg_temp.i('rev:'||(r->>'k')||(x->>'item')), s_id, pg_temp.i(x->>'item'), x->>'rt', pg_temp.h((x->>'ah')::numeric),
          (x->>'el')::int, encode(extensions.digest(s_id::text||(x->>'item')||(x->>'rt'), 'sha256'), 'hex'), pg_temp.h((x->>'next_h')::numeric));
      end loop;
    end loop;

    insert into public.study_profiles(user_id,stage,daily_minutes,timezone,subject_ids,goal,exam_date,updated_at)
    values (uid, 'superior', 20, 'America/Sao_Paulo', array[pg_temp.m('S:ELE'), pg_temp.m('S:ROB'), pg_temp.m('S:RED'), pg_temp.m('S:PRG')],
      d->>'goal', (now() + interval '24 days')::date, now()) on conflict (user_id) do nothing;

    for r in select * from jsonb_array_elements(d->'notes') loop
      insert into public.error_notes(id,user_id,subject,title,description,error_type,reviewed,created_at,updated_at)
      values (pg_temp.i(r->>'k'), uid, r->>'s', r->>'t', r->>'r', r->>'type', (r->>'rev')::boolean, pg_temp.h((r->>'h')::numeric),
        pg_temp.h((r->>'h')::numeric - case when (r->>'rev')::boolean then 30 else 0 end));
    end loop;

    for r in select * from jsonb_array_elements(d->'study') loop
      mid := pg_temp.i('mat:'||(r->>'s'));
      select jsonb_agg(jsonb_build_object('id', pg_temp.i(q->>'k'), 'prompt', q->>'prompt', 'options', q->'options', 'concept', q->>'concept') order by n),
             jsonb_agg(jsonb_build_object('id', pg_temp.i(q->>'k'), 'correct_choice', (q->>'correct_choice')::int, 'explanation', q->>'explanation') order by n)
        into pub, keys from jsonb_array_elements(r->'quiz') with ordinality t(q,n);
      insert into public.study_materials(id,user_id,subject_id,summary,flashcards,quiz,source_count,model,created_at)
      values (mid, uid, pg_temp.m('S:'||(r->>'s')), r->'summary', r->'flash', pub, (r->>'src')::int, 'gemini-2.5-flash', pg_temp.h((r->>'h')::numeric));
      insert into public.study_quiz_keys(material_id,answers) values (mid, keys);
      select jsonb_agg(jsonb_build_object('question_id', k->>'id', 'choice', (r->'round'->>(n-1)::int)::int, 'correct_choice', (k->>'correct_choice')::int,
          'is_correct', (r->'round'->>(n-1)::int)::int = (k->>'correct_choice')::int, 'explanation', k->>'explanation') order by n)
        into res from jsonb_array_elements(keys) with ordinality t(k,n);
      insert into public.study_quiz_rounds(id,material_id,user_id,answers,correct_count,total,created_at)
      values (pg_temp.i('round:'||(r->>'s')), mid, uid, res,
        (select count(*) from jsonb_array_elements(res) z where (z->>'is_correct')::boolean), jsonb_array_length(res), pg_temp.h((r->>'h')::numeric - 0.3));
    end loop;

    -- banco de questões: mesmo caminho do question_bank_service.saveObjective (múltipla escolha)
    for r in select * from jsonb_array_elements(d->'qb') loop
      h := (r->>'h')::numeric; aid := pg_temp.i(r->>'k');
      select b.*, k.answer as key_answer, k.correct_answer, k.explanation into qrow
        from public.question_bank b join public.question_bank_keys k on k.question_id = b.id where b.slug = r->>'slug';
      continue when qrow.id is null;
      select id into subj from public.subjects where user_id = uid and lower(btrim(name)) = lower(qrow.subject) order by created_at limit 1;
      if subj is null then
        insert into public.subjects(id,user_id,name,description,created_at) values (pg_temp.i('qbsubj:'||(r->>'slug')), uid, qrow.subject, d->>'mark', pg_temp.h(h+1)) returning id into subj;
      end if;
      select e2.id into ex from public.exercises e2 where e2.subject_id = subj and e2.question_id = qrow.id order by e2.created_at limit 1;
      if ex is null then
        insert into public.exercises(id,subject_id,source,prompt_text,difficulty,focus_concept,question_id,created_at)
        values (pg_temp.i('qbex:'||(r->>'slug')), subj, 'question_bank',
          qrow.prompt_text || E'\n\nAlternativas:' || (select string_agg(E'\n' || (o->>'id') || ') ' || (o->>'text'), '' order by n)
            from jsonb_array_elements(qrow.payload->'options') with ordinality t(o,n)),
          qrow.difficulty, qrow.theme, qrow.id, pg_temp.h(h+0.5)) returning id into ex;
      end if;
      select (o->>'id') || ') ' || (o->>'text') into ans from jsonb_array_elements(qrow.payload->'options') o where o->>'id' = r->>'choice';
      ok := (r->>'choice') = qrow.key_answer->>'correct';
      diag := qrow.key_answer->'diagnosis'->(r->>'choice');
      an := jsonb_build_object('is_correct', ok, 'correct_answer', qrow.correct_answer, 'explanation', qrow.explanation,
        'transcribed_prompt', (select prompt_text from public.exercises where id = ex), 'transcribed_answer', ans,
        'concepts', jsonb_build_array(left(btrim(qrow.theme),120)),
        'errors', case when ok then '[]'::jsonb else jsonb_build_array(jsonb_build_object(
          'category', coalesce(diag->>'category', qrow.error_category), 'concept', left(btrim(qrow.theme),120),
          'evidence', coalesce(diag->>'feedback', 'Resposta dada: ' || ans || '. Resposta correta: ' || qrow.correct_answer || '.'),
          'confidence', case when diag ? 'feedback' then 0.7 else 0.5 end)) end);
      perform set_config('request.jwt.claim.sub', '', true);
      insert into public.attempts(id,exercise_id,user_id,answer,solution_text,attempted_at,status) values (aid, ex, uid, ans, ans, pg_temp.h(h), 'completed');
      perform set_config('request.jwt.claim.sub', uid::text, true);
      insert into public.attempt_analyses(attempt_id,user_id,subject_id,analysis,model,pipeline_version,created_at)
      values (aid, uid, subj, an, 'gabarito-revisado', 'question-bank-v1', pg_temp.h(h));
      insert into public.corrections(attempt_id,reference_text,created_at) values (aid, qrow.correct_answer || E'\n\n' || qrow.explanation, pg_temp.h(h));
      select id into conc from public.concepts where subject_id = subj and lower(name) = lower(left(btrim(qrow.theme),120)) order by created_at limit 1;
      if conc is null then
        insert into public.concepts(id,subject_id,name,created_at) values (pg_temp.i('qbconc:'||(r->>'slug')), subj, left(btrim(qrow.theme),120), pg_temp.h(h)) returning id into conc;
      end if;
      insert into public.exercise_concepts(exercise_id,concept_id) values (ex, conc) on conflict do nothing;
      if not ok then
        insert into public.error_events(id,attempt_id,error_type_id,concept_id,evidence_ref,confidence,status,created_at)
        select pg_temp.i('qbee:'||(r->>'k')), aid, et.id, conc, an->'errors'->0->>'evidence', (an->'errors'->0->>'confidence')::numeric, 'pending', pg_temp.h(h)
        from public.error_types et where et.name = an->'errors'->0->>'category';
      else
        insert into public.mastery_events(id,concept_id,attempt_id,outcome,created_at) values (pg_temp.i('qbme:'||(r->>'k')), conc, aid, 'question_bank_correct', pg_temp.h(h));
      end if;
      insert into public.question_responses(id,user_id,question_id,attempt_id,response,is_correct,score,created_at)
      values (pg_temp.i('qbr:'||(r->>'k')), uid, qrow.id, aid, jsonb_build_object('choice', r->>'choice'), ok, case when ok then 1 else 0 end, pg_temp.h(h));
    end loop;
    perform set_config('request.jwt.claim.sub', '', true);
  end loop;
end
$seed$;
