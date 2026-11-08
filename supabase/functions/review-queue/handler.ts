import { json, userEndpoint } from "../_shared/ai_http.ts";
import { withDatabase } from "../_shared/ai_service.ts";
import { reviewAction } from "../_shared/review_contract.ts";
import { reviewOperation } from "../_shared/review_service.ts";

export const handler = userEndpoint(async (req, user, input) => {
  const action = reviewAction(input.action);
  return json(
    req,
    await withDatabase((sql) => reviewOperation(sql, user, action, input)),
  );
});
