import { CATEGORIES, PublicError, uuid } from "./ai_contract.ts";

export const REVIEW_POLICY = "mm-intervals-v1";
export const ACTIONS = [
  "dashboard",
  "profile",
  "save_profile",
  "session",
  "start_session",
  "answer",
  "diagnostics",
  "decide",
  "weekly_summary",
  "freeze_streak",
] as const;
export const RATINGS = ["again", "hard", "good", "easy"] as const;
export type Rating = typeof RATINGS[number];
export type StudyProfile = {
  stage: "fundamental" | "medio" | "superior" | "autodidata";
  daily_minutes: number;
  timezone: string;
  subject_ids: string[];
  goal: string;
  exam_date: string | null;
  reminders_enabled: boolean;
};
const DAY = 86400000;
function invalid(code: string, message: string): never {
  throw new PublicError(400, code, message);
}
export function boundedInteger(
  value: unknown,
  min: number,
  max: number,
): number {
  if (
    typeof value !== "number" || !Number.isInteger(value) || value < min ||
    value > max
  ) {
    invalid(
      "invalid_number",
      `Informe um número inteiro entre ${min} e ${max}.`,
    );
  }
  return value;
}
export function reviewAction(value: unknown): typeof ACTIONS[number] {
  if (!ACTIONS.includes(value as typeof ACTIONS[number])) {
    invalid("invalid_action", "Operação de estudo inválida.");
  }
  return value as typeof ACTIONS[number];
}
export function profileInput(value: unknown): StudyProfile {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    invalid("invalid_profile", "Informe seu perfil de estudo.");
  }
  const p = value as Record<string, unknown>;
  const stages = ["fundamental", "medio", "superior", "autodidata"];
  if (!stages.includes(String(p.stage))) {
    invalid("invalid_stage", "Escolha sua etapa de estudo.");
  }
  if (typeof p.timezone !== "string" || p.timezone.length > 80) {
    invalid("invalid_timezone", "Fuso horário inválido.");
  }
  try {
    new Intl.DateTimeFormat("pt-BR", { timeZone: p.timezone });
  } catch {
    invalid("invalid_timezone", "Fuso horário inválido.");
  }
  if (!Array.isArray(p.subject_ids) || p.subject_ids.length > 30) {
    invalid("invalid_subjects", "Escolha até 30 matérias.");
  }
  const subjects = [...new Set(p.subject_ids.map(uuid))];
  if (typeof p.goal !== "string" || p.goal.trim().length > 240) {
    invalid("invalid_goal", "Descreva seu objetivo em até 240 caracteres.");
  }
  const exam = p.exam_date ?? null;
  if (exam !== null) {
    if (
      typeof exam !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(exam) ||
      Number(exam.slice(0, 4)) < 2000 || Number(exam.slice(0, 4)) > 2200 ||
      !Number.isFinite(Date.parse(exam)) ||
      new Date(exam).toISOString().slice(0, 10) !== exam
    ) {
      invalid("invalid_exam_date", "Informe uma data de prova válida.");
    }
  }
  if (typeof p.reminders_enabled !== "boolean") {
    invalid("invalid_reminders", "Preferência de lembretes inválida.");
  }
  return {
    stage: p.stage as StudyProfile["stage"],
    daily_minutes: boundedInteger(p.daily_minutes, 5, 180),
    timezone: p.timezone,
    subject_ids: subjects,
    goal: p.goal.trim(),
    exam_date: exam as string | null,
    reminders_enabled: p.reminders_enabled,
  };
}
export type AnswerInput = {
  session_id: string;
  item_id: string;
  event_id: string;
  rating: Rating;
  answered_at: string;
  elapsed_seconds: number;
};
export function answerInput(
  p: Record<string, unknown>,
  now = new Date(),
): AnswerInput {
  const rating = p.rating as Rating;
  if (!RATINGS.includes(rating)) {
    invalid("invalid_rating", "Informe como foi a revisão.");
  }
  if (
    typeof p.answered_at !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?(Z|[+-]\d{2}:\d{2})$/
      .test(p.answered_at)
  ) {
    invalid("invalid_answered_at", "Data de revisão inválida.");
  }
  const at = new Date(p.answered_at);
  if (
    !Number.isFinite(at.getTime()) || at.getTime() > now.getTime() + 300000 ||
    new Date(p.answered_at.slice(0, 10)).toISOString().slice(0, 10) !==
      p.answered_at.slice(0, 10) ||
    at.getTime() < now.getTime() - 30 * DAY
  ) {
    invalid(
      "invalid_answered_at",
      "A revisão deve ter ocorrido nos últimos 30 dias. Confira o relógio do aparelho.",
    );
  }
  return {
    session_id: uuid(p.session_id),
    item_id: uuid(p.item_id),
    event_id: uuid(p.event_id),
    rating,
    answered_at: at.toISOString(),
    elapsed_seconds: boundedInteger(p.elapsed_seconds, 0, 1800),
  };
}
export async function answerFingerprint(p: AnswerInput): Promise<string> {
  const bytes = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(JSON.stringify(p)),
  );
  return Array.from(
    new Uint8Array(bytes),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
}
export function assertReplay(
  existingHash: string,
  requestedHash: string,
): void {
  if (existingHash !== requestedHash) {
    throw new PublicError(
      409,
      "event_conflict",
      "Esta resposta já foi enviada com outros dados. Atualize a sessão.",
    );
  }
}
// Política transparente para autoavaliação, sem alegações de probabilidade de
// lembrança ou domínio. Uma biblioteca FSRS exigirá migração e avaliação próprias.
export function scheduleReview(
  interval: number,
  repetitions: number,
  lapses: number,
  rating: Rating,
  at: Date,
) {
  const previous = Number.isFinite(interval)
    ? Math.max(0, Math.min(180, interval))
    : 0;
  let days: number;
  if (rating === "again") days = 1;
  else if (rating === "hard") days = Math.max(1, Math.ceil(previous * 1.2));
  else if (rating === "easy") days = Math.max(3, Math.ceil(previous * 2.5));
  else days = Math.max(1, previous ? Math.ceil(previous * 2) : 1);
  days = Math.min(180, days);
  return {
    interval_days: days,
    repetitions: repetitions + 1,
    lapses: lapses + (rating === "again" ? 1 : 0),
    due_at: new Date(at.getTime() + days * DAY).toISOString(),
    policy_version: REVIEW_POLICY,
  };
}
export function sessionCapacity(minutes: number): number {
  return Math.min(
    30,
    Math.max(1, Math.floor(boundedInteger(minutes, 5, 180) / 2)),
  );
}
export function decisionInput(p: Record<string, unknown>) {
  if (p.decision !== "confirmed" && p.decision !== "rejected") {
    invalid("invalid_decision", "Confirme ou descarte a sugestão.");
  }
  if (
    p.category !== undefined &&
    !CATEGORIES.includes(p.category as typeof CATEGORIES[number])
  ) invalid("invalid_category", "Categoria inválida.");
  const importance = p.importance === undefined ? null : p.importance;
  if (
    importance !== null &&
    (typeof importance !== "number" || !Number.isFinite(importance) ||
      importance < .5 || importance > 2)
  ) invalid("invalid_importance", "A importância deve ficar entre 0,5 e 2.");
  return {
    error_event_id: uuid(p.error_event_id),
    decision: p.decision,
    category: p.category as string | undefined,
    importance: importance as number | null,
  };
}
export function duePriority(
  dueAt: Date,
  importance: number,
  now = new Date(),
): number {
  // Vencimento primeiro; importância explicitamente definida desempata a fila.
  const overdue = Math.max(0, (now.getTime() - dueAt.getTime()) / DAY);
  return overdue + Math.max(.5, Math.min(2, importance));
}
