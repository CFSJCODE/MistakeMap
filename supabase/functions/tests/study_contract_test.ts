import { strict as assert } from "node:assert";
import { PublicError } from "../_shared/ai_contract.ts";
import {
  gradeQuiz,
  quizAnswers,
  splitQuiz,
  studyAction,
  validateStudy,
} from "../_shared/study_contract.ts";
import { handler as studyHandler } from "../study-material/handler.ts";

const question = (n: number) => ({
  prompt: `Questão ${n}?`,
  options: ["a", "b", "c", "d"],
  correct_choice: n % 4,
  explanation: "Porque sim.",
  concept: "Frações",
});
const sample = () => ({
  summary: {
    title: "Frações",
    overview: "Partes de um todo.",
    key_points: ["Numerador", "Denominador", "Equivalência"],
    common_mistakes: ["Somar denominadores"],
  },
  flashcards: Array.from({ length: 6 }, (_, i) => ({
    front: `Frente ${i}`,
    back: `Verso ${i}`,
    concept: "Frações",
  })),
  quiz: Array.from({ length: 5 }, (_, i) => question(i)),
});

Deno.test("material válido passa na validação", () => {
  const material = validateStudy(sample());
  assert.equal(material.quiz.length, 5);
  assert.equal(material.flashcards.length, 6);
});

Deno.test("material com alternativas repetidas ou gabarito fora do intervalo é recusado", () => {
  const repeated = sample();
  repeated.quiz[0].options = ["a", "a", "c", "d"];
  assert.throws(() => validateStudy(repeated), PublicError);
  const outOfRange = sample();
  outOfRange.quiz[1].correct_choice = 4;
  assert.throws(() => validateStudy(outOfRange), PublicError);
  const few = sample();
  few.flashcards = few.flashcards.slice(0, 2);
  assert.throws(() => validateStudy(few), PublicError);
});

Deno.test("o quiz público não carrega o gabarito", () => {
  const { publicQuiz, keys } = splitQuiz(validateStudy(sample()).quiz);
  assert.equal(publicQuiz.length, keys.length);
  for (const q of publicQuiz) {
    assert.ok(!("correct_choice" in q));
    assert.ok(!("explanation" in q));
  }
  assert.equal(publicQuiz[2].id, keys[2].id);
});

Deno.test("correção conta acertos e trata questão sem resposta como erro", () => {
  const keys = [
    { id: "a", correct_choice: 1, explanation: "x" },
    { id: "b", correct_choice: 2, explanation: "y" },
    { id: "c", correct_choice: 0, explanation: "z" },
  ];
  const graded = gradeQuiz(keys, new Map([["a", 1], ["b", 3]]));
  assert.equal(graded.correct_count, 1);
  assert.equal(graded.total, 3);
  assert.equal(graded.results[2].choice, null);
  assert.equal(graded.results[2].is_correct, false);
});

Deno.test("respostas e ação inválidas são recusadas", () => {
  const id = crypto.randomUUID();
  assert.equal(quizAnswers([{ question_id: id, choice: 2 }]).get(id), 2);
  assert.throws(
    () => quizAnswers([{ question_id: id, choice: 7 }]),
    PublicError,
  );
  assert.throws(
    () => quizAnswers([{ question_id: "x", choice: 1 }]),
    PublicError,
  );
  assert.throws(() => quizAnswers("nada"), PublicError);
  assert.throws(() => studyAction("delete"), PublicError);
});

Deno.test("study-material exige login", async () => {
  Deno.env.set("ALLOWED_ORIGINS", "https://app.example");
  const response = await studyHandler(
    new Request("https://fn.example/study-material", {
      method: "POST",
      headers: { origin: "https://app.example" },
      body: JSON.stringify({ action: "generate" }),
    }),
  );
  assert.equal(response.status, 401);
  await response.body?.cancel();
});
