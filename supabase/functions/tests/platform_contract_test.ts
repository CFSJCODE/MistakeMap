import { strict as assert } from "node:assert";
import {
  compareAnswer,
  csvCell,
  date,
  flag,
  gradeItems,
  hintFor,
  ids,
  integer,
  materialUrl,
  platformAction,
  strings,
  timestamp,
  weeklyPlan,
} from "../_shared/platform_contract.ts";
import { PublicError } from "../_shared/ai_contract.ts";

Deno.test("platform grading confirms only equivalent text or exact decimals", () => {
  assert.equal(compareAnswer(" X = 4 ", "x=4"), "correct");
  assert.equal(compareAnswer("−002,5000", "-2.5"), "correct");
  assert.equal(compareAnswer("-0.00", "0"), "correct");
  assert.equal(
    compareAnswer("9007199254740993", "9007199254740992"),
    "needs_review",
  );
  assert.equal(compareAnswer("1/2", "0.5"), "needs_review");
  assert.equal(compareAnswer("4", "x = 4"), "needs_review");
  assert.equal(compareAnswer("1 m", "1 s"), "needs_review");
  assert.equal(compareAnswer("1 2", "12"), "needs_review");
  assert.equal(compareAnswer("   ", "x = 4"), "unanswered");
});
Deno.test("platform grade preserves uncertainty and assisted evidence", () => {
  const result = gradeItems([
    {
      id: "a",
      answer: "2,00",
      correct_answer: "2",
      explanation: "Revisada",
      hint_level: 0,
    },
    {
      id: "b",
      answer: "1/2",
      correct_answer: "0.5",
      explanation: "Revisada",
      hint_level: 2,
    },
    {
      id: "c",
      answer: "",
      correct_answer: "3",
      explanation: "Revisada",
      hint_level: 0,
    },
  ]);
  assert.equal(result.correct_count, 1);
  assert.equal(result.total, 3);
  assert.equal(result.assisted, true);
  assert.equal(result.results[1].verdict, "needs_review");
  assert.equal(result.results[2].verdict, "unanswered");
});
Deno.test("platform rejects malformed dates, consent and privilege-shaped actions", () => {
  for (
    const value of [undefined, "checkout", "grant_pro", "set_role", "keys", {}]
  ) assert.throws(() => platformAction(value), PublicError);
  for (const value of [null, undefined, 0, "true", "false"]) {
    assert.throws(() => flag({ share: value }, "share"), PublicError);
  }
  assert.equal(flag({ share: false }, "share"), false);
  assert.throws(() => date({ date: "2026-02-30" }, "date"), PublicError);
  assert.throws(() => date({ date: "2026-2-2" }, "date"), PublicError);
  assert.equal(date({ date: "2028-02-29" }, "date"), "2028-02-29");
  assert.throws(
    () => timestamp({ date: "2026-11-06T10:00:00" }, "date"),
    PublicError,
  );
  assert.equal(
    timestamp({ date: "2026-11-06T10:00:00-03:00" }, "date"),
    "2026-11-06T13:00:00.000Z",
  );
  assert.throws(() => integer({ count: 101 }, "count", 1, 100), PublicError);
  assert.throws(() => integer({ count: "5" }, "count", 1, 100), PublicError);
  assert.throws(() => ids({ items: ["not-id"] }, "items"), PublicError);
  assert.throws(
    () =>
      ids(
        { items: Array(11).fill("00000000-0000-4000-8000-000000000001") },
        "items",
      ),
    PublicError,
  );
  assert.throws(
    () =>
      ids(
        { items: Array(2).fill("00000000-0000-4000-8000-000000000001") },
        "items",
      ),
    PublicError,
  );
  assert.deepEqual(
    strings({ values: ["Matemática", "Matemática"] }, "values"),
    ["Matemática"],
  );
});
Deno.test("material links never accept active schemes or embedded credentials", () => {
  for (
    const url of [
      "javascript:alert(1)",
      "data:text/plain,a",
      "file:///a.pdf",
      "http://example.com/a.pdf",
      "https://user:password@example.com/a.pdf",
    ]
  ) {
    assert.throws(() => materialUrl({ url }), PublicError);
  }
  assert.equal(
    materialUrl({ url: "https://example.com/a.pdf#page=4" }),
    "https://example.com/a.pdf#page=4",
  );
});
Deno.test("hint levels do not expose reviewed explanation before the final level", () => {
  const explanation = "RESPOSTA REVISADA: x = 4.";
  for (
    const theme of [
      "Equação do 1º grau",
      "Lei de Ohm",
      "MRUV",
      "Porcentagem",
      "Tema novo",
    ]
  ) {
    assert.ok(!hintFor(theme, 1, explanation).includes("RESPOSTA"));
    assert.ok(!hintFor(theme, 2, explanation).includes("RESPOSTA"));
    assert.equal(hintFor(theme, 3, explanation), explanation);
  }
});
Deno.test("weekly plan uses available subject coverage and admits missing content", () => {
  const now = new Date("2026-11-06T12:00:00Z");
  const themes = [{ subject: "Matemática", theme: "Porcentagem" }, {
    subject: "Física",
    theme: "MRUV",
  }];
  const short = weeklyPlan(["Física"], themes, 15, "2026-11-07", now);
  assert.equal(short.length, 2);
  assert.ok(
    short.every((day) => day.subject === "Física" && day.theme === "MRUV"),
  );
  const missing = weeklyPlan(["Química"], themes, 5, null, now);
  assert.equal(missing.length, 7);
  assert.match(missing[0].theme, /sem cobertura/);
  assert.equal(weeklyPlan([], themes, 15, "2026-11-01", now).length, 0);
});
Deno.test("CSV escapes quotes, newlines and spreadsheet formulas", () => {
  assert.equal(csvCell('a"b'), '"a""b"');
  for (
    const text of [
      '=IMPORTXML("x")',
      "+2+2",
      "-1+2",
      "@SUM(A1:A2)",
      "  =1+1",
      "\tSUM(A1)",
    ]
  ) assert.ok(csvCell(text).startsWith("\"'"));
  assert.equal(csvCell("Estudo\nseguro"), '"Estudo\nseguro"');
});
