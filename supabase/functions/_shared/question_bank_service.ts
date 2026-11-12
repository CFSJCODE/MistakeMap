// Resposta a uma questão do banco: corrige no servidor e registra a tentativa
// na conta do aluno (matéria, exercício, tentativa e análise), para que o erro
// apareça no Mapa, no histórico e na prática como qualquer outro.
import postgres from "postgresjs";
import { PublicError, uuid } from "./ai_contract.ts";
import { analyzeAttempt, database } from "./ai_service.ts";
import { checkAssignmentAnswer } from "./class_map.ts";
import { assertAiAllowed } from "./guardian_consent.ts";
import {
  fullPrompt,
  type Grade,
  gradeAnalysis,
  gradeObjective,
  type Question,
} from "./question_bank.ts";

type Database = ReturnType<typeof database>;

export const QUESTION_BANK_PIPELINE = "question-bank-v1";
export const QUESTION_BANK_MODEL = "gabarito-revisado";

async function loadQuestion(sql: Database, id: string): Promise<Question> {
  const [q] = await sql`SELECT q.id,q.kind,q.subject,q.theme,q.prompt_text,
      q.error_category,q.payload,k.answer,k.correct_answer,k.explanation
    FROM public.question_bank q
    JOIN public.question_bank_keys k ON k.question_id=q.id
    WHERE q.id=${id}`;
  if (!q) {
    throw new PublicError(404, "question_not_found", "Questão não encontrada.");
  }
  return q as unknown as Question;
}

/** Matéria do aluno com o nome da questão e um exercício por questão: as
 *  respostas seguintes viram novas tentativas do mesmo exercício. */
async function exerciseFor(
  tx: postgres.TransactionSql,
  user: string,
  q: Question,
) {
  // Serializa respostas simultâneas do mesmo aluno à mesma questão.
  await tx`SELECT pg_advisory_xact_lock(hashtext(${user + ":" + q.id}))`;
  let [subject] = await tx`SELECT id FROM public.subjects
    WHERE user_id=${user} AND lower(name)=lower(${q.subject})
    ORDER BY created_at LIMIT 1`;
  if (!subject) {
    [subject] = await tx`INSERT INTO public.subjects(user_id,name)
      VALUES(${user},${q.subject}) RETURNING id`;
  }
  let [exercise] = await tx`SELECT e.id FROM public.exercises e
    JOIN public.subjects s ON s.id=e.subject_id
    WHERE s.user_id=${user} AND e.question_id=${q.id}
    ORDER BY e.created_at LIMIT 1`;
  if (!exercise) {
    [exercise] = await tx`INSERT INTO public.exercises(subject_id,source,
        prompt_text,difficulty,focus_concept,question_id)
      VALUES(${subject.id},'question_bank',${fullPrompt(q)},
        (SELECT difficulty FROM public.question_bank WHERE id=${q.id}),
        ${q.theme},${q.id})
      RETURNING id,subject_id`;
  } else {
    [exercise] = await tx`SELECT id,subject_id FROM public.exercises
      WHERE id=${exercise.id}`;
  }
  return {
    exerciseId: exercise.id as string,
    subjectId: exercise.subject_id as string,
  };
}

async function saveObjective(
  sql: Database,
  user: string,
  q: Question,
  response: unknown,
  grade: Grade,
  assignmentId: string | null,
) {
  const analysis = gradeAnalysis(q, grade);
  return await sql.begin(async (tx) => {
    const { exerciseId, subjectId } = await exerciseFor(tx, user, q);
    const [attempt] = await tx`INSERT INTO public.attempts(exercise_id,user_id,
        answer,solution_text,status)
      VALUES(${exerciseId},${user},${grade.student_answer},
        ${grade.student_answer},'completed') RETURNING id`;
    await tx`INSERT INTO public.attempt_analyses(attempt_id,user_id,subject_id,
        analysis,model,pipeline_version)
      VALUES(${attempt.id},${user},${subjectId},
        ${tx.json(analysis as unknown as postgres.JSONValue)},
        ${QUESTION_BANK_MODEL},${QUESTION_BANK_PIPELINE})`;
    await tx`INSERT INTO public.corrections(attempt_id,reference_text)
      VALUES(${attempt.id},${q.correct_answer + "\n\n" + q.explanation})`;
    // Mesmo bloqueio da análise da IA antes de criar conceitos da matéria.
    await tx`SELECT id FROM public.subjects WHERE id=${subjectId}
      FOR NO KEY UPDATE`;
    let [concept] = await tx`SELECT id FROM public.concepts
      WHERE subject_id=${subjectId} AND lower(name)=lower(${
      analysis.concepts[0]
    })
      ORDER BY created_at LIMIT 1`;
    if (!concept) {
      [concept] = await tx`INSERT INTO public.concepts(subject_id,name)
        VALUES(${subjectId},${analysis.concepts[0]}) RETURNING id`;
    }
    await tx`INSERT INTO public.exercise_concepts(exercise_id,concept_id)
      VALUES(${exerciseId},${concept.id}) ON CONFLICT DO NOTHING`;
    for (const e of analysis.errors) {
      await tx`INSERT INTO public.error_events(attempt_id,error_type_id,
          concept_id,evidence_ref,confidence,status)
        SELECT ${attempt.id},et.id,${concept.id},${e.evidence},${e.confidence},
          'pending'
        FROM public.error_types et WHERE et.name=${e.category}`;
    }
    if (grade.is_correct) {
      await tx`INSERT INTO public.mastery_events(concept_id,attempt_id,outcome)
        VALUES(${concept.id},${attempt.id},'question_bank_correct')`;
    }
    await tx`INSERT INTO public.question_responses(user_id,question_id,
        attempt_id,response,is_correct,score,assignment_id)
      VALUES(${user},${q.id},${attempt.id},
        ${tx.json(response as postgres.JSONValue)},${grade.is_correct},
        ${grade.score},${assignmentId})`;
    return attempt.id as string;
  });
}

async function answerEssay(
  sql: Database,
  user: string,
  q: Question,
  response: Record<string, unknown>,
  assignmentId: string | null,
) {
  const text = typeof response.text === "string" ? response.text.trim() : "";
  if (text.length < 3 || text.length > 8000) {
    throw new PublicError(
      400,
      "invalid_response",
      "Escreva sua resposta (até 8 mil caracteres).",
    );
  }
  const attemptId = await sql.begin(async (tx) => {
    const { exerciseId } = await exerciseFor(tx, user, q);
    const [attempt] = await tx`INSERT INTO public.attempts(exercise_id,user_id,
        answer,solution_text,status)
      VALUES(${exerciseId},${user},${text},${text},'pending') RETURNING id`;
    await tx`INSERT INTO public.question_responses(user_id,question_id,
        attempt_id,response,is_correct,score,assignment_id)
      VALUES(${user},${q.id},${attempt.id},${
      tx.json({ text })
    },NULL,NULL,${assignmentId})`;
    return attempt.id as string;
  });
  // A IA corrige com o gabarito revisado como referência. Sem IA agora, a
  // tentativa fica pendente: o process-batch tenta de novo e o trigger
  // sync_question_response_grade atualiza a nota quando a análise sair.
  try {
    const result = await analyzeAttempt(sql, attemptId, user) as {
      status?: string;
      analysis?: Record<string, unknown>;
    };
    const analysis = result.analysis;
    if (!analysis) {
      return { status: "processing", attempt_id: attemptId };
    }
    const isCorrect = typeof analysis.is_correct === "boolean"
      ? analysis.is_correct
      : null;
    await sql`UPDATE public.question_responses
      SET is_correct=${isCorrect},score=${
      isCorrect === null ? null : isCorrect ? 1 : 0
    }
      WHERE attempt_id=${attemptId}`;
    const errors = Array.isArray(analysis.errors) ? analysis.errors : [];
    return {
      status: "graded",
      attempt_id: attemptId,
      is_correct: isCorrect,
      score: isCorrect === null ? null : isCorrect ? 1 : 0,
      items: [],
      correct_answer: String(analysis.correct_answer ?? q.correct_answer),
      explanation: String(analysis.explanation ?? q.explanation),
      diagnoses: errors.map((e) => ({
        category: String((e as Record<string, unknown>).category ?? "outro"),
        feedback: String((e as Record<string, unknown>).evidence ?? ""),
      })),
    };
  } catch (error) {
    // A resposta já está salva: qualquer falha da IA (limite diário, serviço
    // fora do ar) vira "pendente", nunca a perda do que o aluno escreveu.
    const motivo = error instanceof PublicError && error.status < 500
      ? `${error.publicMessage} `
      : "A correção da IA não respondeu agora. ";
    return {
      status: "pending",
      attempt_id: attemptId,
      message:
        `Sua resposta foi salva. ${motivo}A correção é refeita automaticamente; confira de novo mais tarde.`,
    };
  }
}

export async function answerQuestion(
  sql: Database,
  user: string,
  input: Record<string, unknown>,
) {
  const q = await loadQuestion(sql, uuid(input.question_id));
  // Resposta de tarefa da turma: só vale para questão da tarefa e aluno da turma.
  const assignmentId = input.assignment_id == null
    ? null
    : uuid(input.assignment_id);
  if (assignmentId) await checkAssignmentAnswer(sql, user, assignmentId, q.id);
  const response = input.response;
  if (!response || typeof response !== "object" || Array.isArray(response)) {
    throw new PublicError(400, "invalid_response", "Resposta inválida.");
  }
  if (q.kind === "dissertativa") {
    // A dissertativa é corrigida pela IA.
    await assertAiAllowed(sql, user);
    return await answerEssay(
      sql,
      user,
      q,
      response as Record<string, unknown>,
      assignmentId,
    );
  }
  const grade = gradeObjective(q, response);
  const attemptId = await saveObjective(
    sql,
    user,
    q,
    response,
    grade,
    assignmentId,
  );
  return {
    status: "graded",
    attempt_id: attemptId,
    is_correct: grade.is_correct,
    score: grade.score,
    items: grade.items,
    correct_answer: q.correct_answer,
    explanation: q.explanation,
    diagnoses: grade.diagnoses,
  };
}
