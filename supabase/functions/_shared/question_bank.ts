// Correção do banco de questões (aba Exercícios do app).
//
// Regra do projeto: a correção é do servidor. O app só recebe o enunciado e
// os itens públicos (`payload`); o gabarito (`answer`) fica em
// question_bank_keys, sem acesso do cliente, e só aparece depois que o aluno
// responde. Cada alternativa errada pode trazer um diagnóstico (tipo de erro +
// explicação): é isso que leva o erro de uma questão objetiva para o Mapa.
import { type Analysis, CATEGORIES, PublicError } from "./ai_contract.ts";

export const QUESTION_KINDS = [
  "multipla_escolha",
  "multipla_selecao",
  "verdadeiro_falso",
  "numerica",
  "lacuna",
  "ordenacao",
  "associacao",
  "dissertativa",
] as const;
export type QuestionKind = typeof QUESTION_KINDS[number];
export type Category = typeof CATEGORIES[number];

export const KIND_LABELS: Record<QuestionKind, string> = {
  multipla_escolha: "Múltipla escolha",
  multipla_selecao: "Várias corretas",
  verdadeiro_falso: "Verdadeiro ou falso",
  numerica: "Resposta numérica",
  lacuna: "Complete as lacunas",
  ordenacao: "Ordenação",
  associacao: "Associação",
  dissertativa: "Dissertativa",
};

export type Diagnosis = { category: Category; feedback: string };
type Item = { id: string; text: string };

export type Question = {
  id: string;
  kind: QuestionKind;
  subject: string;
  theme: string;
  prompt_text: string;
  error_category: Category;
  payload: Record<string, unknown>;
  answer: Record<string, unknown>;
  correct_answer: string;
  explanation: string;
};

export type Grade = {
  is_correct: boolean;
  /** Fração de itens certos, de 0 a 1 (crédito parcial). */
  score: number;
  /** Item a item: o app marca o que acertou e o que errou. */
  items: { id: string; correct: boolean }[];
  /** Hipóteses de causa do erro, uma por tipo de erro. */
  diagnoses: Diagnosis[];
  /** Resposta do aluno em texto, para o histórico e o Mapa. */
  student_answer: string;
};

const invalid = () =>
  new PublicError(
    400,
    "invalid_response",
    "Resposta inválida para esta questão. Atualize a lista e tente de novo.",
  );

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw invalid();
  }
  return value as Record<string, unknown>;
}

function items(value: unknown): Item[] {
  return Array.isArray(value)
    ? value.map((v) => record(v)).map((v) => ({
      id: String(v.id),
      text: String(v.text ?? ""),
    }))
    : [];
}

function textAnswer(value: unknown, max = 500): string {
  if (typeof value !== "string") throw invalid();
  const t = value.trim();
  if (t.length > max) throw invalid();
  return t;
}

/** Comparação tolerante de texto curto: sem acento, caixa, espaços extras
 *  nem pontuação final. */
export function normalizeText(value: string): string {
  return value.normalize("NFD").replace(/[̀-ͯ]/g, "")
    .toLowerCase().replace(/\s+/g, " ").trim().replace(/[.;!]+$/, "")
    .trim();
}

/** Número digitado pelo aluno: aceita vírgula ou ponto decimal, notação
 *  científica e unidade escrita depois do número ("330 Ω", "1,5 A"). */
export function parseNumber(raw: string): number | null {
  const m = raw.trim().replace(/\s+/g, "").match(
    /^([+-]?(?:\d+(?:[.,]\d+)?|[.,]\d+)(?:e[+-]?\d+)?)/i,
  );
  if (!m) return null;
  const n = Number(m[1].replace(",", "."));
  return Number.isFinite(n) ? n : null;
}

function near(value: number, target: number, spec: Record<string, unknown>) {
  const abs = Number(spec.tolerance ?? 0);
  const rel = Number(spec.relative_tolerance ?? 0);
  return Math.abs(value - target) <=
    Math.max(abs, rel * Math.abs(target), 1e-9);
}

function diagnosisOf(value: unknown): Diagnosis | null {
  if (!value || typeof value !== "object") return null;
  const d = value as Record<string, unknown>;
  const category = String(d.category ?? "");
  if (!CATEGORIES.includes(category as Category)) return null;
  return { category: category as Category, feedback: String(d.feedback ?? "") };
}

function fallback(q: Question): Diagnosis {
  return { category: q.error_category, feedback: "" };
}

function uniqueByCategory(list: Diagnosis[]): Diagnosis[] {
  const seen = new Map<Category, Diagnosis>();
  for (const d of list) {
    const prev = seen.get(d.category);
    if (!prev) seen.set(d.category, d);
    else if (!prev.feedback && d.feedback) seen.set(d.category, d);
  }
  return [...seen.values()].slice(0, 5);
}

function label(list: Item[], id: string) {
  const i = list.findIndex((x) => x.id === id);
  return i < 0 ? id : `${list[i].id}) ${list[i].text}`;
}

/** Corrige uma questão objetiva. A dissertativa vai para a IA. */
export function gradeObjective(q: Question, rawResponse: unknown): Grade {
  const response = record(rawResponse);
  const diag = record(q.answer.diagnosis ?? {});
  const result = (
    parts: { id: string; correct: boolean; diagnosis?: unknown }[],
    student: string,
  ): Grade => {
    const wrong = parts.filter((p) => !p.correct);
    const score = parts.length
      ? (parts.length - wrong.length) / parts.length
      : 0;
    return {
      is_correct: parts.length > 0 && wrong.length === 0,
      score: Math.round(score * 1000) / 1000,
      items: parts.map(({ id, correct }) => ({ id, correct })),
      diagnoses: wrong.length
        ? uniqueByCategory(
          wrong.map((p) => diagnosisOf(p.diagnosis) ?? fallback(q)),
        )
        : [],
      student_answer: student,
    };
  };

  switch (q.kind) {
    case "multipla_escolha": {
      const options = items(q.payload.options);
      const choice = textAnswer(response.choice, 20);
      if (!options.some((o) => o.id === choice)) throw invalid();
      const correct = choice === String(q.answer.correct);
      return result(
        [{ id: choice, correct, diagnosis: diag[choice] }],
        label(options, choice),
      );
    }
    case "multipla_selecao": {
      const options = items(q.payload.options);
      const raw = response.choices;
      if (!Array.isArray(raw) || raw.length > options.length) throw invalid();
      const chosen = new Set(raw.map((c) => textAnswer(c, 20)));
      if ([...chosen].some((c) => !options.some((o) => o.id === c))) {
        throw invalid();
      }
      const right = new Set((q.answer.correct as unknown[]).map(String));
      return result(
        options.map((o) => ({
          id: o.id,
          correct: chosen.has(o.id) === right.has(o.id),
          diagnosis: diag[o.id],
        })),
        options.filter((o) => chosen.has(o.id)).map((o) => label(options, o.id))
          .join("; ") || "(nenhuma alternativa marcada)",
      );
    }
    case "verdadeiro_falso": {
      const statements = items(q.payload.statements);
      const answers = record(response.answers);
      const key = record(q.answer.answers);
      const parts = statements.map((s) => {
        const given = answers[s.id];
        if (given !== undefined && typeof given !== "boolean") throw invalid();
        return {
          id: s.id,
          correct: given === key[s.id],
          diagnosis: diag[s.id],
          given,
        };
      });
      return result(
        parts,
        parts.map((p) =>
          `${p.id}) ${
            p.given === undefined ? "sem resposta" : p.given ? "V" : "F"
          }`
        ).join("; "),
      );
    }
    case "numerica": {
      const raw = textAnswer(response.value, 40);
      const value = parseNumber(raw);
      if (value === null) {
        throw new PublicError(
          400,
          "invalid_number",
          "Digite só o número (use vírgula ou ponto para decimais).",
        );
      }
      const correct = near(value, Number(q.answer.value), q.answer);
      let diagnosis: unknown;
      if (!correct) {
        for (const c of (q.answer.common_errors as unknown[] ?? [])) {
          const spec = record(c);
          if (near(value, Number(spec.value), spec)) {
            diagnosis = spec;
            break;
          }
        }
      }
      const unit = String(q.payload.unit ?? "").trim();
      return result(
        [{ id: "valor", correct, diagnosis }],
        unit ? `${raw.replace(unit, "").trim()} ${unit}` : raw,
      );
    }
    case "lacuna": {
      const blanks = items(q.payload.blanks);
      const given = record(response.blanks);
      const key = record(q.answer.answers);
      const parts = blanks.map((b) => {
        const v = given[b.id] === undefined ? "" : textAnswer(given[b.id], 200);
        const accepted = (key[b.id] as unknown[] ?? []).map((a) =>
          normalizeText(String(a))
        );
        return {
          id: b.id,
          correct: v !== "" && accepted.includes(normalizeText(v)),
          diagnosis: diag[b.id],
          v,
        };
      });
      return result(
        parts,
        parts.map((p) => `(${p.id}) ${p.v || "em branco"}`).join("; "),
      );
    }
    case "ordenacao": {
      const list = items(q.payload.items);
      const order = response.order;
      const ids = list.map((i) => i.id);
      if (
        !Array.isArray(order) || order.length !== ids.length ||
        new Set(order.map(String)).size !== ids.length ||
        order.some((o) => !ids.includes(String(o)))
      ) throw invalid();
      const key = (q.answer.order as unknown[]).map(String);
      return result(
        order.map((o, i) => ({
          id: String(o),
          correct: String(o) === key[i],
          diagnosis: q.answer,
        })),
        order.map((o, i) =>
          `${i + 1}. ${list.find((x) => x.id === String(o))!.text}`
        ).join("; "),
      );
    }
    case "associacao": {
      const left = items(q.payload.left);
      const right = items(q.payload.right);
      const pairs = record(response.pairs);
      const key = record(q.answer.pairs);
      const parts = left.map((l) => {
        const r = pairs[l.id];
        if (
          r !== undefined &&
          (typeof r !== "string" || !right.some((x) => x.id === r))
        ) throw invalid();
        return {
          id: l.id,
          correct: r === key[l.id],
          diagnosis: diag[l.id],
          r: r as string | undefined,
        };
      });
      return result(
        parts,
        parts.map((p) => {
          const l = left.find((x) => x.id === p.id)!;
          const r = right.find((x) => x.id === p.r);
          return `${l.text} → ${r ? r.text : "sem par"}`;
        }).join("; "),
      );
    }
    case "dissertativa":
      throw new PublicError(
        400,
        "use_ai",
        "Questões dissertativas são corrigidas pela IA.",
      );
  }
}

/** Enunciado completo (com alternativas) para o histórico e para a IA. */
export function fullPrompt(
  q: Pick<Question, "kind" | "prompt_text" | "payload">,
) {
  const lines = [q.prompt_text.trim()];
  const add = (title: string, list: Item[]) => {
    if (!list.length) return;
    lines.push("", title);
    for (const i of list) lines.push(`${i.id}) ${i.text}`);
  };
  switch (q.kind) {
    case "multipla_escolha":
    case "multipla_selecao":
      add("Alternativas:", items(q.payload.options));
      break;
    case "verdadeiro_falso":
      add("Afirmações (V ou F):", items(q.payload.statements));
      break;
    case "ordenacao":
      add("Itens para ordenar:", items(q.payload.items));
      break;
    case "associacao":
      add("Coluna A:", items(q.payload.left));
      add("Coluna B:", items(q.payload.right));
      break;
    case "numerica": {
      const unit = String(q.payload.unit ?? "").trim();
      if (unit) lines.push("", `Responda em ${unit}.`);
      break;
    }
    default:
      break;
  }
  return lines.join("\n");
}

/** Mesmo formato da análise da IA: o Mapa, a prática e o histórico leem as
 *  questões objetivas sem caminho especial. */
export function gradeAnalysis(q: Question, g: Grade): Analysis {
  const concept = q.theme.trim().slice(0, 120);
  const fallbackEvidence =
    `Resposta dada: ${g.student_answer}. Resposta correta: ${q.correct_answer}.`;
  return {
    is_correct: g.is_correct,
    correct_answer: q.correct_answer,
    explanation: q.explanation,
    transcribed_prompt: fullPrompt(q).slice(0, 16000),
    transcribed_answer: g.student_answer.slice(0, 16000),
    concepts: [concept],
    errors: g.diagnoses.map((d) => ({
      category: d.category,
      concept,
      evidence: (d.feedback || fallbackEvidence).slice(0, 1000),
      // Gabarito revisado: o erro é certo; a causa é hipótese.
      confidence: d.feedback ? 0.7 : 0.5,
    })),
  };
}

export function questionKind(value: unknown): QuestionKind {
  if (!QUESTION_KINDS.includes(value as QuestionKind)) throw invalid();
  return value as QuestionKind;
}
