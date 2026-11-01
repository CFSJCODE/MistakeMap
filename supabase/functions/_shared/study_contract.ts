import { PublicError, uuid } from "./ai_contract.ts";

// Contrato do material de estudo (resumo, cartões e quiz). O gabarito do quiz
// (correct_choice e explanation) fica em study_quiz_keys e só volta ao
// cliente na correção.

export type StudySummary = {
  title: string;
  overview: string;
  key_points: string[];
  common_mistakes: string[];
};
export type StudyFlashcard = { front: string; back: string; concept: string };
export type StudyQuestion = {
  prompt: string;
  options: string[];
  correct_choice: number;
  explanation: string;
  concept: string;
};

/** Evita repetir literalmente questões anteriores, inclusive variações de espaço e caixa. */
export function hasRepeatedQuestions(
  questions: { prompt: string }[],
  previous: string[],
): boolean {
  const normalize = (s: string) =>
    s.normalize("NFKC").trim().toLocaleLowerCase("pt-BR").replace(/\s+/g, " ");
  const old = new Set(previous.map(normalize));
  return questions.some((q) => old.has(normalize(q.prompt)));
}
export type StudyMaterial = {
  summary: StudySummary;
  flashcards: StudyFlashcard[];
  quiz: StudyQuestion[];
};

const str = (maxLength: number, minLength = 1) => ({
  type: "string",
  minLength,
  maxLength,
});

export const FLASHCARDS = { min: 6, max: 12 };
export const QUESTIONS = { min: 5, max: 8 };
export const OPTIONS = 4;

export const studySchema = {
  type: "object",
  additionalProperties: false,
  required: ["summary", "flashcards", "quiz"],
  properties: {
    summary: {
      type: "object",
      additionalProperties: false,
      required: ["title", "overview", "key_points", "common_mistakes"],
      properties: {
        title: str(120),
        overview: str(2000),
        key_points: {
          type: "array",
          minItems: 3,
          maxItems: 8,
          items: str(400),
        },
        common_mistakes: {
          type: "array",
          minItems: 0,
          maxItems: 6,
          items: str(400),
        },
      },
    },
    flashcards: {
      type: "array",
      minItems: FLASHCARDS.min,
      maxItems: FLASHCARDS.max,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["front", "back", "concept"],
        properties: { front: str(400), back: str(800), concept: str(120) },
      },
    },
    quiz: {
      type: "array",
      minItems: QUESTIONS.min,
      maxItems: QUESTIONS.max,
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "prompt",
          "options",
          "correct_choice",
          "explanation",
          "concept",
        ],
        properties: {
          prompt: str(1500),
          options: {
            type: "array",
            minItems: OPTIONS,
            maxItems: OPTIONS,
            items: str(400),
          },
          correct_choice: { type: "integer", minimum: 0, maximum: OPTIONS - 1 },
          explanation: str(1500),
          concept: str(120),
        },
      },
    },
  },
};

const invalid = () =>
  new PublicError(
    502,
    "invalid_ai_output",
    "A IA retornou um material inválido. Tente novamente.",
  );

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw invalid();
  }
  return value as Record<string, unknown>;
}

function text(value: unknown, max: number): string {
  if (typeof value !== "string" || !value.trim() || value.length > max) {
    throw invalid();
  }
  return value.trim();
}

function list(value: unknown, min: number, max: number): unknown[] {
  if (!Array.isArray(value) || value.length < min || value.length > max) {
    throw invalid();
  }
  return value;
}

export function validateStudy(value: unknown): StudyMaterial {
  const root = record(value);
  const s = record(root.summary);
  const summary: StudySummary = {
    title: text(s.title, 120),
    overview: text(s.overview, 2000),
    key_points: list(s.key_points, 3, 8).map((p) => text(p, 400)),
    common_mistakes: list(s.common_mistakes, 0, 6).map((p) => text(p, 400)),
  };
  const flashcards = list(root.flashcards, FLASHCARDS.min, FLASHCARDS.max).map(
    (v) => {
      const c = record(v);
      return {
        front: text(c.front, 400),
        back: text(c.back, 800),
        concept: text(c.concept, 120),
      };
    },
  );
  const quiz = list(root.quiz, QUESTIONS.min, QUESTIONS.max).map((v) => {
    const q = record(v);
    const options = list(q.options, OPTIONS, OPTIONS).map((o) => text(o, 400));
    if (new Set(options.map((o) => o.toLowerCase())).size !== OPTIONS) {
      throw invalid();
    }
    const choice = q.correct_choice;
    if (
      !Number.isInteger(choice) || Number(choice) < 0 ||
      Number(choice) >= OPTIONS
    ) {
      throw invalid();
    }
    return {
      prompt: text(q.prompt, 1500),
      options,
      correct_choice: Number(choice),
      explanation: text(q.explanation, 1500),
      concept: text(q.concept, 120),
    };
  });
  if (new Set(quiz.map((q) => q.prompt)).size !== quiz.length) {
    throw invalid();
  }
  return { summary, flashcards, quiz };
}

/** Separa o que o cliente vê do gabarito privado. */
export function splitQuiz(quiz: StudyQuestion[]) {
  const ids = quiz.map(() => crypto.randomUUID());
  return {
    publicQuiz: quiz.map((q, i) => ({
      id: ids[i],
      prompt: q.prompt,
      options: q.options,
      concept: q.concept,
    })),
    keys: quiz.map((q, i) => ({
      id: ids[i],
      correct_choice: q.correct_choice,
      explanation: q.explanation,
    })),
  };
}

export type QuizKey = {
  id: string;
  correct_choice: number;
  explanation: string;
};
export type QuizAnswer = { question_id: string; choice: number | null };

export function quizAnswers(value: unknown): Map<string, number> {
  if (!Array.isArray(value) || value.length > QUESTIONS.max) {
    throw new PublicError(400, "invalid_answers", "Respostas inválidas.");
  }
  const answers = new Map<string, number>();
  for (const item of value) {
    const a = record(item);
    const choice = a.choice;
    if (
      !Number.isInteger(choice) || Number(choice) < 0 ||
      Number(choice) >= OPTIONS
    ) {
      throw new PublicError(400, "invalid_answers", "Respostas inválidas.");
    }
    answers.set(uuid(a.question_id), Number(choice));
  }
  return answers;
}

/** Corrige as respostas contra o gabarito; questão sem resposta conta erro. */
export function gradeQuiz(keys: QuizKey[], answers: Map<string, number>) {
  const results = keys.map((k) => {
    const choice = answers.get(k.id) ?? null;
    return {
      question_id: k.id,
      choice,
      correct_choice: k.correct_choice,
      is_correct: choice === k.correct_choice,
      explanation: k.explanation,
    };
  });
  return {
    results,
    correct_count: results.filter((r) => r.is_correct).length,
    total: results.length,
  };
}

export function studyAction(value: unknown): "generate" | "grade" {
  if (value === "generate" || value === "grade") return value;
  throw new PublicError(400, "invalid_action", "Ação inválida.");
}
