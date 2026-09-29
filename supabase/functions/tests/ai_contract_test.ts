import { strict as assert } from "node:assert";
import {
  analysisSchema,
  imageMime,
  practiceCount,
  PublicError,
  uuid,
  validateAnalysis,
  validatePractice,
  verifyImageHash,
} from "../_shared/ai_contract.ts";
import {
  authenticate,
  body,
  cronAuthorized,
  readLimited,
} from "../_shared/ai_http.ts";
import { structuredResponse } from "../_shared/gemini.ts";
import { handler as analyzeHandler } from "../analyze-attempt/handler.ts";
import { handler as practiceHandler } from "../generate-practice/handler.ts";
import { handler as batchHandler } from "../process-batch/handler.ts";

const sample = () => ({
  is_correct: false,
  correct_answer: "4",
  explanation: "2 + 2 resulta em 4.",
  transcribed_prompt: "Quanto é 2 + 2?",
  transcribed_answer: "5",
  errors: [{
    category: "calculo",
    concept: "Adição",
    evidence: "2 + 2 = 5",
    confidence: 0.9,
  }],
  concepts: ["Adição"],
});
const config = (
  name: string,
) => ({
  GEMINI_API_KEY: "test-only-placeholder",
  GEMINI_MODEL: "test-model",
  SUPABASE_URL: "https://example.invalid",
  SUPABASE_ANON_KEY: "test-public-placeholder",
}[name]);
const options = {
  schema: analysisSchema,
  name: "test_analysis",
  instructions: "Tutor",
  text: "Dados sintéticos",
};
const wrapped = (value: unknown) =>
  new Response(
    JSON.stringify({
      candidates: [{
        content: { parts: [{ text: JSON.stringify(value) }], role: "model" },
        finishReason: "STOP",
      }],
    }),
  );
function fetchMock(
  fn: (
    input: RequestInfo | URL,
    init?: RequestInit,
  ) => Response | Promise<Response>,
): typeof fetch {
  return (async (input, init) => await fn(input, init)) as typeof fetch;
}

Deno.test("runtime accepts a coherent error with evidence", () => {
  assert.deepEqual(validateAnalysis(sample()), sample());
});
Deno.test("runtime rejects unrecognized categories, fields and concepts", () => {
  assert.throws(
    () => validateAnalysis({ ...sample(), injected: "instruction" }),
    PublicError,
  );
  assert.throws(
    () =>
      validateAnalysis({
        ...sample(),
        errors: [{ ...sample().errors[0], category: "inventada" }],
      }),
    PublicError,
  );
  assert.throws(
    () => validateAnalysis({ ...sample(), concepts: ["Outro"] }),
    PublicError,
  );
});
Deno.test("runtime rejects contradictory diagnosis and confidence outside bounds", () => {
  for (const confidence of [-0.1, 1.1, NaN, Infinity]) {
    assert.throws(() =>
      validateAnalysis({
        ...sample(),
        errors: [{ ...sample().errors[0], confidence }],
      }), PublicError);
  }
  assert.throws(
    () => validateAnalysis({ ...sample(), is_correct: true }),
    PublicError,
  );
  assert.throws(
    () => validateAnalysis({ ...sample(), is_correct: null }),
    PublicError,
  );
  assert.throws(
    () => validateAnalysis({ ...sample(), errors: [] }),
    PublicError,
  );
});
Deno.test("uncertain and correct responses do not manufacture errors", () => {
  const uncertain = validateAnalysis({
    ...sample(),
    is_correct: null,
    correct_answer: "",
    errors: [],
  });
  assert.equal(uncertain.is_correct, null);
  assert.equal(
    validateAnalysis({ ...sample(), is_correct: true, errors: [] }).errors
      .length,
    0,
  );
});
Deno.test("runtime enforces output length and cardinality", () => {
  assert.throws(
    () => validateAnalysis({ ...sample(), explanation: "x".repeat(12001) }),
    PublicError,
  );
  assert.throws(
    () =>
      validateAnalysis({
        ...sample(),
        errors: Array(6).fill(sample().errors[0]),
      }),
    PublicError,
  );
  assert.throws(
    () => validateAnalysis({ ...sample(), concepts: Array(13).fill("Adição") }),
    PublicError,
  );
});
Deno.test("practice requires three to five distinct complete exercises", () => {
  const exercises = Array.from(
    { length: 3 },
    (_, i) => ({
      prompt_text: `Calcule ${i}+1`,
      difficulty: "facil",
      focus_concept: "Adição",
      correct_answer: String(i + 1),
      explanation: "Some um.",
    }),
  );
  assert.equal(validatePractice({ exercises }, 3).length, 3);
  assert.throws(() => validatePractice({ exercises }, 4), PublicError);
  assert.throws(
    () =>
      validatePractice({
        exercises: [exercises[0], exercises[0], exercises[0]],
      }, 3),
    PublicError,
  );
  for (const count of [2, 6, 3.5, "3", null]) {
    if (count === null) assert.equal(practiceCount(count), 3);
    else assert.throws(() => practiceCount(count), PublicError);
  }
});
Deno.test("identifiers and image formats reject malformed input", () => {
  assert.equal(
    uuid("00000000-0000-4000-8000-000000000001"),
    "00000000-0000-4000-8000-000000000001",
  );
  for (const id of ["bad", "../../other", 5, null]) {
    assert.throws(() => uuid(id), PublicError);
  }
  assert.equal(
    imageMime(new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0])),
    "image/png",
  );
  assert.throws(() => imageMime(new Uint8Array(12)), PublicError);
  assert.throws(
    () => imageMime(new Uint8Array(8 * 1024 * 1024 + 1)),
    PublicError,
  );
});
Deno.test("bounded body reader rejects oversized streams", async () => {
  await assert.rejects(
    () => readLimited(new Response("x".repeat(5000)).body, 4096),
    PublicError,
  );
  await assert.rejects(
    () =>
      body(
        new Request("https://example.invalid", {
          method: "POST",
          body: "{bad",
        }),
      ),
    PublicError,
  );
  await assert.rejects(
    () =>
      body(
        new Request("https://example.invalid", { method: "POST", body: "[]" }),
      ),
    PublicError,
  );
});
Deno.test("image hash detects changed or legacy placeholder assets", async () => {
  const bytes = new TextEncoder().encode("abc");
  await verifyImageHash(
    bytes,
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  );
  await assert.rejects(() => verifyImageHash(bytes, "0".repeat(64)), {
    code: "image_changed",
  });
  await assert.rejects(() => verifyImageHash(bytes, "pending"), {
    code: "invalid_image_hash",
  });
});
Deno.test("auth refuses absent or invalid JWT without trusting client claims", async () => {
  let calls = 0;
  const fetcher = fetchMock(() => {
    calls++;
    return new Response("{}", { status: 401 });
  });
  await assert.rejects(
    () => authenticate(new Request("https://example.invalid"), config, fetcher),
    { code: "unauthorized" },
  );
  assert.equal(calls, 0);
  await assert.rejects(
    () =>
      authenticate(
        new Request("https://example.invalid", {
          headers: { Authorization: "Bearer forged" },
        }),
        config,
        fetcher,
      ),
    { code: "unauthorized" },
  );
  assert.equal(calls, 1);
});
Deno.test("auth calls the trusted Supabase user endpoint", async () => {
  const id = "00000000-0000-4000-8000-000000000001";
  const user = await authenticate(
    new Request("https://example.invalid", {
      headers: { Authorization: "Bearer test" },
    }),
    config,
    fetchMock((url, init) => {
      assert.equal(url, "https://example.invalid/auth/v1/user");
      assert.equal(
        new Headers(init?.headers).get("apikey"),
        "test-public-placeholder",
      );
      return new Response(JSON.stringify({ id }));
    }),
  );
  assert.equal(user, id);
});
Deno.test("cron fails closed when unconfigured and with incorrect tokens", () => {
  assert.equal(cronAuthorized(null, undefined), false);
  assert.equal(cronAuthorized("", ""), false);
  assert.equal(cronAuthorized("short", "short"), false);
  assert.equal(cronAuthorized("x".repeat(32), "y".repeat(32)), false);
  assert.equal(cronAuthorized("x".repeat(32), "x".repeat(32)), true);
});
Deno.test("generateContent uses JSON schema, system instruction and server-side key", async () => {
  const result = await structuredResponse(
    options,
    config,
    fetchMock((url, init) => {
      assert.ok(
        String(url).startsWith(
          "https://generativelanguage.googleapis.com/v1beta/models/test-model:generateContent?key=",
        ),
      );
      const request = JSON.parse(String(init?.body));
      assert.equal(
        request.generationConfig.response_mime_type,
        "application/json",
      );
      assert.equal(request.generationConfig.maxOutputTokens, 6000);
      assert.ok(request.system_instruction?.parts?.[0]?.text);
      assert.equal(request.contents[0].parts[0].text, options.text);
      return wrapped(sample());
    }),
  );
  assert.deepEqual(validateAnalysis(result), sample());
});
Deno.test("missing API key makes no provider call", async () => {
  let called = false;
  await assert.rejects(
    () =>
      structuredResponse(
        options,
        () => undefined,
        fetchMock(() => {
          called = true;
          return wrapped(sample());
        }),
      ),
    { code: "service_not_configured" },
  );
  assert.equal(called, false);
});
Deno.test("provider errors never echo upstream body", async () => {
  for (const status of [401, 429, 500]) {
    try {
      await structuredResponse(
        options,
        config,
        fetchMock(() => new Response("SENSITIVE_PROVIDER_DETAIL", { status })),
      );
      assert.fail("must reject");
    } catch (error) {
      assert.ok(error instanceof PublicError);
      assert.ok(!error.publicMessage.includes("SENSITIVE"));
      assert.equal(error.status, status === 429 ? 429 : 502);
    }
  }
});
Deno.test("provider network failure produces a sanitized retryable error", async () => {
  await assert.rejects(
    () =>
      structuredResponse(
        options,
        config,
        fetchMock(() => {
          throw new Error("private-url");
        }),
      ),
    { code: "ai_unavailable" },
  );
});
Deno.test("refusals, incomplete results and malformed JSON cannot be persisted", async () => {
  const cases = [
    // Safety block
    {
      candidates: [{
        content: { parts: [], role: "model" },
        finishReason: "SAFETY",
      }],
    },
    // Empty candidates
    { candidates: [] },
    // Malformed JSON text
    {
      candidates: [{
        content: { parts: [{ text: "{bad" }], role: "model" },
        finishReason: "STOP",
      }],
    },
    // No parts
    {
      candidates: [{
        content: { parts: [], role: "model" },
        finishReason: "STOP",
      }],
    },
  ];
  for (const value of cases) {
    await assert.rejects(() =>
      structuredResponse(
        options,
        config,
        fetchMock(() => new Response(JSON.stringify(value))),
      ), PublicError);
  }
});
Deno.test("handlers deny unauthenticated calls before touching database or API", async () => {
  const request = () =>
    new Request("https://example.invalid", {
      method: "POST",
      body: JSON.stringify({
        attempt_id: "00000000-0000-4000-8000-000000000001",
      }),
    });
  assert.equal((await analyzeHandler(request())).status, 401);
  assert.equal((await practiceHandler(request())).status, 401);
  assert.equal((await batchHandler(request())).status, 401);
});
Deno.test("handlers accept preflight and reject unsupported methods", async () => {
  assert.equal(
    (await analyzeHandler(
      new Request("https://example.invalid", { method: "OPTIONS" }),
    )).status,
    204,
  );
  assert.equal(
    (await practiceHandler(new Request("https://example.invalid"))).status,
    405,
  );
});
