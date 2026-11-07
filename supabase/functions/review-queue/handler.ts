import {
  authenticate,
  body,
  failure,
  json,
  preflight,
} from "../_shared/ai_http.ts";
import { database } from "../_shared/ai_service.ts";
import { reviewAction } from "../_shared/review_contract.ts";
import { reviewOperation } from "../_shared/review_service.ts";

export async function handler(req: Request): Promise<Response> {
  const early = preflight(req);
  if (early) return early;
  let sql: ReturnType<typeof database> | undefined;
  try {
    const user = await authenticate(req);
    const input = await body(req);
    const action = reviewAction(input.action);
    sql = database();
    return json(req, await reviewOperation(sql, user, action, input));
  } catch (error) {
    return failure(req, error);
  } finally {
    await sql?.end({ timeout: 5 }).catch(() => {});
  }
}
