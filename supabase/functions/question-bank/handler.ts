import { PublicError } from "../_shared/ai_contract.ts";
import {
  authenticate,
  failure,
  json,
  preflight,
  readLimited,
} from "../_shared/ai_http.ts";
import { database } from "../_shared/ai_service.ts";
import { answerQuestion } from "../_shared/question_bank_service.ts";

export type QuestionBankServices = {
  authenticate: (req: Request) => Promise<string>;
  run: (user: string, input: Record<string, unknown>) => Promise<unknown>;
};

/** Corrige a resposta a uma questão do banco (aba Exercícios do app). */
export function createQuestionBankHandler(services: QuestionBankServices) {
  return async (req: Request): Promise<Response> => {
    const early = preflight(req);
    if (early) return early;
    try {
      const user = await services.authenticate(req);
      let input: Record<string, unknown>;
      try {
        // Dissertativas chegam a 8 mil caracteres (até 4 bytes cada em UTF-8).
        const raw = await readLimited(req.body, 40960);
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
      if (input.action !== "answer") {
        throw new PublicError(400, "invalid_action", "Ação inválida.");
      }
      return json(req, await services.run(user, input));
    } catch (error) {
      return failure(req, error);
    }
  };
}

export const handler = createQuestionBankHandler({
  authenticate,
  async run(user, input) {
    const sql = database();
    try {
      return await answerQuestion(sql, user, input);
    } finally {
      await sql.end({ timeout: 5 }).catch(() => {});
    }
  },
});
