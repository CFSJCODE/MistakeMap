import type postgres from "postgresjs";
import type { database } from "./ai_service.ts";
import { PublicError } from "./ai_contract.ts";

type Database = ReturnType<typeof database>;
type Query = postgres.Sql | postgres.TransactionSql;
type Activity = {
  date: string;
  review_sessions: number;
  practice_sessions: number;
};
type Freeze = { date: string; week_start: string };
export const STREAK_HISTORY_DAYS = 366;

export function localDay(at: Date, timezone: string): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    calendar: "iso8601",
    numberingSystem: "latn",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(at);
  const part = (type: string) =>
    parts.find((p) => p.type === type)?.value ?? "";
  return `${part("year").padStart(4, "0")}-${part("month")}-${part("day")}`;
}
export function shiftDay(day: string, delta: number): string {
  const date = new Date(`${day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + delta);
  return date.toISOString().slice(0, 10);
}
export function mondayOf(day: string): string {
  const sundayZero = new Date(`${day}T00:00:00Z`).getUTCDay();
  return shiftDay(day, -((sundayZero + 6) % 7));
}
export function freezeDates(
  today: string,
  completed: ReadonlySet<string>,
  freezes: readonly Freeze[],
): string[] {
  const usedWeeks = new Set(freezes.map((f) => f.week_start));
  // Só protege uma lacuna real entre duas sessões feitas. Nenhum dia estudado
  // é criado pela pausa e não há sequência artificial sem retomar os estudos.
  return [shiftDay(today, -1), shiftDay(today, -2)].filter((day) =>
    !completed.has(day) &&
    completed.has(shiftDay(day, -1)) && completed.has(shiftDay(day, 1)) &&
    !usedWeeks.has(mondayOf(day))
  );
}
export function streakFor(
  today: string,
  completed: ReadonlySet<string>,
  freezes: readonly Freeze[],
) {
  const protectedDates = new Set(freezes.map((f) => f.date));
  const todayCompleted = completed.has(today);
  let day = todayCompleted ? today : shiftDay(today, -1),
    actual = 0,
    protectedDays = 0,
    covered = 0;
  while (covered < STREAK_HISTORY_DAYS) {
    if (completed.has(day)) actual++;
    else if (protectedDates.has(day)) protectedDays++;
    else break;
    day = shiftDay(day, -1);
    covered++;
  }
  return {
    current_days: actual,
    completed_days: actual,
    protected_days: protectedDays,
    today_completed: todayCompleted,
    history_limit_days: STREAK_HISTORY_DAYS,
    capped: covered === STREAK_HISTORY_DAYS,
    freeze_eligible_dates: freezeDates(today, completed, freezes),
    freezes,
  };
}
export function achievementsFor(
  sessions: number,
  days: number,
  matched: number,
) {
  return [
    {
      id: "week_session",
      label: "Uma sessão concluída",
      description:
        "Finalize uma revisão com resposta ou uma prática respondida.",
      count: sessions,
      target: 1,
      earned: sessions >= 1,
    },
    {
      id: "week_three_days",
      label: "Estudo em três dias",
      description: "Conclua sessões com respostas em três dias diferentes.",
      count: days,
      target: 3,
      earned: days >= 3,
    },
    {
      id: "week_five_new_matches",
      label: "Cinco questões novas sem pista",
      description:
        "Responda cinco questões no primeiro contato registrado com equivalência à referência revisada.",
      count: matched,
      target: 5,
      earned: matched >= 5,
    },
  ];
}

async function timezoneFor(sql: Query, user: string): Promise<string> {
  const [row] =
    await sql`SELECT timezone FROM public.study_profiles WHERE user_id=${user}`;
  return String(row?.timezone ?? "America/Sao_Paulo");
}
async function activities(
  sql: Query,
  user: string,
  timezone: string,
  start: string,
  end: string,
): Promise<Activity[]> {
  // A revisão já finalizada usa o horário da última resposta validada, não a
  // hora em que o aparelho offline voltou a enviar os eventos.
  return await sql<Activity[]>`WITH eligible AS (
    SELECT max(e.answered_at) AS at,'review'::text AS kind
    FROM public.study_sessions s JOIN public.review_events e ON e.session_id=s.id AND e.user_id=s.user_id
    WHERE s.user_id=${user} AND s.status='completed'
      AND s.completed_at>=(${start}::date::timestamp AT TIME ZONE ${timezone})
    GROUP BY s.id
    UNION ALL
    SELECT s.finished_at AS at,'practice'::text AS kind FROM public.platform_sessions s
    WHERE s.user_id=${user} AND s.status='completed'
      AND s.finished_at>=(${start}::date::timestamp AT TIME ZONE ${timezone})
      AND EXISTS(SELECT 1 FROM public.platform_session_items i WHERE i.session_id=s.id AND btrim(i.answer)<>'')
  ) SELECT to_char(at AT TIME ZONE ${timezone},'YYYY-MM-DD') AS date,
    count(*) FILTER(WHERE kind='review')::integer AS review_sessions,
    count(*) FILTER(WHERE kind='practice')::integer AS practice_sessions
  FROM eligible WHERE at>=(${start}::date::timestamp AT TIME ZONE ${timezone})
    AND at<(${end}::date::timestamp AT TIME ZONE ${timezone}) GROUP BY 1 ORDER BY 1`;
}
async function storedFreezes(
  sql: Query,
  user: string,
  start: string,
  end: string,
): Promise<Freeze[]> {
  return await sql<
    Freeze[]
  >`SELECT frozen_date::text AS date,week_start::text FROM public.study_streak_freezes
    WHERE user_id=${user} AND frozen_date>=${start}::date AND frozen_date<${end}::date ORDER BY frozen_date DESC`;
}

export async function weeklySummary(
  sql: Database,
  user: string,
  now = new Date(),
) {
  const timezone = await timezoneFor(sql, user);
  const today = localDay(now, timezone),
    start = shiftDay(today, -6),
    end = shiftDay(today, 1),
    history = shiftDay(today, -STREAK_HISTORY_DAYS);
  const [daily, freezes, [reviews], [catalog]] = await Promise.all([
    activities(sql, user, timezone, history, end),
    storedFreezes(sql, user, history, end),
    sql`SELECT count(*)::integer AS reviews,count(*) FILTER(WHERE rating<>'again')::integer AS recalled,
      count(DISTINCT (answered_at AT TIME ZONE ${timezone})::date)::integer AS study_days
      FROM public.review_events WHERE user_id=${user} AND answered_at>=(${start}::date::timestamp AT TIME ZONE ${timezone})
      AND answered_at<(${end}::date::timestamp AT TIME ZONE ${timezone})`,
    sql`WITH first_seen_answered AS (
      SELECT i.id,s.results FROM public.platform_session_items i JOIN public.platform_sessions s ON s.id=i.session_id
      WHERE s.user_id=${user} AND s.status='completed' AND i.catalog_exercise_id IS NOT NULL
        AND i.hint_level=0 AND btrim(i.answer)<>''
        AND s.finished_at>=(${start}::date::timestamp AT TIME ZONE ${timezone})
        AND s.finished_at<(${end}::date::timestamp AT TIME ZONE ${timezone})
        AND NOT EXISTS(SELECT 1 FROM public.platform_session_items earlier
          JOIN public.platform_sessions es ON es.id=earlier.session_id AND es.user_id=${user}
          WHERE earlier.catalog_exercise_id=i.catalog_exercise_id
            AND (es.created_at,es.id,earlier.position,earlier.id)<(s.created_at,s.id,i.position,i.id))
    ) SELECT count(*)::integer AS answered,
      count(*) FILTER(WHERE EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(results->'results','[]'::jsonb)) r
        WHERE r->>'item_id'=first_seen_answered.id::text AND r->>'verdict'='correct'))::integer AS matched
      FROM first_seen_answered`,
  ]);
  const recent = daily.filter((row) => row.date >= start);
  const reviewSessions = recent.reduce(
    (sum, row) => sum + Number(row.review_sessions),
    0,
  );
  const practiceSessions = recent.reduce(
    (sum, row) => sum + Number(row.practice_sessions),
    0,
  );
  const n = Number(reviews.reviews),
    recalled = Number(reviews.recalled),
    answered = Number(catalog.answered),
    matched = Number(catalog.matched);
  return {
    period: { start_date: start, end_date: today, days: 7, timezone },
    review: {
      reviews: n,
      recalled,
      again: n - recalled,
      study_days: Number(reviews.study_days),
      completed_sessions: reviewSessions,
      evidence: "self_report",
      recall_rate: n >= 5 ? recalled / n : null,
    },
    practice: {
      new_unassisted_answered: answered,
      matched_reference: matched,
      needs_review: answered - matched,
      evidence: "reviewed_catalog",
    },
    streak: streakFor(today, new Set(daily.map((r) => r.date)), freezes),
    achievements: achievementsFor(
      reviewSessions + practiceSessions,
      recent.length,
      matched,
    ),
    notice:
      "Autoavaliação de revisão e questões novas do catálogo são evidências diferentes. As questões consideram o primeiro contato registrado e não estimam domínio ou melhora causal.",
  };
}

export async function freezeStreak(
  sql: Database,
  user: string,
  date: unknown,
  now = new Date(),
) {
  if (
    typeof date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(date) ||
    !Number.isFinite(Date.parse(date)) || shiftDay(date, 0) !== date
  ) {
    throw new PublicError(
      400,
      "invalid_freeze_date",
      "Informe o dia de pausa no formato AAAA-MM-DD.",
    );
  }
  await sql.begin(async (tx) => {
    await tx`SELECT pg_advisory_xact_lock(hashtext(${user}),618)`;
    const [existing] =
      await tx`SELECT frozen_date FROM public.study_streak_freezes WHERE user_id=${user} AND frozen_date=${date}::date`;
    if (existing) return;
    const timezone = await timezoneFor(tx, user),
      today = localDay(now, timezone);
    if (date !== shiftDay(today, -1) && date !== shiftDay(today, -2)) {
      throw new PublicError(
        409,
        "freeze_too_old",
        "A pausa pode proteger ontem ou anteontem no seu fuso de estudo.",
      );
    }
    const week = mondayOf(date);
    const [used] =
      await tx`SELECT frozen_date FROM public.study_streak_freezes WHERE user_id=${user} AND week_start=${week}::date`;
    if (used) {
      throw new PublicError(
        409,
        "freeze_used",
        "A pausa desta semana já foi usada.",
      );
    }
    const daily = await activities(
      tx,
      user,
      timezone,
      shiftDay(today, -3),
      shiftDay(today, 1),
    );
    if (
      !freezeDates(today, new Set(daily.map((r) => r.date)), []).includes(date)
    ) {
      throw new PublicError(
        409,
        "freeze_not_eligible",
        "A pausa protege um dia sem sessão entre dois dias com sessões concluídas.",
      );
    }
    await tx`INSERT INTO public.study_streak_freezes(user_id,frozen_date,week_start,timezone) VALUES(${user},${date}::date,${week}::date,${timezone})`;
  });
  return { ...await weeklySummary(sql, user, now), freeze_date: date };
}
