// Run with Node >=24 --experimental-transform-types and PGLITE_MODULE pointing
// to a separately installed @electric-sql/pglite module. No production access.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { reviewOperation } from "../supabase/functions/_shared/review_service.ts";

export const projectRoot = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
);
export async function createFixture() {
  if (!process.env.PGLITE_MODULE) {
    throw new Error(
      "PGLITE_MODULE must point to an isolated @electric-sql/pglite installation.",
    );
  }
  const { PGlite } = await import(
    pathToFileURL(resolve(process.env.PGLITE_MODULE)).href
  );
  const db = new PGlite();
  await db.exec(
    `CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role BYPASSRLS;
    CREATE SCHEMA auth; CREATE TABLE auth.users(id uuid PRIMARY KEY);
    CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$ SELECT current_user::text $$;
    GRANT USAGE ON SCHEMA auth TO authenticated,anon,service_role;
    GRANT EXECUTE ON FUNCTION auth.uid(),auth.role() TO authenticated,anon,service_role;`,
  );
  const base = await readFile(
    resolve(
      projectRoot,
      "appmistakemap/database/supabase/migrations/20260901163259_create_initial_schema.sql",
    ),
    "utf8",
  );
  await db.exec(
    base.replace(
      /create extension if not exists "pgcrypto" with schema extensions;/i,
      "",
    ),
  );
  await db.exec(
    await readFile(
      resolve(
        projectRoot,
        "appmistakemap/database/supabase/migrations/20261106010000_study_review.sql",
      ),
      "utf8",
    ),
  );
  return db;
}

// A very small postgres.js tagged-template adapter for an embedded real
// PostgreSQL engine. It exercises SQL, constraints, RLS and transactions.
export function bridge(client) {
  const tag = (strings, ...values) => {
    if (!Array.isArray(strings) || !Object.hasOwn(strings, "raw")) {
      return { fragment: strings };
    }
    let text = "";
    const params = [];
    const bind = (value) => {
      if (
        value && typeof value === "object" && Object.hasOwn(value, "fragment")
      ) {
        if (!Array.isArray(value.fragment)) {
          throw new Error("Unsupported fragment");
        }
        return "(" + value.fragment.map(bind).join(",") + ")";
      }
      params.push(value);
      return "$" + params.length;
    };
    for (let i = 0; i < strings.length; i++) {
      text += strings[i] + (i < values.length ? bind(values[i]) : "");
    }
    return client.query(text, params).then((result) => result.rows);
  };
  tag.array = (value) => value;
  tag.json = (value) => JSON.stringify(value);
  tag.begin = (fn) => client.transaction((tx) => fn(bridge(tx)));
  tag.end = async () => {};
  return tag;
}

export async function verifyStudyReview() {
  const db = await createFixture();
  const sql = bridge(db);
  const user = "11111111-1111-4111-8111-111111111111";
  const other = "22222222-2222-4222-8222-222222222222";
  const subject = "33333333-3333-4333-8333-333333333333";
  const concept = "44444444-4444-4444-8444-444444444444";
  const exercise = "55555555-5555-4555-8555-555555555555";
  const attempt = "66666666-6666-4666-8666-666666666666";
  const diagnostic = "77777777-7777-4777-8777-777777777777";
  await db.query("INSERT INTO auth.users(id) VALUES ($1),($2)", [user, other]);
  await db.query("INSERT INTO subjects(id,user_id,name) VALUES($1,$2,$3)", [
    subject,
    user,
    "Circuitos Elétricos",
  ]);
  await db.query("INSERT INTO concepts(id,subject_id,name) VALUES($1,$2,$3)", [
    concept,
    subject,
    "Lei de Ohm",
  ]);
  await db.query(
    "INSERT INTO exercises(id,subject_id,prompt_text) VALUES($1,$2,$3)",
    [
      exercise,
      subject,
      "Um ESP32 fornece 3,3 V a um resistor de 220 Ω. Qual a corrente?",
    ],
  );
  await db.query(
    "INSERT INTO attempts(id,exercise_id,user_id) VALUES($1,$2,$3)",
    [attempt, exercise, user],
  );
  await db.exec(
    `INSERT INTO error_types(name) VALUES('sinal'),('procedimento'),('conceito'),('calculo'),('interpretacao'),('unidade'),('outro');`,
  );
  await db.query(
    `INSERT INTO error_events(id,attempt_id,concept_id,error_type_id,evidence_ref,created_at)
    VALUES($1,$2,$3,(SELECT id FROM error_types WHERE name='sinal'),'Troca de sinal na tensão.',now()-interval '7 days')`,
    [diagnostic, attempt, concept],
  );
  await db.query(
    "INSERT INTO corrections(attempt_id,reference_text) VALUES($1,$2)",
    [attempt, "I = 3,3 / 220 = 0,015 A."],
  );
  const op = (action, input = {}, owner = user) =>
    reviewOperation(sql, owner, action, input);
  assert.equal(
    (await op("dashboard")).due_count,
    0,
    "Silence never confirms a diagnosis",
  );
  assert.equal((await op("dashboard")).pending_diagnostics, 1);
  assert.equal((await op("start_session")).session, null);
  await assert.rejects(
    () =>
      op(
        "decide",
        { error_event_id: diagnostic, decision: "confirmed" },
        other,
      ),
    { code: "diagnostic_not_found" },
  );
  await assert.rejects(
    () =>
      op("save_profile", {
        profile: {
          stage: "superior",
          daily_minutes: 15,
          timezone: "America/Sao_Paulo",
          subject_ids: [subject],
          goal: "Prova",
          exam_date: null,
          reminders_enabled: false,
        },
      }, other),
    { code: "subject_not_found" },
  );
  await op("save_profile", {
    profile: {
      stage: "superior",
      daily_minutes: 15,
      timezone: "America/Sao_Paulo",
      subject_ids: [subject],
      goal: "Preparar a prova de circuitos",
      exam_date: null,
      reminders_enabled: false,
    },
  });
  assert.equal((await op("profile")).profile.subject_ids[0], subject);
  await op("decide", {
    error_event_id: diagnostic,
    decision: "confirmed",
    category: "procedimento",
    importance: 1.5,
  });
  assert.equal((await op("diagnostics")).items[0].category, "procedimento");
  assert.equal((await op("dashboard")).due_count, 1);
  const { session } = await op("start_session", { minutes: 5 });
  assert.equal(session.items.length, 1);
  assert.equal(
    (await op("start_session")).session.id,
    session.id,
    "Resume persisted session",
  );
  assert.ok(
    !JSON.stringify(session).includes("0,015"),
    "No reference before reveal",
  );
  const item = session.items[0];
  await assert.rejects(() => op("session", { session_id: session.id }, other), {
    code: "session_not_found",
  });
  assert.match(
    (await op("session", { session_id: session.id, reveal_item_id: item.id }))
      .reference_text,
    /0,015/,
  );
  const payload = {
    session_id: session.id,
    item_id: item.id,
    event_id: "88888888-8888-4888-8888-888888888888",
    rating: "good",
    answered_at: new Date().toISOString(),
    elapsed_seconds: 30,
  };
  const answered = await op("answer", payload);
  assert.equal(answered.session.status, "completed");
  assert.equal(answered.duplicate, false);
  assert.equal(
    (await op("answer", payload)).duplicate,
    true,
    "Lost response can be replayed safely",
  );
  assert.equal(
    (await db.query("SELECT count(*)::int AS n FROM review_events")).rows[0].n,
    1,
  );
  assert.equal(
    (await db.query("SELECT repetitions FROM review_items")).rows[0]
      .repetitions,
    1,
    "Replay cannot advance schedule",
  );
  await assert.rejects(() => op("answer", { ...payload, rating: "easy" }), {
    code: "event_conflict",
  });
  await assert.rejects(
    () =>
      op("answer", {
        ...payload,
        event_id: "99999999-9999-4999-8999-999999999999",
      }),
    { code: "event_conflict" },
  );
  assert.equal(
    (await op("dashboard")).progress.recall_rate,
    null,
    "Small sample has no rate",
  );
  assert.equal((await op("dashboard")).reviewed_today, 1);
  await op("decide", { error_event_id: diagnostic, decision: "rejected" });
  assert.equal(
    (await db.query("SELECT active FROM review_items")).rows[0].active,
    false,
    "Rejected difficulty leaves active agenda",
  );
  assert.equal((await op("dashboard")).due_count, 0);
  // A large queue produces a bounded session, rather than an unbounded payload.
  await db.query(
    `INSERT INTO concepts(subject_id,name) SELECT $1,'Habilidade tecnológica '||n FROM generate_series(1,45) n`,
    [subject],
  );
  await db.query(
    `INSERT INTO error_events(attempt_id,concept_id,error_type_id,status,evidence_ref)
    SELECT $1,c.id,(SELECT id FROM error_types WHERE name='procedimento'),'confirmed','Etapa confirmada na resolução do circuito'
    FROM concepts c WHERE c.subject_id=$2 AND c.id<>$3`,
    [attempt, subject, concept],
  );
  await db.query(
    `INSERT INTO review_items(user_id,subject_id,concept_id,error_event_id,category)
    SELECT $1,$2,ee.concept_id,ee.id,'procedimento' FROM error_events ee WHERE ee.attempt_id=$3 AND ee.status='confirmed'`,
    [user, subject, attempt],
  );
  assert.equal((await op("dashboard")).due_count, 45);
  const loaded = (await op("start_session", { minutes: 180 })).session;
  assert.equal(
    loaded.items.length,
    30,
    "A 45-item backlog never makes an unbounded session",
  );
  const [{ error_event_id: sourceError }] =
    (await db.query("SELECT error_event_id FROM review_items WHERE id=$1", [
      loaded.items[0].id,
    ])).rows;
  await op("decide", { error_event_id: sourceError, decision: "rejected" });
  assert.equal(
    (await op("session", { session_id: loaded.id })).session.items[0].skipped,
    true,
    "Rejected item is skipped in an already persisted session",
  );
  await db.exec(
    `SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','${other}',false);`,
  );
  for (
    const table of [
      "study_profiles",
      "review_items",
      "study_sessions",
      "study_session_items",
      "review_events",
      "error_event_decisions",
    ]
  ) {
    assert.equal(
      (await db.query(`SELECT count(*)::int AS n FROM public.${table}`)).rows[0]
        .n,
      0,
      `RLS ${table}`,
    );
  }
  await assert.rejects(
    () => db.query("UPDATE review_items SET repetitions=1000"),
    /permission denied/,
  );
  await db.exec("RESET ROLE;");
  await db.close();
  console.log(
    "Study review: real PostgreSQL schema, transactions, ownership, RLS, explicit decisions, replay and progression passed.",
  );
}

if (
  process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) await verifyStudyReview();
