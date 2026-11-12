import { strict as assert } from "node:assert";
import {
  type ActivityRow,
  assignmentCsv,
  buildAssignmentResult,
  buildClassMap,
  type ErrorRow,
  MIN_STUDENTS,
  normalizeConcept,
} from "../_shared/class_map.ts";
import { PLATFORM_ACTIONS } from "../_shared/platform_contract.ts";

const students = (n: number) =>
  Array.from(
    { length: n },
    (_, i) => `00000000-0000-4000-8000-00000000000${i}`,
  );
function activity(ids: string[], weeks = [0]): ActivityRow[] {
  return ids.flatMap((student) =>
    weeks.map((weeks_ago) => ({ student, weeks_ago }))
  );
}
function error(
  student: string,
  concept: string,
  error_type = "calculo",
  weeks_ago = 0,
  errors = 1,
): ErrorRow {
  return {
    student,
    concept_key: concept.toLowerCase(),
    concept,
    subject: "Eletrônica",
    error_type,
    weeks_ago,
    errors,
  };
}

Deno.test("class map stays hidden below five active students and leaks nothing", () => {
  const ids = students(MIN_STUDENTS - 1);
  const map = buildClassMap(
    ids.map((s) => error(s, "Lei de Ohm")),
    activity(ids),
    10,
  );
  assert.equal(map.eligible, false);
  assert.deepEqual(map.grid, []);
  assert.deepEqual(map.top_concepts, []);
  assert.deepEqual(map.trend, []);
  assert.equal(map.students_with_data, 4);
  assert.ok(!JSON.stringify(map).includes(ids[0]));
});

Deno.test("class map aggregates concept x error type without student ids", () => {
  const ids = students(6);
  const rows = [
    ...ids.map((s) => error(s, "Lei de Ohm", "calculo")),
    error(ids[0], "lei de ohm ", "unidade", 1, 2),
    error(ids[1], "PWM", "conceito", 3, 4),
    error(ids[2], "PWM", "conceito", 2),
    error(ids[3], "Divisor de tensão", "nao_existe"),
  ];
  const map = buildClassMap(rows, activity(ids, [0, 1, 2, 3]), 6, {
    "lei de ohm": 3,
  });
  assert.equal(map.eligible, true);
  assert.ok(!JSON.stringify(map).includes("00000000-0000-4000"));
  const ohm = map.grid[0];
  assert.equal(ohm.concept_key, "lei de ohm");
  assert.equal(ohm.students, 6);
  assert.equal(ohm.errors, 8);
  assert.equal(ohm.by_type.calculo, 6);
  assert.equal(ohm.by_type.unidade, 2);
  assert.equal(ohm.main_error_type, "calculo");
  assert.equal(ohm.questions_available, 3);
  // weekly[0] é a semana mais antiga; weekly[3], a atual.
  assert.deepEqual(ohm.weekly, [0, 0, 2, 6]);
  assert.equal(map.grid[1].concept, "PWM");
  assert.deepEqual(map.grid[1].weekly, [4, 1, 0, 0]);
  assert.equal(map.grid[2].by_type.outro, 1);
  assert.equal(map.top_concepts.length, 3);
  assert.deepEqual(map.trend.map((t) => t.errors), [4, 1, 2, 7]);
  assert.deepEqual(map.trend.map((t) => t.active_students), [6, 6, 6, 6]);
  assert.equal(map.trend[3].weeks_ago, 0);
});

Deno.test("top concepts rank by students affected, then by errors", () => {
  const ids = students(7);
  const rows = [
    error(ids[0], "Sensor", "calculo", 0, 50),
    ...ids.slice(0, 5).map((s) => error(s, "Ponte H")),
    ...ids.map((s, i) => error(s, `Conceito ${i}`)),
  ];
  const map = buildClassMap(rows, activity(ids), 7);
  assert.equal(map.top_concepts.length, 5);
  assert.equal(map.top_concepts[0].concept, "Ponte H");
  assert.ok(map.grid.length <= 12);
});

Deno.test("concept normalization ignores case and spacing", () => {
  assert.equal(normalizeConcept("  Lei   de OHM "), "lei de ohm");
});

const questions = ["q1", "q2"].map((id, i) => ({
  id,
  prompt_text: `Questão ${i + 1} sobre o divisor de tensão do sensor`,
  kind: "multipla_escolha",
  theme: "Divisor de tensão",
}));

Deno.test("assignment result hides per-question accuracy below five respondents", () => {
  const ids = students(4);
  const result = buildAssignmentResult(
    questions,
    ids.map((student, i) => ({ student, share_progress: i === 0 })),
    ids.map((student) => ({ student, question_id: "q1", is_correct: true })),
    [{ error_type: "calculo", concept: "Divisor de tensão", errors: 2 }],
  );
  assert.equal(result.eligible, false);
  assert.equal(result.respondents, 4);
  assert.equal(result.questions[0].accuracy, null);
  assert.deepEqual(result.common_errors, []);
  assert.equal(result.participants[0].correct, 1);
  assert.equal(result.participants[1].correct, null);
  assert.equal(result.participants[1].status, "in_progress");
  assert.ok(!JSON.stringify(result).includes(ids[0]));
});

Deno.test("assignment result counts latest answers, pending essays and status", () => {
  const ids = students(6);
  const responses = [
    // Mais recente primeiro: o aluno 0 errou e depois acertou a q1.
    { student: ids[0], question_id: "q1", is_correct: true },
    { student: ids[0], question_id: "q1", is_correct: false },
    { student: ids[0], question_id: "q2", is_correct: null },
    ...ids.slice(1, 5).map((student) => ({
      student,
      question_id: "q1",
      is_correct: false,
    })),
    { student: "fora-da-turma", question_id: "q1", is_correct: true },
  ];
  const result = buildAssignmentResult(
    questions,
    ids.map((student) => ({ student, share_progress: true })),
    responses,
    [
      { error_type: "unidade", concept: "Divisor", errors: 1 },
      { error_type: "calculo", concept: "Divisor", errors: 4 },
    ],
  );
  assert.equal(result.eligible, true);
  assert.equal(result.respondents, 5);
  assert.equal(result.completed, 1);
  assert.equal(result.participants[5].status, "not_started");
  assert.equal(result.questions[0].responses, 5);
  assert.equal(result.questions[0].correct, 1);
  assert.equal(result.questions[0].accuracy, 20);
  // A q2 tem só 1 resposta: o acerto dela fica oculto.
  assert.equal(result.questions[1].responses, 1);
  assert.equal(result.questions[1].pending, null);
  assert.equal(result.questions[1].accuracy, null);
  assert.equal(result.common_errors[0].error_type, "calculo");
  const csv = assignmentCsv("=Treinar: Divisor", result);
  assert.ok(csv.startsWith('"Tarefa";"\'=Treinar: Divisor"'));
  assert.ok(csv.includes('"Participante 6";"Não começou";"0/2";"0"'));
  assert.ok(!csv.includes(ids[0]));
});

Deno.test("platform contract exposes the class map actions", () => {
  for (
    const action of [
      "class_map",
      "create_concept_assignment",
      "assignment_result",
    ]
  ) {
    assert.ok((PLATFORM_ACTIONS as readonly string[]).includes(action));
  }
});
