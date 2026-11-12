import { strict as assert } from "node:assert";
import {
  aiTierForPlan,
  providerAllowed,
  type RoutingEvidence,
  selectModel,
} from "../_shared/model_router.ts";

const now = Date.parse("2026-11-01T12:00:00Z");
const base: RoutingEvidence = {
  provider: "gemini",
  model: "a",
  task: "analysis",
  datasetId: "test-set-v1",
  vision: true,
  samples: 30,
  quality: .9,
  latencyMs: 1000,
  costUsdPerRequest: .001,
  evaluatedAt: "2026-10-31T12:00:00Z",
};

Deno.test("roteador considera qualidade antes de preço e tempo", () => {
  const high = {
    ...base,
    provider: "anthropic" as const,
    model: "b",
    quality: .96,
    costUsdPerRequest: .01,
  };
  assert.equal(
    selectModel([base, high], "analysis", false, now, .02)?.model,
    "b",
  );
  assert.equal(
    selectModel([base, high], "analysis", false, now, .005)?.model,
    undefined,
  );
});

Deno.test("roteador escolhe eficiência entre modelos de qualidade similar", () => {
  const near = { ...base, model: "b", quality: .91, costUsdPerRequest: .0001 };
  assert.equal(
    selectModel([base, near], "analysis", false, now, .1)?.model,
    "b",
  );
});

Deno.test("roteador rejeita evidências insuficientes, obsoletas e sem visão", () => {
  const entries = [
    { ...base, samples: 19 },
    { ...base, model: "old", evaluatedAt: "2026-08-01T00:00:00Z" },
    { ...base, model: "blind", vision: false },
    { ...base, model: "poor", quality: .79 },
  ];
  assert.equal(selectModel(entries, "analysis", true, now, .1), undefined);
  assert.equal(selectModel([base], "analysis", false, now, NaN), undefined);
  assert.equal(
    selectModel(
      [base, { ...base, model: "b", datasetId: "outro" }],
      "analysis",
      false,
      now,
      .1,
    ),
    undefined,
  );
});

Deno.test("plano define o nível de IA: Claude só no Escola Plus", () => {
  assert.equal(aiTierForPlan("plus"), "premium");
  for (const plan of ["free", "escola", "pro", "pilot", null, undefined, 3]) {
    assert.equal(aiTierForPlan(plan), "standard");
  }
  assert.equal(providerAllowed("anthropic", "standard"), false);
  assert.equal(providerAllowed(" Anthropic ", "standard"), false);
  assert.equal(providerAllowed("anthropic", "premium"), true);
  for (const provider of ["gemini", "openrouter", undefined]) {
    assert.equal(providerAllowed(provider, "standard"), true);
  }
});
