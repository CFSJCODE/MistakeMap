import { uuid } from "../_shared/ai_contract.ts";
import { json, userEndpoint } from "../_shared/ai_http.ts";
import { analyzeAttempt, withDatabase } from "../_shared/ai_service.ts";
import { assertAiAllowed } from "../_shared/guardian_consent.ts";
export const handler = userEndpoint(async (req, user, input) => {
  const id = uuid(input.attempt_id);
  const result = await withDatabase(async (sql) => {
    await assertAiAllowed(sql, user);
    return await analyzeAttempt(sql, id, user);
  });
  return json(req, result, result.status === "processing" ? 202 : 200);
});
