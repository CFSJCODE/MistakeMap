export const PIPELINE_VERSION = "gemini-analysis-v1";
export const CATEGORIES = [
  "calculo",
  "conceito",
  "sinal",
  "interpretacao",
  "procedimento",
  "unidade",
  "outro",
] as const;
export class PublicError extends Error {
  constructor(
    public status: number,
    public code: string,
    public publicMessage: string,
  ) {
    super(code);
  }
}
export type Analysis = {
  is_correct: boolean | null;
  correct_answer: string;
  explanation: string;
  transcribed_prompt: string;
  transcribed_answer: string;
  errors: {
    category: typeof CATEGORIES[number];
    concept: string;
    evidence: string;
    confidence: number;
  }[];
  concepts: string[];
};
export type Practice = {
  prompt_text: string;
  difficulty: string;
  focus_concept: string;
  correct_answer: string;
  explanation: string;
};
const str = (maxLength: number, minLength = 1) => ({
  type: "string",
  minLength,
  maxLength,
});
export const analysisSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "is_correct",
    "correct_answer",
    "explanation",
    "transcribed_prompt",
    "transcribed_answer",
    "errors",
    "concepts",
  ],
  properties: {
    is_correct: { type: ["boolean", "null"] },
    correct_answer: str(12000, 0),
    explanation: str(12000),
    transcribed_prompt: str(16000, 0),
    transcribed_answer: str(16000, 0),
    errors: {
      type: "array",
      maxItems: 5,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["category", "concept", "evidence", "confidence"],
        properties: {
          category: { type: "string", enum: CATEGORIES },
          concept: str(120),
          evidence: str(1000),
          confidence: { type: "number", minimum: 0, maximum: 1 },
        },
      },
    },
    concepts: { type: "array", maxItems: 12, items: str(120) },
  },
};
export const practiceSchema = {
  type: "object",
  additionalProperties: false,
  required: ["exercises"],
  properties: {
    exercises: {
      type: "array",
      minItems: 3,
      maxItems: 5,
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "prompt_text",
          "difficulty",
          "focus_concept",
          "correct_answer",
          "explanation",
        ],
        properties: {
          prompt_text: str(8000),
          difficulty: { type: "string", enum: ["facil", "media", "dificil"] },
          focus_concept: str(120),
          correct_answer: str(8000),
          explanation: str(8000),
        },
      },
    },
  },
};
function object(value: unknown, keys: string[]): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new PublicError(
      502,
      "invalid_ai_output",
      "A IA retornou um resultado inválido. Tente novamente.",
    );
  }
  const obj = value as Record<string, unknown>;
  if (
    Object.keys(obj).length !== keys.length || keys.some((k) => !(k in obj))
  ) {
    throw new PublicError(
      502,
      "invalid_ai_output",
      "A IA retornou um resultado inválido. Tente novamente.",
    );
  }
  return obj;
}
function text(value: unknown, max: number, empty = false): string {
  if (
    typeof value !== "string" || value.length > max || (!empty && !value.trim())
  ) {
    throw new PublicError(
      502,
      "invalid_ai_output",
      "A IA retornou um resultado inválido. Tente novamente.",
    );
  }
  return value.trim();
}
export function validateAnalysis(value: unknown): Analysis {
  const a = object(value, [
    "is_correct",
    "correct_answer",
    "explanation",
    "transcribed_prompt",
    "transcribed_answer",
    "errors",
    "concepts",
  ]);
  if (
    !(a.is_correct === null || typeof a.is_correct === "boolean") ||
    !Array.isArray(a.errors) || a.errors.length > 5 ||
    !Array.isArray(a.concepts) || a.concepts.length > 12
  ) {
    throw new PublicError(
      502,
      "invalid_ai_output",
      "A IA retornou um resultado inválido. Tente novamente.",
    );
  }
  const concepts = [...new Set(a.concepts.map((c) => text(c, 120)))];
  const errors = a.errors.map((v) => {
    const e = object(v, ["category", "concept", "evidence", "confidence"]);
    if (
      !CATEGORIES.includes(e.category as typeof CATEGORIES[number]) ||
      typeof e.confidence !== "number" || !Number.isFinite(e.confidence) ||
      e.confidence < 0 || e.confidence > 1
    ) {
      throw new PublicError(
        502,
        "invalid_ai_output",
        "A IA retornou um resultado inválido. Tente novamente.",
      );
    }
    const concept = text(e.concept, 120);
    if (!concepts.includes(concept)) {
      throw new PublicError(
        502,
        "invalid_ai_output",
        "A IA retornou conceitos inconsistentes. Tente novamente.",
      );
    }
    return {
      category: e.category as typeof CATEGORIES[number],
      concept,
      evidence: text(e.evidence, 1000),
      confidence: e.confidence,
    };
  });
  if (
    (a.is_correct !== false && errors.length) ||
    (a.is_correct === false && !errors.length)
  ) {
    throw new PublicError(
      502,
      "invalid_ai_output",
      "A IA retornou um diagnóstico inconsistente. Tente novamente.",
    );
  }
  return {
    is_correct: a.is_correct as boolean | null,
    correct_answer: text(a.correct_answer, 12000, a.is_correct === null),
    explanation: text(a.explanation, 12000),
    transcribed_prompt: text(a.transcribed_prompt, 16000, true),
    transcribed_answer: text(a.transcribed_answer, 16000, true),
    errors,
    concepts,
  };
}
export function validatePractice(
  value: unknown,
  count: number,
  targetConcepts: string[] = [],
): Practice[] {
  const a = object(value, ["exercises"]);
  if (!Array.isArray(a.exercises) || a.exercises.length !== count) {
    throw new PublicError(
      502,
      "invalid_ai_output",
      "A IA não gerou a quantidade de exercícios solicitada.",
    );
  }
  const list = a.exercises.map((v) => {
    const e = object(v, [
      "prompt_text",
      "difficulty",
      "focus_concept",
      "correct_answer",
      "explanation",
    ]);
    if (!["facil", "media", "dificil"].includes(String(e.difficulty))) {
      throw new PublicError(
        502,
        "invalid_ai_output",
        "A IA retornou uma dificuldade inválida.",
      );
    }
    return {
      prompt_text: text(e.prompt_text, 8000),
      difficulty: String(e.difficulty),
      focus_concept: text(e.focus_concept, 120),
      correct_answer: text(e.correct_answer, 8000),
      explanation: text(e.explanation, 8000),
    };
  });
  if (new Set(list.map((e) => e.prompt_text)).size !== list.length) {
    throw new PublicError(
      502,
      "invalid_ai_output",
      "A IA retornou exercícios repetidos.",
    );
  }
  if (
    targetConcepts.length &&
    list.some((e) => !targetConcepts.includes(e.focus_concept))
  ) {
    throw new PublicError(
      502,
      "invalid_ai_output",
      "A IA não focou nos conceitos que precisam de reforço. Tente novamente.",
    );
  }
  return list;
}
export function uuid(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value)
  ) throw new PublicError(400, "invalid_id", "Identificador inválido.");
  return value;
}
export function practiceCount(value: unknown): number {
  const n = value ?? 3;
  if (!Number.isInteger(n) || Number(n) < 3 || Number(n) > 5) {
    throw new PublicError(
      400,
      "invalid_count",
      "Solicite de 3 a 5 exercícios.",
    );
  }
  return Number(n);
}
export function imageMime(bytes: Uint8Array): string {
  if (bytes.length < 12 || bytes.length > 8 * 1024 * 1024) {
    throw new PublicError(
      400,
      "invalid_image",
      "A imagem deve ter até 8 MB e estar em JPEG, PNG ou WebP.",
    );
  }
  if ([137, 80, 78, 71, 13, 10, 26, 10].every((v, i) => bytes[i] === v)) {
    return "image/png";
  }
  if (bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) {
    return "image/jpeg";
  }
  if (
    String.fromCharCode(...bytes.slice(0, 4)) === "RIFF" &&
    String.fromCharCode(...bytes.slice(8, 12)) === "WEBP"
  ) return "image/webp";
  throw new PublicError(400, "invalid_image", "Formato de imagem não aceito.");
}
export async function verifyImageHash(
  bytes: Uint8Array,
  expected: unknown,
): Promise<void> {
  if (typeof expected !== "string" || !/^[0-9a-f]{64}$/.test(expected)) {
    throw new PublicError(
      400,
      "invalid_image_hash",
      "A imagem precisa ser enviada novamente para verificar sua integridade.",
    );
  }
  const digest = await crypto.subtle.digest("SHA-256", new Uint8Array(bytes));
  const actual = Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
  if (actual !== expected) {
    throw new PublicError(
      400,
      "image_changed",
      "A imagem mudou após o envio. Envie-a novamente.",
    );
  }
}
