import {
  createUploadHandler,
  MAX_UPLOAD_BYTES,
  type UploadServices,
  validateUpload,
} from "./handler.ts";

function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
const good = {
  filename: "exercicio.jpg",
  content_type: "image/jpeg",
  size_bytes: 1024,
};
function request(body: unknown = good, auth = "Bearer test-only") {
  return new Request("http://localhost/upload-url", {
    method: "POST",
    headers: { Authorization: auth },
    body: JSON.stringify(body),
  });
}
function services(overrides: Partial<UploadServices> = {}): UploadServices {
  return {
    authenticate: async () => "user-a",
    reserve: async () => true,
    sign: async () => "https://example.invalid/upload",
    uuid: () => "photo-id",
    ...overrides,
  };
}

Deno.test("upload rejects paths, unsupported types, MIME mismatch, zero and oversized photos", () => {
  for (
    const body of [
      null,
      [],
      { ...good, filename: "../photo.jpg" },
      { ...good, filename: "photo.html" },
      { ...good, content_type: "image/png" },
      { ...good, size_bytes: 0 },
      { ...good, size_bytes: MAX_UPLOAD_BYTES + 1 },
    ]
  ) {
    assert(validateUpload(body) === null);
  }
  assert(validateUpload(good)?.extension === "jpg");
});
Deno.test("upload denies absent and rejected authorization before reserving quota", async () => {
  let reservations = 0;
  const handler = createUploadHandler(
    services({
      authenticate: async () => null,
      reserve: async () => {
        reservations++;
        return true;
      },
    }),
  );
  assert((await handler(request(good, ""))).status === 401);
  assert((await handler(request())).status === 401);
  assert(reservations === 0);
});
Deno.test("CORS preflight works without authentication or quota changes", async () => {
  const handler = createUploadHandler(services({
    authenticate: async () => {
      throw new Error("must not authenticate");
    },
  }));
  const response = await handler(
    new Request("http://localhost", { method: "OPTIONS" }),
  );
  assert(response.status === 204);
  assert(
    response.headers.get("Access-Control-Allow-Methods")?.includes("POST"),
  );
});
Deno.test("upload returns user-scoped path, signed MIME, and expiration", async () => {
  let signed = "";
  const handler = createUploadHandler(
    services({
      sign: async (path, mime, size) => {
        signed = `${path}|${mime}|${size}`;
        return "https://example.invalid/upload";
      },
    }),
  );
  const response = await handler(request());
  const body = await response.json();
  assert(response.status === 200 && body.expires_in === 900);
  assert(signed === "uploads/user-a/photo-id.jpg|image/jpeg|1024");
});
Deno.test("quota denial never returns a signed upload URL", async () => {
  const handler = createUploadHandler(services({ reserve: async () => false }));
  const response = await handler(request());
  assert(
    response.status === 429 &&
      !JSON.stringify(await response.json()).includes("https://"),
  );
});
Deno.test("configuration errors do not consume quota or expose internal messages", async () => {
  let reservations = 0;
  const handler = createUploadHandler(services({
    sign: async () => {
      throw new Error("INTERNAL_SENSITIVE_VALUE");
    },
    reserve: async () => {
      reservations++;
      return true;
    },
  }));
  const response = await handler(request());
  assert(response.status === 503 && reservations === 0);
  assert(!(await response.text()).includes("INTERNAL_SENSITIVE_VALUE"));
});
Deno.test("oversized JSON is rejected before signing or reserving quota", async () => {
  const handler = createUploadHandler(services({
    sign: async () => {
      throw new Error("must not sign");
    },
  }));
  assert(
    (await handler(request({ ...good, extra: "a".repeat(5000) }))).status ===
      400,
  );
});
