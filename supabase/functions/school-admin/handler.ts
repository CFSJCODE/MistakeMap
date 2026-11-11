import { PublicError } from "../_shared/ai_contract.ts";
import {
  authenticate,
  failure,
  json,
  preflight,
  readLimited,
} from "../_shared/ai_http.ts";
import { withDatabase } from "../_shared/ai_service.ts";
import type { Input } from "../_shared/platform_contract.ts";
import { schoolAdminAction } from "../_shared/school_admin_contract.ts";
import { schoolAdminOperation } from "../_shared/school_admin_service.ts";

export type SchoolAdminServices = {
  authenticate: (req: Request) => Promise<string>;
  run: (user: string, input: Input) => Promise<unknown>;
};

/**
 * Cadastro por perfil e escola. O perfil escolhido no app é só um pedido:
 * papel de escola só entra com convite validado aqui e no banco.
 */
export function createSchoolAdminHandler(services: SchoolAdminServices) {
  return async (req: Request): Promise<Response> => {
    const early = preflight(req);
    if (early) return early;
    try {
      const user = await services.authenticate(req);
      let input: Input;
      try {
        const raw = await readLimited(req.body, 16384);
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
      schoolAdminAction(input.action);
      return json(req, await services.run(user, input));
    } catch (error) {
      return failure(req, error);
    }
  };
}

export const handler = createSchoolAdminHandler({
  authenticate,
  run: (user, input) =>
    withDatabase((sql) => schoolAdminOperation(sql, user, input)),
});
