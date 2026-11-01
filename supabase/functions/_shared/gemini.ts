import { PublicError } from "./ai_contract.ts";
import { env, type Environment, readLimited, required } from "./ai_http.ts";
import { type RoutingEvidence, selectModel } from "./model_router.ts";
import {
  type ClaudeBudgetStore,
  claudeCharge,
  databaseBudget,
  reserveClaude,
} from "./claude_budget.ts";

// Gemini API (generateContent). Contract verified against ai.google.dev on
// 2026-09-29:
// - JSON output uses generationConfig.responseFormat.text {mimeType, schema}.
//   mimeType is a MimeType enum (APPLICATION_JSON), not the MIME string
//   "application/json" accepted by the older responseMimeType field.
//   The legacy responseSchema (OpenAPI subset) rejects additionalProperties and
//   type arrays such as ["boolean","null"] with HTTP 400. Unsupported keywords
//   (minLength/maxLength) are ignored, so ai_contract.ts still validates output.
// - Gemini 3.x Flash thinks by default ("medium") and thought tokens count
//   toward maxOutputTokens; hitting the cap ends with MAX_TOKENS and truncated
//   JSON. The REST enum uses LOW (MINIMAL is not supported by every Flash model).
// - The key travels in the x-goog-api-key header, never in the URL.
const ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models";
const THINKING_LEVEL = "LOW";
// 503 "high demand" and 429 quota errors are per model, so they move on to the
// next model in the chain; 404 means a retired or misspelled model name.
const RETRYABLE_STATUSES = new Set([404, 429, 500, 502, 503, 504]);
const REFUSALS = new Set([
  "SAFETY",
  "RECITATION",
  "BLOCKLIST",
  "PROHIBITED_CONTENT",
  "SPII",
  "LANGUAGE",
  "IMAGE_SAFETY",
  "IMAGE_PROHIBITED_CONTENT",
  "IMAGE_RECITATION",
]);

export function aiConfig(get: Environment = env) {
  const provider = (get("AI_PROVIDER")?.trim() || "gemini").toLowerCase();
  if (provider === "anthropic" || provider === "openrouter") {
    const prefix = provider === "anthropic" ? "ANTHROPIC" : "OPENROUTER";
    return {
      provider,
      workspaceId: provider === "anthropic"
        ? get("ANTHROPIC_WORKSPACE_ID")?.trim()
        : undefined,
      key: required(`${prefix}_API_KEY`, get),
      model: required(`${prefix}_MODEL`, get),
      fallbackModel: "off",
      liteModel: "off",
    };
  }
  if (provider !== "gemini") {
    throw new PublicError(
      500,
      "ai_configuration",
      "Provedor de IA não configurado.",
    );
  }
  return {
    provider,
    workspaceId: undefined,
    key: required("GEMINI_API_KEY", get),
    model: get("GEMINI_MODEL")?.trim() || "gemini-flash-latest",
    fallbackModel: get("GEMINI_FALLBACK_MODEL")?.trim() || "gemini-3.6-flash",
    // Flash-Lite runs on separate capacity and usually answers while the Flash
    // models are overloaded. Set GEMINI_LITE_MODEL=off to disable it.
    liteModel: get("GEMINI_LITE_MODEL")?.trim() || "gemini-3.5-flash-lite",
  };
}

// Three attempts, each on the next distinct model; a short chain repeats its
// last model so a single configured model still gets retried.
export function modelChain(
  config: Pick<
    ReturnType<typeof aiConfig>,
    "key" | "model" | "fallbackModel" | "liteModel"
  >,
): string[] {
  const models = [
    ...new Set([config.model, config.fallbackModel, config.liteModel]),
  ]
    .filter((model) => model && model.toLowerCase() !== "off");
  while (models.length < 3) models.push(models[models.length - 1]);
  return models.slice(0, 3);
}

const refusal = () =>
  new PublicError(
    422,
    "ai_refusal",
    "A IA não pôde analisar este conteúdo. Revise o exercício enviado.",
  );
const invalid = () =>
  new PublicError(
    502,
    "invalid_ai_output",
    "O serviço de IA retornou um resultado inválido.",
  );

// Logs the provider's error code and message, which name the offending request
// field. Plain-text bodies are never logged: they could echo request content.
async function logProviderError(response: Response): Promise<void> {
  let detail: { status?: unknown; message?: unknown } = {};
  try {
    const parsed = JSON.parse(
      new TextDecoder().decode(await readLimited(response.body, 8192)),
    );
    detail = parsed?.error ?? {};
  } catch {
    await response.body?.cancel().catch(() => {});
  }
  console.warn(JSON.stringify({
    event: "ai_provider_error",
    status: response.status,
    reason: typeof detail.status === "string" ? detail.status : undefined,
    message: typeof detail.message === "string"
      ? detail.message.slice(0, 300)
      : undefined,
  }));
}

// Os validadores locais continuam sendo a autoridade para limites e conteúdo.
function portableSchema(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(portableSchema);
  if (!value || typeof value !== "object") return value;
  const input = value as Record<string, unknown>;
  const result: Record<string, unknown> = {};
  const unsupported = new Set([
    "minLength",
    "maxLength",
    "minimum",
    "maximum",
    "minItems",
    "maxItems",
    "uniqueItems",
    "pattern",
  ]);
  for (const [key, item] of Object.entries(input)) {
    if (!unsupported.has(key)) result[key] = portableSchema(item);
  }
  if (input.type === "object") result.additionalProperties = false;
  return result;
}

async function otherProviderResponse(
  config: ReturnType<typeof aiConfig>,
  options: {
    schema: object;
    name: string;
    instructions: string;
    text: string;
    images?: string[];
    maxOutputTokens?: number;
    onModelUsed?: (model: string) => void;
  },
  fetcher: typeof fetch,
  budget: ClaudeBudgetStore,
): Promise<unknown> {
  const anthropic = config.provider === "anthropic";
  const content: unknown[] = [{ type: "text", text: options.text }];
  for (const image of options.images ?? []) {
    const match = image.match(
      /^data:(image\/(?:png|jpeg|webp|gif));base64,(.+)$/s,
    );
    if (!match) throw invalid();
    content.push(
      anthropic
        ? {
          type: "image",
          source: { type: "base64", media_type: match[1], data: match[2] },
        }
        : { type: "image_url", image_url: { url: image } },
    );
  }
  const schema = portableSchema(options.schema);
  const request = anthropic
    ? {
      model: config.model,
      max_tokens: options.maxOutputTokens ?? 12000,
      system: options.instructions,
      messages: [{ role: "user", content }],
      output_config: { format: { type: "json_schema", schema } },
    }
    : {
      model: config.model,
      max_tokens: options.maxOutputTokens ?? 12000,
      messages: [{ role: "system", content: options.instructions }, {
        role: "user",
        content,
      }],
      provider: { require_parameters: true },
      response_format: {
        type: "json_schema",
        json_schema: { name: options.name, strict: true, schema },
      },
    };
  const reservation = anthropic
    ? await reserveClaude(config, request, budget, fetcher)
    : null;
  let response: Response;
  try {
    response = await fetcher(
      anthropic
        ? "https://api.anthropic.com/v1/messages"
        : "https://openrouter.ai/api/v1/chat/completions",
      {
        method: "POST",
        headers: anthropic
          ? {
            "Content-Type": "application/json",
            "x-api-key": config.key,
            "anthropic-version": "2023-06-01",
            ...(config.workspaceId
              ? { "anthropic-workspace-id": config.workspaceId }
              : {}),
          }
          : {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${config.key}`,
          },
        body: JSON.stringify(request),
        signal: AbortSignal.timeout(80000),
      },
    );
  } catch {
    throw new PublicError(
      502,
      "ai_unavailable",
      "O serviço de IA está indisponível. Tente novamente.",
    );
  }
  if (!response.ok) {
    await response.body?.cancel().catch(() => {});
    throw new PublicError(
      response.status === 429 ? 429 : 502,
      response.status === 429 ? "ai_rate_limited" : "ai_unavailable",
      "O serviço de IA não concluiu a solicitação.",
    );
  }
  let data: Record<string, unknown>;
  try {
    data = JSON.parse(
      new TextDecoder().decode(await readLimited(response.body, 256000)),
    );
  } catch {
    throw invalid();
  }
  if (reservation) {
    const charge = claudeCharge(data.usage);
    if (charge !== null) {
      // If settlement fails the full reservation remains held.
      await budget.settle(reservation, charge).catch(() => {});
    }
  }
  let result: unknown;
  if (anthropic) {
    if (data.stop_reason !== "end_turn") throw invalid();
    result = Array.isArray(data.content)
      ? data.content.filter((part) => part?.type === "text").map((part) =>
        part.text
      ).join("")
      : null;
  } else {
    const choice = Array.isArray(data.choices) ? data.choices[0] : null;
    if (choice?.finish_reason !== "stop" || choice?.message?.refusal) {
      throw invalid();
    }
    result = choice?.message?.content;
  }
  if (typeof result !== "string") throw invalid();
  try {
    const parsed = JSON.parse(result);
    options.onModelUsed?.(`${config.provider}/${config.model}`);
    return parsed;
  } catch {
    throw invalid();
  }
}

type StructuredOptions = {
  schema: object;
  name: string;
  instructions: string;
  text: string;
  images?: string[];
  maxOutputTokens?: number;
  onModelUsed?: (model: string) => void;
};

export async function structuredResponse(
  options: StructuredOptions,
  get: Environment = env,
  fetcher: typeof fetch = fetch,
  budget: ClaudeBudgetStore = databaseBudget(get),
): Promise<unknown> {
  try {
    return await structuredResponseImpl(options, get, fetcher, budget);
  } catch (error) {
    if (
      get("AI_CLAUDE_FALLBACK_ENABLED") !== "true" ||
      !(error instanceof PublicError) ||
      ![
        "ai_unavailable",
        "ai_rate_limited",
        "invalid_ai_output",
        "incomplete_ai_output",
      ].includes(error.code)
    ) throw error;
    const tier = options.images?.length
      ? "VISION"
      : options.name === "mistakemap_study"
      ? "STUDY"
      : options.name === "mistakemap_practice"
      ? "PRACTICE"
      : "ANALYSIS";
    const fallbackGet: Environment = (key) => {
      if (key === "AI_PROVIDER" || key === `AI_${tier}_PROVIDER`) {
        return "anthropic";
      }
      if (key === "ANTHROPIC_MODEL" || key === `AI_${tier}_MODEL`) {
        return "claude-sonnet-5-5";
      }
      if (
        key === "AI_ROUTING_EVIDENCE" || key === "AI_CLAUDE_FALLBACK_ENABLED"
      ) return undefined;
      return get(key);
    };
    return await structuredResponseImpl(options, fallbackGet, fetcher, budget);
  }
}

async function structuredResponseImpl(
  options: StructuredOptions,
  get: Environment = env,
  fetcher: typeof fetch = fetch,
  budget: ClaudeBudgetStore = databaseBudget(get),
): Promise<unknown> {
  const tier = options.images?.length
    ? "VISION"
    : options.name === "mistakemap_study"
    ? "STUDY"
    : options.name === "mistakemap_practice"
    ? "PRACTICE"
    : "ANALYSIS";
  let evidence: RoutingEvidence[] = [];
  try {
    const parsed = JSON.parse(get("AI_ROUTING_EVIDENCE") ?? "[]");
    if (Array.isArray(parsed)) evidence = parsed;
  } catch {
    // Evidência ausente ou inválida mantém a configuração já existente.
  }
  // Claude Sonnet is the only paid model with a guarded price and reservation.
  const freeEvidence = evidence.filter((item) =>
    item && typeof item.model === "string" &&
    ((item.provider === "gemini" &&
      item.model === (get("GEMINI_MODEL")?.trim() || "gemini-flash-latest") &&
      Boolean(get("GEMINI_API_KEY")?.trim())) ||
      (item.provider === "anthropic" && item.model === "claude-sonnet-5-5" &&
        Boolean(get("ANTHROPIC_API_KEY")?.trim())) ||
      (item.provider === "openrouter" &&
        (item.model === "openrouter/free" || item.model.endsWith(":free")) &&
        Boolean(get("OPENROUTER_API_KEY")?.trim())))
  );
  const automatic = selectModel(
    freeEvidence,
    tier.toLowerCase(),
    (options.images?.length ?? 0) > 0,
    Date.now(),
    1,
  );
  const selectedProvider = automatic?.provider ??
    get(`AI_${tier}_PROVIDER`)?.trim();
  const selectedModel = automatic?.model ?? get(`AI_${tier}_MODEL`)?.trim();
  const selectedGet: Environment = (name) => {
    if (name === "AI_PROVIDER" && selectedProvider) return selectedProvider;
    const provider = (selectedProvider || get("AI_PROVIDER") || "gemini")
      .toUpperCase();
    if (name === `${provider}_MODEL` && selectedModel) return selectedModel;
    return get(name);
  };
  const config = aiConfig(selectedGet);
  if (config.provider !== "gemini") {
    try {
      return await otherProviderResponse(config, options, fetcher, budget);
    } catch (error) {
      if (
        automatic && error instanceof PublicError &&
        [
          "ai_unavailable",
          "ai_rate_limited",
          "invalid_ai_output",
          "ai_budget_unavailable",
          "ai_budget_exhausted",
        ].includes(
          error.code,
        )
      ) {
        return await structuredResponseImpl(
          options,
          (key) => key === "AI_ROUTING_EVIDENCE" ? "[]" : get(key),
          fetcher,
          budget,
        );
      }
      throw error;
    }
  }

  const parts: unknown[] = [{ text: options.text }];
  for (const dataUri of options.images ?? []) {
    // dataUri format: "data:image/png;base64,XXXX"
    const match = dataUri.match(/^data:([^;]+);base64,(.+)$/s);
    if (!match) throw invalid();
    parts.push({ inlineData: { mimeType: match[1], data: match[2] } });
  }

  const requestBody = JSON.stringify({
    systemInstruction: { parts: [{ text: options.instructions }] },
    contents: [{ role: "user", parts }],
    generationConfig: {
      responseFormat: {
        text: { mimeType: "APPLICATION_JSON", schema: options.schema },
      },
      maxOutputTokens: options.maxOutputTokens ?? 12000,
      thinkingConfig: { thinkingLevel: THINKING_LEVEL },
    },
  });
  const models = modelChain(config);
  // Edge Functions têm 150 s de wall clock; preserve margem para auth,
  // leitura das imagens no R2 e gravação no banco em todas as tentativas.
  const deadline = Date.now() + 110000;
  let response: Response | undefined;
  for (let attempt = 0; attempt < models.length; attempt++) {
    const remaining = deadline - Date.now();
    if (remaining < 1000) break;
    try {
      response = await fetcher(
        `${ENDPOINT}/${encodeURIComponent(models[attempt])}:generateContent`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-goog-api-key": config.key,
          },
          signal: AbortSignal.timeout(Math.min(80000, remaining)),
          body: requestBody,
        },
      );
    } catch {
      if (attempt === models.length - 1) break;
      console.warn(
        JSON.stringify({
          event: "ai_provider_retry",
          attempt: attempt + 1,
          reason: "network",
        }),
      );
      await new Promise((resolve) => setTimeout(resolve, 500 * 2 ** attempt));
      continue;
    }
    if (response.ok) {
      options.onModelUsed?.(models[attempt]);
      break;
    }
    if (
      !RETRYABLE_STATUSES.has(response.status) ||
      attempt === models.length - 1
    ) break;
    console.warn(
      JSON.stringify({
        event: "ai_provider_retry",
        attempt: attempt + 1,
        status: response.status,
        model: models[attempt],
      }),
    );
    await logProviderError(response);
    response = undefined;
    await new Promise((resolve) => setTimeout(resolve, 500 * 2 ** attempt));
  }

  if (!response) {
    throw new PublicError(
      502,
      "ai_unavailable",
      "A análise demorou ou o serviço está indisponível. Tente novamente.",
    );
  }

  if (!response.ok) {
    await logProviderError(response);
    throw new PublicError(
      response.status === 429 ? 429 : 502,
      response.status === 429 ? "ai_rate_limited" : "ai_unavailable",
      response.status === 429
        ? "O serviço de IA está ocupado. Tente novamente mais tarde."
        : "O serviço de IA não concluiu a análise.",
    );
  }

  let data: Record<string, unknown>;
  try {
    data = JSON.parse(
      new TextDecoder().decode(await readLimited(response.body, 256000)),
    );
  } catch {
    throw invalid();
  }

  const feedback = data?.promptFeedback as Record<string, unknown> | undefined;
  if (feedback?.blockReason) throw refusal();

  const candidates = data?.candidates;
  if (!Array.isArray(candidates) || !candidates.length) {
    throw new PublicError(
      502,
      "incomplete_ai_output",
      "A IA não conseguiu concluir o resultado. Tente novamente.",
    );
  }

  const candidate = candidates[0] as Record<string, unknown>;
  const finishReason = String(candidate.finishReason ?? "");
  if (REFUSALS.has(finishReason)) throw refusal();
  if (finishReason === "MAX_TOKENS") {
    throw new PublicError(
      502,
      "incomplete_ai_output",
      "A IA não conseguiu concluir o resultado. Tente novamente.",
    );
  }
  if (finishReason !== "STOP") throw invalid();

  const content = candidate.content as Record<string, unknown> | undefined;
  const responseParts = Array.isArray(content?.parts) ? content.parts : [];
  // Thought summaries are opt-in (includeThoughts), but skip them defensively.
  const text = responseParts
    .map((p) => p as Record<string, unknown>)
    .filter((p) => p?.thought !== true && typeof p?.text === "string")
    .map((p) => p.text as string)
    .join("");
  if (!text.trim()) throw invalid();

  try {
    return JSON.parse(text);
  } catch {
    throw invalid();
  }
}
