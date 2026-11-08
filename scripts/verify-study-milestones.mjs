import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { bridge, createFixture, projectRoot } from "./verify-study-review.mjs";
import {
  freezeStreak,
  weeklySummary,
} from "../supabase/functions/_shared/study_milestones.ts";

const db = await createFixture(), sql = bridge(db);
const migration = (name) =>
  readFile(
    resolve(projectRoot, "appmistakemap/database/supabase/migrations", name),
    "utf8",
  );
await db.exec(
  "CREATE TABLE catalog_exercises(id uuid PRIMARY KEY DEFAULT gen_random_uuid());",
);
await db.exec(
  await migration("20261106020000_learning_platform_commercial.sql"),
);
await db.exec(await migration("20261106080000_study_milestones.sql"));
const user = randomUUID(),
  other = randomUUID(),
  subject = randomUUID(),
  concept = randomUUID(),
  exercise = randomUUID(),
  attempt = randomUUID();
await db.query("INSERT INTO auth.users VALUES($1),($2)", [user, other]);
await db.query(
  "INSERT INTO study_profiles(user_id,stage,timezone) VALUES($1,'superior','America/Sao_Paulo')",
  [user],
);
await db.query(
  "INSERT INTO subjects(id,user_id,name) VALUES($1,$2,'Circuitos')",
  [subject, user],
);
await db.query(
  "INSERT INTO concepts(id,subject_id,name) VALUES($1,$2,'Lei de Ohm')",
  [concept, subject],
);
await db.query(
  "INSERT INTO exercises(id,subject_id,prompt_text) VALUES($1,$2,'Calcule a corrente no circuito do ESP32.')",
  [exercise, subject],
);
await db.query(
  "INSERT INTO attempts(id,exercise_id,user_id) VALUES($1,$2,$3)",
  [attempt, exercise, user],
);
await db.exec(
  "INSERT INTO error_types(name) VALUES('sinal'),('procedimento');",
);
const [{ id: reviewSession }] = (await db.query(
  `INSERT INTO study_sessions(user_id,status,planned_minutes,started_at,completed_at)
  VALUES($1,'completed',5,'2026-11-03T22:00:00Z','2026-11-05T18:00:00Z') RETURNING id`,
  [user],
)).rows;
for (
  const [position, category, rating] of [[0, "sinal", "good"], [
    1,
    "procedimento",
    "again",
  ]]
) {
  const [{ id: error }] = (await db.query(
    `INSERT INTO error_events(attempt_id,concept_id,error_type_id,status)
    VALUES($1,$2,(SELECT id FROM error_types WHERE name=$3),'confirmed') RETURNING id`,
    [attempt, concept, category],
  )).rows;
  const [{ id: item }] = (await db.query(
    `INSERT INTO review_items(user_id,subject_id,concept_id,error_event_id,category)
    VALUES($1,$2,$3,$4,$5) RETURNING id`,
    [user, subject, concept, error, category],
  )).rows;
  await db.query(
    `INSERT INTO study_session_items(session_id,item_id,user_id,position,source_attempt_id,source_error_event_id,prompt_text,evidence,category)
    VALUES($1,$2,$3,$4,$5,$6,'Calcule a corrente no resistor do circuito.','',$7)`,
    [reviewSession, item, user, position, attempt, error, category],
  );
  await db.query(
    `INSERT INTO review_events(user_id,event_id,session_id,item_id,rating,answered_at,elapsed_seconds,payload_hash,next_due_at)
    VALUES($1,$2,$3,$4,$5,'2026-11-04T01:00:00Z',30,repeat('0',64),'2026-11-05T01:00:00Z')`,
    [user, randomUUID(), reviewSession, item, rating],
  );
}
await db.query(
  `INSERT INTO study_sessions(user_id,status,planned_minutes,started_at,completed_at)
  VALUES($1,'completed',5,'2026-11-04T21:00:00Z','2026-11-04T21:10:00Z')`,
  [user],
);
const [a, b, c, d, e, f] = Array.from({ length: 6 }, () => randomUUID());
for (const id of [a, b, c, d, e, f]) {
  await db.query("INSERT INTO catalog_exercises VALUES($1)", [id]);
}
async function catalogSession(owner, created, finished, entries) {
  const id = randomUUID();
  const items = entries.map(([catalog, answer, hint, verdict]) => ({
    id: randomUUID(),
    catalog,
    answer,
    hint,
    verdict,
  }));
  const results = finished
    ? JSON.stringify({
      results: items.map((i) => ({ item_id: i.id, verdict: i.verdict })),
    })
    : null;
  await db.query(
    `INSERT INTO platform_sessions(id,user_id,request_id,request_payload,mode,title,status,total,results,created_at,finished_at)
    VALUES($1,$2,$3,'{}','exam','Circuitos',$4,$5,$6,$7,$8)`,
    [
      id,
      owner,
      randomUUID(),
      finished ? "completed" : "active",
      items.length,
      results,
      created,
      finished,
    ],
  );
  for (const [position, item] of items.entries()) {
    await db.query(
      `INSERT INTO platform_session_items(id,session_id,catalog_exercise_id,position,prompt,subject,theme,difficulty,answer,hint_level)
    VALUES($1,$2,$3,$4,'Calcule a corrente do circuito de uma placa.','Circuitos','Resistência','facil',$5,$6)`,
      [item.id, id, item.catalog, position, item.answer, item.hint],
    );
  }
}
// Opening a prior session exposes the question, even if it was not answered.
await catalogSession(user, "2026-11-02T12:00:00Z", null, [[
  b,
  "",
  0,
  "unanswered",
]]);
await catalogSession(other, "2026-11-01T12:00:00Z", null, [[
  d,
  "",
  0,
  "unanswered",
]]);
await catalogSession(user, "2026-11-04T19:00:00Z", "2026-11-04T19:10:00Z", [[
  e,
  "",
  0,
  "unanswered",
]]);
await catalogSession(user, "2026-11-05T23:30:00Z", "2026-11-06T00:10:00Z", [
  [a, "15 mA", 0, "correct"],
  [b, "15 mA", 0, "correct"],
  [c, "15 mA", 1, "correct"],
  [d, "corrente em miliampères", 0, "needs_review"],
  [e, "", 0, "unanswered"],
]);
await catalogSession(user, "2026-11-06T00:20:00Z", "2026-11-06T00:30:00Z", [[
  a,
  "15 mA",
  0,
  "correct",
]]);
const now = new Date("2026-11-06T01:30:00Z");
let summary = await weeklySummary(sql, user, now);
assert.equal(summary.period.end_date, "2026-11-05");
assert.deepEqual(summary.review, {
  reviews: 2,
  recalled: 1,
  again: 1,
  study_days: 1,
  completed_sessions: 1,
  evidence: "self_report",
  recall_rate: null,
});
assert.deepEqual(summary.practice, {
  new_unassisted_answered: 2,
  matched_reference: 1,
  needs_review: 1,
  evidence: "reviewed_catalog",
});
assert.deepEqual(
  summary.streak.freeze_eligible_dates,
  ["2026-11-04"],
  "Empty sessions do not close a day; offline completion uses answered_at",
);
assert.equal(summary.streak.current_days, 1);
assert.equal(
  (await weeklySummary(sql, other, now)).practice.new_unassisted_answered,
  0,
);
assert.deepEqual(summary.achievements.map((a) => a.earned), [
  true,
  false,
  false,
]);
await assert.rejects(() => freezeStreak(sql, other, "2026-11-04", now), {
  code: "freeze_not_eligible",
});
await assert.rejects(() => freezeStreak(sql, user, "2026-11-02", now), {
  code: "freeze_too_old",
});
await assert.rejects(() => freezeStreak(sql, user, "2026-02-30", now), {
  code: "invalid_freeze_date",
});
summary = await freezeStreak(sql, user, "2026-11-04", now);
assert.equal(summary.streak.current_days, 2);
assert.equal(summary.streak.protected_days, 1);
assert.equal(
  summary.achievements.find((a) => a.id === "week_three_days").count,
  2,
  "Frozen day is not earned activity",
);
assert.equal(
  (await freezeStreak(sql, user, "2026-11-04", now)).freeze_date,
  "2026-11-04",
  "Retry is idempotent",
);
await catalogSession(user, "2026-11-07T13:00:00Z", "2026-11-07T13:20:00Z", [[
  f,
  "15 mA",
  0,
  "correct",
]]);
await assert.rejects(
  () => freezeStreak(sql, user, "2026-11-06", new Date("2026-11-07T14:00:00Z")),
  { code: "freeze_used" },
);
assert.equal(
  (await db.query("SELECT count(*)::int AS n FROM study_streak_freezes"))
    .rows[0].n,
  1,
);
await db.exec(
  `SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','${other}',false);`,
);
assert.equal(
  (await db.query("SELECT count(*)::int AS n FROM study_streak_freezes"))
    .rows[0].n,
  0,
);
await assert.rejects(
  () =>
    db.query(
      "INSERT INTO study_streak_freezes VALUES(gen_random_uuid(),'2026-11-04','2026-11-02','UTC')",
    ),
  /permission denied/,
);
await db.exec("RESET ROLE");
await db.close();
console.log(
  "Study milestones: PostgreSQL period, timezone, offline dates, first exposure, hints, repeat dedupe, qualified days, freeze and RLS passed.",
);
