// Validação da Edge Function school-billing (cobrança da escola).
// Funções puras: testadas sem banco em tests/billing_test.ts.
import { PublicError } from "./ai_contract.ts";
import type { Input } from "./platform_contract.ts";
import { cnpjValid } from "./school_admin_contract.ts";

export const BILLING_ACTIONS = [
  "overview",
  "quote",
  "save_settings",
  "checkout",
  "invoice_status",
  "issue_invoice",
] as const;
export type BillingAction = typeof BILLING_ACTIONS[number];

export const PAID_PLANS = ["escola", "plus"] as const;
export type PaidPlan = typeof PAID_PLANS[number];
export const CYCLES = ["monthly", "annual"] as const;
export const METHODS = ["pix", "boleto", "credit_card"] as const;
export const PAYER_ROLES = ["owner", "finance"] as const;

const invalid = (field: string) =>
  new PublicError(400, "invalid_field", `Confira o campo ${field}.`);

export function billingAction(value: unknown): BillingAction {
  if (!BILLING_ACTIONS.includes(value as BillingAction)) {
    throw new PublicError(
      400,
      "invalid_action",
      "Escolha uma operação válida.",
    );
  }
  return value as BillingAction;
}

function oneOf<T extends string>(
  input: Input,
  key: string,
  values: readonly T[],
): T {
  const value = input[key];
  if (typeof value !== "string" || !values.includes(value as T)) {
    throw invalid(key);
  }
  return value as T;
}

function optionalOneOf<T extends string>(
  input: Input,
  key: string,
  values: readonly T[],
): T | null {
  return input[key] == null ? null : oneOf(input, key, values);
}

export const paidPlan = (input: Input) => oneOf(input, "plan", PAID_PLANS);
export const cycle = (input: Input) => oneOf(input, "cycle", CYCLES);
export const method = (input: Input) => oneOf(input, "method", METHODS);
export const optionalMethod = (input: Input) =>
  optionalOneOf(input, "default_method", METHODS);
export const optionalPayer = (input: Input) =>
  optionalOneOf(input, "payer_role", PAYER_ROLES);

/** Alunos estimados na contratação: 1 a 20.000. */
export function students(input: Input): number {
  const value = input.students;
  if (
    typeof value !== "number" || !Number.isInteger(value) || value < 1 ||
    value > 20000
  ) {
    throw invalid("students");
  }
  return value;
}

export function optionalDueDays(input: Input): number | null {
  const value = input.due_days;
  if (value == null) return null;
  if (
    typeof value !== "number" || !Number.isInteger(value) || value < 1 ||
    value > 60
  ) {
    throw invalid("due_days");
  }
  return value;
}

/**
 * Texto opcional: `null` quando o campo não veio (não muda nada); string vazia
 * quando veio vazio (apaga, nos campos que aceitam).
 */
export function optionalText(
  input: Input,
  key: string,
  max: number,
): string | null {
  const value = input[key];
  if (value == null) return null;
  if (typeof value !== "string" || value.trim().length > max) {
    throw invalid(key);
  }
  return value.trim();
}

export function optionalCnpj(input: Input): string | null {
  const value = input.cnpj;
  if (value == null || value === "") return null;
  if (typeof value !== "string") throw invalid("cnpj");
  const digits = value.replace(/\D/g, "");
  if (!cnpjValid(digits)) {
    throw new PublicError(400, "invalid_cnpj", "Confira o CNPJ da escola.");
  }
  return digits;
}

export function optionalBillingEmail(input: Input): string | null {
  const value = input.billing_email;
  if (value == null || value === "") return null;
  if (
    typeof value !== "string" || value.length > 254 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim())
  ) throw invalid("billing_email");
  return value.trim().toLowerCase();
}

/** Campo só de dígitos (CEP, telefone): `null` não muda, vazio apaga. */
export function optionalDigits(
  input: Input,
  key: string,
  sizes: readonly number[],
): string | null {
  const value = input[key];
  if (value == null) return null;
  if (typeof value !== "string") throw invalid(key);
  const digits = value.replace(/\D/g, "");
  if (digits === "") return "";
  if (!sizes.includes(digits.length)) throw invalid(key);
  return digits;
}

/** Luhn: descarta número de cartão digitado errado antes de ir ao gateway. */
export function luhnValid(digits: string): boolean {
  let sum = 0;
  for (let i = 0; i < digits.length; i++) {
    let d = Number(digits[digits.length - 1 - i]);
    if (i % 2 === 1) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
  }
  return digits.length > 0 && sum % 10 === 0;
}

export type CardInput =
  | {
    kind: "new";
    holderName: string;
    number: string;
    expiryMonth: string;
    expiryYear: string;
    ccv: string;
  }
  | { kind: "saved" };

/**
 * Cartão da contratação. Os dados passam direto para o Asaas e nunca são
 * gravados nem registrados em log; fica só o token devolvido pelo gateway.
 */
export function cardInput(input: Input, now = new Date()): CardInput | null {
  if (input.use_saved_card === true) return { kind: "saved" };
  const raw = input.card;
  if (raw == null) return null;
  if (typeof raw !== "object" || Array.isArray(raw)) throw invalid("card");
  const c = raw as Record<string, unknown>;
  const text = (v: unknown) => typeof v === "string" ? v.trim() : "";
  const holderName = text(c.holder_name);
  const number = text(c.number).replace(/[\s-]/g, "");
  const month = text(c.expiry_month).padStart(2, "0");
  let year = text(c.expiry_year);
  if (/^[0-9]{2}$/.test(year)) year = `20${year}`;
  const ccv = text(c.ccv);
  if (holderName.length < 2 || holderName.length > 100) {
    throw invalid("nome no cartão");
  }
  if (!/^[0-9]{13,19}$/.test(number) || !luhnValid(number)) {
    throw new PublicError(400, "invalid_card", "Confira o número do cartão.");
  }
  const m = Number(month);
  if (
    !/^[0-9]{2}$/.test(month) || m < 1 || m > 12 || !/^[0-9]{4}$/.test(year)
  ) {
    throw invalid("validade");
  }
  const y = Number(year);
  if (
    y < now.getUTCFullYear() ||
    (y === now.getUTCFullYear() && m < now.getUTCMonth() + 1)
  ) {
    throw new PublicError(400, "card_expired", "O cartão está vencido.");
  }
  if (!/^[0-9]{3,4}$/.test(ccv)) throw invalid("código de segurança");
  return {
    kind: "new",
    holderName,
    number,
    expiryMonth: month,
    expiryYear: year,
    ccv,
  };
}

/** Data de hoje em Brasília somada a `days`, no formato AAAA-MM-DD. */
export function dueDate(days: number, now = new Date()): string {
  const brasilia = new Date(now.getTime() - 3 * 3600 * 1000);
  brasilia.setUTCDate(brasilia.getUTCDate() + days);
  return brasilia.toISOString().slice(0, 10);
}

const MONTHS = [
  "janeiro",
  "fevereiro",
  "março",
  "abril",
  "maio",
  "junho",
  "julho",
  "agosto",
  "setembro",
  "outubro",
  "novembro",
  "dezembro",
];

/** Descrição da cobrança que aparece no boleto/Pix e na nota. */
export function chargeDescription(invoice: {
  kind: string;
  plan: string;
  cycle: string;
  students: number;
  reference_month: string | Date;
  purchase_order?: string | null;
  cost_center?: string | null;
  school_name: string;
}): string {
  const month = new Date(invoice.reference_month);
  const ref = `${MONTHS[month.getUTCMonth()]}/${month.getUTCFullYear()}`;
  const plan = invoice.plan === "plus" ? "Escola Plus" : "Escola";
  const what = invoice.kind === "checkout"
    ? `Contratação MistakeMap ${plan} ${
      invoice.cycle === "annual" ? "anual" : "mensal"
    }`
    : `MistakeMap ${plan}, fechamento de ${ref}`;
  const parts = [
    `${what} · ${invoice.students} alunos ativos · ${invoice.school_name}`,
  ];
  if (invoice.purchase_order) {
    parts.push(`Pedido de compra ${invoice.purchase_order}`);
  }
  if (invoice.cost_center) parts.push(`Centro de custo ${invoice.cost_center}`);
  return parts.join(" · ").slice(0, 500);
}
