import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { randomUUID } from "node:crypto";
import { bridge, createFixture, projectRoot } from "./verify-study-review.mjs";
import { processAccountDeletion } from "../supabase/functions/_shared/privacy_lifecycle.ts";
import { PublicError } from "../supabase/functions/_shared/ai_contract.ts";

const db = await createFixture(), sql = bridge(db);
// Minimal fixtures keep actual owner FKs/cascades without running unrelated jobs.
await db.exec(
  `CREATE TABLE platform_privacy_requests(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,kind text DEFAULT 'account_deletion',
  status text DEFAULT 'pending',created_at timestamptz DEFAULT now(),completed_at timestamptz);
  CREATE TABLE attempt_assets(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),attempt_id uuid REFERENCES attempts(id) ON DELETE CASCADE,object_path text);
  CREATE TABLE knowledge_posts(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),author_id uuid NOT NULL REFERENCES auth.users(id));`,
);
await db.exec(
  await readFile(
    resolve(
      projectRoot,
      "appmistakemap/database/supabase/migrations/20261106040000_account_lifecycle.sql",
    ),
    "utf8",
  ),
);
const user = randomUUID(),
  other = randomUUID(),
  subject = randomUUID(),
  exercise = randomUUID(),
  attempt = randomUUID();
await db.query("INSERT INTO auth.users(id) VALUES($1),($2)", [user, other]);
await db.query(
  "INSERT INTO subjects(id,user_id,name) VALUES($1,$2,'Circuitos')",
  [subject, user],
);
await db.query(
  "INSERT INTO exercises(id,subject_id,prompt_text) VALUES($1,$2,'Um ESP32 alimenta um circuito.')",
  [exercise, subject],
);
await db.query(
  "INSERT INTO attempts(id,exercise_id,user_id) VALUES($1,$2,$3)",
  [attempt, exercise, user],
);
await db.query("INSERT INTO knowledge_posts(author_id) VALUES($1),($2)", [
  user,
  other,
]);
const objects = new Set();
for (let n = 0; n < 30; n++) {
  const key = `uploads/${user}/${randomUUID()}.png`;
  objects.add(key);
  await db.query(
    "INSERT INTO attempt_assets(attempt_id,object_path) VALUES($1,$2)",
    [attempt, key],
  );
}
const orphan = `uploads/${user}/${randomUUID()}.jpg`;
objects.add(orphan);
const otherObject = `uploads/${other}/${randomUUID()}.png`;
objects.add(otherObject);
await db.query("INSERT INTO platform_privacy_requests(user_id) VALUES($1)", [
  user,
]);
let authCalls = 0, storageFails = false;
const services = {
  async listObjects(owner, limit) {
    return [...objects].filter((path) => path.startsWith(`uploads/${owner}/`))
      .slice(0, limit);
  },
  async deleteObject(path) {
    if (storageFails) {
      throw new PublicError(502, "storage_unavailable", "never leak this");
    }
    objects.delete(path);
  },
  async deleteAuthUser(owner) {
    authCalls++;
    await db.query("DELETE FROM auth.users WHERE id=$1", [owner]);
  },
};
assert.equal((await processAccountDeletion(sql, services)).status, "waiting");
assert.equal(authCalls, 0);
assert.equal(
  (await processAccountDeletion(sql, services)).status,
  "idle",
  "URLs have time to expire",
);
assert.equal(
  (await db.query("SELECT status FROM platform_privacy_requests")).rows[0]
    .status,
  "processing",
);
const due = () =>
  db.exec(
    "UPDATE account_deletion_jobs SET not_before=now()-interval '1 second',next_attempt_at=now()-interval '1 second',lease_until=NULL",
  );
await due();
storageFails = true;
assert.equal(
  (await processAccountDeletion(sql, services)).error,
  "storage_unavailable",
);
assert.equal(authCalls, 0, "Auth cannot disappear before files are deleted");
assert.equal(
  (await db.query("SELECT count(*)::int AS n FROM attempt_assets")).rows[0].n,
  30,
);
storageFails = false;
await due();
const chunk = await processAccountDeletion(sql, services);
assert.equal(chunk.status, "continuing");
assert.equal(chunk.removed_objects, 25);
assert.equal(authCalls, 0);
await due();
const final = await processAccountDeletion(sql, services);
assert.equal(final.completed, true);
assert.equal(authCalls, 1);
assert.deepEqual(
  [...objects],
  [otherObject],
  "Only requested owner including abandoned uploads was removed",
);
assert.equal(
  (await db.query("SELECT count(*)::int AS n FROM auth.users WHERE id=$1", [
    user,
  ])).rows[0].n,
  0,
);
assert.equal(
  (await db.query("SELECT count(*)::int AS n FROM subjects WHERE user_id=$1", [
    user,
  ])).rows[0].n,
  0,
);
assert.equal(
  (await db.query("SELECT count(*)::int AS n FROM platform_privacy_requests"))
    .rows[0].n,
  0,
  "Auth cascade removes original request",
);
assert.equal(
  (await db.query("SELECT status FROM account_deletion_jobs")).rows[0].status,
  "completed",
  "Tombstone survives cascade",
);
assert.equal(
  (await db.query("SELECT author_id FROM knowledge_posts")).rows[0].author_id,
  other,
);
assert.equal(
  (await processAccountDeletion(sql, services)).status,
  "idle",
  "Repeated invocation never deletes another account",
);

// Lost Auth response is retryable even though user and request already cascaded.
await db.query("INSERT INTO platform_privacy_requests(user_id) VALUES($1)", [
  other,
]);
await processAccountDeletion(sql, services);
await due();
let lost = true;
const lostServices = {
  ...services,
  async deleteAuthUser(owner) {
    await services.deleteAuthUser(owner);
    if (lost) {
      lost = false;
      throw new PublicError(
        502,
        "auth_unavailable",
        "private upstream details",
      );
    }
  },
};
assert.equal((await processAccountDeletion(sql, lostServices)).status, "retry");
assert.equal(
  (await db.query("SELECT count(*)::int AS n FROM auth.users")).rows[0].n,
  0,
);
await due();
assert.equal((await processAccountDeletion(sql, lostServices)).completed, true);
await db.exec(
  "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);",
);
await assert.rejects(
  () => db.query("SELECT * FROM account_deletion_jobs"),
  /permission denied/,
);
await db.exec("RESET ROLE");
await db.close();
console.log(
  "Account lifecycle: real PostgreSQL leases/cascades, grace period, R2 failure, bounded batches, tenant ownership and lost Auth response passed. No external calls.",
);
