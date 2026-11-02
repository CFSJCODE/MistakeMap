import { strict as assert } from "node:assert";
import { technologyLearningContext } from "../_shared/educational_context.ts";

Deno.test("contexto de tecnologia é obrigatório em toda questão", () => {
  assert.match(technologyLearningContext, /Toda questão deve ter temática de tecnologia/);
  assert.doesNotMatch(technologyLearningContext, /Sempre que for pedagogicamente adequado/);
});
