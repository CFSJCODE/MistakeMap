// Cobrança ponta a ponta contra o Postgres local do verify-school-billing.sh:
// Edge Function (billing_service.ts) + migrations, com um Asaas falso em
// memória no lugar da API. Nunca toca o banco publicado nem a API do Asaas.
import { strict as assert } from "node:assert";
import postgres from "postgresjs";
import { PublicError } from "../../supabase/functions/_shared/ai_contract.ts";
import type { Database } from "../../supabase/functions/_shared/ai_service.ts";
import {
  applyProviderEvent,
  billingOperation,
  issuePending,
  type ProviderFactory,
} from "../../supabase/functions/_shared/billing_service.ts";
import type {
  ChargeRequest,
  NfseRequest,
  PaymentProvider,
  ProviderStatus,
} from "../../supabase/functions/_shared/payment_provider.ts";
import { asUser } from "../../supabase/functions/_shared/school_admin_service.ts";

const url = Deno.env.get("SUPABASE_DB_URL");
if (!url) throw new Error("SUPABASE_DB_URL não definido");
const sql = postgres(url, { prepare: false, max: 1, onnotice: () => {} }) as unknown as Database;

/** Asaas de mentira: guarda clientes, cobranças e notas em memória. */
class FakeAsaas implements PaymentProvider {
  readonly name = "asaas" as const;
  customers = 0;
  charges = new Map<string, ProviderStatus>();
  requests: ChargeRequest[] = [];
  nfse: NfseRequest[] = [];
  refuseCard = false;
  constructor(readonly nfseEnabled = false, readonly prefix = "pay") {}
  ensureCustomer(_c: unknown, known: string | null) {
    if (known) return Promise.resolve(known);
    this.customers++;
    return Promise.resolve(`cus_${this.customers}`);
  }
  createCharge(r: ChargeRequest) {
    this.requests.push(r);
    if (r.method === "credit_card" && this.refuseCard) {
      return Promise.reject(
        new PublicError(422, "gateway_refused", "O Asaas recusou: Cartão recusado."),
      );
    }
    const id = `${this.prefix}_${this.requests.length}`;
    const card = r.method === "credit_card";
    const status: ProviderStatus = card ? "paid" : "awaiting_payment";
    this.charges.set(id, status);
    return Promise.resolve({
      id,
      status,
      invoiceUrl: `https://www.asaas.com/i/${id}`,
      bankSlipUrl: r.method === "boleto" ? `https://www.asaas.com/b/${id}` : null,
      pixPayload: r.method === "pix" ? "000201FAKE" : null,
      pixQrImage: r.method === "pix" ? "iVBORw0KGgo=" : null,
      pixExpiresAt: null,
      boletoLine: r.method === "boleto" ? "00190.00009 01234.567891 23456.789012 1 99990000015325" : null,
      cardToken: card && r.card && "data" in r.card ? "tok_1" : null,
      cardBrand: card ? "VISA" : null,
      cardLast4: card ? "1111" : null,
    });
  }
  getStatus(id: string) {
    return Promise.resolve(this.charges.get(id) ?? "awaiting_payment");
  }
  scheduleNfse(r: NfseRequest) {
    this.nfse.push(r);
    return Promise.resolve({ id: `nf_${this.nfse.length}`, status: "scheduled" as const, number: null, pdfUrl: null });
  }
}

const fake = new FakeAsaas();
const asaas: ProviderFactory = () => fake;
const withNfse = new FakeAsaas(true, "payn");
const asaasNfse: ProviderFactory = () => withNfse;
const noKey: ProviderFactory = () => {
  throw new PublicError(503, "billing_not_configured", "O pagamento pelo Asaas ainda não foi configurado no servidor.");
};

const OWNER = "d0000000-0000-4000-8000-000000000001";
const FIN = "d0000000-0000-4000-8000-000000000002";
const STUDENT = "d0000000-0000-4000-8000-000000000003";
const OWNER2 = "d0000000-0000-4000-8000-000000000004";
const IP = { remoteIp: "200.10.20.30" };
const CARD = {
  holder_name: "Escola Pequena de Robotica",
  number: "4111 1111 1111 1111",
  expiry_month: "03",
  expiry_year: "2031",
  ccv: "123",
};

async function op(user: string, input: Record<string, unknown>, providers = asaas) {
  // deno-lint-ignore no-explicit-any
  return await billingOperation(sql, user, input, providers, IP) as any;
}
async function rejects(promise: Promise<unknown>, status: number, label: string) {
  await assert.rejects(promise, (e: unknown) => {
    if (e instanceof PublicError && e.status === status) return true;
    throw new Error(`${label}: esperava ${status}, veio ${e}`);
  });
  console.log(`ok: ${label}`);
}
const ok = (cond: unknown, label: string) => {
  assert.ok(cond, label);
  console.log(`ok: ${label}`);
};
const paidEvent = (id: string, paymentId: string, ref: string) => ({
  kind: "payment" as const,
  eventId: id,
  event: "PAYMENT_RECEIVED",
  paymentId,
  externalReference: ref,
  status: "paid" as const,
  paidAt: "2026-11-12T15:00:00Z",
  transactionId: paymentId,
});

try {
  await sql`INSERT INTO auth.users(id, email) VALUES
    (${OWNER}, 'dono@nexo.dev'), (${FIN}, 'compras@nexo.dev'),
    (${STUDENT}, 'aluno@nexo.dev'), (${OWNER2}, 'dono@pequena.dev')`;

  // ------------------------------------------- escola pequena: dono paga no cartão
  const [{ id: small }] = await asUser(sql, OWNER2, (tx) =>
    tx`SELECT public.create_school('Escola Pequena de Robótica') AS id`);
  const ov = await op(OWNER2, { action: "overview", school_id: small });
  ok(ov.is_payer === true && ov.settings.payer_role === "owner", "escola pequena: o dono paga");
  ok(ov.provider === "not_configured", "sem chave de produção, cobrança indisponível");
  ok(ov.prices.length === 3 && ov.volume_discounts.length === 2, "tabela de preços e descontos");
  await rejects(
    op(OWNER2, { action: "checkout", school_id: small, plan: "escola", cycle: "monthly", students: 30, method: "pix" }, noKey),
    503,
    "sem chave do Asaas não há cobrança (nem simulada)",
  );
  await sql`UPDATE public.school_invoices SET status = 'canceled' WHERE school_id = ${small}`;
  await op(OWNER2, { action: "save_settings", school_id: small, cnpj: "11.444.777/0001-61" });
  await rejects(
    op(OWNER2, { action: "checkout", school_id: small, plan: "escola", cycle: "monthly", students: 30, method: "credit_card", card: CARD }),
    409,
    "cartão exige e-mail, CEP, número e telefone do titular",
  );
  const saved = await op(OWNER2, {
    action: "save_settings", school_id: small, billing_email: "dono@pequena.dev",
    postal_code: "30620-090", address_number: "126", phone: "(31) 3333-4444",
  });
  ok(saved.settings.postal_code === "30620090" && saved.settings.phone === "3133334444", "CEP e telefone gravados só com dígitos");
  ok(!("card_token" in saved.settings), "token do cartão nunca volta para o app");
  const small1 = await op(OWNER2, {
    action: "checkout", school_id: small, plan: "escola", cycle: "monthly",
    students: 30, method: "credit_card", card: CARD,
  });
  ok(small1.invoice.total === 360 && small1.invoice.status === "paid", "cartão de R$ 360 aprovado na hora");
  ok(small1.invoice.card_last4 === "1111" && small1.invoice.receipt_number?.startsWith("MM-"), "recibo com final do cartão");
  const sent = fake.requests.at(-1)!;
  ok(sent.remoteIp === "200.10.20.30" && sent.card && "data" in sent.card, "cartão vai ao Asaas com o IP de quem paga");
  const [card] = await sql`SELECT card_token, card_last4 FROM public.school_billing_settings WHERE school_id = ${small}`;
  ok(card.card_token === "tok_1" && card.card_last4 === "1111", "só o token do cartão fica guardado");
  const [plan] = await sql`SELECT plan, billing_cycle FROM public.schools WHERE id = ${small}`;
  ok(plan.plan === "escola" && plan.billing_cycle === "monthly", "plano Escola ativado");

  // Cartão recusado: fatura 'failed' (não tenta sozinho) e troca para Pix.
  fake.refuseCard = true;
  await rejects(
    op(OWNER2, { action: "checkout", school_id: small, plan: "plus", cycle: "monthly", students: 30, method: "credit_card", use_saved_card: true }),
    422,
    "cartão recusado devolve a mensagem do Asaas",
  );
  const [refused] = await sql`SELECT id, status, failure_reason FROM public.school_invoices
    WHERE school_id = ${small} AND plan = 'plus'`;
  ok(refused.status === "failed" && /recusado/.test(refused.failure_reason), "cobrança recusada fica 'failed' com o motivo");
  fake.refuseCard = false;
  const retry = await op(OWNER2, { action: "issue_invoice", invoice_id: refused.id, method: "pix" });
  ok(retry.invoice.status === "awaiting_payment" && retry.invoice.method === "pix", "reemissão em Pix depois da recusa");

  // ------------------------------------------ rede: financeiro/compras paga
  const [{ id: rede }] = await asUser(sql, OWNER, (tx) =>
    tx`SELECT public.create_school('Colégio Nexo — Unidade Vale do Ferro (teste)') AS id`);
  const [{ code: finCode }] = await asUser(sql, OWNER, (tx) =>
    tx`SELECT code FROM public.create_school_invite(${rede}::uuid, 'finance', 'compras@nexo.dev')`);
  const [{ code: stCode }] = await asUser(sql, OWNER, (tx) =>
    tx`SELECT code FROM public.create_school_invite(${rede}::uuid, 'student', null, 10, 7)`);
  await asUser(sql, FIN, (tx) => tx`SELECT * FROM public.redeem_school_invite(${finCode})`);
  await asUser(sql, STUDENT, (tx) => tx`SELECT * FROM public.redeem_school_invite(${stCode})`);
  await rejects(op(STUDENT, { action: "overview", school_id: rede }), 403, "aluno não abre a cobrança");
  await rejects(
    op(FIN, { action: "save_settings", school_id: rede, payer_role: "finance" }),
    403,
    "financeiro não se nomeia pagante",
  );
  await op(OWNER, {
    action: "save_settings", school_id: rede, payer_role: "finance",
    default_method: "boleto", due_days: 30,
  });
  await rejects(
    op(OWNER, { action: "checkout", school_id: rede, plan: "escola", cycle: "annual", students: 1935, method: "boleto" }),
    403,
    "no modelo rede o dono acompanha e não paga",
  );
  await rejects(
    op(FIN, { action: "checkout", school_id: rede, plan: "escola", cycle: "annual", students: 1935, method: "boleto" }),
    409,
    "Asaas exige CNPJ antes da cobrança",
  );
  await op(FIN, {
    action: "save_settings", school_id: rede, cnpj: "11.222.333/0001-81",
    legal_name: "Rede Nexo de Educação Tecnológica", billing_email: "compras@nexo.dev",
    purchase_order: "PC-2026-0042", cost_center: "CC-EDU-17",
  });
  const big = await op(FIN, {
    action: "checkout", school_id: rede, plan: "escola", cycle: "annual",
    students: 1935, method: "boleto",
  }, asaasNfse);
  ok(big.invoice.total === 15325.2 && big.invoice.volume_discount_percent === 20, "1.935 alunos: R$ 15.325,20 com −20%");
  ok(big.invoice.boleto_line && big.invoice.purchase_order === "PC-2026-0042", "boleto com pedido de compra");
  const payId = big.invoice.provider_payment_id;
  ok(big.invoice.provider === "asaas" && payId, "cobrança criada no Asaas");
  const ownerView = await op(OWNER, { action: "invoice_status", invoice_id: big.invoice.id }, asaasNfse);
  ok(ownerView.invoice.status === "awaiting_payment", "dono acompanha a fatura");

  // Webhook do Asaas confirma; reenvio é ignorado; a NFS-e é agendada.
  const event = paidEvent("evt_1", payId, big.invoice.id);
  ok(await applyProviderEvent(sql, "asaas", event, { id: "evt_1" }, asaasNfse) === "paid", "webhook confirma o pagamento");
  ok(await applyProviderEvent(sql, "asaas", event, { id: "evt_1" }, asaasNfse) === "duplicate", "webhook repetido é ignorado");
  const [after] = await sql`SELECT s.plan, s.billing_cycle, i.status, i.nfse_status, i.nfse_provider_id
    FROM public.schools s JOIN public.school_invoices i ON i.school_id = s.id
    WHERE i.id = ${big.invoice.id}`;
  ok(after.plan === "escola" && after.billing_cycle === "annual" && after.status === "paid", "rede no Escola anual");
  ok(after.nfse_status === "scheduled" && after.nfse_provider_id === "nf_1" && withNfse.nfse.length === 1, "NFS-e agendada no Asaas");
  const nfseEvent = {
    kind: "nfse" as const, eventId: "evt_n1", event: "INVOICE_AUTHORIZED", nfseId: "nf_1",
    paymentId: payId, status: "issued" as const, number: "4321", pdfUrl: "https://www.asaas.com/n/1",
    statusDescription: null,
  };
  ok(await applyProviderEvent(sql, "asaas", nfseEvent, { id: "evt_n1" }, asaasNfse) === "nfse_issued", "webhook da nota autorizada");
  const [nf] = await sql`SELECT nfse_status, nfse_number FROM public.school_invoices WHERE id = ${big.invoice.id}`;
  ok(nf.nfse_status === "issued" && nf.nfse_number === "4321", "número da NFS-e gravado");

  // Sem serviço municipal: a nota fica 'not_configured'.
  const again = await op(FIN, {
    action: "checkout", school_id: rede, plan: "plus", cycle: "monthly",
    students: 200, method: "pix",
  });
  ok(again.invoice.pix_qr_image === "iVBORw0KGgo=", "Pix do Asaas traz o QR");
  fake.charges.set(again.invoice.provider_payment_id, "paid");
  const polled = await op(FIN, { action: "invoice_status", invoice_id: again.invoice.id });
  ok(polled.invoice.status === "paid", "consulta ao Asaas confirma quando o webhook atrasa");
  ok(polled.invoice.nfse_status === "not_configured", "nota espera a configuração municipal");

  // Fechamento: mês anterior com ativos reais, cobrança emitida pelo cron.
  await sql`INSERT INTO public.school_usage_months(school_id, month, plan, active_students, extra_analyses)
    VALUES (${rede}, (public.school_usage_month() - interval '1 month')::date, 'plus', 1940, 120)`;
  const [{ n }] = await sql`SELECT public.school_close_month() AS n`;
  ok(n === 1, "fechamento do mês gera a fatura da rede");
  const result = await issuePending(sql, asaas);
  // As duas faturas da escola do tests.sql não têm CNPJ: ficam pendentes com
  // o motivo, para o reenvio.
  ok(result.issued === 1 && result.failed === 2, "cron emite a fatura pendente e guarda a que falhou");
  const [monthly] = await sql`SELECT status, method, total::float8 AS total, due_date - current_date AS days
    FROM public.school_invoices WHERE school_id = ${rede} AND kind = 'monthly'`;
  ok(monthly.status === "awaiting_payment" && monthly.method === "boleto" && monthly.days === 30, "fatura mensal em boleto com 30 dias");
  ok(monthly.total === Math.round(16 * 1940 * 0.8 * 100) / 100 + 18, "valor do fechamento: ativos × preço − 20% + extras");
  // Escola de demonstração nunca gera cobrança no Asaas.
  await sql`UPDATE public.school_billing_settings SET demo = true WHERE school_id = ${small}`;
  const before = fake.requests.length;
  await rejects(
    op(OWNER2, { action: "checkout", school_id: small, plan: "escola", cycle: "monthly", students: 30, method: "pix" }),
    409,
    "escola de demonstração não contrata",
  );
  ok(fake.requests.length === before, "nada foi enviado ao Asaas pela escola demo");
  console.log("service_test: todos os testes passaram");
} finally {
  await sql.end({ timeout: 2 });
}
