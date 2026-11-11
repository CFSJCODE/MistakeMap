// Validação da Edge Function school-admin (cadastro por perfil e escola).
// Funções puras: testadas sem banco em tests/school_admin_test.ts.
import { PublicError } from "./ai_contract.ts";
import { type Input, text } from "./platform_contract.ts";

export const SCHOOL_ADMIN_ACTIONS = [
  "context",
  "save_profile",
  "redeem_invite",
  "join_class",
  "start_free_teacher",
  "create_school",
  "school_overview",
  "create_invite",
  "revoke_invite",
  "request_guardian_consent",
  "guardian_code",
  "revoke_guardian_consent",
  "create_team",
  "join_team",
  "leave_team",
] as const;
export type SchoolAdminAction = typeof SCHOOL_ADMIN_ACTIONS[number];

export const PERSONAS = [
  "student",
  "student_team",
  "teacher",
  "guardian",
  "owner",
  "coordinator",
  "it_admin",
] as const;
export type Persona = typeof PERSONAS[number];

export const SCHOOL_ROLES = [
  "owner",
  "coordinator",
  "it_admin",
  "teacher",
  "student",
  "guardian",
] as const;
export type SchoolRole = typeof SCHOOL_ROLES[number];

export const TEAM_ROLES = [
  "programacao",
  "mecanica",
  "eletronica",
  "estrategia",
] as const;
export const COMPETITIONS = [
  "obr",
  "fll",
  "ftc",
  "frc",
  "projeto",
  "outra",
] as const;

/** Papel de escola que cada perfil do cadastro aceita receber por convite. */
export const INVITE_ROLES_BY_PERSONA: Record<Persona, readonly SchoolRole[]> = {
  student: ["student"],
  student_team: ["student"],
  teacher: ["teacher"],
  guardian: ["guardian"],
  owner: ["owner"],
  coordinator: ["coordinator"],
  it_admin: ["it_admin"],
};

const invalid = (field: string) =>
  new PublicError(400, "invalid_field", `Confira o campo ${field}.`);

export function schoolAdminAction(value: unknown): SchoolAdminAction {
  if (!SCHOOL_ADMIN_ACTIONS.includes(value as SchoolAdminAction)) {
    throw new PublicError(
      400,
      "invalid_action",
      "Escolha uma operação válida.",
    );
  }
  return value as SchoolAdminAction;
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

export const persona = (input: Input) => oneOf(input, "persona", PERSONAS);
export const schoolRole = (input: Input) => oneOf(input, "role", SCHOOL_ROLES);
export const teamRole = (input: Input) => oneOf(input, "team_role", TEAM_ROLES);
export const competition = (input: Input) =>
  input.competition == null
    ? "projeto"
    : oneOf(input, "competition", COMPETITIONS);

/** Lista opcional de papéis esperados para o convite (o perfil escolhido). */
export function expectedRoles(input: Input): SchoolRole[] | null {
  const value = input.expected_roles;
  if (value == null) return null;
  if (
    !Array.isArray(value) || value.length < 1 || value.length > 6 ||
    value.some((role) => !SCHOOL_ROLES.includes(role as SchoolRole))
  ) throw invalid("expected_roles");
  return [...new Set(value as SchoolRole[])];
}

/**
 * Data de nascimento no formato AAAA-MM-DD, entre hoje e 120 anos atrás.
 * O banco confere de novo; aqui a mensagem fica mais clara.
 */
export function birthDate(input: Input, today = new Date()): string | null {
  const value = input.birth_date;
  if (value == null || value === "") return null;
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw invalid("birth_date");
  }
  const date = new Date(`${value}T00:00:00Z`);
  if (
    Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== value
  ) throw invalid("birth_date");
  const limit = new Date(today);
  limit.setUTCFullYear(limit.getUTCFullYear() - 120);
  if (date > today || date < limit) {
    throw new PublicError(
      400,
      "invalid_birth_date",
      "Confira a data de nascimento.",
    );
  }
  return value;
}

/** Código curto (convite da escola, equipe ou consentimento). */
export function shortCode(input: Input, key = "code"): string {
  const value = text(input, key, 40).replace(/[\s-]/g, "").toUpperCase();
  if (!/^[A-Z0-9]{6,32}$/.test(value)) {
    throw new PublicError(400, "invalid_code", "Confira o código.");
  }
  return value;
}

/** Código de turma (32 hexadecimais) ou convite da escola (curto). */
export function classOrInviteCode(
  input: Input,
): { kind: "class" | "invite"; code: string } {
  const raw = text(input, "code", 40).replace(/[\s-]/g, "");
  if (/^[a-f0-9]{32}$/i.test(raw)) {
    return { kind: "class", code: raw.toLowerCase() };
  }
  return { kind: "invite", code: shortCode({ code: raw }) };
}

/** CNPJ com 14 dígitos e dígitos verificadores válidos (pontuação ignorada). */
export function cnpj(input: Input): string | null {
  const value = input.cnpj;
  if (value == null || value === "") return null;
  if (typeof value !== "string") throw invalid("cnpj");
  const digits = value.replace(/\D/g, "");
  if (!cnpjValid(digits)) {
    throw new PublicError(400, "invalid_cnpj", "Confira o CNPJ da escola.");
  }
  return digits;
}

export function cnpjValid(digits: string): boolean {
  if (!/^\d{14}$/.test(digits) || /^(\d)\1{13}$/.test(digits)) return false;
  const check = (length: number) => {
    const weights = length === 12
      ? [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
      : [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    const sum = weights.reduce(
      (total, weight, index) => total + weight * Number(digits[index]),
      0,
    );
    const rest = sum % 11;
    return rest < 2 ? 0 : 11 - rest;
  };
  return check(12) === Number(digits[12]) && check(13) === Number(digits[13]);
}

export function optionalEmail(input: Input): string | null {
  const value = input.email;
  if (value == null || value === "") return null;
  if (
    typeof value !== "string" || value.length > 254 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim())
  ) throw invalid("email");
  return value.trim().toLowerCase();
}

export function boundedInteger(
  input: Input,
  key: string,
  min: number,
  max: number,
  fallback: number,
): number {
  const value = input[key] ?? fallback;
  if (
    typeof value !== "number" || !Number.isInteger(value) || value < min ||
    value > max
  ) throw invalid(key);
  return value;
}

const ERRORS: Record<string, [number, string, string]> = {
  MM401: [401, "unauthorized", "Entre na sua conta para continuar."],
  MM403: [403, "access_denied", "Você não tem permissão para esta operação."],
  MM402: [
    402,
    "plan_limit",
    "O plano atual da escola chegou ao limite. Fale com o dono da escola.",
  ],
  MM404: [404, "code_invalid", "Código inválido, vencido ou já usado."],
  MM409: [409, "not_needed", "Esta etapa não é necessária para a sua conta."],
  MM429: [429, "limit_reached", "Limite atingido. Tente de novo mais tarde."],
  "22023": [400, "invalid_field", "Confira os dados informados."],
  "23514": [400, "invalid_field", "Confira os dados informados."],
  "23505": [409, "already_exists", "Já existe um cadastro com esses dados."],
  "42501": [403, "access_denied", "Você não tem permissão para esta operação."],
};

/** Mensagens específicas para alguns erros levantados pelas funções do banco. */
const MESSAGES: Record<string, string> = {
  school_invite_invalid:
    "Convite inválido, vencido, já usado ou de outro e-mail.",
  consent_code_invalid: "Código do responsável inválido, vencido ou já usado.",
  team_code_invalid: "Código da equipe inválido.",
  guardian_is_student:
    "O consentimento precisa ser dado na conta do responsável, não na sua.",
  guardian_minor: "O responsável precisa ser maior de idade.",
  consent_not_required:
    "Sua conta não precisa do consentimento do responsável.",
  school_limit_reached: "Cada conta pode criar até 5 escolas.",
  team_limit_reached: "A escola atingiu o limite de 50 equipes.",
  team_full: "Esta equipe atingiu o limite de participantes.",
  too_many_requests: "Muitos códigos gerados hoje. Tente amanhã.",
  birth_date_required: "Informe a data de nascimento.",
  invalid_birth_date: "Confira a data de nascimento.",
  class_teacher_not_in_school: "Você não dá aula nesta escola.",
};

/** Converte erro do Postgres (SQLSTATE MMxxx das funções) em erro público. */
export function databaseError(error: unknown): unknown {
  if (error instanceof PublicError) return error;
  const code = (error as { code?: unknown })?.code;
  if (typeof code !== "string" || !(code in ERRORS)) return error;
  const [status, publicCode, fallback] = ERRORS[code];
  const message = (error as { message?: unknown }).message;
  const specific = typeof message === "string" ? MESSAGES[message] : undefined;
  // Limite de plano: a dica do banco já diz o limite e o que fazer.
  const hint = (error as { hint?: unknown }).hint;
  const planHint = code === "MM402" && typeof hint === "string"
    ? hint
    : undefined;
  return new PublicError(status, publicCode, specific ?? planHint ?? fallback);
}
