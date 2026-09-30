import { uuid } from "../_shared/ai_contract.ts";
import {
  authenticate,
  body,
  failure,
  json,
  preflight,
} from "../_shared/ai_http.ts";
import { analyzeAttempt, database } from "../_shared/ai_service.ts";
export async function handler(req: Request): Promise<Response> {
  const early = preflight(req);
  if (early) return early;
  let sql: ReturnType<typeof database> | undefined;
  try {
    const user = await authenticate(req);
    const input = await body(req);
    const id = uuid(input.attempt_id);
    sql = database();
    const result = await analyzeAttempt(sql, id, user);
    return json(req, result, result.status === "processing" ? 202 : 200);
  } catch (error) {
    return failure(req, error);
  } finally {
    await sql?.end({ timeout: 5 }).catch(() => {});
  }
}
