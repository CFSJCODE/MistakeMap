import { PublicError, uuid } from "./ai_contract.ts";

export const PLATFORM_ACTIONS = [
  "overview",
  "catalog",
  "save_goal",
  "refresh_goal",
  "delete_goal",
  "start_session",
  "get_session",
  "save_answer",
  "finish_session",
  "hints",
  "create_class",
  "join_class",
  "set_sharing",
  "leave_class",
  "rotate_class_code",
  "remove_class_member",
  "create_assignment",
  "class_progress",
  "grant_teacher",
  "save_material",
  "delete_material",
  "save_note",
  "delete_note",
  "export_data",
  "report_csv",
  "request_deletion",
  "cancel_deletion",
  "content_drafts",
  "save_content_draft",
  "submit_content_draft",
  "publish_content_draft",
  "reject_content_draft",
  "save_feedback",
] as const;
export type PlatformAction = typeof PLATFORM_ACTIONS[number];
export type Input = Record<string, unknown>;
export function platformAction(value: unknown): PlatformAction {
  if (!PLATFORM_ACTIONS.includes(value as PlatformAction)) {
    throw new PublicError(
      400,
      "invalid_action",
      "Escolha uma operação válida.",
    );
  }
  return value as PlatformAction;
}
export function text(
  input: Input,
  key: string,
  max = 160,
  optional = false,
): string {
  const value = input[key];
  if (optional && (value === null || value === undefined)) return "";
  if (
    typeof value !== "string" || value.trim().length > max ||
    (!optional && !value.trim())
  ) {
    throw new PublicError(400, "invalid_field", `Confira o campo ${key}.`);
  }
  return value.trim();
}
export function integer(
  input: Input,
  key: string,
  min: number,
  max: number,
  fallback?: number,
): number {
  const value = input[key] ?? fallback;
  if (
    typeof value !== "number" || !Number.isInteger(value) || value < min ||
    value > max
  ) {
    throw new PublicError(400, "invalid_field", `Confira o campo ${key}.`);
  }
  return value;
}
export function flag(input: Input, key: string): boolean {
  if (typeof input[key] !== "boolean") {
    throw new PublicError(
      400,
      "invalid_consent",
      "Escolha explicitamente o que deseja compartilhar.",
    );
  }
  return input[key] as boolean;
}
export function id(input: Input, key: string): string {
  return uuid(input[key]);
}
export function optionalId(input: Input, key: string): string | null {
  return input[key] == null ? null : id(input, key);
}
export function strings(input: Input, key: string, max = 12): string[] {
  const values = input[key];
  if (!Array.isArray(values) || values.length > max) {
    throw new PublicError(400, "invalid_field", `Confira o campo ${key}.`);
  }
  return [...new Set(values.map((value) => text({ value }, "value", 120)))];
}
export function ids(input: Input, key: string, max = 10): string[] {
  const values = input[key];
  if (!Array.isArray(values) || values.length < 1 || values.length > max) {
    throw new PublicError(
      400,
      "invalid_field",
      "Selecione de 1 a 10 questões.",
    );
  }
  const result = values.map(uuid);
  if (new Set(result).size !== result.length) {
    throw new PublicError(
      400,
      "duplicate_items",
      "Escolha questões diferentes.",
    );
  }
  return result;
}
export function date(input: Input, key: string): string | null {
  if (input[key] == null || input[key] === "") return null;
  const value = text(input, key, 10);
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(value) || !Number.isFinite(Date.parse(value)) ||
    new Date(value).toISOString().slice(0, 10) !== value
  ) {
    throw new PublicError(400, "invalid_date", "Informe uma data válida.");
  }
  return value;
}
export function timestamp(input: Input, key: string): string | null {
  if (input[key] == null || input[key] === "") return null;
  const value = text(input, key, 40);
  if (
    !/T.*(?:Z|[+-]\d{2}:\d{2})$/.test(value) ||
    !Number.isFinite(Date.parse(value))
  ) {
    throw new PublicError(
      400,
      "invalid_date",
      "Informe data e fuso horário válidos.",
    );
  }
  return new Date(value).toISOString();
}
export function materialUrl(input: Input): string {
  const value = text(input, "url", 2000);
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new PublicError(
      400,
      "invalid_url",
      "Informe um endereço HTTPS válido.",
    );
  }
  if (
    url.protocol !== "https:" || !url.hostname || url.username || url.password
  ) {
    throw new PublicError(
      400,
      "invalid_url",
      "Use um endereço HTTPS sem credenciais.",
    );
  }
  // Apenas guarda o link. O servidor não busca o arquivo nem envia a terceiros.
  return url.href;
}

function normalizedAnswer(value: string): string {
  return value.normalize("NFKC").toLocaleLowerCase("pt-BR")
    .replace(/[−–]/g, "-")
    .replace(/\s*([=+*/^()<>:;,\-])\s*/g, "$1")
    .replace(/\s+/g, " ").trim();
}
export type Verdict = "correct" | "needs_review" | "unanswered";
/** Não avalia código/fórmulas nem declara errado o que não consegue verificar. */
export function compareAnswer(answer: string, reference: string): Verdict {
  if (!answer.trim()) return "unanswered";
  const a = normalizedAnswer(answer);
  const b = normalizedAnswer(reference);
  if (a === b && b.length > 0) return "correct";
  const numeric = /^[+-]?\d+(?:[.,]\d+)?$/;
  if (numeric.test(a) && numeric.test(b)) {
    // Comparação decimal exata, sem arredondamento binário ou perda de precisão.
    const decimal = (v: string) => {
      const [whole, fraction = ""] = v.replace(",", ".").replace(/^\+/, "")
        .split(".");
      const negative = whole.startsWith("-");
      const digits = whole.replace(/^-/, "").replace(/^0+(?=\d)/, "");
      const tail = fraction.replace(/0+$/, "");
      return `${negative && (digits !== "0" || tail) ? "-" : ""}${digits}${
        tail ? "." + tail : ""
      }`;
    };
    if (decimal(a) === decimal(b)) return "correct";
  }
  return "needs_review";
}
export type GradeItem = {
  id: string;
  answer: string;
  correct_answer: string;
  explanation: string;
  hint_level: number;
};
export function gradeItems(items: GradeItem[]) {
  const results = items.map((item) => ({
    item_id: item.id,
    answer: item.answer,
    correct_answer: item.correct_answer,
    explanation: item.explanation,
    assisted: item.hint_level > 0,
    verdict: compareAnswer(item.answer, item.correct_answer),
  }));
  return {
    results,
    correct_count: results.filter((r) => r.verdict === "correct").length,
    total: results.length,
    assisted: results.some((r) => r.assisted),
  };
}
export function hintFor(
  theme: string,
  level: number,
  explanation: string,
): string {
  if (level === 3) return explanation;
  if (level === 1) {
    return `Identifique o que o dispositivo ou sistema precisa determinar em “${theme}”. Anote os dados e as unidades antes de calcular.`;
  }
  const normalized = theme.toLocaleLowerCase("pt-BR");
  if (normalized.includes("equa")) {
    return "Isole a incógnita aplicando a mesma operação aos dois lados da igualdade; confira especialmente os sinais.";
  }
  if (normalized.includes("porcent")) {
    return "Compare a variação com o valor inicial. Uma taxa percentual é a razão entre essas grandezas multiplicada por 100.";
  }
  if (normalized.includes("ohm")) {
    return "Relacione tensão, corrente e resistência por V = R × I. Converta as unidades antes de substituir os dados.";
  }
  if (normalized.includes("newton")) {
    return "Desenhe as forças que atuam no sistema. A soma das forças na direção escolhida se relaciona à massa e à aceleração.";
  }
  if (normalized.includes("mruv")) {
    return "Escolha uma relação de movimento uniformemente variado que use os dados fornecidos. Verifique se o problema pede posição, velocidade ou aceleração.";
  }
  return "Escreva a relação que conecta os dados à grandeza pedida. Resolva um passo por vez e confira unidades e sinais; a próxima pista abre a explicação revisada.";
}

export function weeklyPlan(
  subjects: string[],
  themes: { subject: string; theme: string }[],
  minutes: number,
  examDate: string | null,
  now = new Date(),
) {
  const available = themes.filter((t) =>
    !subjects.length || subjects.includes(t.subject)
  );
  const days = examDate
    ? Math.max(
      0,
      Math.ceil(
        (Date.parse(examDate + "T23:59:59Z") - now.getTime()) / 86400000,
      ),
    )
    : 7;
  return Array.from({ length: Math.min(7, days) }, (_, i) => ({
    date: new Date(now.getTime() + i * 86400000).toISOString().slice(0, 10),
    minutes,
    subject: available.length
      ? available[i % available.length].subject
      : subjects[i % Math.max(1, subjects.length)] ?? "Seu objetivo",
    theme: available.length
      ? available[i % available.length].theme
      : "Conteúdo próprio: ainda sem cobertura no catálogo",
    activity: i % 3 === 2
      ? "Retomar questões e conferir sem ajuda"
      : "Praticar e registrar a regra aprendida",
  }));
}
export function csvCell(value: unknown): string {
  let text = String(value ?? "");
  // Arquivos abertos em planilhas não devem executar fórmulas do aluno.
  if (/^[\s]*[=+\-@\t\r]/.test(text)) text = "'" + text;
  return `"${text.replace(/"/g, '""')}"`;
}
