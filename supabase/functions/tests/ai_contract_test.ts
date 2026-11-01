import { strict as assert } from "node:assert";
import {
  analysisSchema,
  imageMime,
  practiceCategory,
  practiceCount,
  PublicError,
  rankConcepts,
  uuid,
  validateAnalysis,
  validatePractice,
  verifyImageHash,
} from "../_shared/ai_contract.ts";
import {
  authenticate,
  body,
  cors,
  cronAuthorized,
  originAllowed,
  readLimited,
} from "../_shared/ai_http.ts";
import { modelChain, structuredResponse } from "../_shared/gemini.ts";
import { analysisRetryExhausted } from "../_shared/ai_service.ts";
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
Deno.test("provider outages do not permanently block attempt analysis", () => {
  assert.equal(analysisRetryExhausted("ai_unavailable", 3), false);
  assert.equal(analysisRetryExhausted("ai_rate_limited", 10), false);
  assert.equal(analysisRetryExhausted("invalid_asset", 3), true);
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
Deno.test("practice category accepts only the taxonomy or nothing", () => {
  assert.equal(practiceCategory(undefined), null);
  assert.equal(practiceCategory(null), null);
  assert.equal(practiceCategory(""), null);
  assert.equal(practiceCategory("sinal"), "sinal");
  for (const value of ["Sinal", "algebra", 3, {}]) {
    assert.throws(() => practiceCategory(value), PublicError);
  }
});
Deno.test("rankConcepts weighs frequency and recency and discounts recovery", () => {
  const now = new Date("2026-10-26T12:00:00Z");
  const daysAgo = (d: number) => new Date(now.getTime() - d * 86_400_000);
  const errors = [
    { concept: "Frações", category: "calculo" as const, at: daysAgo(30) },
    { concept: "frações", category: "sinal" as const, at: daysAgo(29) },
    { concept: "Frações", category: "calculo" as const, at: daysAgo(28) },
    { concept: "Equações", category: "sinal" as const, at: daysAgo(1) },
    { concept: "Unidades", category: "unidade" as const, at: daysAgo(2) },
    { concept: "Unidades", category: "unidade" as const, at: daysAgo(3) },
  ];
  const ranked = rankConcepts(errors, [], now);
  // Dois erros recentes valem mais que três erros de um mês atrás.
  assert.deepEqual(ranked.map((r) => r.concept), [
    "Unidades",
    "Equações",
    "Frações",
  ]);
  assert.equal(ranked[2].frequency, 3);
  assert.deepEqual(ranked[2].categories.sort(), ["calculo", "sinal"]);
  // Filtro por tipo de erro.
  assert.deepEqual(
    rankConcepts(errors, [], now, "sinal").map((r) => r.concept),
    ["Equações", "frações"],
  );
  // Acertos depois do último erro reduzem a prioridade; três o removem.
  const partial = rankConcepts(errors, [
    { concept: "UNIDADES", at: daysAgo(1) },
    { concept: "Unidades", at: daysAgo(1) },
  ], now);
  assert.deepEqual(partial.map((r) => r.concept), [
    "Equações",
    "Frações",
    "Unidades",
  ]);
  assert.ok(Math.abs(partial[2].mastery - 2 / 3) < 1e-9);
  const recovered = rankConcepts(errors, [
    { concept: "Unidades", at: daysAgo(1) },
    { concept: "Unidades", at: daysAgo(1) },
    { concept: "Unidades", at: daysAgo(0.5) },
  ], now);
  assert.ok(!recovered.some((r) => r.concept === "Unidades"));
  // Acertos anteriores ao último erro não contam como recuperação.
  const stale = rankConcepts(errors, [
    { concept: "Unidades", at: daysAgo(10) },
  ], now);
  assert.equal(stale[0].mastery, 0);
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
  assert.equal(validatePractice({ exercises }, 3, ["Adição"]).length, 3);
  assert.throws(
    () => validatePractice({ exercises }, 3, ["Frações"]),
    PublicError,
  );
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
Deno.test("CORS accepts loopback dev ports and configured origins only", () => {
  const origins = (list?: string) => (name: string) =>
    name === "ALLOWED_ORIGINS" ? list : undefined;
  for (
    const origin of [
      "http://127.0.0.1:65360",
      "http://localhost:5000",
      "http://localhost",
      "http://[::1]:8080",
    ]
  ) assert.equal(originAllowed(origin, origins()), true, origin);
  for (
    const origin of [
      "",
      "null",
      "https://evil.example",
      "http://localhost.evil.example",
      "http://127.0.0.1.nip.io",
      "http://127.0.0.1:65360/path",
    ]
  ) assert.equal(originAllowed(origin, origins()), false, origin);
  const configured = origins(" https://app.example , https://b.example");
  assert.equal(originAllowed("https://app.example", configured), true);
  assert.equal(originAllowed("https://c.example", configured), false);
  const headers = (origin: string) =>
    new Headers(
      cors(
        new Request("https://example.invalid", { headers: { Origin: origin } }),
        origins(),
      ),
    ).get("Access-Control-Allow-Origin");
  assert.equal(headers("http://127.0.0.1:65360"), "http://127.0.0.1:65360");
  // Refused origins get no Allow-Origin at all; "null" would admit opaque
  // origins (sandboxed iframes), which send `Origin: null`.
  assert.equal(headers("https://evil.example"), null);
  assert.equal(headers("null"), null);
});
Deno.test("generateContent sends JSON Schema output, low thinking and the key only in a header", async () => {
  const result = await structuredResponse(
    { ...options, images: ["data:image/png;base64,AAAA"] },
    config,
    fetchMock((url, init) => {
      assert.equal(
        String(url),
        "https://generativelanguage.googleapis.com/v1beta/models/test-model:generateContent",
      );
      const headers = new Headers(init?.headers);
      assert.equal(headers.get("x-goog-api-key"), "test-only-placeholder");
      const request = JSON.parse(String(init?.body));
      // responseFormat accepts additionalProperties and ["boolean","null"];
      // the legacy responseSchema rejects both with HTTP 400.
      assert.deepEqual(request.generationConfig.responseFormat, {
        text: { mimeType: "APPLICATION_JSON", schema: analysisSchema },
      });
      assert.equal(request.generationConfig.responseSchema, undefined);
      assert.equal(request.generationConfig.response_schema, undefined);
      assert.equal(request.generationConfig.maxOutputTokens, 12000);
      assert.deepEqual(request.generationConfig.thinkingConfig, {
        thinkingLevel: "LOW",
      });
      assert.equal(request.systemInstruction.parts[0].text, "Tutor");
      assert.equal(request.contents[0].parts[0].text, options.text);
      assert.deepEqual(request.contents[0].parts[1], {
        inlineData: { mimeType: "image/png", data: "AAAA" },
      });
      assert.ok(!String(init?.body).includes("test-only-placeholder"));
      return wrapped(sample());
    }),
  );
  assert.deepEqual(validateAnalysis(result), sample());
});
Deno.test("Anthropic e OpenRouter recebem imagem e retornam JSON estruturado", async () => {
  for (const provider of ["anthropic", "openrouter"]) {
    const values: Record<string, string> = {
      AI_PROVIDER: provider,
      ANTHROPIC_API_KEY: "test-only-key",
      ANTHROPIC_MODEL: "claude-sonnet-5-5",
      ANTHROPIC_WORKSPACE_ID: "wrkspc_test",
      OPENROUTER_API_KEY: "test-only-key",
      OPENROUTER_MODEL: "test/model",
    };
    const result = await structuredResponse(
      { ...options, images: ["data:image/png;base64,AAAA"] },
      (key) => values[key],
      fetchMock((url, init) => {
        assert.match(
          String(url),
          provider === "anthropic" ? /api\.anthropic\.com/ : /openrouter\.ai/,
        );
        const request = JSON.parse(String(init?.body));
        assert.equal(
          new Headers(init?.headers).get("anthropic-workspace-id"),
          provider === "anthropic" ? "wrkspc_test" : null,
        );
        assert.equal(JSON.stringify(request).includes("test-only-key"), false);
        assert.equal(request.messages.at(-1).content.length, 2);
        if (String(url).endsWith("/count_tokens")) {
          return new Response(JSON.stringify({ input_tokens: 100 }));
        }
        return new Response(
          JSON.stringify(
            provider === "anthropic"
              ? {
                stop_reason: "end_turn",
                usage: { input_tokens: 100, output_tokens: 50 },
                content: [{ type: "text", text: JSON.stringify(sample()) }],
              }
              : {
                choices: [{
                  finish_reason: "stop",
                  message: { content: JSON.stringify(sample()) },
                }],
              },
          ),
        );
      }),
      {
        reserve: () => Promise.resolve("test-reservation"),
        settle: () => Promise.resolve(),
      },
    );
    assert.deepEqual(validateAnalysis(result), sample());
  }
});
Deno.test("Claude não recebe chamada de geração quando orçamento foi esgotado", async () => {
  const values: Record<string, string> = {
    AI_PROVIDER: "anthropic",
    ANTHROPIC_API_KEY: "test",
    ANTHROPIC_MODEL: "claude-sonnet-5-5",
  };
  const calls: string[] = [];
  await assert.rejects(
    () =>
      structuredResponse(
        options,
        (key) => values[key],
        fetchMock((url) => {
          calls.push(String(url));
          return new Response(JSON.stringify({ input_tokens: 100 }));
        }),
        {
          reserve: () => Promise.resolve(null),
          settle: () => Promise.resolve(),
        },
      ),
    (error: unknown) =>
      error instanceof PublicError && error.code === "ai_budget_exhausted",
  );
  assert.equal(calls.length, 1);
  assert.match(calls[0], /count_tokens$/);
});
Deno.test("fallback para Claude reserva orçamento antes de gerar", async () => {
  const values: Record<string, string> = {
    GEMINI_API_KEY: "test",
    ANTHROPIC_API_KEY: "test",
    AI_CLAUDE_FALLBACK_ENABLED: "true",
  };
  const calls: string[] = [];
  let reserved = false;
  let charged = false;
  const result = await structuredResponse(
    options,
    (key) => values[key],
    fetchMock((url) => {
      calls.push(String(url));
      if (String(url).includes("generativelanguage")) {
        return new Response("{}", { status: 400 });
      }
      if (String(url).endsWith("/count_tokens")) {
        return new Response(JSON.stringify({ input_tokens: 100 }));
      }
      assert.equal(reserved, true);
      return new Response(
        JSON.stringify({
          stop_reason: "end_turn",
          usage: { input_tokens: 100, output_tokens: 50 },
          content: [{ type: "text", text: JSON.stringify(sample()) }],
        }),
      );
    }),
    {
      reserve: () => {
        reserved = true;
        return Promise.resolve("reservation");
      },
      settle: () => {
        charged = true;
        return Promise.resolve();
      },
    },
  );
  assert.equal(calls.length, 3);
  assert.equal(charged, true);
  assert.deepEqual(validateAnalysis(result), sample());
});
Deno.test("roteamento por tipo de solicitação seleciona provedor e modelo configurados", async () => {
  const values: Record<string, string> = {
    AI_STUDY_PROVIDER: "openrouter",
    AI_STUDY_MODEL: "test/study-model",
    OPENROUTER_API_KEY: "test-only-key",
    GEMINI_API_KEY: "test-only-key",
  };
  const result = await structuredResponse(
    { ...options, name: "mistakemap_study" },
    (key) => values[key],
    fetchMock((url, init) => {
      assert.match(String(url), /openrouter\.ai/);
      assert.equal(JSON.parse(String(init?.body)).model, "test/study-model");
      return new Response(
        JSON.stringify({
          choices: [{
            finish_reason: "stop",
            message: { content: JSON.stringify(sample()) },
          }],
        }),
      );
    }),
  );
  assert.deepEqual(validateAnalysis(result), sample());
});
Deno.test("comparação seleciona modelo gratuito avaliado para a tarefa", async () => {
  const records = [
    {
      provider: "anthropic",
      model: "claude-sonnet-5-5",
      task: "analysis",
      datasetId: "test-v1",
      vision: true,
      samples: 30,
      quality: .99,
      latencyMs: 1000,
      costUsdPerRequest: 0,
      evaluatedAt: new Date().toISOString(),
    },
    {
      provider: "openrouter",
      model: "openrouter/free",
      task: "analysis",
      datasetId: "test-v1",
      vision: true,
      samples: 30,
      quality: .9,
      latencyMs: 1000,
      costUsdPerRequest: 0,
      evaluatedAt: new Date().toISOString(),
    },
    {
      provider: "gemini",
      model: "gemini-flash-latest",
      task: "analysis",
      datasetId: "test-v1",
      vision: true,
      samples: 30,
      quality: .85,
      latencyMs: 1000,
      costUsdPerRequest: 0,
      evaluatedAt: new Date().toISOString(),
    },
  ];
  const values: Record<string, string> = {
    GEMINI_API_KEY: "key",
    OPENROUTER_API_KEY: "key",
    AI_ROUTING_EVIDENCE: JSON.stringify(records),
  };
  const result = await structuredResponse(
    { ...options, name: "mistakemap_analysis" },
    (key) => values[key],
    fetchMock((url, init) => {
      assert.match(String(url), /openrouter\.ai/);
      assert.equal(JSON.parse(String(init?.body)).model, "openrouter/free");
      return new Response(
        JSON.stringify({
          choices: [{
            finish_reason: "stop",
            message: { content: JSON.stringify(sample()) },
          }],
        }),
      );
    }),
  );
  assert.deepEqual(validateAnalysis(result), sample());
});
Deno.test("falha do modelo gratuito retorna à configuração anterior", async () => {
  const records = [{
    provider: "openrouter",
    model: "openrouter/free",
    task: "analysis",
    datasetId: "test-v1",
    vision: false,
    samples: 30,
    quality: .9,
    latencyMs: 1000,
    costUsdPerRequest: 0,
    evaluatedAt: new Date().toISOString(),
  }, {
    provider: "gemini",
    model: "gemini-flash-latest",
    task: "analysis",
    datasetId: "test-v1",
    vision: false,
    samples: 30,
    quality: .85,
    latencyMs: 1000,
    costUsdPerRequest: 0,
    evaluatedAt: new Date().toISOString(),
  }];
  const values: Record<string, string> = {
    GEMINI_API_KEY: "key",
    OPENROUTER_API_KEY: "key",
    AI_ROUTING_EVIDENCE: JSON.stringify(records),
  };
  const calls: string[] = [];
  const result = await structuredResponse(
    { ...options, name: "mistakemap_analysis" },
    (key) => values[key],
    fetchMock((url) => {
      calls.push(String(url));
      return String(url).includes("openrouter.ai")
        ? new Response("", { status: 503 })
        : wrapped(sample());
    }),
  );
  assert.equal(calls.length, 2);
  assert.match(calls[1], /generativelanguage\.googleapis\.com/);
  assert.deepEqual(validateAnalysis(result), sample());
});
Deno.test("comparação mantém Gemini quando supera o modelo gratuito", async () => {
  const base = {
    task: "analysis",
    datasetId: "test-v1",
    vision: false,
    samples: 30,
    latencyMs: 1000,
    costUsdPerRequest: 0,
    evaluatedAt: new Date().toISOString(),
  };
  const records = [
    { ...base, provider: "gemini", model: "test-model", quality: .96 },
    { ...base, provider: "openrouter", model: "openrouter/free", quality: .89 },
  ];
  const values: Record<string, string> = {
    GEMINI_API_KEY: "key",
    GEMINI_MODEL: "test-model",
    OPENROUTER_API_KEY: "key",
    AI_ROUTING_EVIDENCE: JSON.stringify(records),
  };
  const result = await structuredResponse(
    { ...options, name: "mistakemap_analysis" },
    (key) => values[key],
    fetchMock((url) => {
      assert.match(String(url), /generativelanguage\.googleapis\.com/);
      return wrapped(sample());
    }),
  );
  assert.deepEqual(validateAnalysis(result), sample());
});
Deno.test("thought parts are skipped and split text parts are joined", async () => {
  const json = JSON.stringify(sample());
  const result = await structuredResponse(
    options,
    config,
    fetchMock(() =>
      new Response(JSON.stringify({
        candidates: [{
          content: {
            parts: [
              { text: "raciocínio interno", thought: true },
              { text: json.slice(0, 20) },
              { text: json.slice(20) },
            ],
            role: "model",
          },
          finishReason: "STOP",
        }],
      }))
    ),
  );
  assert.deepEqual(validateAnalysis(result), sample());
});
Deno.test("transient overload retries on a stable model and reports the model used", async () => {
  const urls: string[] = [];
  const used: string[] = [];
  const warn = console.warn;
  console.warn = () => {};
  try {
    const result = await structuredResponse(
      { ...options, onModelUsed: (model) => used.push(model) },
      config,
      fetchMock((url) => {
        urls.push(String(url));
        return urls.length === 1
          ? new Response("", { status: 503 })
          : wrapped(sample());
      }),
    );
    assert.deepEqual(validateAnalysis(result), sample());
  } finally {
    console.warn = warn;
  }
  assert.equal(urls.length, 2);
  assert.ok(urls[0].includes("/test-model:generateContent"));
  assert.ok(urls[1].includes("/gemini-3.6-flash:generateContent"));
  assert.deepEqual(used, ["gemini-3.6-flash"]);
});
Deno.test("overload and quota errors move through the model chain to Flash-Lite", async () => {
  const urls: string[] = [];
  const used: string[] = [];
  const warn = console.warn;
  console.warn = () => {};
  try {
    const result = await structuredResponse(
      { ...options, onModelUsed: (model) => used.push(model) },
      config,
      fetchMock((url) => {
        urls.push(String(url));
        if (urls.length === 1) return new Response("", { status: 503 });
        if (urls.length === 2) return new Response("", { status: 429 });
        return wrapped(sample());
      }),
    );
    assert.deepEqual(validateAnalysis(result), sample());
  } finally {
    console.warn = warn;
  }
  assert.equal(urls.length, 3);
  assert.ok(urls[2].includes("/gemini-3.5-flash-lite:generateContent"));
  assert.deepEqual(used, ["gemini-3.5-flash-lite"]);
});
Deno.test("model chain dedupes, honours off and repeats a single model", () => {
  assert.deepEqual(
    modelChain({ key: "k", model: "a", fallbackModel: "b", liteModel: "c" }),
    ["a", "b", "c"],
  );
  assert.deepEqual(
    modelChain({ key: "k", model: "a", fallbackModel: "a", liteModel: "off" }),
    ["a", "a", "a"],
  );
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
  const logged: string[] = [];
  const warn = console.warn;
  console.warn = (...args: unknown[]) => logged.push(args.join(" "));
  try {
    for (const status of [401, 429, 500]) {
      try {
        await structuredResponse(
          options,
          config,
          fetchMock(() =>
            new Response("SENSITIVE_PROVIDER_DETAIL", { status })
          ),
        );
        assert.fail("must reject");
      } catch (error) {
        assert.ok(error instanceof PublicError);
        assert.ok(!error.publicMessage.includes("SENSITIVE"));
        assert.equal(error.status, status === 429 ? 429 : 502);
      }
    }
    // Structured provider errors are logged (field names only) for diagnosis.
    await assert.rejects(() =>
      structuredResponse(
        options,
        config,
        fetchMock(() =>
          new Response(
            JSON.stringify({
              error: {
                status: "INVALID_ARGUMENT",
                message: 'Unknown name "additionalProperties"',
              },
            }),
            { status: 400 },
          )
        ),
      ), { code: "ai_unavailable" });
  } finally {
    console.warn = warn;
  }
  assert.ok(logged.every((line) => !line.includes("SENSITIVE")));
  assert.ok(logged.some((line) => line.includes("INVALID_ARGUMENT")));
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
Deno.test("provider refusals and blocked prompts map to 422 ai_refusal", async () => {
  const text = JSON.stringify(sample());
  const cases = [
    { promptFeedback: { blockReason: "SAFETY" } },
    ...["SAFETY", "RECITATION", "PROHIBITED_CONTENT", "IMAGE_SAFETY"].map((
      finishReason,
    ) => ({
      candidates: [{
        content: { parts: [{ text }], role: "model" },
        finishReason,
      }],
    })),
  ];
  for (const value of cases) {
    await assert.rejects(
      () =>
        structuredResponse(
          options,
          config,
          fetchMock(() => new Response(JSON.stringify(value))),
        ),
      { code: "ai_refusal", status: 422 },
    );
  }
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
    // Thinking consumed the budget: truncated JSON must not be parsed
    {
      candidates: [{
        content: { parts: [{ text: '{"is_correct": fal' }], role: "model" },
        finishReason: "MAX_TOKENS",
      }],
    },
    // Unknown or unexpected finish reason, even with complete JSON
    {
      candidates: [{
        content: {
          parts: [{ text: JSON.stringify(sample()) }],
          role: "model",
        },
        finishReason: "OTHER",
      }],
    },
    // Only thought parts
    {
      candidates: [{
        content: { parts: [{ text: "{}", thought: true }], role: "model" },
        finishReason: "STOP",
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
  for (const handler of [analyzeHandler, practiceHandler]) {
    const response = await handler(
      new Request("https://example.invalid", {
        method: "OPTIONS",
        headers: { Origin: "http://localhost:62159" },
      }),
    );
    assert.equal(response.status, 204);
    assert.equal(
      response.headers.get("Access-Control-Allow-Origin"),
      "http://localhost:62159",
    );
  }
  assert.equal(
    (await practiceHandler(new Request("https://example.invalid"))).status,
    405,
  );
});
