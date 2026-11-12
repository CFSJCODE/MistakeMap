import { readLimited } from "../_shared/ai_http.ts";
import { withDatabase } from "../_shared/ai_service.ts";
import {
  applyProviderEvent,
  issuePending,
} from "../_shared/billing_service.ts";
import {
  parseAsaasEvent,
  type ProviderEvent,
  sameSecret,
} from "../_shared/payment_provider.ts";

export type BillingWebhookServices = {
  secret: (name: string) => string | undefined;
  applyEvent: (event: ProviderEvent, payload: unknown) => Promise<string>;
  issuePending: () => Promise<{ issued: number; failed: number }>;
};

const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });

/**
 * Entrada do servidor, sem JWT de usuário:
 * - webhook do Asaas, autenticado pelo cabeçalho asaas-access-token
 *   (= secret ASAAS_WEBHOOK_TOKEN), sempre respondido com 200 depois de
 *   gravado, para o Asaas não pausar a fila;
 * - pg_cron, com x-cron-secret (= SCHOOL_BILLING_CRON_SECRET, o mesmo valor
 *   do Vault school_billing_cron_secret), para emitir as faturas pendentes.
 */
export function createBillingWebhookHandler(services: BillingWebhookServices) {
  return async (req: Request): Promise<Response> => {
    if (req.method !== "POST") {
      return reply({ error: "method_not_allowed" }, 405);
    }
    let payload: unknown;
    try {
      const raw = await readLimited(req.body, 65536);
      payload = JSON.parse(new TextDecoder().decode(raw));
    } catch {
      return reply({ error: "invalid_body" }, 400);
    }
    const cron = req.headers.get("x-cron-secret");
    if (cron) {
      if (!sameSecret(cron, services.secret("SCHOOL_BILLING_CRON_SECRET"))) {
        return reply({ error: "unauthorized" }, 401);
      }
      const action = (payload as { action?: unknown })?.action;
      if (action !== "issue_pending") {
        return reply({ error: "invalid_action" }, 400);
      }
      return reply(await services.issuePending());
    }
    if (
      !sameSecret(
        req.headers.get("asaas-access-token"),
        services.secret("ASAAS_WEBHOOK_TOKEN"),
      )
    ) {
      return reply({ error: "unauthorized" }, 401);
    }
    const event = parseAsaasEvent(payload);
    if (!event) return reply({ received: true, result: "not_payment" });
    try {
      const result = await services.applyEvent(event, payload);
      console.log(
        JSON.stringify({ event: "billing_webhook", type: event.event, result }),
      );
      return reply({ received: true, result });
    } catch (error) {
      // Erro nosso: 500 faz o Asaas reenviar; o evento não ficou gravado.
      console.warn(JSON.stringify({
        event: "billing_webhook_failed",
        type: event.event,
        message: error instanceof Error
          ? error.message.slice(0, 120)
          : "unknown",
      }));
      return reply({ error: "internal_error" }, 500);
    }
  };
}

export const handler = createBillingWebhookHandler({
  secret: (name) => Deno.env.get(name)?.trim(),
  applyEvent: (event, payload) =>
    withDatabase((sql) => applyProviderEvent(sql, "asaas", event, payload)),
  issuePending: () => withDatabase((sql) => issuePending(sql)),
});
