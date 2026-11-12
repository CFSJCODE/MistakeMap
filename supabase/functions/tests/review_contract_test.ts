import { strict as assert } from "node:assert";
import {
  answerFingerprint,
  answerInput,
  assertReplay,
  decisionInput,
  duePriority,
  profileInput,
  REVIEW_POLICY,
  scheduleReview,
  sessionCapacity,
} from "../_shared/review_contract.ts";
import { rankConcepts } from "../_shared/ai_contract.ts";
import { handler } from "../review-queue/handler.ts";

const now = new Date("2026-11-06T12:00:00Z");
const answer = {
  session_id: "11111111-1111-4111-8111-111111111111",
  item_id: "22222222-2222-4222-8222-222222222222",
  event_id: "33333333-3333-4333-8333-333333333333",
  rating: "good",
  answered_at: now.toISOString(),
  elapsed_seconds: 60,
};
const profile = {
  stage: "superior",
  daily_minutes: 15,
  timezone: "America/Sao_Paulo",
  subject_ids: [],
  goal: "Prova de circuitos",
  exam_date: "2026-12-02",
  reminders_enabled: false,
};

Deno.test("revisões offline aceitam 30 dias e recusam futuro e data sem fuso", () => {
  assert.equal(
    answerInput({ ...answer, answered_at: "2026-10-08T12:00:00Z" }, now).rating,
    "good",
  );
  for (
    const date of [
      "2026-10-06T12:00:00Z",
      "2026-11-06T12:06:00Z",
      "2026-11-06",
      "2026-11-06T12:00:00",
      "invalid",
      "2026-10-32T12:00:00Z",
    ]
  ) {
    assert.throws(() => answerInput({ ...answer, answered_at: date }, now), {
      code: "invalid_answered_at",
    });
  }
  for (const rating of ["known", "correct", null, 1]) {
    assert.throws(() => answerInput({ ...answer, rating }, now), {
      code: "invalid_rating",
    });
  }
});

Deno.test("fingerprint idempotente normaliza fuso e recusa reuso alterado", async () => {
  const a = await answerFingerprint(answerInput(answer, now));
  const b = await answerFingerprint(
    answerInput({ ...answer, answered_at: "2026-11-06T09:00:00-03:00" }, now),
  );
  assert.equal(a, b);
  assert.doesNotThrow(() => assertReplay(a, b));
  const changed = await answerFingerprint(
    answerInput({ ...answer, rating: "easy" }, now),
  );
  assert.throws(() => assertReplay(a, changed), {
    code: "event_conflict",
    status: 409,
  });
});

Deno.test("agenda tem versão explícita, reaprendizado e carga limitada", () => {
  const failed = scheduleReview(
    90,
    3,
    1,
    "again",
    new Date("2026-02-28T12:00:00Z"),
  );
  assert.equal(failed.due_at, "2026-03-01T12:00:00.000Z");
  assert.equal(failed.interval_days, 1);
  assert.equal(failed.lapses, 2);
  assert.equal(failed.policy_version, REVIEW_POLICY);
  for (const rating of ["again", "hard", "good", "easy"] as const) {
    let state = { interval_days: 0, repetitions: 0, lapses: 0 };
    for (let i = 0; i < 100; i++) {
      state = scheduleReview(
        state.interval_days,
        state.repetitions,
        state.lapses,
        rating,
        now,
      );
      assert.ok(state.interval_days >= 1 && state.interval_days <= 180);
    }
    assert.equal(state.repetitions, 100);
  }
  assert.equal(sessionCapacity(5), 2);
  assert.equal(sessionCapacity(180), 30);
  assert.throws(() => sessionCapacity(0), { code: "invalid_number" });
  assert.throws(() => sessionCapacity(181), { code: "invalid_number" });
});

Deno.test("perfil valida calendário, fuso, carga e preferências sem inferência", () => {
  assert.deepEqual(profileInput(profile), profile);
  for (
    const patch of [
      { exam_date: "2026-02-30" },
      { exam_date: "0000-01-01" },
      { timezone: "Not/A_Zone" },
      { daily_minutes: 4 },
      { daily_minutes: 200 },
      { reminders_enabled: "yes" },
      { goal: "x".repeat(241) },
      { stage: "teacher" },
      { subject_ids: ["not-a-uuid"] },
    ]
  ) assert.throws(() => profileInput({ ...profile, ...patch }));
});

Deno.test("sugestões pendentes e rejeitadas não entram no ranking; importância é explícita", () => {
  const ranked = rankConcepts(
    [
      {
        concept: "Pendente",
        category: "conceito",
        at: now,
        status: "pending",
        importance: 2,
      },
      {
        concept: "Rejeitado",
        category: "sinal",
        at: now,
        status: "rejected",
        importance: 2,
      },
      { concept: "Neutro", category: "sinal", at: now, status: "confirmed" },
      {
        concept: "Objetivo escolhido",
        category: "conceito",
        at: now,
        status: "confirmed",
        importance: 2,
      },
      {
        concept: "Data inválida",
        category: "outro",
        at: new Date("invalid"),
        status: "confirmed",
      },
    ],
    [],
    now,
  );
  assert.deepEqual(ranked.map((r) => r.concept), [
    "Objetivo escolhido",
    "Neutro",
  ]);
  assert.equal(ranked[0].score, 2);
  assert.equal(ranked[1].score, 1);
  assert.ok(
    duePriority(new Date("2026-11-01T12:00:00Z"), 1, now) >
      duePriority(now, 2, now),
  );
});

Deno.test("decisões exigem ato explícito e categoria válida", () => {
  assert.throws(
    () =>
      decisionInput({ error_event_id: answer.item_id, decision: "timeout" }),
    { code: "invalid_decision" },
  );
  assert.throws(
    () =>
      decisionInput({
        error_event_id: answer.item_id,
        decision: "confirmed",
        category: "attention",
      }),
    { code: "invalid_category" },
  );
  assert.throws(
    () =>
      decisionInput({
        error_event_id: answer.item_id,
        decision: "confirmed",
        importance: 10,
      }),
    { code: "invalid_importance" },
  );
  assert.equal(
    decisionInput({ error_event_id: answer.item_id, decision: "rejected" })
      .decision,
    "rejected",
  );
});

Deno.test("review-queue recusa acesso sem sessão antes de banco e aceita preflight", async () => {
  const unauth = await handler(
    new Request("https://example.invalid", {
      method: "POST",
      body: JSON.stringify({ action: "dashboard" }),
    }),
  );
  assert.equal(unauth.status, 401);
  assert.deepEqual(await unauth.json(), {
    error: "unauthorized",
    message: "Entre na sua conta para continuar.",
  });
  assert.equal(
    (await handler(new Request("https://example.invalid"))).status,
    405,
  );
  assert.equal(
    (await handler(
      new Request("https://example.invalid", { method: "OPTIONS" }),
    )).status,
    204,
  );
});
