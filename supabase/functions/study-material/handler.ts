import { uuid } from "../_shared/ai_contract.ts";
import {
  authenticate,
  body,
  failure,
  json,
  preflight,
} from "../_shared/ai_http.ts";
import { database } from "../_shared/ai_service.ts";
import { quizAnswers, studyAction } from "../_shared/study_contract.ts";
import { generateStudy, gradeStudy } from "../_shared/study_service.ts";
export async function handler(req: Request): Promise<Response> {
  const early = preflight(req);
  if (early) return early;
  let sql: ReturnType<typeof database> | undefined;
  try {
    const user = await authenticate(req);
    const input = await body(req);
    const action = studyAction(input.action);
    if (action === "grade") {
      const material = uuid(input.material_id);
      const answers = quizAnswers(input.answers);
      sql = database();
      return json(req, await gradeStudy(sql, user, material, answers));
    }
    const subject = uuid(input.subject_id);
    sql = database();
    const previous = input.previous_material_id == null
      ? undefined
      : uuid(input.previous_material_id);
    return json(req, await generateStudy(sql, user, subject, previous));
  } catch (error) {
    return failure(req, error);
  } finally {
    await sql?.end({ timeout: 5 }).catch(() => {});
  }
}
