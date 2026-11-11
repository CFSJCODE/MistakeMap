import type postgres from "postgresjs";
import { aiTierForPlan } from "./model_router.ts";
import { PublicError } from "./ai_contract.ts";
import type { Database } from "./ai_service.ts";
import {
  assignmentResult,
  classMap,
  createConceptAssignment,
} from "./class_map.ts";
import { contentOperation } from "./platform_content.ts";
import {
  csvCell,
  date,
  flag,
  type GradeItem,
  gradeItems,
  hintFor,
  id,
  ids,
  type Input,
  integer,
  materialUrl,
  optionalId,
  platformAction,
  strings,
  text,
  timestamp,
  weeklyPlan,
} from "./platform_contract.ts";

type Query = postgres.Sql | postgres.TransactionSql;
const denied = () =>
  new PublicError(403, "access_denied", "Você não tem acesso a esta operação.");
const missing = () =>
  new PublicError(404, "not_found", "O item não foi encontrado na sua conta.");
const jsonValue = (value: unknown) => value as postgres.JSONValue;

async function isAdmin(sql: Query, user: string): Promise<boolean> {
  const [row] = await sql`SELECT role FROM public.profiles WHERE id=${user}`;
  return row?.role === "admin";
}
async function teacherEnabled(sql: Query, user: string): Promise<boolean> {
  if (await isAdmin(sql, user)) return true;
  const rows =
    await sql`SELECT 1 FROM public.platform_teachers WHERE user_id=${user}`;
  return rows.length > 0;
}
async function ownClass(sql: Query, user: string, classId: string) {
  const [row] =
    await sql`SELECT id,title,teacher_id FROM public.platform_classes
    WHERE id=${classId} AND teacher_id=${user}`;
  if (!row) throw denied();
  return row;
}
async function entitlements(sql: Query, user: string) {
  const [row] =
    await sql`SELECT plan,sessions_per_day FROM public.platform_entitlements
    WHERE user_id=${user} AND (expires_at IS NULL OR expires_at>now())`;
  const [usage] =
    await sql`SELECT count(*)::int AS used FROM public.platform_sessions
    WHERE user_id=${user} AND created_at>=date_trunc('day',now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'`;
  // Membro de escola herda o plano dela (Grátis, Escola ou Escola Plus);
  // sem escola vale o plano individual de platform_entitlements.
  // Confere a função antes: banco sem a migration 20261111071500 segue no
  // plano individual (migrations e funções publicam em paralelo).
  const [ready] =
    await sql`SELECT to_regprocedure('public.user_school_plan(uuid)') IS NOT NULL AS ok`;
  const [school] = ready?.ok
    ? await sql`SELECT * FROM public.user_school_plan(${user})`
    : [];
  const individual = row?.plan ?? "free";
  return {
    plan: school ? String(school.plan) : individual,
    plan_label: school
      ? String(school.plan_label)
      : individual === "free"
      ? "Gratuito"
      : individual === "pro"
      ? "Pro"
      : "Piloto",
    plan_source: school ? "school" : "individual",
    school: school
      ? {
        id: school.school_id,
        name: school.school_name,
        role: school.role,
        status: school.school_status,
      }
      : null,
    ai_tier: aiTierForPlan(school?.plan),
    sessions_per_day: Number(row?.sessions_per_day ?? 10),
    sessions_used_today: Number(usage?.used ?? 0),
    usage_day_zone: "UTC",
    teacher_enabled: await teacherEnabled(sql, user),
    payments_available: false,
  };
}
async function ownSession(
  sql: Query,
  user: string,
  sessionId: string,
  lock = false,
) {
  const [row] = lock
    ? await sql`SELECT * FROM public.platform_sessions WHERE id=${sessionId} AND user_id=${user} FOR UPDATE`
    : await sql`SELECT * FROM public.platform_sessions WHERE id=${sessionId} AND user_id=${user}`;
  if (!row) throw missing();
  return row;
}
async function publicSession(sql: Query, user: string, sessionId: string) {
  const row = await ownSession(sql, user, sessionId);
  const items =
    await sql`SELECT id,catalog_exercise_id,position,prompt,subject,theme,difficulty,answer,hint_level
    FROM public.platform_session_items WHERE session_id=${sessionId} ORDER BY position`;
  return {
    id: row.id,
    title: row.title,
    mode: row.mode,
    status: row.status,
    goal_id: row.goal_id,
    assignment_id: row.assignment_id,
    total: row.total,
    correct_count: row.correct_count,
    assisted: row.assisted,
    created_at: row.created_at,
    finished_at: row.finished_at,
    items,
    results: row.status === "completed" ? row.results : null,
    grading_notice:
      "Comparação conservadora com resposta revisada. Respostas diferentes pedem conferência; não são automaticamente erros.",
  };
}

export async function platformOverview(sql: Database, user: string) {
  const [
    goals,
    sessions,
    classes,
    assignments,
    materials,
    notes,
    privacyRequests,
    progress,
    feedback,
  ] = await Promise.all([
    sql`SELECT id,title,exam_date,minutes_per_day,subjects,weekly_plan,created_at,updated_at,
      coalesce((weekly_plan->0->>'date')<to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD'),true) AS refresh_recommended
      FROM public.platform_goals WHERE user_id=${user} ORDER BY updated_at DESC LIMIT 20`,
    sql`SELECT id,title,mode,status,total,correct_count,assisted,created_at,finished_at
      FROM public.platform_sessions WHERE user_id=${user} ORDER BY created_at DESC LIMIT 100`,
    sql`SELECT c.id,c.title,c.teacher_id,c.teacher_id=${user} AS is_teacher,
      CASE WHEN c.teacher_id=${user} THEN i.code ELSE NULL END AS code,
      coalesce(m.share_progress,false) AS share_progress,coalesce(m.share_answers,false) AS share_answers,
      coalesce(m.share_notes,false) AS share_notes
      FROM public.platform_classes c LEFT JOIN public.platform_memberships m ON m.class_id=c.id AND m.user_id=${user}
      LEFT JOIN public.platform_class_invites i ON i.class_id=c.id
      WHERE c.teacher_id=${user} OR m.user_id=${user} ORDER BY c.created_at DESC LIMIT 100`,
    sql`SELECT a.id,a.class_id,a.title,a.due_at,a.catalog_ids,a.question_ids,a.source_concept FROM public.platform_assignments a
      JOIN public.platform_classes c ON c.id=a.class_id WHERE c.teacher_id=${user} OR EXISTS(
        SELECT 1 FROM public.platform_memberships m WHERE m.class_id=c.id AND m.user_id=${user})
      ORDER BY a.created_at DESC LIMIT 100`,
    sql`SELECT id,title,url,notes,page_number,created_at FROM public.platform_materials WHERE user_id=${user} ORDER BY created_at DESC LIMIT 100`,
    sql`SELECT id,title,body,concept,attempt_id,catalog_exercise_id,created_at,updated_at FROM public.platform_connected_notes WHERE user_id=${user} ORDER BY updated_at DESC LIMIT 100`,
    sql`SELECT id,kind,status,created_at,completed_at FROM public.platform_privacy_requests WHERE user_id=${user} ORDER BY created_at DESC LIMIT 10`,
    sql`SELECT coalesce(sum(total),0)::int AS attempts,coalesce(sum(correct_count),0)::int AS correct,
      count(*) FILTER (WHERE assisted)::int AS assisted FROM public.platform_sessions
      WHERE user_id=${user} AND status='completed' AND finished_at>=now()-interval '30 days'`,
    sql`SELECT f.id,f.session_id,f.student_id,f.teacher_id,f.body,f.created_at,f.updated_at,
      s.title AS session_title,c.title AS class_title
      FROM public.platform_teacher_feedback f JOIN public.platform_sessions s ON s.id=f.session_id
      LEFT JOIN public.platform_assignments a ON a.id=s.assignment_id LEFT JOIN public.platform_classes c ON c.id=a.class_id
      WHERE f.student_id=${user} AND s.user_id=${user} ORDER BY f.updated_at DESC LIMIT 100`,
  ]);
  return {
    goals: goals.map((goal) => ({
      ...goal,
      refresh_notice: goal.refresh_recommended
        ? "Seu plano tem datas anteriores. Reorganize a semana para considerar suas respostas recentes."
        : null,
    })),
    sessions,
    classes,
    assignments,
    materials,
    notes,
    privacy_requests: privacyRequests,
    feedback,
    entitlements: await entitlements(sql, user),
    progress: {
      period_days: 30,
      attempts: Number(progress[0].attempts),
      correct: Number(progress[0].correct),
      assisted: Number(progress[0].assisted),
      label:
        "Sessões do catálogo; correção por equivalência textual conservadora",
    },
    limits: {
      sessions: 100,
      materials: 100,
      notes: 100,
      assignments: 100,
      export_page_size: 100,
    },
  };
}

async function startSession(sql: Database, user: string, input: Input) {
  const requestId = id(input, "request_id"), mode = text(input, "mode", 12);
  if (!["practice", "exam"].includes(mode)) {
    throw new PublicError(400, "invalid_mode", "Escolha prática ou simulado.");
  }
  const subject = text(input, "subject", 120, true),
    theme = text(input, "theme", 120, true);
  const count = integer(input, "count", 1, 10, 5),
    assignmentId = optionalId(input, "assignment_id"),
    goalId = optionalId(input, "goal_id");
  const payload = { mode, subject, theme, count, assignmentId, goalId };
  return await sql.begin(async (tx) => {
    // Serializa cota e request_id por conta, inclusive em aparelhos diferentes.
    await tx`SELECT pg_advisory_xact_lock(hashtextextended(${
      "platform-session:" + user
    },0))`;
    const [existing] = await tx`SELECT id,request_payload=${
      tx.json(payload)
    }::jsonb AS matches FROM public.platform_sessions WHERE user_id=${user} AND request_id=${requestId}`;
    if (existing) {
      if (!existing.matches) {
        throw new PublicError(
          409,
          "request_reused",
          "Este pedido já foi usado para outra sessão.",
        );
      }
      return { session: await publicSession(tx, user, String(existing.id)) };
    }
    const entitlement = await entitlements(tx, user);
    if (entitlement.sessions_used_today >= entitlement.sessions_per_day) {
      throw new PublicError(
        429,
        "session_limit",
        "Você atingiu a cota de sessões de hoje (UTC). As sessões salvas continuam acessíveis.",
      );
    }
    if (goalId) {
      const goals =
        await tx`SELECT 1 FROM public.platform_goals WHERE id=${goalId} AND user_id=${user}`;
      if (!goals.length) throw missing();
    }
    let selected: postgres.RowList<postgres.Row[]>;
    let title = mode === "exam"
      ? "Simulado do catálogo"
      : "Prática do catálogo";
    if (assignmentId) {
      const [assignment] =
        await tx`SELECT a.* FROM public.platform_assignments a JOIN public.platform_classes c ON c.id=a.class_id
        WHERE a.id=${assignmentId} AND (c.teacher_id=${user} OR EXISTS(SELECT 1 FROM public.platform_memberships m WHERE m.class_id=c.id AND m.user_id=${user}))`;
      if (!assignment) throw missing();
      if (!(assignment.catalog_ids as string[]).length) {
        throw new PublicError(
          409,
          "question_assignment",
          "Esta tarefa usa o banco de questões. Responda pela opção Responder tarefa.",
        );
      }
      title = String(assignment.title);
      selected =
        await tx`SELECT c.*,k.correct_answer,k.explanation FROM public.catalog_exercises c JOIN public.catalog_answer_keys k ON k.catalog_exercise_id=c.id
        WHERE c.id=ANY(${assignment.catalog_ids}::uuid[]) ORDER BY array_position(${assignment.catalog_ids}::uuid[],c.id)`;
    } else {
      // Prefere questões ainda não vistas; repetir depois preserva acesso ao conteúdo.
      selected =
        await tx`SELECT c.*,k.correct_answer,k.explanation FROM public.catalog_exercises c JOIN public.catalog_answer_keys k ON k.catalog_exercise_id=c.id
        WHERE (${subject}='' OR c.subject=${subject}) AND (${theme}='' OR c.theme=${theme})
        ORDER BY (SELECT count(*) FROM public.platform_session_items i JOIN public.platform_sessions s ON s.id=i.session_id WHERE s.user_id=${user} AND i.catalog_exercise_id=c.id),c.position,c.id LIMIT ${count}`;
    }
    if (!selected.length) {
      throw new PublicError(
        409,
        "catalog_empty",
        "Não há questões revisadas para este recorte. Escolha outro tema.",
      );
    }
    const [row] =
      await tx`INSERT INTO public.platform_sessions(user_id,request_id,request_payload,goal_id,assignment_id,mode,title,total)
      VALUES(${user},${requestId},${
        tx.json(payload)
      },${goalId},${assignmentId},${mode},${title},${selected.length}) RETURNING id`;
    for (let i = 0; i < selected.length; i++) {
      const c = selected[i];
      const [item] =
        await tx`INSERT INTO public.platform_session_items(session_id,catalog_exercise_id,position,prompt,subject,theme,difficulty)
        VALUES(${row.id},${c.id},${i},${c.prompt_text},${c.subject},${c.theme},${c.difficulty}) RETURNING id`;
      await tx`INSERT INTO public.platform_session_keys(item_id,correct_answer,explanation) VALUES(${item.id},${c.correct_answer},${c.explanation})`;
    }
    return { session: await publicSession(tx, user, String(row.id)) };
  });
}

async function sessionMutation(
  sql: Database,
  user: string,
  input: Input,
  action: string,
) {
  const sessionId = id(input, "session_id");
  return await sql.begin(async (tx) => {
    const session = await ownSession(tx, user, sessionId, true);
    if (action === "finish_session") {
      if (session.status === "completed") {
        return {
          session: await publicSession(tx, user, sessionId),
          ...session.results as Record<string, unknown>,
        };
      }
      const rows =
        await tx`SELECT i.id,i.answer,i.hint_level,k.correct_answer,k.explanation FROM public.platform_session_items i JOIN public.platform_session_keys k ON k.item_id=i.id WHERE i.session_id=${sessionId} ORDER BY i.position`;
      const graded = gradeItems(rows as unknown as GradeItem[]);
      if (graded.total !== session.total) {
        throw new PublicError(
          409,
          "incomplete_session",
          "A sessão precisa ser conferida antes da correção.",
        );
      }
      await tx`UPDATE public.platform_sessions SET status='completed',results=${
        tx.json(jsonValue(graded))
      },correct_count=${graded.correct_count},assisted=${graded.assisted},finished_at=now() WHERE id=${sessionId}`;
      return { session: await publicSession(tx, user, sessionId), ...graded };
    }
    if (session.status !== "active") {
      throw new PublicError(
        409,
        "session_finished",
        "Esta sessão já foi finalizada. A correção permanece disponível.",
      );
    }
    const itemId = id(input, "item_id");
    if (action === "save_answer") {
      const answer = text(input, "answer", 2000, true);
      const updated =
        await tx`UPDATE public.platform_session_items SET answer=${answer},updated_at=now() WHERE id=${itemId} AND session_id=${sessionId} RETURNING id`;
      if (!updated.length) throw missing();
      return { saved: true };
    }
    if (session.mode !== "practice") {
      throw new PublicError(
        403,
        "exam_no_hints",
        "As pistas ficam desativadas durante o simulado.",
      );
    }
    const level = integer(input, "level", 1, 3);
    const [item] =
      await tx`SELECT i.theme,k.explanation FROM public.platform_session_items i JOIN public.platform_session_keys k ON k.item_id=i.id WHERE i.id=${itemId} AND i.session_id=${sessionId}`;
    if (!item) throw missing();
    await tx`UPDATE public.platform_session_items SET hint_level=greatest(hint_level,${level}),updated_at=now() WHERE id=${itemId}`;
    await tx`UPDATE public.platform_sessions SET assisted=true WHERE id=${sessionId}`;
    return {
      hint: hintFor(String(item.theme), level, String(item.explanation)),
      level,
      assisted: true,
      source: "Catálogo revisado; orientação pedagógica sem IA",
    };
  });
}

async function saveGoal(sql: Database, user: string, input: Input) {
  const goalId = optionalId(input, "id"),
    title = text(input, "title"),
    examDate = date(input, "exam_date"),
    minutes = integer(input, "minutes_per_day", 5, 180),
    subjects = strings(input, "subjects");
  if (examDate && Date.parse(examDate + "T23:59:59Z") < Date.now()) {
    throw new PublicError(
      400,
      "past_exam",
      "Escolha uma data a partir de hoje.",
    );
  }
  const themes =
    await sql`SELECT DISTINCT subject,theme FROM public.catalog_exercises ORDER BY subject,theme`;
  const plan = weeklyPlan(
    subjects,
    themes.map((row) => ({
      subject: String(row.subject),
      theme: String(row.theme),
    })),
    minutes,
    examDate,
  );
  return await sql.begin(async (tx) => {
    await tx`SELECT pg_advisory_xact_lock(hashtextextended(${
      "platform-goal:" + user
    },0))`;
    if (goalId) {
      const [goal] =
        await tx`UPDATE public.platform_goals SET title=${title},exam_date=${examDate},minutes_per_day=${minutes},subjects=${subjects},weekly_plan=${
          tx.json(jsonValue(plan))
        },updated_at=now() WHERE id=${goalId} AND user_id=${user} RETURNING *`;
      if (!goal) throw missing();
      return { goal };
    }
    const [size] =
      await tx`SELECT count(*)::int AS n FROM public.platform_goals WHERE user_id=${user}`;
    if (size.n >= 20) {
      throw new PublicError(
        409,
        "goal_limit",
        "Mantenha até 20 objetivos; remova um objetivo antigo para continuar.",
      );
    }
    const [goal] =
      await tx`INSERT INTO public.platform_goals(user_id,title,exam_date,minutes_per_day,subjects,weekly_plan)
      VALUES(${user},${title},${examDate},${minutes},${subjects},${
        tx.json(jsonValue(plan))
      }) RETURNING *`;
    return { goal };
  });
}

async function refreshGoal(sql: Database, user: string, input: Input) {
  const goalId = id(input, "id");
  return await sql.begin(async (tx) => {
    const [goal] =
      await tx`SELECT id,title,exam_date::text AS exam_date,minutes_per_day,subjects
      FROM public.platform_goals WHERE id=${goalId} AND user_id=${user} FOR UPDATE`;
    if (!goal) throw missing();
    const themes = await tx`WITH recent AS (
      SELECT i.subject,i.theme,count(*)::int AS needs_review_count,max(s.finished_at) AS latest
      FROM public.platform_sessions s JOIN public.platform_session_items i ON i.session_id=s.id
      JOIN LATERAL jsonb_array_elements(coalesce(s.results->'results','[]'::jsonb)) r
        ON r->>'item_id'=i.id::text
      WHERE s.user_id=${user} AND s.goal_id=${goalId} AND s.status='completed'
        AND s.finished_at>=now()-interval '30 days' AND r->>'verdict'='needs_review'
      GROUP BY i.subject,i.theme
    ), available AS (SELECT DISTINCT subject,theme FROM public.catalog_exercises)
    SELECT a.subject,a.theme,coalesce(r.needs_review_count,0)::int AS needs_review_count
      FROM available a LEFT JOIN recent r ON r.subject=a.subject AND r.theme=a.theme
      ORDER BY coalesce(r.needs_review_count,0) DESC,r.latest DESC NULLS LAST,a.subject,a.theme`;
    const plan = weeklyPlan(
      goal.subjects as string[],
      themes.map((row) => ({
        subject: String(row.subject),
        theme: String(row.theme),
      })),
      Number(goal.minutes_per_day),
      goal.exam_date ? String(goal.exam_date) : null,
    )
      .map((day) => {
        const count = Number(
          themes.find((row) =>
            row.subject === day.subject && row.theme === day.theme
          )?.needs_review_count ?? 0,
        );
        return {
          ...day,
          needs_review_count: count,
          activity: count > 0
            ? "Conferir respostas recentes e praticar o tema novamente"
            : day.activity,
          reason: count > 0
            ? "Respostas recentes deste objetivo pedem conferência; isso não significa que estejam erradas."
            : "Distribuição pelos temas disponíveis deste objetivo.",
        };
      });
    const [updated] = await tx`UPDATE public.platform_goals SET weekly_plan=${
      tx.json(jsonValue(plan))
    },updated_at=now()
      WHERE id=${goalId} AND user_id=${user} RETURNING *`;
    return {
      goal: updated,
      notice: plan.length
        ? "Semana reorganizada com as respostas dos últimos 30 dias deste objetivo. Tempo diário e data da prova preservados."
        : "A data da prova já passou. Atualize o objetivo para planejar novos dias; nenhum orçamento ou data foi alterado.",
    };
  });
}

async function classMutation(
  sql: Database,
  user: string,
  input: Input,
  action: string,
) {
  if (action === "grant_teacher") {
    if (!await isAdmin(sql, user)) throw denied();
    const teacher = id(input, "user_id");
    const [profile] =
      await sql`SELECT id FROM public.profiles WHERE id=${teacher}`;
    if (!profile) throw missing();
    await sql`INSERT INTO public.platform_teachers(user_id,approved_by) VALUES(${teacher},${user}) ON CONFLICT(user_id) DO NOTHING`;
    return { granted: true };
  }
  if (action === "create_class") {
    const title = text(input, "title");
    if (!await teacherEnabled(sql, user)) {
      throw new PublicError(
        403,
        "teacher_required",
        "Peça à administração a habilitação de professor antes de criar uma turma.",
      );
    }
    return await sql.begin(async (tx) => {
      await tx`SELECT pg_advisory_xact_lock(hashtextextended(${
        "platform-class:" + user
      },0))`;
      const [size] =
        await tx`SELECT count(*)::int AS n FROM public.platform_classes WHERE teacher_id=${user}`;
      if (size.n >= 20) {
        throw new PublicError(
          409,
          "class_limit",
          "O limite atual é de 20 turmas por professor.",
        );
      }
      const [row] =
        await tx`INSERT INTO public.platform_classes(teacher_id,title) VALUES(${user},${title}) RETURNING id,title,teacher_id`;
      const [invite] =
        await tx`INSERT INTO public.platform_class_invites(class_id) VALUES(${row.id}) RETURNING code`;
      return { class: { ...row, code: invite.code, is_teacher: true } };
    });
  }
  if (action === "join_class") {
    const code = text(input, "code", 32).toLowerCase();
    if (!/^[a-f0-9]{32}$/.test(code)) {
      throw new PublicError(
        400,
        "invalid_code",
        "Confira o código de convite.",
      );
    }
    return await sql.begin(async (tx) => {
      const [row] =
        await tx`SELECT c.id,c.title,c.teacher_id FROM public.platform_class_invites i JOIN public.platform_classes c ON c.id=i.class_id WHERE i.code=${code} FOR UPDATE OF c`;
      if (!row) throw missing();
      if (row.teacher_id !== user) {
        const [size] =
          await tx`SELECT count(*)::int AS n FROM public.platform_memberships WHERE class_id=${row.id}`;
        const existing =
          await tx`SELECT 1 FROM public.platform_memberships WHERE class_id=${row.id} AND user_id=${user}`;
        if (!existing.length && size.n >= 500) {
          throw new PublicError(
            409,
            "class_full",
            "Esta turma atingiu o limite atual de participantes.",
          );
        }
        await tx`INSERT INTO public.platform_memberships(class_id,user_id) VALUES(${row.id},${user}) ON CONFLICT DO NOTHING`;
      }
      return {
        class: { ...row, is_teacher: row.teacher_id === user },
        sharing_notice:
          "Entrar na turma não compartilha suas respostas, progresso ou notas. Você escolhe cada permissão. Seus erros entram sem seu nome no mapa da turma, que só aparece com 5 alunos ou mais.",
      };
    });
  }
  const classId = id(input, "class_id");
  if (action === "set_sharing") {
    const progress = flag(input, "share_progress"),
      answers = flag(input, "share_answers"),
      notes = flag(input, "share_notes");
    const updated =
      await sql`UPDATE public.platform_memberships SET share_progress=${progress},share_answers=${answers},share_notes=${notes},consent_updated_at=now() WHERE class_id=${classId} AND user_id=${user} RETURNING class_id`;
    if (!updated.length) throw missing();
    return { saved: true };
  }
  if (action === "leave_class") {
    await sql`DELETE FROM public.platform_memberships WHERE class_id=${classId} AND user_id=${user}`;
    return { left: true };
  }
  await ownClass(sql, user, classId);
  if (action === "rotate_class_code") {
    const [invite] =
      await sql`UPDATE public.platform_class_invites SET code=replace(gen_random_uuid()::text,'-',''),created_at=now() WHERE class_id=${classId} RETURNING code`;
    return { code: invite.code };
  }
  if (action === "remove_class_member") {
    const member = id(input, "user_id");
    await sql`DELETE FROM public.platform_memberships WHERE class_id=${classId} AND user_id=${member}`;
    return { removed: true };
  }
  if (action === "create_assignment") {
    const title = text(input, "title"),
      dueAt = timestamp(input, "due_at"),
      catalogIds = ids(input, "catalog_ids");
    const rows =
      await sql`SELECT id FROM public.catalog_exercises WHERE id=ANY(${catalogIds}::uuid[])`;
    if (rows.length !== catalogIds.length) {
      throw new PublicError(
        400,
        "invalid_catalog",
        "Uma das questões não está disponível no catálogo.",
      );
    }
    const [assignment] =
      await sql`INSERT INTO public.platform_assignments(class_id,title,due_at,catalog_ids) VALUES(${classId},${title},${dueAt},${catalogIds}) RETURNING *`;
    return { assignment };
  }
  // Uma única consulta observa o consentimento atual e nunca inclui sessões
  // ativas/gabaritos. Somente dados de tarefas desta turma são compartilhados.
  const students =
    await sql`SELECT m.user_id,m.share_progress,m.share_answers,m.share_notes,
    CASE WHEN m.share_progress THEN (SELECT jsonb_build_object('sessions',count(*),'attempts',coalesce(sum(s.total),0),'correct',coalesce(sum(s.correct_count),0),'assisted',count(*) FILTER (WHERE s.assisted)) FROM public.platform_sessions s JOIN public.platform_assignments a ON a.id=s.assignment_id WHERE s.user_id=m.user_id AND a.class_id=m.class_id AND s.status='completed') ELSE NULL END AS progress,
    CASE WHEN m.share_answers THEN (SELECT coalesce(jsonb_agg(r),'[]'::jsonb) FROM (SELECT s.id,s.title,s.finished_at,s.results,
      (SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'body',f.body,'created_at',f.created_at,'updated_at',f.updated_at)),'[]'::jsonb) FROM public.platform_teacher_feedback f WHERE f.session_id=s.id AND f.teacher_id=${user}) AS feedback
      FROM public.platform_sessions s JOIN public.platform_assignments a ON a.id=s.assignment_id WHERE s.user_id=m.user_id AND a.class_id=m.class_id AND s.status='completed' ORDER BY s.finished_at DESC LIMIT 20) r) ELSE NULL END AS answers,
    CASE WHEN m.share_notes THEN (SELECT coalesce(jsonb_agg(r),'[]'::jsonb) FROM (SELECT n.id,n.title,n.body,n.concept FROM public.platform_connected_notes n WHERE n.user_id=m.user_id AND n.catalog_exercise_id IN (SELECT unnest(a.catalog_ids) FROM public.platform_assignments a WHERE a.class_id=m.class_id) ORDER BY n.updated_at DESC LIMIT 20) r) ELSE NULL END AS notes
    FROM public.platform_memberships m WHERE m.class_id=${classId} ORDER BY m.joined_at LIMIT 500`;
  return {
    students,
    scope:
      "Somente tarefas desta turma; permissões atuais do estudante. Até 20 sessões/notas por estudante.",
  };
}

async function saveMaterial(sql: Database, user: string, input: Input) {
  if (input.rights_confirmed !== true) {
    throw new PublicError(
      400,
      "rights_required",
      "Confirme que pode usar este material pessoalmente.",
    );
  }
  const title = text(input, "title"),
    url = materialUrl(input),
    notes = text(input, "notes", 3000, true),
    page = input.page_number == null
      ? null
      : integer(input, "page_number", 1, 100000);
  const [material] =
    await sql`INSERT INTO public.platform_materials(user_id,title,url,notes,page_number) VALUES(${user},${title},${url},${notes},${page}) RETURNING id,title,url,notes,page_number,created_at`;
  return {
    material,
    notice:
      "Link pessoal salvo. O PDF não foi importado, processado ou enviado a uma IA.",
  };
}
async function saveNote(sql: Database, user: string, input: Input) {
  const noteId = optionalId(input, "id"),
    title = text(input, "title"),
    body = text(input, "body", 5000),
    concept = text(input, "concept", 160, true),
    attemptId = optionalId(input, "attempt_id"),
    catalogId = optionalId(input, "catalog_exercise_id");
  if (attemptId) {
    const own =
      await sql`SELECT 1 FROM public.attempts WHERE id=${attemptId} AND user_id=${user}`;
    if (!own.length) throw missing();
  }
  if (catalogId) {
    const catalog =
      await sql`SELECT 1 FROM public.catalog_exercises WHERE id=${catalogId}`;
    if (!catalog.length) throw missing();
  }
  if (noteId) {
    const [note] =
      await sql`UPDATE public.platform_connected_notes SET title=${title},body=${body},concept=${concept},attempt_id=${attemptId},catalog_exercise_id=${catalogId},updated_at=now() WHERE id=${noteId} AND user_id=${user} RETURNING *`;
    if (!note) throw missing();
    return { note };
  }
  const [note] =
    await sql`INSERT INTO public.platform_connected_notes(user_id,title,body,concept,attempt_id,catalog_exercise_id) VALUES(${user},${title},${body},${concept},${attemptId},${catalogId}) RETURNING *`;
  return { note };
}

// Lista fechada de tabelas exportáveis. SQL é literal em cada caso: table/cursor
// não viram identificadores interpolados. Página máxima 100; cliente continua
// até next_cursor=null em todas as tabelas. Nenhuma chave privada é exportada.
const EXPORT_TABLES = [
  "profiles",
  "subjects",
  "concepts",
  "exercises",
  "attempts",
  "attempt_analyses",
  "error_events",
  "mastery_events",
  "error_notes",
  "study_materials",
  "study_quiz_rounds",
  "practice_sets",
  "goals",
  "sessions",
  "session_items",
  "materials",
  "notes",
  "memberships",
  "classes",
  "assignments",
  "privacy_requests",
  "study_profiles",
  "review_items",
  "study_sessions",
  "study_session_items",
  "review_events",
  "study_streak_freezes",
  "error_event_decisions",
  "corrections",
  "attempt_assets",
  "notebook_entries",
  "content_drafts",
  "feedback",
] as const;
async function exportData(sql: Database, user: string, input: Input) {
  const table = text(input, "table", 40, true) || "profiles",
    cursor = integer(input, "cursor", 0, 1000000, 0);
  if (!EXPORT_TABLES.includes(table as typeof EXPORT_TABLES[number])) {
    throw new PublicError(
      400,
      "invalid_export_table",
      "Escolha uma tabela disponível para exportação.",
    );
  }
  let rows: postgres.RowList<postgres.Row[]>;
  switch (table) {
    case "profiles":
      rows =
        await sql`SELECT id,institution_name,course,education_level,higher_education_type,role,created_at FROM public.profiles WHERE id=${user} ORDER BY id OFFSET ${cursor} LIMIT 101`;
      break;
    case "subjects":
      rows =
        await sql`SELECT * FROM public.subjects WHERE user_id=${user} ORDER BY id OFFSET ${cursor} LIMIT 101`;
      break;
    case "concepts":
      rows =
        await sql`SELECT c.* FROM public.concepts c JOIN public.subjects s ON s.id=c.subject_id WHERE s.user_id=${user} ORDER BY c.id OFFSET ${cursor} LIMIT 101`;
      break;
    case "exercises":
      rows =
        await sql`SELECT e.* FROM public.exercises e JOIN public.subjects s ON s.id=e.subject_id WHERE s.user_id=${user} ORDER BY e.id OFFSET ${cursor} LIMIT 101`;
      break;
    case "attempts":
      rows =
        await sql`SELECT * FROM public.attempts WHERE user_id=${user} ORDER BY id OFFSET ${cursor} LIMIT 101`;
      break;
    case "attempt_analyses":
      rows =
        await sql`SELECT * FROM public.attempt_analyses WHERE user_id=${user} ORDER BY attempt_id OFFSET ${cursor} LIMIT 101`;
      break;
    case "error_events":
      rows =
        await sql`SELECT e.* FROM public.error_events e JOIN public.attempts a ON a.id=e.attempt_id WHERE a.user_id=${user} ORDER BY e.id OFFSET ${cursor} LIMIT 101`;
      break;
    case "mastery_events":
      rows =
        await sql`SELECT m.* FROM public.mastery_events m JOIN public.attempts a ON a.id=m.attempt_id WHERE a.user_id=${user} ORDER BY m.id OFFSET ${cursor} LIMIT 101`;
      break;
    case "error_notes":
      rows =
        await sql`SELECT * FROM public.error_notes WHERE user_id=${user} ORDER BY id OFFSET ${cursor} LIMIT 101`;
      break;
    case "study_materials":
      rows =
        await sql`SELECT * FROM public.study_materials WHERE user_id=${user} ORDER BY id OFFSET ${cursor} LIMIT 101`;
      break;
    case "study_quiz_rounds":
      rows =
        await sql`SELECT * FROM public.study_quiz_rounds WHERE user_id=${user} ORDER BY id OFFSET ${cursor} LIMIT 101`;
      break;
    case "practice_sets":
      rows =
        await sql`SELECT * FROM public.practice_sets WHERE user_id=${user} ORDER BY id OFFSET ${cursor} LIMIT 101`;
      break;
    case "goals":
      rows =
        await sql`SELECT * FROM public.platform_goals WHERE user_id=${user} ORDER BY id OFFSET ${cursor} LIMIT 101`;
      break;
    case "sessions":
      rows =
        await sql`SELECT id,user_id,mode,title,status,total,correct_count,assisted,results,created_at,finished_at,goal_id,assignment_id FROM public.platform_sessions WHERE user_id=${user} ORDER BY id OFFSET ${cursor} LIMIT 101`;
      break;
    case "session_items":
      rows =
        await sql`SELECT i.* FROM public.platform_session_items i JOIN public.platform_sessions s ON s.id=i.session_id WHERE s.user_id=${user} ORDER BY i.id OFFSET ${cursor} LIMIT 101`;
      break;
    case "materials":
      rows =
        await sql`SELECT * FROM public.platform_materials WHERE user_id=${user} ORDER BY id OFFSET ${cursor} LIMIT 101`;
      break;
    case "notes":
      rows =
        await sql`SELECT * FROM public.platform_connected_notes WHERE user_id=${user} ORDER BY id OFFSET ${cursor} LIMIT 101`;
      break;
    case "memberships":
      rows =
        await sql`SELECT * FROM public.platform_memberships WHERE user_id=${user} ORDER BY class_id OFFSET ${cursor} LIMIT 101`;
      break;
    case "classes":
      rows =
        await sql`SELECT c.* FROM public.platform_classes c WHERE c.teacher_id=${user} OR EXISTS(SELECT 1 FROM public.platform_memberships m WHERE m.class_id=c.id AND m.user_id=${user}) ORDER BY c.id OFFSET ${cursor} LIMIT 101`;
      break;
    case "assignments":
      rows =
        await sql`SELECT a.* FROM public.platform_assignments a JOIN public.platform_classes c ON c.id=a.class_id WHERE c.teacher_id=${user} OR EXISTS(SELECT 1 FROM public.platform_memberships m WHERE m.class_id=c.id AND m.user_id=${user}) ORDER BY a.id OFFSET ${cursor} LIMIT 101`;
      break;
    case "privacy_requests":
      rows =
        await sql`SELECT * FROM public.platform_privacy_requests WHERE user_id=${user} ORDER BY id OFFSET ${cursor} LIMIT 101`;
      break;
    case "study_profiles":
      rows =
        await sql`SELECT * FROM public.study_profiles WHERE user_id=${user} ORDER BY user_id OFFSET ${cursor} LIMIT 101`;
      break;
    case "review_items":
      rows =
        await sql`SELECT * FROM public.review_items WHERE user_id=${user} ORDER BY id OFFSET ${cursor} LIMIT 101`;
      break;
    case "study_sessions":
      rows =
        await sql`SELECT * FROM public.study_sessions WHERE user_id=${user} ORDER BY id OFFSET ${cursor} LIMIT 101`;
      break;
    case "study_session_items":
      rows =
        await sql`SELECT * FROM public.study_session_items WHERE user_id=${user} ORDER BY session_id,item_id OFFSET ${cursor} LIMIT 101`;
      break;
    case "review_events":
      rows =
        await sql`SELECT user_id,event_id,session_id,item_id,rating,evidence,answered_at,received_at,elapsed_seconds,next_due_at,policy_version FROM public.review_events WHERE user_id=${user} ORDER BY event_id OFFSET ${cursor} LIMIT 101`;
      break;
    case "study_streak_freezes":
      rows =
        await sql`SELECT user_id,frozen_date,week_start,timezone,created_at FROM public.study_streak_freezes WHERE user_id=${user} ORDER BY frozen_date OFFSET ${cursor} LIMIT 101`;
      break;
    case "error_event_decisions":
      rows =
        await sql`SELECT * FROM public.error_event_decisions WHERE user_id=${user} ORDER BY id OFFSET ${cursor} LIMIT 101`;
      break;
    case "corrections":
      rows =
        await sql`SELECT c.* FROM public.corrections c JOIN public.attempts a ON a.id=c.attempt_id WHERE a.user_id=${user} ORDER BY c.id OFFSET ${cursor} LIMIT 101`;
      break;
    case "attempt_assets":
      rows =
        await sql`SELECT aa.id,aa.attempt_id,aa.object_path,aa.sha256,aa.created_at FROM public.attempt_assets aa JOIN public.attempts a ON a.id=aa.attempt_id WHERE a.user_id=${user} ORDER BY aa.id OFFSET ${cursor} LIMIT 101`;
      break;
    case "notebook_entries":
      rows =
        await sql`SELECT * FROM public.notebook_entries WHERE user_id=${user} ORDER BY id OFFSET ${cursor} LIMIT 101`;
      break;
    case "content_drafts":
      rows =
        await sql`SELECT * FROM public.platform_content_drafts WHERE author_id=${user} ORDER BY id OFFSET ${cursor} LIMIT 101`;
      break;
    case "feedback":
      rows =
        await sql`SELECT * FROM public.platform_teacher_feedback WHERE student_id=${user} ORDER BY id OFFSET ${cursor} LIMIT 101`;
      break;
    default:
      throw new PublicError(
        400,
        "invalid_export_table",
        "Tabela indisponível.",
      );
  }
  return {
    exported_at: new Date().toISOString(),
    table,
    data: rows.slice(0, 100),
    next_cursor: rows.length > 100 ? cursor + 100 : null,
    tables: EXPORT_TABLES,
    page_size: 100,
    pagination: "offset; evite editar dados durante a exportação",
    binary_files_included: false,
  };
}

export async function platformOperation(
  sql: Database,
  user: string,
  input: Input,
): Promise<unknown> {
  const action = platformAction(input.action);
  switch (action) {
    case "overview":
      return await platformOverview(sql, user);
    case "save_feedback": {
      const sessionId = id(input, "session_id"),
        body = text(input, "body", 3000);
      return await sql.begin(async (tx) => {
        // Mantém o consentimento/vínculo bloqueado durante a gravação. Revogar
        // ou sair da turma concorre no mesmo registro e impede novas gravações.
        const [session] =
          await tx`SELECT s.id,s.user_id FROM public.platform_sessions s
          JOIN public.platform_assignments a ON a.id=s.assignment_id
          JOIN public.platform_classes c ON c.id=a.class_id
          JOIN public.platform_memberships m ON m.class_id=c.id AND m.user_id=s.user_id
          WHERE s.id=${sessionId} AND s.status='completed' AND c.teacher_id=${user} AND m.share_answers
          FOR SHARE OF m,c`;
        if (!session) {
          throw new PublicError(
            403,
            "feedback_not_authorized",
            "O aluno precisa autorizar o compartilhamento das respostas de uma tarefa finalizada da sua turma.",
          );
        }
        const [feedback] =
          await tx`INSERT INTO public.platform_teacher_feedback(session_id,student_id,teacher_id,body)
          VALUES(${sessionId},${session.user_id},${user},${body})
          ON CONFLICT(session_id,teacher_id) DO UPDATE SET body=EXCLUDED.body,updated_at=now() RETURNING *`;
        return { feedback };
      });
    }
    case "class_map":
      return await classMap(sql, user, input);
    case "create_concept_assignment":
      return await createConceptAssignment(sql, user, input);
    case "assignment_result":
      return await assignmentResult(sql, user, input);
    case "content_drafts":
    case "save_content_draft":
    case "submit_content_draft":
    case "publish_content_draft":
    case "reject_content_draft":
      return await contentOperation(sql, user, input, action);
    case "catalog": {
      const query = text(input, "query", 100, true),
        subject = text(input, "subject", 120, true),
        theme = text(input, "theme", 120, true);
      const exercises =
        await sql`SELECT id,subject,topic,theme,difficulty,prompt_text,reviewed_at FROM public.catalog_exercises
        WHERE (${subject}='' OR subject=${subject}) AND (${theme}='' OR theme=${theme}) AND (${query}='' OR concat_ws(' ',subject,topic,theme,prompt_text) ILIKE ${
          "%" + query + "%"
        }) ORDER BY subject,topic,theme,position LIMIT 100`;
      return { exercises, limit: 100, keys_included: false };
    }
    case "save_goal":
      return await saveGoal(sql, user, input);
    case "refresh_goal":
      return await refreshGoal(sql, user, input);
    case "start_session":
      return await startSession(sql, user, input);
    case "get_session":
      return {
        session: await publicSession(sql, user, id(input, "session_id")),
      };
    case "save_answer":
    case "finish_session":
    case "hints":
      return await sessionMutation(sql, user, input, action);
    case "create_class":
    case "join_class":
    case "set_sharing":
    case "leave_class":
    case "rotate_class_code":
    case "remove_class_member":
    case "create_assignment":
    case "class_progress":
    case "grant_teacher":
      return await classMutation(sql, user, input, action);
    case "save_material":
      return await saveMaterial(sql, user, input);
    case "save_note":
      return await saveNote(sql, user, input);
    case "delete_goal":
    case "delete_material":
    case "delete_note": {
      const rowId = id(input, "id");
      if (action === "delete_goal") {
        await sql`DELETE FROM public.platform_goals WHERE id=${rowId} AND user_id=${user}`;
      }
      if (action === "delete_material") {
        await sql`DELETE FROM public.platform_materials WHERE id=${rowId} AND user_id=${user}`;
      }
      if (action === "delete_note") {
        await sql`DELETE FROM public.platform_connected_notes WHERE id=${rowId} AND user_id=${user}`;
      }
      return { deleted: true };
    }
    case "export_data":
      return await exportData(sql, user, input);
    case "report_csv": {
      const rows =
        await sql`SELECT title,mode,total,correct_count,assisted,finished_at FROM public.platform_sessions WHERE user_id=${user} AND status='completed' ORDER BY finished_at DESC LIMIT 1000`;
      const lines = [
        [
          "Sessão",
          "Modo",
          "Questões",
          "Equivalências confirmadas",
          "Com ajuda",
          "Finalizada (UTC)",
        ],
        ...rows.map(
          (r) => [
            r.title,
            r.mode,
            r.total,
            r.correct_count,
            r.assisted,
            r.finished_at,
          ],
        ),
      ];
      return {
        csv: lines.map((line) => line.map(csvCell).join(";")).join("\r\n"),
        sample_count: rows.length,
        scope:
          "Até 1000 sessões finalizadas do catálogo; respostas não equivalentes precisam de conferência",
        limited: rows.length === 1000,
      };
    }
    case "request_deletion": {
      if (input.confirmation !== "EXCLUIR MINHA CONTA") {
        throw new PublicError(
          400,
          "confirmation_required",
          "Digite EXCLUIR MINHA CONTA para solicitar a exclusão.",
        );
      }
      const [request] =
        await sql`INSERT INTO public.platform_privacy_requests(user_id,kind) VALUES(${user},'account_deletion') ON CONFLICT (user_id,kind) WHERE status IN ('pending','processing') DO UPDATE SET user_id=EXCLUDED.user_id RETURNING id,kind,status,created_at`;
      return {
        request,
        deleted: false,
        message:
          "Solicitação registrada e aguardando processamento. Você pode cancelar antes de o processo começar. Depois do início, novos uploads serão bloqueados e haverá uma espera de 20 minutos para expirar os envios já autorizados. A conta e os arquivos só são excluídos após o processamento no armazenamento e na autenticação; este pedido não confirma a exclusão.",
      };
    }
    case "cancel_deletion": {
      const requestId = id(input, "id");
      const rows =
        await sql`UPDATE public.platform_privacy_requests SET status='cancelled' WHERE id=${requestId} AND user_id=${user} AND status='pending' RETURNING id`;
      if (!rows.length) {
        throw new PublicError(
          409,
          "request_not_pending",
          "A solicitação não está pendente. Consulte o suporte.",
        );
      }
      return { cancelled: true };
    }
  }
}
