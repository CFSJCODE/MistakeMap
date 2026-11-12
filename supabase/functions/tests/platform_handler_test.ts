import { strict as assert } from "node:assert";
import {
  createPlatformHandler,
  type PlatformServices,
} from "../study-platform/handler.ts";
import { PublicError } from "../_shared/ai_contract.ts";

const USER = "00000000-0000-4000-8000-000000000001";
function setup(overrides: Partial<PlatformServices> = {}) {
  const calls: { user: string; input: unknown }[] = [];
  const handler = createPlatformHandler({
    authenticate: () => Promise.resolve(USER),
    run: (user, input) => {
      calls.push({ user, input });
      return Promise.resolve({ ok: true });
    },
    ...overrides,
  });
  return { handler, calls };
}
function request(value: unknown, method = "POST") {
  return new Request("http://localhost/study-platform", {
    method,
    headers: { "Content-Type": "application/json" },
    ...(method === "POST"
      ? { body: typeof value === "string" ? value : JSON.stringify(value) }
      : {}),
  });
}
Deno.test("platform handler binds authenticated identity independently of body user_id", async () => {
  const { handler, calls } = setup();
  const response = await handler(
    request({ action: "overview", user_id: "other" }),
  );
  assert.equal(response.status, 200);
  assert.equal(calls[0].user, USER);
});
Deno.test("platform denies unauthorized requests before invoking the database", async () => {
  const { handler, calls } = setup({
    authenticate: () =>
      Promise.reject(new PublicError(401, "unauthorized", "Entre.")),
  });
  const response = await handler(request({ action: "overview" }));
  assert.equal(response.status, 401);
  assert.equal(calls.length, 0);
});
Deno.test("platform handler bounds bodies and rejects malformed actions without side effects", async () => {
  const { handler, calls } = setup();
  for (
    const input of ["{", [], null, { action: "keys" }, {
      action: "overview",
      large: "x".repeat(66000),
    }]
  ) {
    const response = await handler(request(input));
    assert.equal(response.status, 400);
  }
  assert.equal(calls.length, 0);
  assert.equal((await handler(request({}, "GET"))).status, 405);
  assert.equal((await handler(request({}, "OPTIONS"))).status, 204);
});
Deno.test("platform accepts complete notes within its declared 64KB request limit", async () => {
  const { handler, calls } = setup();
  assert.equal(
    (await handler(
      request({ action: "save_note", title: "Regra", body: "x".repeat(5000) }),
    )).status,
    200,
  );
  assert.equal(calls.length, 1);
});
Deno.test("deletion requires recent authentication before its database mutation", async () => {
  const { handler, calls } = setup({
    requireRecentSignin: () =>
      Promise.reject(
        new PublicError(403, "reauthentication_required", "Entre novamente."),
      ),
  });
  const response = await handler(
    request({
      action: "request_deletion",
      confirmation: "EXCLUIR MINHA CONTA",
    }),
  );
  assert.equal(response.status, 403);
  assert.equal(calls.length, 0);
  const recent = setup({ requireRecentSignin: () => Promise.resolve() });
  assert.equal(
    (await recent.handler(
      request({
        action: "request_deletion",
        confirmation: "EXCLUIR MINHA CONTA",
      }),
    )).status,
    200,
  );
  assert.equal(recent.calls.length, 1);
});
Deno.test("platform errors never serialize internal SQL or secrets", async () => {
  const { handler } = setup({
    run: () =>
      Promise.reject(
        new Error("postgres://private token SELECT correct_answer"),
      ),
  });
  const response = await handler(request({ action: "overview" }));
  assert.equal(response.status, 500);
  const body = await response.text();
  assert.ok(!body.includes("private"));
  assert.ok(!body.includes("correct_answer"));
});
