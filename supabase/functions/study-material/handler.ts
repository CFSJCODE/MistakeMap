import { uuid } from "../_shared/ai_contract.ts";
import { json, userEndpoint } from "../_shared/ai_http.ts";
import { withDatabase } from "../_shared/ai_service.ts";
import { assertAiAllowed } from "../_shared/guardian_consent.ts";
import { quizAnswers, studyAction } from "../_shared/study_contract.ts";
import { generateStudy, gradeStudy } from "../_shared/study_service.ts";
export const handler = userEndpoint(async (req, user, input) => {
  const action = studyAction(input.action);
  if (action === "grade") {
    const material = uuid(input.material_id);
    const answers = quizAnswers(input.answers);
    return json(
      req,
      await withDatabase((sql) => gradeStudy(sql, user, material, answers)),
    );
  }
  const subject = uuid(input.subject_id);
  const previous = input.previous_material_id == null
    ? undefined
    : uuid(input.previous_material_id);
  return json(
    req,
    await withDatabase(async (sql) => {
      await assertAiAllowed(sql, user);
      return await generateStudy(sql, user, subject, previous);
    }),
  );
});
