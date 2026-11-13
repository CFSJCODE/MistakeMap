// Funções da TI ponta a ponta contra o Postgres local do verify-school-it.sh:
// Edge Function (school_it_service.ts) + migrations, com um Auth falso no
// lugar do e-mail de redefinição. Nunca toca o banco publicado.
import { strict as assert } from "node:assert";
import postgres from "postgresjs";
import { PublicError } from "../../supabase/functions/_shared/ai_contract.ts";
import type { Database } from "../../supabase/functions/_shared/ai_service.ts";
import { schoolAdminOperation } from "../../supabase/functions/_shared/school_admin_service.ts";
import { schoolItOperation } from "../../supabase/functions/_shared/school_it_service.ts";

const url = Deno.env.get("SUPABASE_DB_URL");
if (!url) throw new Error("SUPABASE_DB_URL não definido");
const sql = postgres(url, {
  prepare: false,
  max: 1,
  onnotice: () => {},
}) as unknown as Database;

const ti = "c0000000-0000-4000-8000-000000000002";
const prof = "c0000000-0000-4000-8000-000000000005";
const al1 = "c0000000-0000-4000-8000-000000000006";
const [school] =
  await sql`SELECT id FROM public.schools WHERE name = 'Escola C (teste)'`;
const school_id = String(school.id);

const dir = await schoolAdminOperation(sql, ti, {
  action: "it_directory",
  school_id,
}) as {
  people: { email: string }[];
};
assert.ok(dir.people.some((p) => p.email === "al1@c.dev"));
console.log("ok: it_directory pela Edge Function");

const sent: string[] = [];
await schoolItOperation(sql, ti, "it_reset_password", {
  school_id,
  user_id: al1,
}, (email) => {
  sent.push(email);
  return Promise.resolve();
});
assert.deepEqual(sent, ["al1@c.dev"]);
console.log(
  "ok: it_reset_password pede o e-mail ao Auth sem devolver o endereço",
);

// Falha no Auth: nada registrado e a próxima tentativa não fica bloqueada.
const other = "c0000000-0000-4000-8000-00000000000b";
const owner = "c0000000-0000-4000-8000-000000000001";
await sql`INSERT INTO auth.users(id, email) VALUES (${other}, 'al3@c.dev')`;
await sql.begin(async (tx) => {
  await tx`SELECT set_config('request.jwt.claim.sub', ${owner}, true)`;
  const [inv] = await tx`SELECT code FROM public.create_school_invite(
    ${school_id}::uuid, 'student', null, 1, 7)`;
  await tx`SELECT set_config('request.jwt.claim.sub', ${other}, true)`;
  await tx`SELECT * FROM public.redeem_school_invite(${inv.code})`;
});
await assert.rejects(
  schoolItOperation(
    sql,
    ti,
    "it_reset_password",
    { school_id, user_id: other },
    () => Promise.reject(new PublicError(502, "auth_failed", "falhou")),
  ),
  (e: unknown) => e instanceof PublicError && e.status === 502,
);
const [logged] = await sql`SELECT count(*)::int AS n
  FROM public.school_audit_log
  WHERE action = 'password_reset_sent' AND target_user = ${other}`;
assert.equal(logged.n, 0);
await schoolItOperation(
  sql,
  ti,
  "it_reset_password",
  { school_id, user_id: other },
  () => Promise.resolve(),
);
console.log("ok: falha no Auth não registra envio nem bloqueia nova tentativa");

await assert.rejects(
  schoolItOperation(
    sql,
    ti,
    "it_reset_password",
    { school_id, user_id: prof },
    () => {
      throw new Error("não deveria enviar");
    },
  ),
  (e: unknown) => e instanceof PublicError && e.status === 403,
);
console.log("ok: sem permissão, nenhum e-mail sai");

const batch = await schoolAdminOperation(sql, ti, {
  action: "it_import_invites",
  school_id,
  rows: [{ email: "lote@c.dev", role: "guardian" }],
}) as { created: number };
assert.equal(batch.created, 1);
console.log("ok: it_import_invites");

await assert.rejects(
  schoolAdminOperation(sql, al1, { action: "it_licenses", school_id }),
  (e: unknown) => e instanceof PublicError && e.status === 403,
);
console.log("ok: aluno recebe 403 nas ações da TI");
await (sql as unknown as { end: () => Promise<void> }).end();
