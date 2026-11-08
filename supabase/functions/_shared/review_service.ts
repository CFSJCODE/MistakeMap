import type postgres from "postgresjs";
import { PublicError, uuid } from "./ai_contract.ts";
import type { database } from "./ai_service.ts";
import { freezeStreak, weeklySummary } from "./study_milestones.ts";
import {
  ACTIONS,
  answerFingerprint,
  answerInput,
  assertReplay,
  boundedInteger,
  decisionInput,
  profileInput,
  REVIEW_POLICY,
  scheduleReview,
  sessionCapacity,
} from "./review_contract.ts";

type Database = ReturnType<typeof database>;
type Queries = postgres.Sql | postgres.TransactionSql;
const notFound = (kind: string): never => {
  throw new PublicError(
    404,
    `${kind}_not_found`,
    "Registro de estudo não encontrado.",
  );
};
type SessionRow = {
  id: string;
  status: string;
  started_at: Date;
  completed_at: Date | null;
};

async function getProfile(sql: Queries, user: string) {
  const [p] = await sql`SELECT stage,daily_minutes,timezone,subject_ids,goal,
    to_char(exam_date,'YYYY-MM-DD') AS exam_date,reminders_enabled FROM public.study_profiles WHERE user_id=${user}`;
  const subjects =
    await sql`SELECT id,name FROM public.subjects WHERE user_id=${user} ORDER BY name LIMIT 200`;
  return { profile: p ?? null, subjects };
}

async function saveProfile(
  sql: Database,
  user: string,
  input: Record<string, unknown>,
) {
  const p = profileInput(input.profile);
  await sql.begin(async (tx) => {
    const [zone] =
      await tx`SELECT name FROM pg_timezone_names WHERE name=${p.timezone}`;
    if (!zone) {
      throw new PublicError(400, "invalid_timezone", "Fuso horário inválido.");
    }
    if (p.subject_ids.length) {
      const owned =
        await tx`SELECT id FROM public.subjects WHERE user_id=${user} AND id IN ${
          tx(p.subject_ids)
        }`;
      if (owned.length !== p.subject_ids.length) notFound("subject");
    }
    await tx`INSERT INTO public.study_profiles(user_id,stage,daily_minutes,timezone,subject_ids,goal,exam_date,reminders_enabled)
      VALUES(${user},${p.stage},${p.daily_minutes},${p.timezone},${
      tx.array(p.subject_ids, 2950)
    },${p.goal},${p.exam_date},${p.reminders_enabled})
      ON CONFLICT(user_id) DO UPDATE SET stage=excluded.stage,daily_minutes=excluded.daily_minutes,
      timezone=excluded.timezone,subject_ids=excluded.subject_ids,goal=excluded.goal,exam_date=excluded.exam_date,
      reminders_enabled=excluded.reminders_enabled,updated_at=now()`;
  });
  return await getProfile(sql, user);
}

async function dueItems(
  sql: Queries,
  user: string,
  limit = 30,
  subjectId: string | null = null,
) {
  return await sql`SELECT r.id,r.subject_id,s.name AS subject_name,r.concept_id,c.name AS concept_name,
    r.category,e.prompt_text,coalesce(ee.evidence_ref,'') AS evidence,ee.attempt_id,
    r.error_event_id,r.due_at,r.interval_days,
    CASE WHEN r.repetitions=0 THEN 'Você confirmou esta dificuldade. Vamos revisar?'
      ELSE 'Revisão agendada após sua última autoavaliação.' END AS reason,false AS answered
    FROM public.review_items r
    JOIN public.subjects s ON s.id=r.subject_id AND s.user_id=r.user_id
    JOIN public.concepts c ON c.id=r.concept_id AND c.subject_id=s.id
    JOIN public.error_events ee ON ee.id=r.error_event_id AND ee.status='confirmed'
    JOIN public.attempts a ON a.id=ee.attempt_id AND a.user_id=r.user_id
    JOIN public.exercises e ON e.id=a.exercise_id AND e.subject_id=s.id
    WHERE r.user_id=${user} AND r.active AND r.due_at<=now()
      AND (${subjectId}::uuid IS NULL OR r.subject_id=${subjectId})
    ORDER BY extract(epoch FROM(now()-r.due_at))/86400+greatest(.5,least(2,c.importance)) DESC,r.id
    LIMIT ${limit}`;
}

async function sessionView(
  sql: Queries,
  user: string,
  sessionId: string | null,
) {
  const [session] = sessionId
    ? await sql<
      SessionRow[]
    >`SELECT id,status,started_at,completed_at FROM public.study_sessions WHERE id=${sessionId} AND user_id=${user}`
    : await sql<
      SessionRow[]
    >`SELECT id,status,started_at,completed_at FROM public.study_sessions WHERE user_id=${user} AND status='active' LIMIT 1`;
  if (!session) {
    if (sessionId) notFound("session");
    return { session: null };
  }
  const items =
    await sql`SELECT r.id,r.subject_id,s.name AS subject_name,r.concept_id,c.name AS concept_name,
    si.category,si.prompt_text,si.evidence,r.due_at,r.interval_days,
    CASE WHEN NOT r.active OR ee.status<>'confirmed' THEN true ELSE ev.event_id IS NOT NULL END AS answered,
    (NOT r.active OR ee.status<>'confirmed') AS skipped,
    'Revisão de uma dificuldade que você confirmou.' AS reason
    FROM public.study_session_items si
    JOIN public.review_items r ON r.id=si.item_id AND r.user_id=si.user_id
    JOIN public.subjects s ON s.id=r.subject_id AND s.user_id=si.user_id
    JOIN public.concepts c ON c.id=r.concept_id
    JOIN public.error_events ee ON ee.id=si.source_error_event_id
    LEFT JOIN public.review_events ev ON ev.session_id=si.session_id AND ev.item_id=si.item_id AND ev.user_id=si.user_id
    WHERE si.session_id=${session.id} AND si.user_id=${user} ORDER BY si.position`;
  if (session.status === "active" && items.every((i) => i.answered)) {
    const [completed] =
      await sql`UPDATE public.study_sessions SET status='completed',completed_at=now()
      WHERE id=${session.id} AND user_id=${user} AND status='active' RETURNING completed_at`;
    session.status = "completed";
    session.completed_at = completed?.completed_at ?? new Date();
  }
  return { session: { ...session, items } };
}

async function startSession(
  sql: Database,
  user: string,
  input: Record<string, unknown>,
) {
  const subjectId = input.subject_id ? uuid(input.subject_id) : null;
  return await sql.begin(async (tx) => {
    // Serializa a criação por dono; duas abas retomam a mesma sessão.
    await tx`SELECT pg_advisory_xact_lock(hashtext(${user}),617)`;
    const current = await sessionView(tx, user, null);
    if (current.session?.status === "active") return current;
    const [p] =
      await tx`SELECT daily_minutes FROM public.study_profiles WHERE user_id=${user}`;
    const minutes = boundedInteger(
      input.minutes ?? p?.daily_minutes ?? 15,
      5,
      180,
    );
    if (subjectId) {
      const [subject] =
        await tx`SELECT id FROM public.subjects WHERE id=${subjectId} AND user_id=${user}`;
      if (!subject) notFound("subject");
    }
    const items = await dueItems(tx, user, sessionCapacity(minutes), subjectId);
    if (!items.length) return { session: null };
    const [session] =
      await tx`INSERT INTO public.study_sessions(user_id,planned_minutes) VALUES(${user},${minutes}) RETURNING id`;
    for (let position = 0; position < items.length; position++) {
      const i = items[position];
      await tx`INSERT INTO public.study_session_items(session_id,item_id,user_id,position,source_attempt_id,source_error_event_id,prompt_text,evidence,category)
        VALUES(${session.id},${i.id},${user},${position},${i.attempt_id},${i.error_event_id},${i.prompt_text},${i.evidence},${i.category})`;
    }
    return await sessionView(tx, user, session.id);
  });
}

async function referenceFor(
  sql: Queries,
  user: string,
  sessionId: string,
  itemId: string,
) {
  const [row] = await sql`SELECT coalesce(c.reference_text,'') AS reference_text
    FROM public.study_session_items si JOIN public.attempts a ON a.id=si.source_attempt_id AND a.user_id=${user}
    LEFT JOIN public.corrections c ON c.attempt_id=a.id
    WHERE si.session_id=${sessionId} AND si.item_id=${itemId} AND si.user_id=${user}
    ORDER BY c.created_at DESC LIMIT 1`;
  return String(row?.reference_text ?? "");
}

async function answer(
  sql: Database,
  user: string,
  input: Record<string, unknown>,
) {
  const now = new Date();
  const p = answerInput(input, now);
  const fingerprint = await answerFingerprint(p);
  return await sql.begin(async (tx) => {
    // A sessão é a unidade serializada. A unique(session_id,item_id) constitui
    // uma segunda barreira: um item nunca avança duas vezes na mesma sessão.
    const [session] =
      await tx`SELECT id,status,started_at FROM public.study_sessions WHERE id=${p.session_id} AND user_id=${user} FOR UPDATE`;
    if (!session) notFound("session");
    const [existing] =
      await tx`SELECT payload_hash,rating,next_due_at FROM public.review_events WHERE event_id=${p.event_id} AND user_id=${user}`;
    if (existing) {
      assertReplay(existing.payload_hash, fingerprint);
      return {
        duplicate: true,
        ...await sessionView(tx, user, p.session_id),
        feedback: {
          reference_text: await referenceFor(tx, user, p.session_id, p.item_id),
          next_due_at: existing.next_due_at,
          rating: existing.rating,
          evidence: "self_report",
        },
      };
    }
    const [answered] =
      await tx`SELECT event_id FROM public.review_events WHERE session_id=${p.session_id} AND item_id=${p.item_id} AND user_id=${user}`;
    if (answered) {
      throw new PublicError(
        409,
        "event_conflict",
        "Este item já foi respondido nesta sessão. Atualize a tela.",
      );
    }
    if (session.status !== "active") {
      throw new PublicError(
        409,
        "session_conflict",
        "Esta sessão já terminou. Atualize a tela.",
      );
    }
    const [item] =
      await tx`SELECT r.id,r.interval_days,r.repetitions,r.lapses,r.last_reviewed_at,r.active,ee.status
      FROM public.study_session_items si JOIN public.review_items r ON r.id=si.item_id AND r.user_id=si.user_id
      JOIN public.error_events ee ON ee.id=si.source_error_event_id
      WHERE si.session_id=${p.session_id} AND si.item_id=${p.item_id} AND si.user_id=${user} FOR UPDATE OF r`;
    if (!item) notFound("item");
    if (!item.active || item.status !== "confirmed") {
      throw new PublicError(
        409,
        "item_unavailable",
        "Esta sugestão foi descartada. Atualize a sessão.",
      );
    }
    const at = new Date(Math.min(now.getTime(), Date.parse(p.answered_at)));
    if (
      at.getTime() < new Date(session.started_at).getTime() - 300000 ||
      (item.last_reviewed_at &&
        at.getTime() < new Date(item.last_reviewed_at).getTime())
    ) {
      throw new PublicError(
        409,
        "stale_review",
        "A revisão é anterior ao estado atual. Atualize a sessão.",
      );
    }
    const next = scheduleReview(
      Number(item.interval_days),
      Number(item.repetitions),
      Number(item.lapses),
      p.rating,
      at,
    );
    await tx`INSERT INTO public.review_events(user_id,event_id,session_id,item_id,rating,answered_at,elapsed_seconds,payload_hash,next_due_at,policy_version)
      VALUES(${user},${p.event_id},${p.session_id},${p.item_id},${p.rating},${at},${p.elapsed_seconds},${fingerprint},${next.due_at},${REVIEW_POLICY})`;
    await tx`UPDATE public.review_items SET interval_days=${next.interval_days},repetitions=${next.repetitions},lapses=${next.lapses},
      last_reviewed_at=${at},due_at=${next.due_at},policy_version=${REVIEW_POLICY},updated_at=now() WHERE id=${p.item_id} AND user_id=${user}`;
    return {
      duplicate: false,
      ...await sessionView(tx, user, p.session_id),
      feedback: {
        reference_text: await referenceFor(tx, user, p.session_id, p.item_id),
        next_due_at: next.due_at,
        rating: p.rating,
        evidence: "self_report",
      },
    };
  });
}

async function diagnostics(
  sql: Queries,
  user: string,
  errorId: string | null = null,
) {
  return await sql`SELECT ee.id,ee.attempt_id,s.id AS subject_id,s.name AS subject_name,c.id AS concept_id,c.name AS concept_name,
    et.name AS category,coalesce(ee.evidence_ref,'') AS evidence,ee.confidence,ee.status,e.prompt_text,c.importance
    FROM public.error_events ee JOIN public.attempts a ON a.id=ee.attempt_id AND a.user_id=${user}
    JOIN public.exercises e ON e.id=a.exercise_id JOIN public.subjects s ON s.id=e.subject_id AND s.user_id=${user}
    JOIN public.concepts c ON c.id=ee.concept_id AND c.subject_id=s.id
    JOIN public.error_types et ON et.id=ee.error_type_id
    WHERE (${errorId}::uuid IS NOT NULL AND ee.id=${errorId} OR ${errorId}::uuid IS NULL AND ee.status IN ('pending','confirmed'))
    ORDER BY CASE WHEN ee.status='pending' THEN 0 ELSE 1 END,ee.created_at DESC LIMIT 100`;
}

async function decide(
  sql: Database,
  user: string,
  input: Record<string, unknown>,
) {
  const p = decisionInput(input);
  return await sql.begin(async (tx) => {
    // Mesma ordem de lock da criação da sessão. Evita disputa ao mudar a agenda.
    await tx`SELECT pg_advisory_xact_lock(hashtext(${user}),617)`;
    const [row] =
      await tx`SELECT ee.id,ee.status,ee.concept_id,ee.error_type_id,c.importance,s.id AS subject_id,et.name AS category
      FROM public.error_events ee JOIN public.attempts a ON a.id=ee.attempt_id AND a.user_id=${user}
      JOIN public.exercises e ON e.id=a.exercise_id JOIN public.subjects s ON s.id=e.subject_id AND s.user_id=${user}
      JOIN public.concepts c ON c.id=ee.concept_id AND c.subject_id=s.id JOIN public.error_types et ON et.id=ee.error_type_id
      WHERE ee.id=${p.error_event_id} FOR UPDATE OF ee`;
    if (!row) notFound("diagnostic");
    const category = p.category ?? String(row.category);
    const importance = p.importance ??
      Math.max(.5, Math.min(2, Number(row.importance)));
    const [type] =
      await tx`SELECT id FROM public.error_types WHERE name=${category}`;
    if (!type) notFound("category");
    const changed = row.status !== p.decision || row.category !== category ||
      Number(row.importance) !== importance;
    if (changed) {
      await tx`UPDATE public.error_events SET status=${p.decision},error_type_id=${type.id} WHERE id=${row.id}`;
      await tx`UPDATE public.concepts SET importance=${importance} WHERE id=${row.concept_id} AND subject_id=${row.subject_id}`;
      await tx`INSERT INTO public.error_event_decisions(user_id,error_event_id,decision,category,importance)
        VALUES(${user},${row.id},${p.decision},${category},${importance})`;
    }
    // Se a origem atual foi rejeitada/corrigida, busca outra confirmação da
    // mesma habilidade; sem ela, desativa o item e a sessão o ignora.
    await tx`UPDATE public.review_items r SET error_event_id=coalesce((
        SELECT ee.id FROM public.error_events ee JOIN public.attempts a ON a.id=ee.attempt_id AND a.user_id=${user}
        JOIN public.error_types et ON et.id=ee.error_type_id
        WHERE ee.concept_id=r.concept_id AND et.name=r.category AND ee.status='confirmed'
        ORDER BY ee.created_at DESC LIMIT 1),r.error_event_id),
      active=EXISTS(SELECT 1 FROM public.error_events ee JOIN public.attempts a ON a.id=ee.attempt_id AND a.user_id=${user}
        JOIN public.error_types et ON et.id=ee.error_type_id
        WHERE ee.concept_id=r.concept_id AND et.name=r.category AND ee.status='confirmed'),updated_at=now()
      WHERE r.user_id=${user} AND r.concept_id=${row.concept_id}`;
    let reviewItem = null;
    if (p.decision === "confirmed") {
      const [r] =
        await tx`INSERT INTO public.review_items(user_id,subject_id,concept_id,error_event_id,category)
        VALUES(${user},${row.subject_id},${row.concept_id},${row.id},${category})
        ON CONFLICT(user_id,concept_id,category) DO UPDATE SET error_event_id=excluded.error_event_id,active=true,updated_at=now()
        RETURNING id,subject_id,concept_id,category,due_at,interval_days`;
      reviewItem = r;
    }
    const [diagnostic] = await diagnostics(tx, user, row.id);
    return { diagnostic, review_item: reviewItem };
  });
}

async function dashboard(sql: Database, user: string) {
  const { profile } = await getProfile(sql, user);
  const zone = String(profile?.timezone ?? "America/Sao_Paulo");
  const [counts] = await sql`SELECT
    (SELECT count(*)::integer FROM public.review_items r JOIN public.error_events ee ON ee.id=r.error_event_id
      WHERE r.user_id=${user} AND r.active AND ee.status='confirmed' AND r.due_at<=now()) AS due_count,
    (SELECT count(*)::integer FROM public.error_events ee JOIN public.attempts a ON a.id=ee.attempt_id
      WHERE a.user_id=${user} AND ee.status='pending') AS pending_diagnostics,
    (SELECT count(*)::integer FROM public.review_events WHERE user_id=${user}
      AND (answered_at AT TIME ZONE ${zone})::date=(now() AT TIME ZONE ${zone})::date) AS reviewed_today`;
  const [progress] = await sql`SELECT count(*)::integer AS reviews,
    count(*) FILTER(WHERE rating<>'again')::integer AS recalled,
    count(DISTINCT (answered_at AT TIME ZONE ${zone})::date)::integer AS study_days
    FROM public.review_events WHERE user_id=${user} AND answered_at>=now()-interval '7 days'`;
  const current = await sessionView(sql, user, null);
  const budget = Number(profile?.daily_minutes ?? 15);
  return {
    profile,
    ...counts,
    estimated_minutes: Math.min(budget, Number(counts.due_count) * 2),
    active_session_id: current.session?.status === "active"
      ? current.session.id
      : null,
    policy_version: REVIEW_POLICY,
    progress: {
      reviews: Number(progress.reviews),
      recall_rate: Number(progress.reviews) >= 5
        ? Number(progress.recalled) / Number(progress.reviews)
        : null,
      study_days: Number(progress.study_days),
      evidence: "self_report",
      period_days: 7,
    },
    items: await dueItems(sql, user),
  };
}

export async function reviewOperation(
  sql: Database,
  user: string,
  action: typeof ACTIONS[number],
  input: Record<string, unknown>,
) {
  switch (action) {
    case "profile":
      return await getProfile(sql, user);
    case "save_profile":
      return await saveProfile(sql, user, input);
    case "dashboard":
      return await dashboard(sql, user);
    case "session": {
      const result = await sessionView(
        sql,
        user,
        input.session_id ? uuid(input.session_id) : null,
      );
      if (input.reveal_item_id) {
        const itemId = uuid(input.reveal_item_id);
        const session = result.session;
        if (!session) return notFound("session");
        if (!session.items.some((i) => i.id === itemId)) {
          return notFound("item");
        }
        return {
          ...result,
          reference_text: await referenceFor(
            sql,
            user,
            session.id,
            itemId,
          ),
        };
      }
      return result;
    }
    case "start_session":
      return await startSession(sql, user, input);
    case "answer":
      return await answer(sql, user, input);
    case "diagnostics":
      return { items: await diagnostics(sql, user) };
    case "decide":
      return await decide(sql, user, input);
    case "weekly_summary":
      return await weeklySummary(sql, user);
    case "freeze_streak":
      return await freezeStreak(sql, user, input.date);
  }
}
