import { strict as assert } from "node:assert";
import { PublicError } from "../_shared/ai_contract.ts";
import {
  billingAction,
  cardInput,
  chargeDescription,
  dueDate,
  luhnValid,
  method,
  optionalCnpj,
  optionalDigits,
  optionalPayer,
  students,
} from "../_shared/billing_contract.ts";
import {
  ASAAS_PRODUCTION_URL,
  asaasNfseStatus,
  AsaasProvider,
  asaasStatus,
  nfseConfig,
  parseAsaasEvent,
  providerMode,
  sameSecret,
  selectProvider,
} from "../_shared/payment_provider.ts";
import {
  type BillingWebhookServices,
  createBillingWebhookHandler,
} from "../billing-webhook/handler.ts";
import { createSchoolBillingHandler } from "../school-billing/handler.ts";

// ------------------------------------------------------------------ contrato

Deno.test("cobrança aceita só as ações conhecidas", () => {
  assert.equal(billingAction("checkout"), "checkout");
  assert.throws(() => billingAction("mark_paid"), PublicError);
  // Só produção: não existe confirmação de pagamento de teste.
  assert.throws(() => billingAction("confirm_sandbox_payment"), PublicError);
  assert.throws(() => billingAction("simulate_payment"), PublicError);
});

Deno.test("formas de pagamento: Pix, boleto e cartão", () => {
  for (const m of ["pix", "boleto", "credit_card"]) {
    assert.equal(method({ method: m }), m);
  }
  assert.throws(() => method({ method: "dinheiro" }), PublicError);
});

Deno.test("cartão: Luhn, validade e código conferidos antes do gateway", () => {
  const now = new Date("2026-11-12T12:00:00Z");
  assert.equal(luhnValid("4111111111111111"), true);
  assert.equal(luhnValid("4111111111111112"), false);
  const card = {
    holder_name: "Rede Nexo",
    number: "4111 1111 1111 1111",
    expiry_month: "3",
    expiry_year: "29",
    ccv: "123",
  };
  assert.deepEqual(cardInput({ card }, now), {
    kind: "new",
    holderName: "Rede Nexo",
    number: "4111111111111111",
    expiryMonth: "03",
    expiryYear: "2029",
    ccv: "123",
  });
  assert.deepEqual(cardInput({ use_saved_card: true }, now), { kind: "saved" });
  assert.equal(cardInput({}, now), null);
  const bad = [
    { ...card, number: "4111111111111112" },
    { ...card, expiry_month: "13" },
    { ...card, expiry_month: "10", expiry_year: "2026" },
    { ...card, ccv: "12" },
    { ...card, holder_name: "" },
  ];
  for (const c of bad) {
    assert.throws(() => cardInput({ card: c }, now), PublicError);
  }
  // Mês corrente ainda vale.
  assert.ok(
    cardInput(
      { card: { ...card, expiry_month: "11", expiry_year: "2026" } },
      now,
    ),
  );
});

Deno.test("CEP e telefone viram só dígitos", () => {
  assert.equal(
    optionalDigits({ postal_code: "30620-090" }, "postal_code", [8]),
    "30620090",
  );
  assert.equal(
    optionalDigits({ phone: "(31) 3333-4444" }, "phone", [10, 11]),
    "3133334444",
  );
  assert.equal(optionalDigits({ phone: "" }, "phone", [10, 11]), "");
  assert.equal(optionalDigits({}, "phone", [10, 11]), null);
  assert.throws(
    () => optionalDigits({ postal_code: "123" }, "postal_code", [8]),
    PublicError,
  );
});

Deno.test("alunos estimados vão de 1 a 20.000", () => {
  assert.equal(students({ students: 1935 }), 1935);
  for (const value of [0, -1, 20001, 1.5, "30", null]) {
    assert.throws(() => students({ students: value }), PublicError);
  }
});

Deno.test("quem paga é dono ou financeiro", () => {
  assert.equal(optionalPayer({}), null);
  assert.equal(optionalPayer({ payer_role: "finance" }), "finance");
  assert.throws(() => optionalPayer({ payer_role: "it_admin" }), PublicError);
});

Deno.test("CNPJ da cobrança confere os dígitos verificadores", () => {
  assert.equal(optionalCnpj({ cnpj: "11.222.333/0001-81" }), "11222333000181");
  assert.equal(optionalCnpj({ cnpj: "" }), null);
  assert.throws(
    () => optionalCnpj({ cnpj: "11.222.333/0001-82" }),
    PublicError,
  );
});

Deno.test("vencimento é contado no dia de Brasília", () => {
  // 02:00 UTC de 13/11 ainda é 12/11 em Brasília.
  assert.equal(dueDate(1, new Date("2026-11-13T02:00:00Z")), "2026-11-13");
  assert.equal(dueDate(30, new Date("2026-11-12T15:00:00Z")), "2026-12-12");
});

Deno.test("descrição leva pedido de compra e centro de custo do financeiro", () => {
  const text = chargeDescription({
    kind: "monthly",
    plan: "escola",
    cycle: "annual",
    students: 1935,
    reference_month: "2026-10-01",
    purchase_order: "PC-2026-0042",
    cost_center: "CC-EDU-17",
    school_name: "Rede Nexo de Educação Tecnológica",
  });
  assert.match(text, /fechamento de outubro\/2026/);
  assert.match(text, /1935 alunos ativos/);
  assert.match(text, /Pedido de compra PC-2026-0042/);
  assert.match(text, /Centro de custo CC-EDU-17/);
});

// ------------------------------------------------------------------- gateway

Deno.test("status do Asaas viram status do MistakeMap", () => {
  assert.equal(asaasStatus("RECEIVED"), "paid");
  assert.equal(asaasStatus("CONFIRMED"), "paid");
  assert.equal(asaasStatus("PENDING"), "awaiting_payment");
  assert.equal(asaasStatus("OVERDUE"), "overdue");
  assert.equal(asaasStatus("REFUNDED"), "canceled");
  assert.equal(asaasStatus("???"), null);
});

Deno.test("webhook de pagamento do Asaas é normalizado", () => {
  const event = parseAsaasEvent({
    id: "evt_1",
    event: "PAYMENT_RECEIVED",
    payment: {
      id: "pay_9",
      status: "RECEIVED",
      externalReference: "8e8b6d6c-1d1f-4a5e-9a51-0e7c9bba3c11",
      paymentDate: "2026-11-12",
    },
  });
  assert.deepEqual(event, {
    kind: "payment",
    eventId: "evt_1",
    event: "PAYMENT_RECEIVED",
    paymentId: "pay_9",
    externalReference: "8e8b6d6c-1d1f-4a5e-9a51-0e7c9bba3c11",
    status: "paid",
    paidAt: "2026-11-12",
    transactionId: "pay_9",
  });
  assert.equal(parseAsaasEvent({ event: "TRANSFER_DONE" }), null);
  assert.equal(parseAsaasEvent("x"), null);
  assert.equal(
    parseAsaasEvent({ event: "PAYMENT_OVERDUE", payment: { id: "p" } })?.status,
    "overdue",
  );
});

Deno.test("webhook de nota fiscal do Asaas é normalizado", () => {
  const event = parseAsaasEvent({
    id: "evt_n",
    event: "INVOICE_AUTHORIZED",
    invoice: {
      id: "inv_1",
      payment: "pay_9",
      status: "AUTHORIZED",
      number: 1234,
      pdfUrl: "https://www.asaas.com/n/1",
    },
  });
  assert.equal(event?.kind, "nfse");
  if (event?.kind !== "nfse") return;
  assert.equal(event.status, "issued");
  assert.equal(event.number, "1234");
  assert.equal(event.nfseId, "inv_1");
  assert.equal(event.paymentId, "pay_9");
  assert.equal(asaasNfseStatus("SCHEDULED"), "scheduled");
  assert.equal(
    parseAsaasEvent({ event: "INVOICE_ERROR", invoice: { id: "i" } })?.status,
    "error",
  );
});

Deno.test("só a chave de produção do Asaas é aceita", () => {
  const key = (value?: string) => (name: string) =>
    name === "ASAAS_API_KEY" ? value : undefined;
  assert.equal(providerMode(key("$aact_prod_abc")), "asaas");
  assert.equal(providerMode(key("$aact_hmlg_abc")), "invalid_key");
  assert.equal(providerMode(key("qualquer")), "invalid_key");
  assert.equal(providerMode(key()), "not_configured");
  assert.equal(selectProvider(key("$aact_prod_abc")).name, "asaas");
  for (const value of [undefined, "", "$aact_hmlg_abc", "k"]) {
    assert.throws(
      () => selectProvider(key(value)),
      (e: unknown) => e instanceof PublicError && e.status === 503,
    );
  }
});

Deno.test("nota fiscal só com o serviço municipal configurado", () => {
  assert.equal(nfseConfig(() => undefined), null);
  const cfg = nfseConfig((name) =>
    ({
      ASAAS_NFSE_SERVICE_CODE: "01.07",
      ASAAS_NFSE_SERVICE_NAME: "Suporte técnico em informática",
    } as Record<string, string>)[name]
  );
  assert.equal(cfg?.municipalServiceCode, "01.07");
  assert.equal(cfg?.iss, 2);
});

type Call = { url: string; method: string; key: string | null; body: unknown };

function fakeAsaas(respond: (url: string, method: string) => unknown) {
  const calls: Call[] = [];
  const http = (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    const headers = new Headers(init?.headers);
    const method = init?.method ?? "GET";
    calls.push({
      url,
      method,
      key: headers.get("access_token"),
      body: init?.body ? JSON.parse(String(init.body)) : null,
    });
    return Promise.resolve(
      new Response(JSON.stringify(respond(url, method) ?? {}), { status: 200 }),
    );
  };
  return { calls, http: http as typeof fetch };
}

Deno.test("Asaas: produção, chave no cabeçalho, cliente reaproveitado e Pix com QR", async () => {
  const { calls, http } = fakeAsaas((url, method) => {
    if (url.includes("/customers?cpfCnpj=")) return { data: [] };
    if (url.endsWith("/customers") && method === "POST") return { id: "cus_1" };
    if (url.endsWith("/payments")) {
      return {
        id: "pay_1",
        status: "PENDING",
        invoiceUrl: "https://www.asaas.com/i/1",
      };
    }
    if (url.endsWith("/pixQrCode")) {
      return {
        encodedImage: "iVBOR",
        payload: "000201PIX",
        expirationDate: "2026-11-13 23:59:59",
      };
    }
    if (url.endsWith("/pay_1")) return { id: "pay_1", status: "RECEIVED" };
  });
  const asaas = new AsaasProvider("$aact_prod_x", ASAAS_PRODUCTION_URL, http);
  const customer = await asaas.ensureCustomer({
    name: "Rede Nexo",
    cpfCnpj: "11222333000181",
    externalReference: "school-1",
  }, null);
  assert.equal(customer, "cus_1");
  assert.equal(calls[0].method, "GET");
  assert.match(
    calls[0].url,
    /^https:\/\/api\.asaas\.com\/v3\/customers\?cpfCnpj=11222333000181/,
  );
  assert.equal(
    await asaas.ensureCustomer({
      name: "x",
      cpfCnpj: "1",
      externalReference: "y",
    }, "cus_known"),
    "cus_known",
  );
  const charge = await asaas.createCharge({
    customerId: customer,
    method: "pix",
    value: 15325.2,
    dueDate: "2026-11-13",
    description: "MistakeMap",
    externalReference: "inv-1",
  });
  assert.equal(charge.pixPayload, "000201PIX");
  assert.equal(charge.pixQrImage, "iVBOR");
  assert.equal(charge.status, "awaiting_payment");
  assert.ok(calls.every((c) => c.key === "$aact_prod_x"));
  assert.ok(calls.every((c) => c.url.startsWith(ASAAS_PRODUCTION_URL)));
  const payment = calls.find((c) => c.url.endsWith("/payments"))!;
  assert.equal((payment.body as Record<string, unknown>).billingType, "PIX");
  assert.equal(await asaas.getStatus("pay_1"), "paid");
});

Deno.test("Asaas: cliente existente pelo CNPJ não é duplicado", async () => {
  const { calls, http } = fakeAsaas(() => ({ data: [{ id: "cus_old" }] }));
  const asaas = new AsaasProvider("$aact_prod_x", ASAAS_PRODUCTION_URL, http);
  assert.equal(
    await asaas.ensureCustomer({
      name: "x",
      cpfCnpj: "11222333000181",
      externalReference: "s",
    }, null),
    "cus_old",
  );
  assert.equal(calls.filter((c) => c.method === "POST").length, 0);
});

Deno.test("Asaas: cartão vai com titular e IP, e volta só o token", async () => {
  const { calls, http } = fakeAsaas(() => ({
    id: "pay_c",
    status: "CONFIRMED",
    creditCard: {
      creditCardNumber: "1111",
      creditCardBrand: "VISA",
      creditCardToken: "tok_abc",
    },
  }));
  const asaas = new AsaasProvider("$aact_prod_x", ASAAS_PRODUCTION_URL, http);
  const holder = {
    name: "Rede Nexo",
    email: "compras@nexo.dev",
    cpfCnpj: "11222333000181",
    postalCode: "30620090",
    addressNumber: "100",
    phone: "3133334444",
  };
  const charge = await asaas.createCharge({
    customerId: "cus_1",
    method: "credit_card",
    value: 360,
    dueDate: "2026-11-13",
    description: "MistakeMap",
    externalReference: "inv-2",
    card: {
      data: {
        holderName: "Rede Nexo",
        number: "4111111111111111",
        expiryMonth: "03",
        expiryYear: "2029",
        ccv: "123",
      },
      holder,
    },
    remoteIp: "200.10.20.30",
  });
  assert.equal(charge.status, "paid");
  assert.equal(charge.cardToken, "tok_abc");
  assert.equal(charge.cardLast4, "1111");
  const body = calls[0].body as Record<string, unknown>;
  assert.equal(body.billingType, "CREDIT_CARD");
  assert.equal(body.remoteIp, "200.10.20.30");
  assert.deepEqual(body.creditCardHolderInfo, holder);
  // Com token, o número do cartão não viaja de novo.
  await asaas.createCharge({
    customerId: "cus_1",
    method: "credit_card",
    value: 360,
    dueDate: "2026-12-13",
    description: "MistakeMap",
    externalReference: "inv-3",
    card: { token: "tok_abc" },
  });
  const second = calls[1].body as Record<string, unknown>;
  assert.equal(second.creditCardToken, "tok_abc");
  assert.equal(second.creditCard, undefined);
  await assert.rejects(
    () =>
      asaas.createCharge({
        customerId: "cus_1",
        method: "credit_card",
        value: 1,
        dueDate: "2026-12-13",
        description: "x",
        externalReference: "y",
      }),
    PublicError,
  );
});

Deno.test("Asaas: nota fiscal agendada com o serviço municipal", async () => {
  const { calls, http } = fakeAsaas(() => ({
    id: "inv_1",
    status: "SCHEDULED",
  }));
  const asaas = new AsaasProvider("$aact_prod_x", ASAAS_PRODUCTION_URL, http, {
    municipalServiceCode: "01.07",
    municipalServiceName: "Suporte técnico",
    municipalServiceId: null,
    iss: 2,
    retainIss: false,
  });
  assert.equal(asaas.nfseEnabled, true);
  const nfse = await asaas.scheduleNfse({
    paymentId: "pay_1",
    value: 360,
    description: "MistakeMap Escola",
    observations: "Recibo MM-2026-ABCDEF12",
    effectiveDate: "2026-11-12",
    externalReference: "inv-1",
  });
  assert.deepEqual(nfse, {
    id: "inv_1",
    status: "scheduled",
    number: null,
    pdfUrl: null,
  });
  assert.equal(calls[0].url, `${ASAAS_PRODUCTION_URL}/invoices`);
  const body = calls[0].body as Record<string, unknown>;
  assert.equal(body.payment, "pay_1");
  assert.equal(body.municipalServiceCode, "01.07");
  const without = new AsaasProvider("$aact_prod_x", ASAAS_PRODUCTION_URL, http);
  assert.equal(without.nfseEnabled, false);
});

Deno.test("Asaas: recusa vira mensagem pública sem a chave e sem log do corpo", async () => {
  const logs: string[] = [];
  const warn = console.warn;
  console.warn = (msg: string) => logs.push(String(msg));
  try {
    const http = () =>
      Promise.resolve(
        new Response(
          JSON.stringify({ errors: [{ description: "Cartão recusado." }] }),
          { status: 400 },
        ),
      );
    const asaas = new AsaasProvider(
      "$aact_prod_segredo",
      ASAAS_PRODUCTION_URL,
      http as typeof fetch,
    );
    await assert.rejects(
      () =>
        asaas.createCharge({
          customerId: "cus_1",
          method: "credit_card",
          value: 1,
          dueDate: "2026-11-13",
          description: "x",
          externalReference: "y",
          card: {
            data: {
              holderName: "x",
              number: "4111111111111111",
              expiryMonth: "03",
              expiryYear: "2029",
              ccv: "123",
            },
            holder: {
              name: "x",
              email: "x@y.z",
              cpfCnpj: "1",
              postalCode: "1",
              addressNumber: "1",
              phone: "1",
            },
          },
        }),
      (error: unknown) =>
        error instanceof PublicError && error.status === 422 &&
        error.publicMessage.includes("Cartão recusado.") &&
        !error.publicMessage.includes("segredo"),
    );
  } finally {
    console.warn = warn;
  }
  assert.ok(logs.length > 0);
  assert.ok(logs.every((l) => !l.includes("4111") && !l.includes("segredo")));
});

Deno.test("comparação de segredo", () => {
  assert.equal(sameSecret("abc", "abc"), true);
  assert.equal(sameSecret("abc", "abd"), false);
  assert.equal(sameSecret("abc", "abcd"), false);
  assert.equal(sameSecret(null, "abc"), false);
  assert.equal(sameSecret("", ""), false);
});

// ------------------------------------------------------------------ handlers

const post = (body: unknown, headers: Record<string, string> = {}) =>
  new Request("http://localhost/fn", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

function webhook(overrides: Partial<BillingWebhookServices> = {}) {
  const applied: string[] = [];
  let issued = 0;
  const handler = createBillingWebhookHandler({
    secret: (name) =>
      ({
        ASAAS_WEBHOOK_TOKEN: "token-do-webhook-com-32-caracteres!",
        SCHOOL_BILLING_CRON_SECRET: "segredo-do-cron-com-mais-de-24",
      } as Record<string, string>)[name],
    applyEvent: (event) => {
      applied.push(event.eventId);
      return Promise.resolve("paid");
    },
    issuePending: () => {
      issued++;
      return Promise.resolve({ issued: 2, failed: 0 });
    },
    ...overrides,
  });
  return { handler, applied, issued: () => issued };
}

const PAID = {
  id: "evt_1",
  event: "PAYMENT_RECEIVED",
  payment: { id: "pay_1", status: "RECEIVED" },
};

Deno.test("webhook recusa sem o token do Asaas", async () => {
  const { handler, applied } = webhook();
  assert.equal((await handler(post(PAID))).status, 401);
  assert.equal(
    (await handler(post(PAID, { "asaas-access-token": "errado" }))).status,
    401,
  );
  assert.equal(applied.length, 0);
});

Deno.test("webhook com token aplica o evento e responde 200", async () => {
  const { handler, applied } = webhook();
  const response = await handler(
    post(PAID, { "asaas-access-token": "token-do-webhook-com-32-caracteres!" }),
  );
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { received: true, result: "paid" });
  assert.deepEqual(applied, ["evt_1"]);
  const other = await handler(
    post({ event: "TRANSFER_DONE" }, {
      "asaas-access-token": "token-do-webhook-com-32-caracteres!",
    }),
  );
  assert.equal(other.status, 200);
});

Deno.test("webhook devolve 500 para o Asaas reenviar quando o banco falha", async () => {
  const { handler } = webhook({
    applyEvent: () => Promise.reject(new Error("db down")),
  });
  const response = await handler(
    post(PAID, { "asaas-access-token": "token-do-webhook-com-32-caracteres!" }),
  );
  assert.equal(response.status, 500);
});

Deno.test("cron emite pendentes só com o segredo certo", async () => {
  const { handler, issued } = webhook();
  assert.equal(
    (await handler(post({ action: "issue_pending" }, { "x-cron-secret": "x" })))
      .status,
    401,
  );
  const ok = await handler(
    post({ action: "issue_pending" }, {
      "x-cron-secret": "segredo-do-cron-com-mais-de-24",
    }),
  );
  assert.equal(ok.status, 200);
  assert.equal(issued(), 1);
  // O segredo do cron não serve de token do webhook.
  assert.equal(
    (await handler(post(PAID, {
      "asaas-access-token": "segredo-do-cron-com-mais-de-24",
    }))).status,
    401,
  );
});

Deno.test("school-billing confere o login antes do banco", async () => {
  const calls: unknown[] = [];
  const handler = createSchoolBillingHandler({
    authenticate: () =>
      Promise.reject(new PublicError(401, "unauthorized", "Entre.")),
    run: (_user, input) => {
      calls.push(input);
      return Promise.resolve({});
    },
  });
  assert.equal((await handler(post({ action: "overview" }))).status, 401);
  assert.equal(calls.length, 0);
});

Deno.test("school-billing passa o IP do proxy, nunca o do corpo", async () => {
  const seen: (string | null | undefined)[] = [];
  const handler = createSchoolBillingHandler({
    authenticate: () => Promise.resolve("u-1"),
    run: (_user, _input, context) => {
      seen.push(context.remoteIp);
      return Promise.resolve({});
    },
  });
  await handler(
    post({ action: "overview", remote_ip: "1.1.1.1" }, {
      "x-forwarded-for": "200.10.20.30, 10.0.0.1",
    }),
  );
  await handler(
    post({ action: "overview" }, { "x-forwarded-for": "<script>" }),
  );
  assert.deepEqual(seen, ["200.10.20.30", null]);
});

Deno.test("school-billing usa o usuário da sessão e recusa ação desconhecida", async () => {
  const users: string[] = [];
  const handler = createSchoolBillingHandler({
    authenticate: () => Promise.resolve("u-1"),
    run: (user) => {
      users.push(user);
      return Promise.resolve({ ok: true });
    },
  });
  assert.equal(
    (await handler(post({ action: "overview", user_id: "outro" }))).status,
    200,
  );
  assert.deepEqual(users, ["u-1"]);
  assert.equal((await handler(post({ action: "mark_paid" }))).status, 400);
  assert.equal((await handler(post("{"))).status, 400);
});
