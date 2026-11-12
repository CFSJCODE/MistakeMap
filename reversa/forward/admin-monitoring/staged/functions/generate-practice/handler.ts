import { practiceCount, uuid } from "../_shared/ai_contract.ts";
import {
  authenticate,
  body,
  failure,
  json,
  preflight,
} from "../_shared/ai_http.ts";
import { database, generatePractice } from "../_shared/ai_service.ts";
export async function handler(req: Request): Promise<Response> {
  const early = preflight(req);
  if (early) return early;
  let sql: ReturnType<typeof database> | undefined;
  try {
    const user = await authenticate(req);
    const input = await body(req);
    const subject = uuid(input.subject_id);
    const count = practiceCount(input.count);
    sql = database();
    return json(req, await generatePractice(sql, user, subject, count));
  } catch (error) {
    return failure(req, error);
  } finally {
    await sql?.end({ timeout: 5 }).catch(() => {});
  }
}
