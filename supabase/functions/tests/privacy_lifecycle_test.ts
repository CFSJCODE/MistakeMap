import { strict as assert } from "node:assert";
import {
  deletionError,
  ownedObjectPath,
} from "../_shared/privacy_lifecycle.ts";
import {
  deletionServices,
  listedObjectPaths,
} from "../_shared/privacy_adapters.ts";
import { requireRecentSignin } from "../_shared/privacy_auth.ts";
import { createAccountDataHandler } from "../account-data/handler.ts";
import { PublicError } from "../_shared/ai_contract.ts";

const user = "11111111-1111-4111-8111-111111111111";
const path = `uploads/${user}/22222222-2222-4222-8222-222222222222.png`;
const config = (name: string) =>
  ({
    SUPABASE_URL: "https://example.invalid",
    SUPABASE_ANON_KEY: "test-anon",
    SUPABASE_SERVICE_ROLE_KEY: "test-service",
    CLOUDFLARE_R2_S3_ENDPOINT: "https://storage.invalid",
    CLOUDFLARE_R2_BUCKET: "test-bucket",
    CLOUDFLARE_R2_ACCESS_KEY_ID: "test-access",
    CLOUDFLARE_R2_SECRET_ACCESS_KEY: "test-secret",
  } as Record<string, string>)[name];
const now = new Date("2026-11-06T12:00:00Z");
const nowSeconds = now.getTime() / 1000;
const sessionId = "22222222-2222-4222-8222-222222222222";
function signedClaimsFixture(overrides: Record<string, unknown> = {}): Request {
  const encode = (value: unknown) =>
    btoa(JSON.stringify(value))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const jwt = `${encode({ alg: "ES256", typ: "JWT" })}.${
    encode({
      sub: user,
      session_id: sessionId,
      role: "authenticated",
      is_anonymous: false,
      amr: [{ method: "password", timestamp: nowSeconds - 300 }],
      ...overrides,
    })
  }.simulated-signature`;
  // A assinatura é uma fixture. O mock Auth representa a validação e confirma
  // que recebeu exatamente o bearer cujo payload será lido pelo serviço.
  return new Request("https://example.invalid", {
    headers: { Authorization: `Bearer ${jwt}` },
  });
}
function authFor(
  request: Request,
  data: Record<string, unknown> = {},
  status = 200,
): typeof fetch {
  return (url, init) => {
    assert.equal(String(url), "https://example.invalid/auth/v1/user");
    assert.equal(
      new Headers(init?.headers).get("Authorization"),
      request.headers.get("Authorization"),
    );
    return Promise.resolve(
      Response.json({
        id: user,
        is_anonymous: false,
        last_sign_in_at: now.toISOString(),
        ...data,
      }, { status }),
    );
  };
}

Deno.test("exclusão só aceita arquivos no prefixo do dono e sem travessia", () => {
  assert.equal(ownedObjectPath(user, path), path);
  for (
    const invalid of [
      `uploads/33333333-3333-4333-8333-333333333333/p.png`,
      `uploads/${user}/../other.png`,
      `uploads/${user}/%2e%2e%2fother.png`,
      "https://example.invalid/a.png",
      "",
    ]
  ) {
    assert.throws(() => ownedObjectPath(user, invalid), {
      code: "invalid_asset_path",
    });
  }
  assert.equal(
    deletionError(new Error("secret upstream content")),
    "internal_error",
  );
  assert.equal(
    deletionError(
      new PublicError(502, "storage_unavailable", "private detail"),
    ),
    "storage_unavailable",
  );
});

Deno.test("listagem R2 inválida não é confundida com prefixo vazio", () => {
  assert.deepEqual(
    listedObjectPaths(
      `<ListBucketResult><IsTruncated>false</IsTruncated><Contents><Key>${path}</Key></Contents></ListBucketResult>`,
      user,
    ),
    [path],
  );
  assert.deepEqual(
    listedObjectPaths(
      "<ListBucketResult><IsTruncated>false</IsTruncated></ListBucketResult>",
      user,
    ),
    [],
  );
  for (
    const invalid of [
      "",
      "<Error>AccessDenied</Error>",
      "<ListBucketResult></ListBucketResult>",
      "<ListBucketResult><IsTruncated>true</IsTruncated></ListBucketResult>",
    ]
  ) {
    assert.throws(() => listedObjectPaths(invalid, user), {
      code: "storage_unavailable",
    });
  }
});

Deno.test("login global recente em outro aparelho não torna o bearer antigo recente", async () => {
  const old = signedClaimsFixture({
    amr: [{ method: "password", timestamp: nowSeconds - 601 }],
  });
  await assert.rejects(
    () => requireRecentSignin(old, user, config, authFor(old), now),
    { code: "reauthentication_required" },
  );
});

Deno.test("token_refresh e iat novo não comprovam reautenticação", async () => {
  const refreshed = signedClaimsFixture({
    iat: nowSeconds - 10,
    amr: [
      { method: "password", timestamp: nowSeconds - 3600 },
      { method: "token_refresh", timestamp: nowSeconds - 10 },
    ],
  });
  await assert.rejects(
    () => requireRecentSignin(refreshed, user, config, authFor(refreshed), now),
    { code: "reauthentication_required" },
  );
});

Deno.test("AMR recente de autenticação real vale só no bearer da própria sessão validado no Auth", async () => {
  for (
    const method of [
      "password",
      "oauth",
      "otp",
      "totp",
      "sso/saml",
      "magiclink",
    ]
  ) {
    const current = signedClaimsFixture({
      amr: [{ method, timestamp: nowSeconds - 600 }],
    });
    await requireRecentSignin(
      current,
      user,
      config,
      authFor(current, { last_sign_in_at: null }),
      now,
    );
  }
  const fresh = signedClaimsFixture();
  await assert.rejects(
    () =>
      requireRecentSignin(fresh, user, config, authFor(fresh, {}, 401), now),
    { code: "unauthorized" },
  );
  await assert.rejects(
    () =>
      requireRecentSignin(
        fresh,
        user,
        config,
        authFor(fresh, { id: "other" }),
        now,
      ),
    { code: "reauthentication_required" },
  );
});

Deno.test("exclusão falha fechada para terceiro, anônimo, claims ausentes ou data AMR inválida", async () => {
  for (
    const overrides of [
      { client_id: "third-party" },
      { is_anonymous: true },
      { is_anonymous: undefined },
      { role: "service_role" },
      { sub: "other" },
      { session_id: undefined },
      { session_id: "not-a-session" },
      { session_id: "00000000-0000-0000-0000-000000000000" },
      { amr: undefined },
      { amr: [] },
      { amr: [{ method: "password", timestamp: String(nowSeconds) }] },
      { amr: [{ method: "password", timestamp: nowSeconds + 1 }] },
    ]
  ) {
    const invalid = signedClaimsFixture(overrides);
    await assert.rejects(
      () => requireRecentSignin(invalid, user, config, authFor(invalid), now),
      { code: "reauthentication_required" },
    );
  }
});

Deno.test("Admin delete idempotente aceita 404 e nunca devolve corpo privado de erro", async () => {
  let requested = "";
  const services = deletionServices(
    config,
    (url, options) => {
      requested = String(url);
      assert.equal(options?.method, "DELETE");
      assert.equal(
        new Headers(options?.headers).get("Authorization"),
        "Bearer test-service",
      );
      return Promise.resolve(
        new Response("private user information", { status: 404 }),
      );
    },
  );
  await services.deleteAuthUser(user);
  assert.equal(
    requested,
    `https://example.invalid/auth/v1/admin/users/${user}`,
  );
  const failing = deletionServices(
    config,
    () =>
      Promise.resolve(new Response("private failure details", { status: 500 })),
  );
  await assert.rejects(() => failing.deleteAuthUser(user), {
    code: "auth_unavailable",
  });
});

Deno.test("worker não aceita JWT do estudante ou segredo ausente e não conecta ao banco", async () => {
  let connected = false;
  const handler = createAccountDataHandler({
    get: () => undefined,
    connect: () => {
      connected = true;
      throw new Error("must not connect");
    },
  });
  const req = new Request("https://example.invalid", {
    method: "POST",
    headers: { Authorization: "Bearer student-token" },
    body: JSON.stringify({ action: "process_deletion" }),
  });
  assert.equal((await handler(req)).status, 401);
  assert.equal(connected, false);
  assert.equal(
    (await handler(new Request("https://example.invalid"))).status,
    405,
  );
});
