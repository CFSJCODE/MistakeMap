import { monitoredFetch } from "./provider_monitor.ts";
import { PublicError } from "./ai_contract.ts";
import { env, type Environment, readLimited, required } from "./ai_http.ts";

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
const TRANSIENT_STATUSES = new Set([500, 502, 503, 504]);
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
  return {
    key: required("GEMINI_API_KEY", get),
    model: get("GEMINI_MODEL")?.trim() || "gemini-flash-latest",
    fallbackModel: get("GEMINI_FALLBACK_MODEL")?.trim() || "gemini-3.6-flash",
  };
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

export async function structuredResponse(
  options: {
    schema: object;
    name: string;
    instructions: string;
    text: string;
    images?: string[];
    maxOutputTokens?: number;
    onModelUsed?: (model: string) => void;
  },
  get: Environment = env,
  fetcher: typeof fetch = fetch,
): Promise<unknown> {
  const config = aiConfig(get);

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
  const fallback = config.fallbackModel === config.model
    ? config.model
    : config.fallbackModel;
  const models = [config.model, fallback, fallback];
  // Edge Functions têm 150 s de wall clock; preserve margem para auth,
  // leitura das imagens no R2 e gravação no banco em todas as tentativas.
  const deadline = Date.now() + 110000;
  let response: Response | undefined;
  for (let attempt = 0; attempt < models.length; attempt++) {
    const remaining = deadline - Date.now();
    if (remaining < 1000) break;
    try {
      response = await monitoredFetch(fetcher, get)(
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
      !TRANSIENT_STATUSES.has(response.status) || attempt === models.length - 1
    ) break;
    console.warn(
      JSON.stringify({
        event: "ai_provider_retry",
        attempt: attempt + 1,
        status: response.status,
      }),
    );
    await response.body?.cancel().catch(() => {});
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
