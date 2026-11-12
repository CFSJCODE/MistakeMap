import { strict as assert } from "node:assert";
import { contentInput } from "../_shared/platform_content.ts";
import { PublicError } from "../_shared/ai_contract.ts";
const draft = {
  subject: "Matemática",
  topic: "Álgebra",
  theme: "Equações",
  position: 1,
  difficulty: "facil",
  error_category: "calculo",
  prompt_text:
    "Um sensor mede uma tensão x. Resolva x + 2 = 5 para calibrar o sensor.",
  correct_answer: "x = 3",
  explanation: "Subtraia 2 dos dois lados para obter x = 3.",
  technology_context: "O sensor fornece a grandeza que precisa ser calibrada.",
  rights_confirmed: true,
};
Deno.test("editor validates explicit rights and technology-centered content", () => {
  const valid = contentInput(draft);
  assert.equal(valid.answer, "x = 3");
  assert.equal(valid.source, null);
  for (
    const input of [
      { ...draft, rights_confirmed: false },
      { ...draft, technology_context: "curto" },
      {
        ...draft,
        prompt_text: "Maria comprou 2 maçãs e quer mais 3. Quantas maçãs terá?",
      },
      { ...draft, position: 6 },
      { ...draft, difficulty: "qualquer" },
      { ...draft, error_category: "invalida" },
      { ...draft, source_url: "javascript:alert(1)" },
    ]
  ) {
    assert.throws(() => contentInput(input), PublicError);
  }
});
