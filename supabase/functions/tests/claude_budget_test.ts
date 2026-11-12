import { strict as assert } from "node:assert";
import {
  type ClaudeBudgetStore,
  claudeCharge,
  reserveClaude,
} from "../_shared/claude_budget.ts";
import { PublicError } from "../_shared/ai_contract.ts";

const config = {
  model: "claude-sonnet-5-5",
  key: "test",
  workspaceId: "workspace-test",
};
const request = { model: config.model, max_tokens: 16000, messages: [] };
const now = Date.parse("2026-11-01T00:00:00Z");
const store: ClaudeBudgetStore = {
  reserve: () => Promise.resolve("reservation"),
  settle: () => Promise.resolve(),
};
const count = (_: string | URL | Request, init?: RequestInit) => {
  assert.equal(
    new Headers(init?.headers).get("anthropic-workspace-id"),
    "workspace-test",
  );
  assert.equal(JSON.parse(String(init?.body)).max_tokens, undefined);
  return Promise.resolve(new Response(JSON.stringify({ input_tokens: 100 })));
};

Deno.test("reserva exige contagem e confirmação do banco", async () => {
  assert.equal(
    await reserveClaude(config, request, store, count as typeof fetch, now),
    "reservation",
  );
  await assert.rejects(
    () =>
      reserveClaude(
        config,
        request,
        { ...store, reserve: () => Promise.resolve(null) },
        count as typeof fetch,
        now,
      ),
    (e: unknown) =>
      e instanceof PublicError && e.code === "ai_budget_exhausted",
  );
});

Deno.test("recusa preço vencido, modelo não avaliado ou excesso de entrada", async () => {
  await assert.rejects(() =>
    reserveClaude(
      config,
      request,
      store,
      count as typeof fetch,
      Date.parse("2026-12-01T00:00:00Z"),
    )
  );
  await assert.rejects(() =>
    reserveClaude(
      { ...config, model: "other" },
      request,
      store,
      count as typeof fetch,
      now,
    )
  );
  await assert.rejects(() =>
    reserveClaude(
      config,
      request,
      store,
      (() =>
        Promise.resolve(
          new Response(JSON.stringify({ input_tokens: 100001 })),
        )) as typeof fetch,
      now,
    )
  );
});

Deno.test("liquidação mantém reserva para uso desconhecido ou acima dos limites", () => {
  assert.equal(claudeCharge({ input_tokens: 100, output_tokens: 50 }), .00077);
  assert.equal(
    claudeCharge({
      input_tokens: 100,
      output_tokens: 50,
      cache_creation_input_tokens: 1,
    }),
    null,
  );
  assert.equal(claudeCharge({ input_tokens: 100, output_tokens: 16001 }), null);
  assert.equal(claudeCharge({ input_tokens: 100 }), null);
});
