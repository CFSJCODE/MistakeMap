import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { bridge, createFixture, projectRoot } from "./verify-study-review.mjs";
import { reviewOperation } from "../supabase/functions/_shared/review_service.ts";

const db = await createFixture(), sql = bridge(db);
await db.exec(
  `CREATE TABLE attempt_analyses(attempt_id uuid PRIMARY KEY REFERENCES attempts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,subject_id uuid REFERENCES subjects(id),
  analysis jsonb NOT NULL,model text NOT NULL,pipeline_version text NOT NULL,created_at timestamptz DEFAULT now());
  ALTER TABLE attempt_analyses ENABLE ROW LEVEL SECURITY;
  CREATE POLICY owner_read ON attempt_analyses FOR SELECT TO authenticated USING(user_id=auth.uid());
  GRANT SELECT ON attempt_analyses,attempts,error_events,concepts,subjects,error_types TO authenticated;`,
);
await db.exec(
  await readFile(
    resolve(
      projectRoot,
      "appmistakemap/database/supabase/migrations/20261106070000_student_attempt_analyses.sql",
    ),
    "utf8",
  ),
);
const user = randomUUID(),
  other = randomUUID(),
  subject = randomUUID(),
  concept = randomUUID(),
  exercise = randomUUID(),
  attempt = randomUUID();
await db.query("INSERT INTO auth.users VALUES($1),($2)", [user, other]);
await db.query(
  "INSERT INTO subjects(id,user_id,name) VALUES($1,$2,'Eletrônica')",
  [subject, user],
);
await db.query(
  "INSERT INTO concepts(id,subject_id,name) VALUES($1,$2,'Lei de Ohm')",
  [concept, subject],
);
await db.query(
  "INSERT INTO exercises(id,subject_id,prompt_text) VALUES($1,$2,'Um ESP32 alimenta um LED por resistor. Calcule a corrente.')",
  [exercise, subject],
);
await db.query(
  "INSERT INTO attempts(id,exercise_id,user_id) VALUES($1,$2,$3)",
  [attempt, exercise, user],
);
await db.exec(
  "INSERT INTO error_types(name) VALUES('sinal'),('conceito'),('procedimento');",
);
const raw = {
  is_correct: false,
  errors: [{
    concept: "Lei de Ohm",
    category: "sinal",
    evidence: "Trocou o sinal",
    confidence: .8,
  }, {
    concept: "Lei de Ohm",
    category: "conceito",
    evidence: "Escolheu a relação inadequada",
    confidence: .7,
  }],
  concepts: ["Lei de Ohm"],
};
await db.query(
  "INSERT INTO attempt_analyses(attempt_id,user_id,subject_id,analysis,model,pipeline_version) VALUES($1,$2,$3,$4,'fixture','fixture')",
  [attempt, user, subject, JSON.stringify(raw)],
);
const [first] = (await db.query(
  "INSERT INTO error_events(attempt_id,concept_id,error_type_id,evidence_ref,confidence) VALUES($1,$2,(SELECT id FROM error_types WHERE name='sinal'),'Trocou o sinal',.8) RETURNING id",
  [attempt, concept],
)).rows;
const [second] = (await db.query(
  "INSERT INTO error_events(attempt_id,concept_id,error_type_id,evidence_ref,confidence) VALUES($1,$2,(SELECT id FROM error_types WHERE name='conceito'),'Escolheu a relação inadequada',.7) RETURNING id",
  [attempt, concept],
)).rows;
const view = async (owner = user) => {
  await db.exec(
    `SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','${owner}',false);`,
  );
  try {
    return (await db.query("SELECT * FROM student_attempt_analyses")).rows;
  } finally {
    await db.exec("RESET ROLE");
  }
};
let rows = await view();
assert.equal(rows[0].analysis.errors.length, 2);
assert.equal(rows[0].analysis.diagnostic_status, "suggested");
assert.equal(rows[0].analysis.errors[0].status, "pending");
assert.equal(
  (await view(other)).length,
  0,
  "Invoker RLS hides another learner",
);
await reviewOperation(sql, user, "decide", {
  error_event_id: first.id,
  decision: "rejected",
});
rows = await view();
assert.equal(
  rows[0].analysis.errors.length,
  1,
  "Reject removes error from Map source",
);
await reviewOperation(sql, user, "decide", {
  error_event_id: second.id,
  decision: "confirmed",
  category: "procedimento",
});
rows = await view();
assert.equal(rows[0].analysis.errors[0].category, "procedimento");
assert.equal(rows[0].analysis.errors[0].status, "confirmed");
assert.equal(rows[0].analysis.diagnostic_status, "confirmed");
assert.deepEqual(
  (await db.query("SELECT analysis FROM attempt_analyses")).rows[0].analysis,
  raw,
  "Original diagnostic was not rewritten",
);
await db.exec("SET ROLE anon");
await assert.rejects(
  () => db.query("SELECT * FROM student_attempt_analyses"),
  /permission denied/,
);
await db.exec("RESET ROLE");
await db.close();
console.log(
  "Student analysis view: real PostgreSQL invoker RLS, pending labels, rejection, correction and raw preservation passed.",
);
