import {
  practiceCategory,
  practiceCount,
  uuid,
} from "../_shared/ai_contract.ts";
import { json, userEndpoint } from "../_shared/ai_http.ts";
import { generatePractice, withDatabase } from "../_shared/ai_service.ts";
export const handler = userEndpoint(async (req, user, input) => {
  const subject = uuid(input.subject_id);
  const count = practiceCount(input.count);
  const category = practiceCategory(input.category);
  return json(
    req,
    await withDatabase((sql) =>
      generatePractice(sql, user, subject, count, category)
    ),
  );
});
