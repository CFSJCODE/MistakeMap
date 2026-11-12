import { strict as assert } from "node:assert";
import { PublicError } from "../_shared/ai_contract.ts";
import {
  fullPrompt,
  gradeAnalysis,
  gradeObjective,
  normalizeText,
  parseNumber,
  type Question,
} from "../_shared/question_bank.ts";
import { createQuestionBankHandler } from "../question-bank/handler.ts";

const base = {
  id: "00000000-0000-4000-8000-000000000001",
  subject: "Eletrônica",
  theme: "Lei de Ohm",
  prompt_text: "Qual resistor limita a corrente do LED a 20 mA?",
  error_category: "calculo" as const,
  correct_answer: "a) 100 Ω",
  explanation: "R = 2 ÷ 0,020 = 100 Ω.",
};
const q = (
  kind: Question["kind"],
  payload: Record<string, unknown>,
  answer: Record<string, unknown>,
): Question => ({ ...base, kind, payload, answer });

const options = [
  { id: "a", text: "100 Ω" },
  { id: "b", text: "250 Ω" },
  { id: "c", text: "150 Ω" },
];
const escolha = q("multipla_escolha", { options }, {
  correct: "a",
  diagnosis: { b: { category: "interpretacao", feedback: "Usou 5 V." } },
});

Deno.test("múltipla escolha: acerto e alternativa com diagnóstico", () => {
  const ok = gradeObjective(escolha, { choice: "a" });
  assert.equal(ok.is_correct, true);
  assert.equal(ok.score, 1);
  assert.deepEqual(ok.diagnoses, []);
  const erro = gradeObjective(escolha, { choice: "b" });
  assert.equal(erro.is_correct, false);
  assert.deepEqual(erro.diagnoses, [
    { category: "interpretacao", feedback: "Usou 5 V." },
  ]);
  assert.equal(erro.student_answer, "b) 250 Ω");
  // Sem diagnóstico próprio, vale o tipo de erro da questão.
  assert.equal(
    gradeObjective(escolha, { choice: "c" }).diagnoses[0].category,
    "calculo",
  );
});

Deno.test("resposta fora das alternativas é recusada", () => {
  assert.throws(
    () => gradeObjective(escolha, { choice: "z" }),
    (e: unknown) => e instanceof PublicError && e.code === "invalid_response",
  );
  assert.throws(() => gradeObjective(escolha, { choice: 1 }), PublicError);
});

Deno.test("várias corretas dá crédito parcial por alternativa", () => {
  const sel = q("multipla_selecao", { options }, {
    correct: ["a", "c"],
    diagnosis: {},
  });
  assert.equal(gradeObjective(sel, { choices: ["c", "a"] }).is_correct, true);
  const parcial = gradeObjective(sel, { choices: ["a"] });
  assert.equal(parcial.is_correct, false);
  assert.equal(parcial.score, 0.667);
  assert.deepEqual(parcial.items.map((i) => i.correct), [true, true, false]);
  assert.equal(
    gradeObjective(sel, { choices: [] }).student_answer,
    "(nenhuma alternativa marcada)",
  );
});

Deno.test("verdadeiro ou falso: afirmação sem resposta conta como erro", () => {
  const vf = q("verdadeiro_falso", {
    statements: [{ id: "1", text: "x" }, { id: "2", text: "y" }],
  }, {
    answers: { "1": true, "2": false },
    diagnosis: { "2": { category: "conceito", feedback: "y é falsa." } },
  });
  assert.equal(
    gradeObjective(vf, { answers: { "1": true, "2": false } }).is_correct,
    true,
  );
  const g = gradeObjective(vf, { answers: { "1": true } });
  assert.equal(g.score, 0.5);
  assert.equal(g.diagnoses[0].feedback, "y é falsa.");
  assert.throws(() => gradeObjective(vf, { answers: { "1": "V" } }));
});

Deno.test("numérica aceita vírgula, unidade e erros comuns", () => {
  const nu = q("numerica", { unit: "Ω" }, {
    value: 1020,
    tolerance: 0.5,
    common_errors: [{
      value: 1.02,
      tolerance: 0.005,
      category: "unidade",
      feedback: "Respondeu em kΩ.",
    }],
  });
  assert.equal(gradeObjective(nu, { value: "1020" }).is_correct, true);
  assert.equal(gradeObjective(nu, { value: "1020,2 Ω" }).is_correct, true);
  const kilo = gradeObjective(nu, { value: "1,02" });
  assert.equal(kilo.is_correct, false);
  assert.deepEqual(kilo.diagnoses, [
    { category: "unidade", feedback: "Respondeu em kΩ." },
  ]);
  assert.equal(kilo.student_answer, "1,02 Ω");
  assert.throws(
    () => gradeObjective(nu, { value: "mil" }),
    (e: unknown) => e instanceof PublicError && e.code === "invalid_number",
  );
  assert.equal(parseNumber("-4"), -4);
  assert.equal(parseNumber("1e-3"), 0.001);
  assert.equal(parseNumber(",5"), 0.5);
});

Deno.test("lacunas ignoram acento, caixa e ponto final", () => {
  const la = q("lacuna", {
    blanks: [{ id: "1", text: "Lacuna 1" }, { id: "2", text: "Lacuna 2" }],
  }, { answers: { "1": ["corrente elétrica"], "2": ["não", "not"] } });
  assert.equal(
    gradeObjective(la, { blanks: { "1": " Corrente Eletrica. ", "2": "NAO" } })
      .is_correct,
    true,
  );
  const g = gradeObjective(la, { blanks: { "1": "tensão" } });
  assert.equal(g.score, 0);
  assert.equal(g.student_answer, "(1) tensão; (2) em branco");
  assert.equal(normalizeText("  Ação  Rápida! "), "acao rapida");
});

Deno.test("ordenação exige todos os itens, sem repetição", () => {
  const or = q("ordenacao", {
    items: [{ id: "b", text: "B" }, { id: "a", text: "A" }, {
      id: "c",
      text: "C",
    }],
  }, { order: ["a", "b", "c"], category: "procedimento", feedback: "A→B→C" });
  assert.equal(gradeObjective(or, { order: ["a", "b", "c"] }).is_correct, true);
  const g = gradeObjective(or, { order: ["b", "a", "c"] });
  assert.equal(g.score, 0.333);
  assert.deepEqual(g.diagnoses, [{
    category: "procedimento",
    feedback: "A→B→C",
  }]);
  assert.throws(() => gradeObjective(or, { order: ["a", "a", "c"] }));
  assert.throws(() => gradeObjective(or, { order: ["a", "b"] }));
});

Deno.test("associação confere cada par", () => {
  const as = q("associacao", {
    left: [{ id: "l1", text: "Resistor" }, { id: "l2", text: "Diodo" }],
    right: [{ id: "r2", text: "Um sentido" }, { id: "r1", text: "Limita" }],
  }, { pairs: { l1: "r1", l2: "r2" } });
  assert.equal(
    gradeObjective(as, { pairs: { l1: "r1", l2: "r2" } }).is_correct,
    true,
  );
  const g = gradeObjective(as, { pairs: { l1: "r2" } });
  assert.equal(g.score, 0);
  assert.equal(g.student_answer, "Resistor → Um sentido; Diodo → sem par");
  assert.throws(() => gradeObjective(as, { pairs: { l1: "r9" } }));
});

Deno.test("dissertativa não é corrigida pelo gabarito objetivo", () => {
  assert.throws(
    () => gradeObjective(q("dissertativa", {}, {}), { text: "..." }),
    (e: unknown) => e instanceof PublicError && e.code === "use_ai",
  );
});

Deno.test("análise segue o formato da IA e leva o erro ao Mapa", () => {
  const a = gradeAnalysis(escolha, gradeObjective(escolha, { choice: "b" }));
  assert.equal(a.is_correct, false);
  assert.deepEqual(a.concepts, ["Lei de Ohm"]);
  assert.deepEqual(a.errors, [{
    category: "interpretacao",
    concept: "Lei de Ohm",
    evidence: "Usou 5 V.",
    confidence: 0.7,
  }]);
  assert.match(a.transcribed_prompt, /Alternativas:\na\) 100 Ω/);
  const fallback = gradeAnalysis(
    escolha,
    gradeObjective(escolha, { choice: "c" }),
  );
  assert.equal(fallback.errors[0].confidence, 0.5);
  assert.match(fallback.errors[0].evidence, /Resposta correta: a\) 100 Ω/);
  assert.match(
    fullPrompt(q("numerica", { unit: "cm" }, {})),
    /Responda em cm\.$/,
  );
});

Deno.test("handler exige a ação answer e repassa ao serviço", async () => {
  const calls: unknown[] = [];
  const handler = createQuestionBankHandler({
    authenticate: () => Promise.resolve("user-1"),
    run: (user, input) => {
      calls.push([user, input]);
      return Promise.resolve({ status: "graded" });
    },
  });
  const post = (body: unknown) =>
    handler(
      new Request("http://x/question-bank", {
        method: "POST",
        body: JSON.stringify(body),
      }),
    );
  assert.equal((await post({ action: "list" })).status, 400);
  const ok = await post({ action: "answer", question_id: "x" });
  assert.equal(ok.status, 200);
  assert.deepEqual(await ok.json(), { status: "graded" });
  assert.deepEqual(calls, [["user-1", { action: "answer", question_id: "x" }]]);
  const options = await handler(
    new Request("http://x/question-bank", { method: "OPTIONS" }),
  );
  assert.equal(options.status, 204);
});
