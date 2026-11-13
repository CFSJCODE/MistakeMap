import { strict as assert } from "node:assert";
import {
  functionName,
  recordFailure,
  shouldRecord,
} from "../_shared/ai_http.ts";

Deno.test("functionName lê o nome da Edge Function na URL", () => {
  assert.equal(
    functionName("https://x.supabase.co/functions/v1/analyze-attempt"),
    "analyze-attempt",
  );
  assert.equal(functionName("http://localhost/question-bank"), "question-bank");
  assert.equal(functionName("http://localhost/"), "unknown");
  assert.equal(functionName("http://localhost/%20drop"), "unknown");
  assert.equal(functionName("não é url"), "unknown");
});

Deno.test("shouldRecord guarda só limite e erro do servidor", () => {
  assert.equal(shouldRecord(400), false);
  assert.equal(shouldRecord(401), false);
  assert.equal(shouldRecord(429), true);
  assert.equal(shouldRecord(502), true);
});

Deno.test("recordFailure envia só função, código e status", async () => {
  const calls: { url: string; init?: RequestInit }[] = [];
  const fetcher = ((url: string, init?: RequestInit) => {
    calls.push({ url, init });
    return Promise.resolve(new Response(null, { status: 201 }));
  }) as typeof fetch;
  const get = (name: string) =>
    ({
      SUPABASE_URL: "https://x.supabase.co/",
      SUPABASE_SERVICE_ROLE_KEY: "service",
    })[name];
  const req = new Request(
    "https://x.supabase.co/functions/v1/analyze-attempt",
    {
      method: "POST",
      body: JSON.stringify({ secret: "resposta do aluno" }),
    },
  );

  await recordFailure(req, "invalid_ai_output", 502, get, fetcher);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "https://x.supabase.co/rest/v1/team_error_events");
  assert.deepEqual(JSON.parse(String(calls[0].init?.body)), {
    function_name: "analyze-attempt",
    code: "invalid_ai_output",
    status: 502,
  });

  await recordFailure(req, "unauthorized", 401, get, fetcher);
  await recordFailure(req, "internal_error", 500, () => undefined, fetcher);
  assert.equal(calls.length, 1);
});

Deno.test("recordFailure engole falha de rede", async () => {
  const fetcher = (() => Promise.reject(new Error("offline"))) as typeof fetch;
  const get = (name: string) =>
    ({ SUPABASE_URL: "https://x", SUPABASE_SERVICE_ROLE_KEY: "k" })[name];
  await recordFailure(
    new Request("https://x/functions/v1/health"),
    "internal_error",
    500,
    get,
    fetcher,
  );
});
