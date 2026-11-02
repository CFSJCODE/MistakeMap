import { strict as assert } from "node:assert";
import { technologyLearningContext } from "../_shared/educational_context.ts";

Deno.test("contexto de tecnologia é obrigatório em toda questão", () => {
  assert.match(technologyLearningContext, /Toda questão deve ter temática de tecnologia, sem exceção/);
  assert.doesNotMatch(technologyLearningContext, /Sempre que for pedagogicamente adequado/);
});

Deno.test("contexto cobre várias áreas e pede o dispositivo como protagonista", () => {
  for (const area of ["robótica", "eletrônica", "elétrica", "hardware", "software", "programação"]) {
    assert.ok(technologyLearningContext.includes(area), area);
  }
  assert.match(technologyLearningContext, /variando as áreas/);
  assert.match(technologyLearningContext, /protagonista do problema/);
});
