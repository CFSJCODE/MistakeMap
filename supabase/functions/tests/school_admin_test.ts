import { strict as assert } from "node:assert";
import { PublicError } from "../_shared/ai_contract.ts";
import {
  birthDate,
  classOrInviteCode,
  cnpj,
  cnpjValid,
  databaseError,
  expectedRoles,
  importRows,
  INVITE_ROLES_BY_PERSONA,
  memberStatus,
  persona,
  shortCode,
} from "../_shared/school_admin_contract.ts";
import {
  authRecovery,
  isSchoolItAction,
} from "../_shared/school_it_service.ts";
import {
  createSchoolAdminHandler,
  type SchoolAdminServices,
} from "../school-admin/handler.ts";

const USER = "00000000-0000-4000-8000-000000000001";
function setup(overrides: Partial<SchoolAdminServices> = {}) {
  const calls: { user: string; input: unknown }[] = [];
  const handler = createSchoolAdminHandler({
    authenticate: () => Promise.resolve(USER),
    run: (user, input) => {
      calls.push({ user, input });
      return Promise.resolve({ ok: true });
    },
    ...overrides,
  });
  return { handler, calls };
}
const request = (value: unknown) =>
  new Request("http://localhost/school-admin", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: typeof value === "string" ? value : JSON.stringify(value),
  });

Deno.test("school-admin usa o usuário da sessão, nunca o do corpo", async () => {
  const { handler, calls } = setup();
  const response = await handler(request({ action: "context", user_id: "x" }));
  assert.equal(response.status, 200);
  assert.equal(calls[0].user, USER);
});

Deno.test("school-admin recusa sem login antes de tocar o banco", async () => {
  const { handler, calls } = setup({
    authenticate: () =>
      Promise.reject(new PublicError(401, "unauthorized", "Entre.")),
  });
  const response = await handler(request({ action: "context" }));
  assert.equal(response.status, 401);
  assert.equal(calls.length, 0);
});

Deno.test("school-admin recusa corpo inválido e ação desconhecida", async () => {
  const { handler, calls } = setup();
  for (const body of ["{", "[]", "null", { action: "grant_role" }, {}]) {
    const response = await handler(request(body));
    assert.equal(response.status, 400);
  }
  assert.equal(calls.length, 0);
});

Deno.test("perfil escolhido: só os 8 perfis do cadastro", () => {
  assert.equal(persona({ persona: "student_team" }), "student_team");
  assert.throws(() => persona({ persona: "admin" }), PublicError);
  assert.deepEqual(INVITE_ROLES_BY_PERSONA.coordinator, ["coordinator"]);
  assert.deepEqual(INVITE_ROLES_BY_PERSONA.finance, ["finance"]);
  assert.deepEqual(INVITE_ROLES_BY_PERSONA.student_team, ["student"]);
  assert.deepEqual(expectedRoles({ expected_roles: ["teacher", "teacher"] }), [
    "teacher",
  ]);
  assert.throws(
    () => expectedRoles({ expected_roles: ["admin"] }),
    PublicError,
  );
});

Deno.test("data de nascimento: formato, futuro e limite de 120 anos", () => {
  const today = new Date("2026-11-11T12:00:00Z");
  assert.equal(birthDate({ birth_date: "2012-02-29" }, today), "2012-02-29");
  assert.equal(birthDate({}, today), null);
  for (
    const value of [
      "2013-02-29",
      "11/11/2012",
      "2027-01-01",
      "1900-01-01",
      2012,
    ]
  ) {
    assert.throws(() => birthDate({ birth_date: value }, today), PublicError);
  }
});

Deno.test("códigos: convite curto e código de turma", () => {
  assert.equal(shortCode({ code: " ab12-cd34 ef56 " }), "AB12CD34EF56");
  assert.throws(() => shortCode({ code: "a;b" }), PublicError);
  assert.deepEqual(classOrInviteCode({ code: "A".repeat(32) }), {
    kind: "class",
    code: "a".repeat(32),
  });
  assert.equal(classOrInviteCode({ code: "XK7P2M9QRT4W" }).kind, "invite");
});

Deno.test("CNPJ: dígitos verificadores", () => {
  assert.equal(cnpjValid("11222333000181"), true);
  assert.equal(cnpj({ cnpj: "11.222.333/0001-81" }), "11222333000181");
  assert.equal(cnpj({}), null);
  assert.equal(cnpjValid("11222333000182"), false);
  assert.equal(cnpjValid("00000000000000"), false);
  assert.throws(() => cnpj({ cnpj: "123" }), PublicError);
});

Deno.test("erros do banco viram mensagens públicas", () => {
  const invite = databaseError({
    code: "MM404",
    message: "school_invite_invalid",
  });
  assert.ok(invite instanceof PublicError);
  assert.equal(invite.status, 404);
  assert.match(invite.publicMessage, /Convite/);
  const minor = databaseError({ code: "MM403", message: "guardian_minor" });
  assert.ok(minor instanceof PublicError);
  assert.match(minor.publicMessage, /maior de idade/);
  const other = new Error("boom");
  assert.equal(databaseError(other), other);
});

// ─── Perfil TI ──────────────────────────────────────────────────────────────

Deno.test("school-admin aceita as ações da TI e planilha maior", async () => {
  const { handler, calls } = setup();
  const rows = Array.from({ length: 500 }, (_, i) => ({
    email: `aluno${i}@escola.dev`,
    role: "student",
  }));
  const response = await handler(request({
    action: "it_import_invites",
    school_id: USER,
    rows,
  }));
  assert.equal(response.status, 200);
  assert.equal(calls.length, 1);
});

Deno.test("planilha de convites: 1 a 500 linhas, campos aparados", () => {
  assert.deepEqual(
    importRows({ rows: [{ email: " A@B.dev ", role: " student " }, 3] }),
    [{ email: "A@B.dev", role: "student" }, { email: "", role: "" }],
  );
  for (const rows of [[], null, "x", Array(501).fill({})]) {
    assert.throws(
      () => importRows({ rows }),
      (e: unknown) => e instanceof PublicError && e.code === "invalid_rows",
    );
  }
});

Deno.test("situação do membro só ativo ou suspenso", () => {
  assert.equal(memberStatus({ status: "suspended" }), "suspended");
  assert.throws(() => memberStatus({ status: "banido" }));
});

Deno.test("ações da TI são reconhecidas pelo prefixo", () => {
  assert.equal(isSchoolItAction("it_directory"), true);
  assert.equal(isSchoolItAction("school_overview"), false);
});

Deno.test("redefinição de senha chama o recover do Auth com a chave anon", async () => {
  const seen: { url: string; init?: RequestInit }[] = [];
  const send = authRecovery(
    (name) =>
      ({ SUPABASE_URL: "https://x.supabase.co/", SUPABASE_ANON_KEY: "anon" })[
        name
      ],
    (url, init) => {
      seen.push({ url: String(url), init });
      return Promise.resolve(new Response("{}", { status: 200 }));
    },
  );
  await send("al@b.dev");
  assert.equal(seen[0].url, "https://x.supabase.co/auth/v1/recover");
  assert.equal(
    (seen[0].init?.headers as Record<string, string>).apikey,
    "anon",
  );
  assert.equal(seen[0].init?.body, JSON.stringify({ email: "al@b.dev" }));
});

Deno.test("redefinição de senha traduz limite e falha do Auth", async () => {
  const get = (name: string) =>
    ({ SUPABASE_URL: "https://x", SUPABASE_ANON_KEY: "k" })[name];
  for (const [status, code] of [[429, "limit_reached"], [500, "auth_failed"]]) {
    const send = authRecovery(
      get,
      () => Promise.resolve(new Response("", { status: status as number })),
    );
    await assert.rejects(
      send("a@b.dev"),
      (e: unknown) => e instanceof PublicError && e.code === code,
    );
  }
});

Deno.test("erros do banco da TI viram mensagens claras", () => {
  const recent = databaseError({
    code: "MM429",
    message: "password_reset_recent",
  });
  assert.ok(recent instanceof PublicError && recent.status === 429);
  assert.match((recent as PublicError).publicMessage, /10 minutos/);
  const limit = databaseError({
    code: "MM402",
    message: "school_plan_user_limit",
    hint: "O plano Grátis vai até 5 usuários. Mude para o plano Escola.",
  });
  assert.match((limit as PublicError).publicMessage, /até 5 usuários/);
});
