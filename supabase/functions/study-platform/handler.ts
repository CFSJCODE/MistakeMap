import {
  authenticate,
  failure,
  json,
  preflight,
  readLimited,
} from "../_shared/ai_http.ts";
import { PublicError } from "../_shared/ai_contract.ts";
import { database } from "../_shared/ai_service.ts";
import { type Input, platformAction } from "../_shared/platform_contract.ts";
import { platformOperation } from "../_shared/platform_service.ts";
import { requireRecentSignin } from "../_shared/privacy_auth.ts";

export type PlatformServices = {
  authenticate: (req: Request) => Promise<string>;
  run: (user: string, input: Input) => Promise<unknown>;
  requireRecentSignin?: (req: Request, user: string) => Promise<void>;
};
export function createPlatformHandler(services: PlatformServices) {
  return async (req: Request): Promise<Response> => {
    const early = preflight(req);
    if (early) return early;
    try {
      const user = await services.authenticate(req);
      let input: Input;
      try {
        const raw = await readLimited(req.body, 65536);
        const parsed = JSON.parse(new TextDecoder().decode(raw));
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
          throw new Error();
        }
        input = parsed;
      } catch {
        throw new PublicError(
          400,
          "invalid_body",
          "O pedido contém dados inválidos ou excede 64 KB.",
        );
      }
      platformAction(input.action);
      if (input.action === "request_deletion") {
        await (services.requireRecentSignin ?? requireRecentSignin)(req, user);
      }
      return json(req, await services.run(user, input));
    } catch (error) {
      return failure(req, error);
    }
  };
}
export const handler = createPlatformHandler({
  authenticate,
  async run(user, input) {
    const sql = database();
    try {
      return await platformOperation(sql, user, input);
    } finally {
      await sql.end({ timeout: 5 }).catch(() => {});
    }
  },
});
