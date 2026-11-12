import { strict as assert } from "node:assert";
import { PublicError } from "../_shared/ai_contract.ts";
import {
  birthDate,
  classOrInviteCode,
  cnpj,
  cnpjValid,
  databaseError,
  expectedRoles,
  INVITE_ROLES_BY_PERSONA,
  persona,
  shortCode,
} from "../_shared/school_admin_contract.ts";
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
