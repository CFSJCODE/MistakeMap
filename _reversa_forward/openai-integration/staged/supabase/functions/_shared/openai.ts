import { PublicError } from "./ai_contract.ts";
import { env, type Environment, readLimited, required } from "./ai_http.ts";
export function aiConfig(get: Environment = env) {
  return {
    key: required("OPENAI_API_KEY", get),
    model: get("OPENAI_MODEL")?.trim() || "gpt-4.1-mini",
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
  let response: Response;
  try {
    response = await fetcher("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${config.key}`,
        "Content-Type": "application/json",
      },
      signal: AbortSignal.timeout(70000),
      body: JSON.stringify({
        model: config.model,
        store: false,
        instructions: options.instructions,
        input: [{
          role: "user",
          content: [
            { type: "input_text", text: options.text },
            ...(options.images ?? []).map((image_url) => ({
              type: "input_image",
              image_url,
              detail: "auto",
            })),
          ],
        }],
        max_output_tokens: options.maxOutputTokens ?? 6000,
        text: {
          format: {
            type: "json_schema",
            name: options.name,
            strict: true,
            schema: options.schema,
          },
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
  if (
    !data || typeof data !== "object" || data.status !== "completed" ||
    !Array.isArray(data.output)
  ) {
    throw new PublicError(
      502,
      "incomplete_ai_output",
      "A IA não conseguiu concluir o resultado. Tente novamente.",
    );
  }
  const texts: string[] = [];
  for (const item of data.output) {
    if (item.type !== "message" || !Array.isArray(item.content)) continue;
    for (const part of item.content) {
      if (part.type === "refusal") {
        throw new PublicError(
          422,
          "ai_refusal",
          "A IA não pôde analisar este conteúdo. Revise o exercício enviado.",
        );
      }
      if (part.type === "output_text" && typeof part.text === "string") {
        texts.push(part.text);
      }
    }
  }
  if (texts.length !== 1) {
    throw new PublicError(
      502,
      "invalid_ai_output",
      "O serviço de IA retornou um resultado inválido.",
    );
  }
  try {
    return JSON.parse(texts[0]);
  } catch {
    throw new PublicError(
      502,
      "invalid_ai_output",
      "O serviço de IA retornou um resultado inválido.",
    );
  }
}
