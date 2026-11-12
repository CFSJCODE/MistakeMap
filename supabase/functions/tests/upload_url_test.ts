import { strict as assert } from "node:assert";
import {
  createUploadHandler,
  MAX_UPLOAD_BYTES,
  type UploadServices,
  validateUpload,
} from "../upload-url/handler.ts";

const USER = "00000000-0000-4000-8000-000000000001";
const OBJECT = "00000000-0000-4000-8000-0000000000aa";

function services(overrides: Partial<UploadServices> = {}) {
  const calls = { sign: 0, reserve: 0 };
  const value: UploadServices = {
    authenticate: () => Promise.resolve(USER),
    reserve: () => {
      calls.reserve++;
      return Promise.resolve(true);
    },
    sign: (path) => {
      calls.sign++;
      return Promise.resolve(`https://r2.example/${path}?signed`);
    },
    uuid: () => OBJECT,
    ...overrides,
  };
  return { value, calls };
}

const request = (body: unknown, auth = "Bearer token") =>
  new Request("http://localhost/upload-url", {
    method: "POST",
    headers: { Authorization: auth, "Content-Type": "application/json" },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

Deno.test("upload contract maps extension to the signed content type", () => {
  assert.deepEqual(
    validateUpload({
      filename: "foto.JPG",
      content_type: "image/jpeg",
      size_bytes: 1024,
    }),
    { extension: "jpg", contentType: "image/jpeg", sizeBytes: 1024 },
  );
  assert.equal(
    validateUpload({
      filename: "foto.png",
      content_type: "image/png",
      size_bytes: 1,
    })?.contentType,
    "image/png",
  );
});

Deno.test("upload contract rejects legacy and malformed bodies", () => {
  for (
    const body of [
      { file_ext: "jpg" },
      { filename: "foto.jpg", content_type: "image/jpg", size_bytes: 10 },
      { filename: "foto.pdf", content_type: "application/pdf", size_bytes: 10 },
      { filename: "../foto.jpg", content_type: "image/jpeg", size_bytes: 10 },
      { filename: "foto.jpg", content_type: "image/jpeg", size_bytes: 0 },
      { filename: "foto.jpg", content_type: "image/jpeg", size_bytes: 1.5 },
      {
        filename: "foto.jpg",
        content_type: "image/jpeg",
        size_bytes: MAX_UPLOAD_BYTES + 1,
      },
      [],
      null,
    ]
  ) {
    assert.equal(validateUpload(body), null, JSON.stringify(body));
  }
});

Deno.test("upload handler returns a user-scoped object path", async () => {
  const { value, calls } = services();
  const response = await createUploadHandler(value)(
    request({ filename: "a.webp", content_type: "image/webp", size_bytes: 9 }),
  );
  assert.equal(response.status, 200);
  const data = await response.json();
  assert.equal(data.object_path, `uploads/${USER}/${OBJECT}.webp`);
  assert.equal(data.content_type, "image/webp");
  assert.equal(data.expires_in, 900);
  assert.match(
    data.object_path,
    /^uploads\/[0-9a-f-]+\/[0-9a-f-]+\.(jpg|jpeg|png|webp)$/,
  );
  assert.deepEqual(calls, { sign: 1, reserve: 1 });
});

Deno.test("upload handler denies before signing or reserving quota", async () => {
  const { value, calls } = services({
    authenticate: () => Promise.resolve(null),
  });
  const handler = createUploadHandler(value);
  const body = { filename: "a.png", content_type: "image/png", size_bytes: 9 };
  assert.equal((await handler(request(body, ""))).status, 401);
  assert.equal((await handler(request(body))).status, 401);
  const invalid = await createUploadHandler(services().value)(
    request({ file_ext: "png" }),
  );
  assert.equal(invalid.status, 400);
  assert.equal((await invalid.json()).error, "invalid_upload");
  assert.deepEqual(calls, { sign: 0, reserve: 0 });
});

Deno.test("upload handler reports exhausted quota and hides internal errors", async () => {
  const body = { filename: "a.png", content_type: "image/png", size_bytes: 9 };
  const full = await createUploadHandler(
    services({ reserve: () => Promise.resolve(false) }).value,
  )(request(body));
  assert.equal(full.status, 429);
  const broken = await createUploadHandler(
    services({
      sign: () => Promise.reject(new Error("secret-endpoint-detail")),
    }).value,
  )(request(body));
  assert.equal(broken.status, 503);
  assert.ok(!(await broken.text()).includes("secret-endpoint-detail"));
});
