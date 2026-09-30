import { PublicError } from "./ai_contract.ts";
import { env, type Environment, readLimited, required } from "./ai_http.ts";

export function aiConfig(get: Environment = env) {
  return {
    key: required("GEMINI_API_KEY", get),
    model: get("GEMINI_MODEL")?.trim() || "gemini-flash-latest",
  };
}

export async function structuredResponse(
  options: {
    schema: object;
    name: string;
    instructions: string;
    text: string;
    images?: string[];
    maxOutputTokens?: number;
  },
  get: Environment = env,
  fetcher: typeof fetch = fetch,
): Promise<unknown> {
  const config = aiConfig(get);
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${config.model}:generateContent?key=${config.key}`;

  const parts: unknown[] = [{ text: options.text }];
  for (const dataUri of (options.images ?? [])) {
    // dataUri format: "data:image/png;base64,XXXX"
    const match = dataUri.match(/^data:([^;]+);base64,(.+)$/s);
    if (!match) continue;
    parts.push({ inline_data: { mime_type: match[1], data: match[2] } });
  }

  let response: Response;
  try {
    response = await fetcher(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      signal: AbortSignal.timeout(70000),
      body: JSON.stringify({
        system_instruction: { parts: [{ text: options.instructions }] },
        contents: [{ role: "user", parts }],
        generationConfig: {
          response_mime_type: "application/json",
          response_schema: options.schema,
          maxOutputTokens: options.maxOutputTokens ?? 6000,
        },
      }),
    });
  } catch {
    throw new PublicError(
      502,
      "ai_unavailable",
      "A análise demorou ou o serviço está indisponível. Tente novamente.",
    );
  }

  if (!response.ok) {
    await response.body?.cancel();
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
    throw new PublicError(
      502,
      "invalid_ai_output",
      "O serviço de IA retornou um resultado inválido.",
    );
  }

  const candidates = data?.candidates;
  if (!Array.isArray(candidates) || !candidates.length) {
    throw new PublicError(
      502,
      "incomplete_ai_output",
      "A IA não conseguiu concluir o resultado. Tente novamente.",
    );
  }

  const candidate = candidates[0] as Record<string, unknown>;
  if (candidate.finishReason === "SAFETY") {
    throw new PublicError(
      422,
      "ai_refusal",
      "A IA não pôde analisar este conteúdo. Revise o exercício enviado.",
    );
  }

  const content = candidate.content as Record<string, unknown> | undefined;
  const responseParts = content?.parts;
  if (!Array.isArray(responseParts) || !responseParts.length) {
    throw new PublicError(
      502,
      "invalid_ai_output",
      "O serviço de IA retornou um resultado inválido.",
    );
  }

  const textPart = (responseParts.find(
    (p) => typeof (p as Record<string, unknown>)?.text === "string",
  ) as Record<string, unknown> | undefined)?.text;
  if (typeof textPart !== "string") {
    throw new PublicError(
      502,
      "invalid_ai_output",
      "O serviço de IA retornou um resultado inválido.",
    );
  }

  try {
    return JSON.parse(textPart);
  } catch {
    throw new PublicError(
      502,
      "invalid_ai_output",
      "O serviço de IA retornou um resultado inválido.",
    );
  }
}
