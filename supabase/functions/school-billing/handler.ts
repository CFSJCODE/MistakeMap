import { PublicError } from "../_shared/ai_contract.ts";
import {
  authenticate,
  failure,
  json,
  preflight,
  readLimited,
} from "../_shared/ai_http.ts";
import { withDatabase } from "../_shared/ai_service.ts";
import { billingAction } from "../_shared/billing_contract.ts";
import {
  billingOperation,
  type RequestContext,
} from "../_shared/billing_service.ts";
import type { Input } from "../_shared/platform_contract.ts";

export type SchoolBillingServices = {
  authenticate: (req: Request) => Promise<string>;
  run: (
    user: string,
    input: Input,
    context: RequestContext,
  ) => Promise<unknown>;
};

/**
 * IP de quem paga, exigido pelo Asaas no cartão. Vem do proxy do Supabase
 * (primeiro endereço do x-forwarded-for), nunca do corpo enviado pelo app.
 */
export function remoteIp(req: Request): string | null {
  const forwarded = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  const ip = forwarded || req.headers.get("x-real-ip")?.trim();
  return ip && /^[0-9a-fA-F:.]{3,45}$/.test(ip) ? ip : null;
}

/**
 * Cobrança da escola: plano, quem paga, Pix/boleto/cartão e faturas. Quem escolhe o
 * plano e paga é conferido no banco (school_is_payer); o valor é calculado no
 * banco (school_billing_quote) e o gateway fica atrás de PaymentProvider.
 */
export function createSchoolBillingHandler(services: SchoolBillingServices) {
  return async (req: Request): Promise<Response> => {
    const early = preflight(req);
    if (early) return early;
    try {
      const user = await services.authenticate(req);
      let input: Input;
      try {
        const raw = await readLimited(req.body, 8192);
        const parsed = JSON.parse(new TextDecoder().decode(raw));
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
          throw new Error();
        }
        input = parsed;
      } catch {
        throw new PublicError(
          400,
          "invalid_body",
          "O pedido contém dados inválidos.",
        );
      }
      billingAction(input.action);
      return json(
        req,
        await services.run(user, input, { remoteIp: remoteIp(req) }),
      );
    } catch (error) {
      return failure(req, error);
    }
  };
}

export const handler = createSchoolBillingHandler({
  authenticate,
  run: (user, input, context) =>
    withDatabase((sql) =>
      billingOperation(sql, user, input, undefined, context)
    ),
});
