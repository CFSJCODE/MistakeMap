import {
  body,
  cronAuthorized,
  env,
  type Environment,
  failure,
  json,
} from "../_shared/ai_http.ts";
import { database } from "../_shared/ai_service.ts";
import { processAccountDeletion } from "../_shared/privacy_lifecycle.ts";
import { deletionServices } from "../_shared/privacy_adapters.ts";

export type DeletionHandlerDependencies = {
  get: Environment;
  connect: typeof database;
  services: typeof deletionServices;
  run: typeof processAccountDeletion;
};
export function createAccountDataHandler(
  deps: Partial<DeletionHandlerDependencies> = {},
) {
  const get = deps.get ?? env;
  return async function (req: Request): Promise<Response> {
    if (req.method !== "POST") {
      return json(req, { error: "method_not_allowed" }, 405);
    }
    if (
      !cronAuthorized(
        req.headers.get("x-account-deletion-secret"),
        get("ACCOUNT_DELETION_CRON_SECRET"),
      )
    ) {
      return json(req, { error: "unauthorized" }, 401);
    }
    let sql: ReturnType<typeof database> | undefined;
    try {
      const input = await body(req);
      if (input.action !== "process_deletion") {
        return json(req, { error: "invalid_action" }, 400);
      }
      // Configuração validada antes de alterar qualquer pedido ou remover dados.
      const services = (deps.services ?? deletionServices)(get);
      sql = (deps.connect ?? database)();
      return json(
        req,
        await (deps.run ?? processAccountDeletion)(sql, services),
      );
    } catch (error) {
      return failure(req, error);
    } finally {
      await sql?.end({ timeout: 5 }).catch(() => {});
    }
  };
}
export const handler = createAccountDataHandler();
