import { strict as assert } from "node:assert";
import { PGlite } from "./node_modules/@electric-sql/pglite/dist/index.js";
import {
  analyzeAttempt,
  generatePractice,
} from "../staged/supabase/functions/_shared/ai_service.ts";

type Queryable = {
  query: (
    query: string,
    params?: unknown[],
  ) => Promise<{ rows: unknown[]; affectedRows?: number }>;
  transaction?: (fn: (tx: Queryable) => Promise<unknown>) => Promise<unknown>;
};
function sqlAdapter(db: Queryable): Parameters<typeof analyzeAttempt>[0] {
  const tag = async (parts: TemplateStringsArray, ...values: unknown[]) => {
    const text = parts.reduce(
      (query, part, i) => query + (i ? `$${i}` : "") + part,
      "",
    );
    const result = await db.query(text, values);
    return Object.assign(result.rows, {
      count: result.affectedRows ?? result.rows.length,
    });
  };
  Object.assign(tag, {
    begin: async (
      fn: (tx: Parameters<typeof analyzeAttempt>[0]) => Promise<unknown>,
    ) => {
      if (!db.transaction) {
        throw new Error("Nested transaction unsupported in test adapter");
      }
      return await db.transaction((tx) => fn(sqlAdapter(tx)));
    },
  });
  return tag as unknown as Parameters<typeof analyzeAttempt>[0];
}
const root = new URL("../../../", import.meta.url);
const read = (path: string) => Deno.readTextFile(new URL(path, root));
const userA = "10000000-0000-4000-8000-000000000001";
const userB = "10000000-0000-4000-8000-000000000002";
const subject = "20000000-0000-4000-8000-000000000001";
const exercise = "30000000-0000-4000-8000-000000000001";
const attempt = "40000000-0000-4000-8000-000000000001";
const failedAttempt = "40000000-0000-4000-8000-000000000002";
const expiredAttempt = "40000000-0000-4000-8000-000000000003";
const analysis = {
  is_correct: false,
  correct_answer: "4",
  explanation: "Some dois e dois para chegar a quatro.",
  transcribed_prompt: "2+2?",
  transcribed_answer: "5",
  errors: [{
    category: "calculo",
    concept: "Adição",
    evidence: "2+2 = 5",
    confidence: 0.9,
  }],
  concepts: ["Adição"],
};

Deno.test({
  name:
    "vertical service with real local PostgreSQL semantics and mocked Responses",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async (t) => {
    const db = new PGlite();
    const nativeFetch = globalThis.fetch;
    let providerCalls = 0;
    let providerFailure = false;
    try {
      await db.exec(`
      create role anon;create role authenticated;create role service_role bypassrls;
      create schema auth;create schema extensions;create table auth.users(id uuid primary key);
      create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
      create function auth.role() returns text language sql stable as $$ select current_setting('role',true) $$;
      grant usage on schema auth,public to anon,authenticated,service_role;
      create function public.enforce_rate_limit() returns trigger language plpgsql as $$ begin return new;end $$;
    `);
      await db.exec(
        (await read(
          "appmistakemap/database/supabase/migrations/20260901163259_create_initial_schema.sql",
        )).replace(
          'create extension if not exists "pgcrypto" with schema extensions;',
          "",
        ),
      );
      await db.exec(
        await read(
          "appmistakemap/database/supabase/migrations/20260910023647_create_ingestion_pipeline_tables.sql",
        ),
      );
      await db.exec(
        await read(
          "appmistakemap/database/supabase/migrations/20260914120000_create_r2_quota_tracking.sql",
        ),
      );
      await db.exec(
        "grant all on all tables in schema public to authenticated,service_role;",
      );
      await db.exec(
        await read(
          "_reversa_forward/openai-integration/staged/supabase/change.sql",
        ),
      );
      await db.exec(`insert into auth.users values('${userA}'),('${userB}');
      insert into subjects(id,user_id,name) values('${subject}','${userA}','Matemática');
      insert into exercises(id,subject_id,prompt_text) values('${exercise}','${subject}','2+2?');
      insert into attempts(id,exercise_id,user_id,answer,status) values
      ('${attempt}','${exercise}','${userA}','5','pending'),('${failedAttempt}','${exercise}','${userA}','5','pending'),('${expiredAttempt}','${exercise}','${userA}','5','pending');`);
      Deno.env.set("OPENAI_API_KEY", "test-only-placeholder");
      Deno.env.set("OPENAI_MODEL", "test-model");
      globalThis.fetch =
        (async (input: RequestInfo | URL, init?: RequestInit) => {
          assert.equal(
            String(input),
            "https://api.openai.com/v1/responses",
            "test must never reach real network",
          );
          providerCalls++;
          if (providerFailure) {
            return new Response("private-upstream-failure", { status: 500 });
          }
          const request = JSON.parse(String(init?.body));
          const result = request.text.format.name === "mistakemap_practice"
            ? {
              exercises: Array.from(
                { length: 3 },
                (_, i) => ({
                  prompt_text: `Calcule ${i}+1`,
                  difficulty: "facil",
                  focus_concept: "Adição",
                  correct_answer: String(i + 1),
                  explanation: "Some uma unidade.",
                }),
              ),
            }
            : analysis;
          return new Response(
            JSON.stringify({
              status: "completed",
              output: [{
                type: "message",
                content: [{
                  type: "output_text",
                  text: JSON.stringify(result),
                }],
              }],
            }),
          );
        }) as typeof fetch;
      const sql = sqlAdapter(db as unknown as Queryable);

      await t.step(
        "text-only analysis persists correction, evidence and real status atomically",
        async () => {
          const result = await analyzeAttempt(sql, attempt, userA);
          assert.equal(result.status, "completed");
          assert.equal(providerCalls, 1);
          const state = await db.query(
            "select status,version from attempts where id=$1",
            [attempt],
          );
          assert.deepEqual(state.rows, [{ status: "completed", version: 3 }]);
          assert.equal(
            (await db.query(
              "select * from attempt_analyses where attempt_id=$1",
              [attempt],
            )).rows.length,
            1,
          );
          assert.equal(
            (await db.query("select * from corrections where attempt_id=$1", [
              attempt,
            ])).rows.length,
            1,
          );
          assert.equal(
            (await db.query(
              "select * from error_events where attempt_id=$1 and status='pending'",
              [attempt],
            )).rows.length,
            1,
          );
          assert.equal(
            (await db.query(
              "select * from exercise_concepts where exercise_id=$1",
              [exercise],
            )).rows.length,
            1,
          );
        },
      );
      await t.step(
        "cache prevents a repeated API charge or duplicated events",
        async () => {
          const result = await analyzeAttempt(sql, attempt, userA);
          assert.equal(result.status, "completed");
          assert.equal(providerCalls, 1);
          assert.deepEqual(
            (await db.query(
              "select requests from ai_daily_usage where user_id=$1 and kind='analysis'",
              [userA],
            )).rows,
            [{ requests: 1 }],
          );
          assert.equal(
            (await db.query("select * from error_events where attempt_id=$1", [
              attempt,
            ])).rows.length,
            1,
          );
        },
      );
      await t.step(
        "another owner cannot analyze or read this attempt through service",
        async () => {
          await assert.rejects(() => analyzeAttempt(sql, attempt, userB), {
            code: "attempt_not_found",
          });
          assert.equal(providerCalls, 1);
        },
      );
      await t.step(
        "upstream failure leaves retryable state without partial diagnosis",
        async () => {
          providerFailure = true;
          await assert.rejects(
            () => analyzeAttempt(sql, failedAttempt, userA),
            {
              code: "ai_unavailable",
            },
          );
          providerFailure = false;
          assert.deepEqual(
            (await db.query("select status from attempts where id=$1", [
              failedAttempt,
            ])).rows,
            [{ status: "retryable_failed" }],
          );
          assert.equal(
            (await db.query(
              "select * from attempt_analyses where attempt_id=$1",
              [failedAttempt],
            )).rows.length,
            0,
          );
          assert.deepEqual(
            (await db.query(
              "select retry_count,status from processing_runs where attempt_id=$1",
              [failedAttempt],
            )).rows,
            [{ retry_count: 1, status: "retryable_failed" }],
          );
        },
      );
      await t.step(
        "retry persists exactly one analysis and increments retry count",
        async () => {
          await analyzeAttempt(sql, failedAttempt, userA);
          assert.equal(providerCalls, 3);
          assert.deepEqual(
            (await db.query(
              "select retry_count,status from processing_runs where attempt_id=$1",
              [failedAttempt],
            )).rows,
            [{ retry_count: 2, status: "completed" }],
          );
          assert.equal(
            (await db.query("select * from error_events where attempt_id=$1", [
              failedAttempt,
            ])).rows.length,
            1,
          );
        },
      );
      await t.step(
        "third expired lease becomes dead letter without calling API",
        async () => {
          await db.exec(
            `update attempts set status='processing' where id='${expiredAttempt}';
        insert into processing_runs(attempt_id,pipeline_version,status,retry_count,trace_id,lease_until)
        values('${expiredAttempt}','openai-analysis-v1','processing',3,'expired',now()-interval '1 minute');`,
          );
          await assert.rejects(
            () => analyzeAttempt(sql, expiredAttempt, userA),
            {
              code: "retry_limit",
            },
          );
          assert.equal(providerCalls, 3);
          assert.deepEqual(
            (await db.query("select status from attempts where id=$1", [
              expiredAttempt,
            ])).rows,
            [{ status: "dead_letter" }],
          );
          assert.deepEqual(
            (await db.query(
              "select status from processing_runs where attempt_id=$1",
              [expiredAttempt],
            )).rows,
            [{ status: "dead_letter" }],
          );
        },
      );
      await t.step(
        "practice persists exercises but never returns the private answer key",
        async () => {
          const result = await generatePractice(sql, userA, subject, 3);
          assert.equal(result.exercises.length, 3);
          assert.equal(providerCalls, 4);
          for (const exercise of result.exercises) {
            assert.ok(!("correct_answer" in exercise));
            assert.ok(!("explanation" in exercise));
          }
          assert.equal(
            (await db.query(
              "select * from practice_answer_keys where practice_set_id=$1",
              [result.practice_set_id],
            )).rows.length,
            3,
          );
          assert.deepEqual(
            (await db.query(
              "select exercise_count from practice_sets where id=$1",
              [result.practice_set_id],
            )).rows,
            [{ exercise_count: 3 }],
          );
          const generatedId = result.exercises[0].id;
          const key = await db.query(
            "select correct_answer from practice_answer_keys where exercise_id=$1",
            [generatedId],
          );
          assert.equal(key.rows.length, 1);
        },
      );
      await t.step(
        "generated exercises cannot be changed underneath their private keys",
        async () => {
          await assert.rejects(() =>
            db.query(
              "update exercises set prompt_text='changed' where source='openai_practice'",
            ), { code: "42501" });
        },
      );
    } finally {
      globalThis.fetch = nativeFetch;
      Deno.env.delete("OPENAI_API_KEY");
      Deno.env.delete("OPENAI_MODEL");
      await db.close();
    }
  },
});
