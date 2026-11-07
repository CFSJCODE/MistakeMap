import { PublicError } from "./ai_contract.ts";
import { env, type Environment, required } from "./ai_http.ts";

// https://supabase.com/docs/guides/auth/jwt-fields
// A prova de login recente pertence à sessão deste bearer. O último login
// global do usuário e a emissão de um token renovado não comprovam isso.
const RECENT_METHODS = new Set([
  "password",
  "oauth",
  "otp",
  "totp",
  "sso/saml",
  "magiclink",
]);
const SESSION_UUID =
  /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const BASE64URL = /^[A-Za-z0-9_-]+$/;
const reauthenticationRequired = () =>
  new PublicError(
    403,
    "reauthentication_required",
    "Entre novamente na sua conta neste aparelho e solicite a exclusão em até 10 minutos.",
  );

function object(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

// Exclusivo para o bearer que /auth/v1/user acabou de validar. Decodificar
// aqui só permite ler os claims assinados; não é verificação de assinatura.
function verifiedClaims(jwt: string): Record<string, unknown> | null {
  const parts = jwt.split(".");
  if (parts.length !== 3 || parts.some((part) => !BASE64URL.test(part))) {
    return null;
  }
  try {
    const raw = atob(parts[1].replace(/-/g, "+").replace(/_/g, "/"));
    const bytes = Uint8Array.from(raw, (char) => char.charCodeAt(0));
    return object(
      JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)),
    );
  } catch {
    return null;
  }
}

export async function requireRecentSignin(
  req: Request,
  user: string,
  get: Environment = env,
  fetcher: typeof fetch = fetch,
  now = new Date(),
): Promise<void> {
  const authorization = req.headers.get("authorization");
  const bearer = authorization?.match(/^Bearer[ \t]+(\S+)$/i);
  if (!authorization || !bearer) {
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
          Authorization: authorization,
          apikey: required("SUPABASE_ANON_KEY", get),
        },
        redirect: "error",
        signal: AbortSignal.timeout(10000),
      },
    );
  } catch {
    throw new PublicError(
      503,
      "auth_unavailable",
      "Não foi possível confirmar sua sessão.",
    );
  }
  if (!response.ok) {
    await response.body?.cancel();
    throw new PublicError(
      401,
      "unauthorized",
      "Entre na sua conta para continuar.",
    );
  }
  const data = object(await response.json().catch(() => null));
  if (!data || data.id !== user || data.is_anonymous === true) {
    throw reauthenticationRequired();
  }
  const claims = verifiedClaims(bearer[1]);
  if (
    !claims || claims.sub !== user || claims.role !== "authenticated" ||
    claims.is_anonymous !== false || Object.hasOwn(claims, "client_id") ||
    typeof claims.session_id !== "string" ||
    !SESSION_UUID.test(claims.session_id) ||
    claims.session_id === "00000000-0000-0000-0000-000000000000" ||
    !Array.isArray(claims.amr)
  ) {
    throw reauthenticationRequired();
  }
  const nowSeconds = Math.floor(now.getTime() / 1000);
  if (
    !claims.amr.some((value: unknown) => {
      const event = object(value);
      return event && typeof event.method === "string" &&
        RECENT_METHODS.has(event.method) &&
        typeof event.timestamp === "number" &&
        Number.isSafeInteger(event.timestamp) &&
        event.timestamp > 0 && event.timestamp >= nowSeconds - 600 &&
        event.timestamp <= nowSeconds;
    })
  ) {
    throw reauthenticationRequired();
  }
}
