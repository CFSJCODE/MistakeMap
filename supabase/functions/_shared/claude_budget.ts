import postgres from "postgresjs";
import { PublicError } from "./ai_contract.ts";
import { type Environment, readLimited, required } from "./ai_http.ts";

const MODEL = "claude-sonnet-5-5";
const RESERVATION_USD = 1;
const MAX_INPUT_TOKENS = 100000;
const MAX_OUTPUT_TOKENS = 16000;
// Fail closed when the checked pricing must be reviewed.
const PRICE_VALID_UNTIL = Date.parse("2026-12-01T00:00:00Z");

export interface ClaudeBudgetStore {
  reserve(model: string): Promise<string | null>;
  settle(id: string, usd: number): Promise<void>;
}

export function databaseBudget(get: Environment): ClaudeBudgetStore {
  const connection = () =>
    postgres(required("SUPABASE_DB_URL", get), {
      prepare: false,
      max: 1,
      connect_timeout: 10,
      idle_timeout: 5,
    });
  return {
    async reserve(model) {
      const sql = connection();
      try {
        const [row] =
          await sql`select public.reserve_claude_budget(${model}, ${RESERVATION_USD}) as id`;
        return typeof row?.id === "string" ? row.id : null;
      } finally {
        await sql.end({ timeout: 5 });
      }
    },
    async settle(id, usd) {
      const sql = connection();
      try {
        await sql`update public.ai_budget_reservations set settled_usd=${usd}, settled_at=now()
          where id=${id} and settled_at is null and ${usd} <= reserved_usd`;
      } finally {
        await sql.end({ timeout: 5 });
      }
    },
  };
}

export async function reserveClaude(
  config: { model: string; key: string; workspaceId?: string },
  request: Record<string, unknown>,
  store: ClaudeBudgetStore,
  fetcher: typeof fetch,
  now = Date.now(),
): Promise<string> {
  if (
    config.model !== MODEL || now >= PRICE_VALID_UNTIL ||
    typeof request.max_tokens !== "number" ||
    request.max_tokens > MAX_OUTPUT_TOKENS || request.max_tokens <= 0
  ) {
    throw new PublicError(
      503,
      "ai_budget_unavailable",
      "Controle de custo indisponível para este modelo.",
    );
  }
  const { max_tokens: _maxTokens, ...countRequest } = request;
  let response: Response;
  try {
    response = await fetcher(
      "https://api.anthropic.com/v1/messages/count_tokens",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": config.key,
          "anthropic-version": "2023-06-01",
          ...(config.workspaceId
            ? { "anthropic-workspace-id": config.workspaceId }
            : {}),
        },
        body: JSON.stringify(countRequest),
        signal: AbortSignal.timeout(15000),
      },
    );
  } catch {
    throw new PublicError(
      503,
      "ai_budget_unavailable",
      "Não foi possível verificar o custo da solicitação.",
    );
  }
  if (!response.ok) {
    await response.body?.cancel().catch(() => {});
    throw new PublicError(
      503,
      "ai_budget_unavailable",
      "Não foi possível verificar o custo da solicitação.",
    );
  }
  let tokens: unknown;
  try {
    tokens = JSON.parse(
      new TextDecoder().decode(await readLimited(response.body, 8192)),
    ).input_tokens;
  } catch {
    throw new PublicError(
      503,
      "ai_budget_unavailable",
      "Não foi possível verificar o custo da solicitação.",
    );
  }
  if (
    !Number.isInteger(tokens) || (tokens as number) <= 0 ||
    (tokens as number) > MAX_INPUT_TOKENS
  ) {
    throw new PublicError(
      503,
      "ai_budget_unavailable",
      "Solicitação excede o limite de custo permitido.",
    );
  }
  let id: string | null;
  try {
    id = await store.reserve(config.model);
  } catch {
    throw new PublicError(
      503,
      "ai_budget_unavailable",
      "Controle de custo temporariamente indisponível.",
    );
  }
  if (!id) {
    throw new PublicError(
      429,
      "ai_budget_exhausted",
      "Limite de uso da IA atingido.",
    );
  }
  return id;
}

export function claudeCharge(usage: unknown): number | null {
  if (!usage || typeof usage !== "object") return null;
  const u = usage as Record<string, unknown>;
  const input = u.input_tokens, output = u.output_tokens;
  if (
    !Number.isInteger(input) || !Number.isInteger(output) ||
    (input as number) < 0 || (input as number) > MAX_INPUT_TOKENS * 2 + 10000 ||
    (output as number) < 0 || (output as number) > MAX_OUTPUT_TOKENS ||
    (u.cache_creation_input_tokens ?? 0) !== 0 ||
    (u.cache_read_input_tokens ?? 0) !== 0
  ) return null;
  // 10% safety margin and rounding upward to microdollars.
  const usd = Math.ceil(
    ((input as number) * 2 + (output as number) * 10) * 11 / 10,
  ) / 1e6;
  return usd <= RESERVATION_USD ? usd : null;
}
