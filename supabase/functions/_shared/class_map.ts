// Mapa da turma, tarefa pelo mapa e resultado da tarefa.
//
// Privacidade: o professor só recebe agregados. O mapa e o acerto por questão
// só aparecem com MIN_STUDENTS alunos ou mais, e nenhum identificador de aluno
// sai daqui. "Quem fez" lista participantes numerados, com o acerto individual
// apenas de quem autorizou compartilhar o progresso na turma.
import type postgres from "postgresjs";
import { PublicError } from "./ai_contract.ts";
import {
  csvCell,
  id,
  type Input,
  text,
  timestamp,
} from "./platform_contract.ts";

type Query = postgres.Sql | postgres.TransactionSql;

export const MIN_STUDENTS = 5;
export const WINDOW_WEEKS = 4;
export const GRID_CONCEPTS = 12;
export const TOP_CONCEPTS = 5;
export const ERROR_TYPES = [
  "conceito",
  "calculo",
  "procedimento",
  "interpretacao",
  "sinal",
  "unidade",
  "outro",
] as const;

/** Uma linha por aluno × conceito × tipo de erro × semana (0 = a mais recente). */
export type ErrorRow = {
  student: string;
  concept_key: string;
  concept: string;
  subject: string;
  error_type: string;
  weeks_ago: number;
  errors: number;
};
/** Alunos com alguma tentativa em cada semana. */
export type ActivityRow = { student: string; weeks_ago: number };

function mode(values: string[]): string {
  const count = new Map<string, number>();
  for (const v of values) count.set(v, (count.get(v) ?? 0) + 1);
  let best = "", n = 0;
  for (const [v, c] of count) {
    if (c > n || (c === n && v < best)) [best, n] = [v, c];
  }
  return best;
}

export function normalizeConcept(value: string): string {
  return value.normalize("NFKC").trim().replace(/\s+/g, " ")
    .toLocaleLowerCase("pt-BR");
}

/** Monta o mapa agregado. Sem dados de aluno na saída. */
export function buildClassMap(
  errors: ErrorRow[],
  activity: ActivityRow[],
  members: number,
  questionCounts: Record<string, number> = {},
) {
  const activeStudents = new Set(activity.map((a) => a.student));
  const studentsWithData = activeStudents.size;
  const base = {
    members,
    students_with_data: studentsWithData,
    min_students: MIN_STUDENTS,
    window_weeks: WINDOW_WEEKS,
    error_types: [...ERROR_TYPES],
    privacy:
      `Agregado sem nomes. Aparece com ${MIN_STUDENTS} alunos ou mais com atividade nas últimas ${WINDOW_WEEKS} semanas.`,
  };
  if (studentsWithData < MIN_STUDENTS) {
    return {
      ...base,
      eligible: false,
      grid: [],
      top_concepts: [],
      trend: [],
      message:
        `O mapa da turma aparece quando ${MIN_STUDENTS} alunos ou mais estudarem no app. Hoje são ${studentsWithData}.`,
    };
  }
  const concepts = new Map<string, {
    names: string[];
    subjects: string[];
    students: Set<string>;
    byType: Record<string, number>;
    weekly: number[];
    total: number;
  }>();
  for (const row of errors) {
    if (!activeStudents.has(row.student)) continue;
    const key = normalizeConcept(row.concept_key || row.concept);
    if (!key) continue;
    const entry = concepts.get(key) ?? {
      names: [] as string[],
      subjects: [] as string[],
      students: new Set<string>(),
      byType: Object.fromEntries(ERROR_TYPES.map((t) => [t, 0])),
      weekly: Array(WINDOW_WEEKS).fill(0),
      total: 0,
    };
    const type = (ERROR_TYPES as readonly string[]).includes(row.error_type)
      ? row.error_type
      : "outro";
    const n = Math.max(0, Math.trunc(Number(row.errors) || 0));
    const week = Math.min(WINDOW_WEEKS - 1, Math.max(0, row.weeks_ago));
    entry.names.push(row.concept.trim());
    entry.subjects.push(row.subject.trim());
    entry.students.add(row.student);
    entry.byType[type] += n;
    // weekly[0] = semana mais antiga; weekly[3] = semana atual.
    entry.weekly[WINDOW_WEEKS - 1 - week] += n;
    entry.total += n;
    concepts.set(key, entry);
  }
  const ranked = [...concepts.entries()].map(([key, c]) => ({
    concept_key: key,
    concept: mode(c.names),
    subject: mode(c.subjects),
    students: c.students.size,
    errors: c.total,
    by_type: c.byType,
    weekly: c.weekly,
    main_error_type: Object.entries(c.byType)
      .sort((a, b) => b[1] - a[1])[0][0],
    questions_available: questionCounts[key] ?? 0,
  })).sort((a, b) =>
    b.students - a.students || b.errors - a.errors ||
    a.concept.localeCompare(b.concept, "pt-BR")
  );
  const weeklyActive = Array.from(
    { length: WINDOW_WEEKS },
    (_, i) =>
      new Set(
        activity.filter((a) => a.weeks_ago === WINDOW_WEEKS - 1 - i).map((
          a,
        ) => a.student),
      ).size,
  );
  const weeklyErrors = Array.from(
    { length: WINDOW_WEEKS },
    (_, i) => ranked.reduce((sum, c) => sum + c.weekly[i], 0),
  );
  return {
    ...base,
    eligible: true,
    grid: ranked.slice(0, GRID_CONCEPTS),
    top_concepts: ranked.slice(0, TOP_CONCEPTS),
    trend: weeklyErrors.map((errors, i) => ({
      weeks_ago: WINDOW_WEEKS - 1 - i,
      errors,
      active_students: weeklyActive[i],
      errors_per_student: weeklyActive[i]
        ? Math.round((errors / weeklyActive[i]) * 10) / 10
        : 0,
    })),
    message: null,
  };
}

export type ResponseRow = {
  student: string;
  question_id: string;
  is_correct: boolean | null;
};
export type MemberRow = { student: string; share_progress: boolean };
export type QuestionRow = {
  id: string;
  prompt_text: string;
  kind: string;
  theme: string;
};
export type AssignmentErrorRow = {
  error_type: string;
  concept: string;
  errors: number;
};

/** Resultado da tarefa: quem fez, acerto por questão e erros mais comuns. */
export function buildAssignmentResult(
  questions: QuestionRow[],
  members: MemberRow[],
  responses: ResponseRow[],
  errors: AssignmentErrorRow[],
) {
  const total = questions.length;
  const byStudent = new Map<string, Map<string, boolean | null>>();
  for (const r of responses) {
    const answers = byStudent.get(r.student) ?? new Map();
    // Linhas chegam da mais recente para a mais antiga: vale a última resposta.
    if (!answers.has(r.question_id)) answers.set(r.question_id, r.is_correct);
    byStudent.set(r.student, answers);
  }
  const participants = members.map((m, index) => {
    const answers = byStudent.get(m.student) ?? new Map();
    const answered = questions.filter((q) => answers.has(q.id)).length;
    const status = answered === 0
      ? "not_started"
      : answered >= total
      ? "completed"
      : "in_progress";
    const correct = questions.filter((q) => answers.get(q.id) === true).length;
    return {
      label: `Participante ${index + 1}`,
      status,
      answered,
      correct: m.share_progress ? correct : null,
      shared: m.share_progress,
    };
  });
  const respondents = participants.filter((p) => p.answered > 0).length;
  const eligible = respondents >= MIN_STUDENTS;
  const perQuestion = questions.map((q, index) => {
    const answers = [...byStudent.entries()]
      .filter(([student]) => members.some((m) => m.student === student))
      .map(([, a]) => a.get(q.id))
      .filter((v) => v !== undefined);
    const graded = answers.filter((v) => v !== null);
    const correct = graded.filter((v) => v === true).length;
    // Cada questão também precisa de MIN_STUDENTS respostas: com menos, o
    // acerto da questão revelaria o resultado de um aluno identificável.
    const shown = eligible && answers.length >= MIN_STUDENTS;
    return {
      position: index + 1,
      question_id: q.id,
      prompt: q.prompt_text.length > 140
        ? q.prompt_text.slice(0, 137) + "..."
        : q.prompt_text,
      kind: q.kind,
      theme: q.theme,
      responses: answers.length,
      correct: shown ? correct : null,
      pending: shown ? answers.length - graded.length : null,
      accuracy: shown && graded.length
        ? Math.round((correct / graded.length) * 100)
        : null,
    };
  });
  const commonErrors = eligible
    ? [...errors].sort((a, b) =>
      b.errors - a.errors || a.error_type.localeCompare(b.error_type)
    ).slice(0, 5)
    : [];
  return {
    total_questions: total,
    members: members.length,
    respondents,
    completed: participants.filter((p) => p.status === "completed").length,
    min_students: MIN_STUDENTS,
    eligible,
    participants,
    questions: perQuestion,
    common_errors: commonErrors,
    privacy: eligible
      ? "Acerto individual só de quem autorizou compartilhar o progresso. Acerto por questão e erros são da turma, sem nomes."
      : `Acerto por questão e erros mais comuns aparecem quando ${MIN_STUDENTS} alunos ou mais responderem. Hoje são ${respondents}.`,
  };
}

export const ERROR_LABEL: Record<string, string> = {
  calculo: "Cálculo",
  conceito: "Conceito",
  sinal: "Sinal",
  interpretacao: "Interpretação",
  procedimento: "Procedimento",
  unidade: "Unidade",
  outro: "Outro",
};

const STATUS_LABEL: Record<string, string> = {
  completed: "Concluiu",
  in_progress: "Em andamento",
  not_started: "Não começou",
};

export function assignmentCsv(
  title: string,
  result: ReturnType<typeof buildAssignmentResult>,
): string {
  const lines: unknown[][] = [
    ["Tarefa", title],
    [
      "Participantes",
      result.members,
      "Responderam",
      result.respondents,
      "Concluíram",
      result.completed,
    ],
    [],
    ["Participante", "Situação", "Questões respondidas", "Acertos"],
    ...result.participants.map((p) => [
      p.label,
      STATUS_LABEL[p.status],
      `${p.answered}/${result.total_questions}`,
      p.correct === null ? "não compartilhado" : p.correct,
    ]),
    [],
    [
      "Questão",
      "Tema",
      "Enunciado",
      "Respostas",
      "Acertos",
      "Aguardando correção",
      "% de acerto",
    ],
    ...result.questions.map((q) => [
      q.position,
      q.theme,
      q.prompt,
      q.responses ?? "",
      q.correct ?? "",
      q.pending ?? "",
      q.accuracy ?? "",
    ]),
    [],
    ["Erros mais comuns", "Conceito", "Ocorrências"],
    ...result.common_errors.map((e) => [
      ERROR_LABEL[e.error_type] ?? e.error_type,
      e.concept,
      e.errors,
    ]),
    [],
    [result.privacy],
  ];
  return lines.map((line) => line.map(csvCell).join(";")).join("\r\n");
}

const denied = () =>
  new PublicError(403, "access_denied", "Você não tem acesso a esta operação.");

async function ownClassTitle(sql: Query, user: string, classId: string) {
  const [row] = await sql`SELECT id,title FROM public.platform_classes
    WHERE id=${classId} AND teacher_id=${user}
      AND public.platform_teacher_active(school_id, teacher_id)`;
  if (!row) throw denied();
  return String(row.title);
}

/** Questões do banco cujo tema ou assunto é o conceito (sem diferenciar caixa). */
async function questionCounts(sql: Query, keys: string[]) {
  if (!keys.length) return {};
  const rows = await sql`SELECT k AS key,count(q.id)::int AS n
    FROM unnest(${keys}::text[]) AS k
    LEFT JOIN public.question_bank q
      ON lower(btrim(q.theme))=k OR lower(btrim(q.topic))=k
    GROUP BY k`;
  return Object.fromEntries(rows.map((r) => [String(r.key), Number(r.n)]));
}

export async function classMap(sql: Query, user: string, input: Input) {
  const classId = id(input, "class_id");
  const title = await ownClassTitle(sql, user, classId);
  const [errors, activity, members] = await Promise.all([
    sql`SELECT a.user_id::text AS student,
        lower(btrim(c.name)) AS concept_key,btrim(c.name) AS concept,
        s.name AS subject,et.name AS error_type,
        least(3,floor(extract(epoch FROM now()-a.attempted_at)/604800))::int AS weeks_ago,
        count(*)::int AS errors
      FROM public.platform_memberships m
      JOIN public.platform_classes pc ON pc.id=m.class_id AND pc.teacher_id<>m.user_id
      JOIN public.attempts a ON a.user_id=m.user_id
        AND a.attempted_at>=now()-interval '28 days'
      JOIN public.error_events ee ON ee.attempt_id=a.id
        AND ee.status IN ('pending','confirmed')
      JOIN public.concepts c ON c.id=ee.concept_id
      JOIN public.subjects s ON s.id=c.subject_id AND s.user_id=a.user_id
      JOIN public.error_types et ON et.id=ee.error_type_id
      WHERE m.class_id=${classId}
      GROUP BY 1,2,3,4,5,6 LIMIT 50000`,
    sql`SELECT DISTINCT a.user_id::text AS student,
        least(3,floor(extract(epoch FROM now()-a.attempted_at)/604800))::int AS weeks_ago
      FROM public.platform_memberships m
      JOIN public.platform_classes pc ON pc.id=m.class_id AND pc.teacher_id<>m.user_id
      JOIN public.attempts a ON a.user_id=m.user_id
        AND a.attempted_at>=now()-interval '28 days'
      WHERE m.class_id=${classId}`,
    sql`SELECT count(*)::int AS n FROM public.platform_memberships m
      JOIN public.platform_classes pc ON pc.id=m.class_id
      WHERE m.class_id=${classId} AND m.user_id<>pc.teacher_id`,
  ]);
  const errorRows = errors as unknown as ErrorRow[];
  const keys = [
    ...new Set(errorRows.map((r) => normalizeConcept(r.concept_key))),
  ];
  const map = buildClassMap(
    errorRows,
    activity as unknown as ActivityRow[],
    Number(members[0]?.n ?? 0),
    // Só consulta o banco quando o mapa vai aparecer.
    new Set(activity.map((a) => a.student)).size >= MIN_STUDENTS
      ? await questionCounts(sql, keys)
      : {},
  );
  return { class_id: classId, class_title: title, ...map };
}

export async function createConceptAssignment(
  sql: postgres.Sql,
  user: string,
  input: Input,
) {
  const classId = id(input, "class_id");
  const concept = text(input, "concept", 160);
  const dueAt = timestamp(input, "due_at");
  const count = typeof input.count === "number" && Number.isInteger(input.count)
    ? Math.min(10, Math.max(1, input.count))
    : 5;
  await ownClassTitle(sql, user, classId);
  const key = normalizeConcept(concept);
  // Tema exato primeiro, depois assunto; dentro disso, a ordem do banco.
  const questions = await sql`SELECT id FROM public.question_bank
    WHERE lower(btrim(theme))=${key} OR lower(btrim(topic))=${key}
    ORDER BY (lower(btrim(theme))=${key}) DESC,position,id LIMIT ${count}`;
  if (!questions.length) {
    throw new PublicError(
      409,
      "no_questions",
      "O banco ainda não tem questões deste conceito. Escolha outro conceito ou monte uma lista do catálogo.",
    );
  }
  const ids = questions.map((q) => String(q.id));
  const [assignment] = await sql`INSERT INTO public.platform_assignments
      (class_id,title,due_at,catalog_ids,question_ids,source_concept)
    VALUES(${classId},${"Treinar: " + concept},${dueAt},${[]}::uuid[],
      ${ids}::uuid[],${concept})
    RETURNING *`;
  return { assignment, questions: ids.length };
}

export async function assignmentResult(sql: Query, user: string, input: Input) {
  const assignmentId = id(input, "assignment_id");
  const [assignment] = await sql`SELECT a.id,a.title,a.class_id,a.question_ids,
      a.source_concept,a.due_at,a.created_at
    FROM public.platform_assignments a
    JOIN public.platform_classes c ON c.id=a.class_id
    WHERE a.id=${assignmentId} AND c.teacher_id=${user}
      AND public.platform_teacher_active(c.school_id, c.teacher_id)`;
  if (!assignment) throw denied();
  const questionIds = assignment.question_ids as string[];
  if (!questionIds.length) {
    throw new PublicError(
      409,
      "not_question_assignment",
      "O resultado por questão está disponível para tarefas criadas pelo mapa da turma.",
    );
  }
  const [questions, members, responses, errors] = await Promise.all([
    sql`SELECT id::text,prompt_text,kind,theme FROM public.question_bank
      WHERE id=ANY(${questionIds}::uuid[])
      ORDER BY array_position(${questionIds}::uuid[],id)`,
    sql`SELECT m.user_id::text AS student,m.share_progress
      FROM public.platform_memberships m
      JOIN public.platform_classes c ON c.id=m.class_id
      WHERE m.class_id=${assignment.class_id} AND m.user_id<>c.teacher_id
      ORDER BY m.joined_at,m.user_id LIMIT 500`,
    sql`SELECT r.user_id::text AS student,r.question_id::text,r.is_correct
      FROM public.question_responses r
      JOIN public.platform_memberships m ON m.user_id=r.user_id
        AND m.class_id=${assignment.class_id}
      WHERE r.assignment_id=${assignmentId}
      ORDER BY r.created_at DESC LIMIT 20000`,
    sql`SELECT et.name AS error_type,
        coalesce(mode() WITHIN GROUP (ORDER BY btrim(c.name)),'') AS concept,
        count(*)::int AS errors
      FROM public.question_responses r
      JOIN public.platform_memberships m ON m.user_id=r.user_id
        AND m.class_id=${assignment.class_id}
      JOIN public.error_events ee ON ee.attempt_id=r.attempt_id
        AND ee.status IN ('pending','confirmed')
      JOIN public.error_types et ON et.id=ee.error_type_id
      LEFT JOIN public.concepts c ON c.id=ee.concept_id
      WHERE r.assignment_id=${assignmentId}
      GROUP BY et.name,lower(btrim(c.name)) ORDER BY 3 DESC LIMIT 20`,
  ]);
  const result = buildAssignmentResult(
    questions as unknown as QuestionRow[],
    members as unknown as MemberRow[],
    responses as unknown as ResponseRow[],
    (errors as unknown as AssignmentErrorRow[]).map((e) => ({
      ...e,
      concept: e.concept ?? "",
    })),
  );
  return {
    assignment: {
      id: assignment.id,
      title: assignment.title,
      class_id: assignment.class_id,
      source_concept: assignment.source_concept,
      due_at: assignment.due_at,
    },
    ...result,
    csv: assignmentCsv(String(assignment.title), result),
  };
}

/** Confere se a resposta pertence a uma tarefa da turma do aluno. */
export async function checkAssignmentAnswer(
  sql: Query,
  user: string,
  assignmentId: string,
  questionId: string,
) {
  const rows = await sql`SELECT 1 FROM public.platform_assignments a
    JOIN public.platform_memberships m ON m.class_id=a.class_id AND m.user_id=${user}
    WHERE a.id=${assignmentId} AND ${questionId}::uuid=ANY(a.question_ids)`;
  if (!rows.length) {
    throw new PublicError(
      403,
      "assignment_not_available",
      "Esta questão não faz parte de uma tarefa da sua turma.",
    );
  }
}
