import { PublicError } from "./ai_contract.ts";
export type Environment = (name: string) => string | undefined;
export const env: Environment = (name) => Deno.env.get(name);
export function required(name: string, get: Environment = env): string {
  const value = get(name)?.trim();
  if (!value) {
    throw new PublicError(
      503,
      "service_not_configured",
      "O serviço de IA ainda não foi configurado.",
    );
  }
  return value;
}
export function cors(req: Request): HeadersInit {
  const origin = req.headers.get("Origin") ?? "";
  const allowed = (env("ALLOWED_ORIGINS") ?? "").split(",").map((s) => s.trim())
    .filter(Boolean);
  return {
    "Access-Control-Allow-Origin": allowed.includes(origin) ? origin : "null",
    "Access-Control-Allow-Headers":
      "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}
export function json(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...cors(req),
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}
export function preflight(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors(req) });
  }
  if (req.method !== "POST") {
    return json(req, {
      error: "method_not_allowed",
      message: "Método não permitido.",
    }, 405);
  }
  return null;
}
export function failure(req: Request, e: unknown): Response {
  const error = e instanceof PublicError ? e : new PublicError(
    500,
    "internal_error",
    "Não foi possível concluir a operação. Tente novamente.",
  );
  console.warn(
    JSON.stringify({ event: "ai_request_failed", code: error.code }),
  );
  return json(
    req,
    { error: error.code, message: error.publicMessage },
    error.status,
  );
}
export async function body(req: Request): Promise<Record<string, unknown>> {
  try {
    const bytes = await readLimited(req.body, 4096);
    const value = JSON.parse(new TextDecoder().decode(bytes));
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error();
    }
    return value;
  } catch {
    throw new PublicError(
      400,
      "invalid_body",
      "O pedido contém dados inválidos.",
    );
  }
}
export async function readLimited(
  stream: ReadableStream<Uint8Array> | null,
  limit: number,
): Promise<Uint8Array> {
  if (!stream) return new Uint8Array();
  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.length;
      if (total > limit) {
        await reader.cancel();
        throw new PublicError(
          400,
          "payload_too_large",
          "O arquivo excede o limite permitido.",
        );
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return bytes;
}
export async function authenticate(
  req: Request,
  get: Environment = env,
  fetcher: typeof fetch = fetch,
): Promise<string> {
  const token = req.headers.get("Authorization");
  if (!token || !/^Bearer\s+\S+$/i.test(token)) {
    throw new PublicError(
      401,
      "unauthorized",
      "Entre na sua conta para continuar.",
    );
  }
  let response: Response;
  try {
    response = await fetcher(
      `${required("SUPABASE_URL", get).replace(/\/$/, "")}/auth/v1/user`,
      {
        headers: {
          Authorization: token,
          apikey: required("SUPABASE_ANON_KEY", get),
        },
        signal: AbortSignal.timeout(10000),
      },
    );
  } catch (e) {
    if (e instanceof PublicError) throw e;
    throw new PublicError(
      503,
      "auth_unavailable",
      "Não foi possível validar a sessão.",
    );
  }
  if (!response.ok) {
    await response.body?.cancel();
    throw new PublicError(
      401,
      "unauthorized",
      "Sua sessão expirou. Entre novamente.",
    );
  }
  const data = await response.json();
  if (typeof data.id !== "string") {
    throw new PublicError(401, "unauthorized", "Sessão inválida.");
  }
  return data.id;
}
export function cronAuthorized(
  received: string | null,
  expected: string | undefined,
): boolean {
  if (
    !expected || expected.length < 24 || !received ||
    received.length !== expected.length
  ) return false;
  let difference = 0;
  for (let i = 0; i < expected.length; i++) {
    difference |= received.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return difference === 0;
}
