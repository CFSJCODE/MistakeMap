// Camada única de pagamento da escola. O resto do backend só conhece
// PaymentProvider; trocar ou somar gateway é escrever outra implementação.
//
// Hoje a única implementação é o Asaas (API REST v3), seguindo o roteiro de
// checkout transparente: o app fala só com a Edge Function, e ela orquestra
// cliente → cobrança (Pix, boleto ou cartão) → webhook → nota fiscal.
//
// - A chave vem do secret ASAAS_API_KEY da Edge Function, nunca do banco nem
//   do app. Só produção (dinheiro de verdade): a chave precisa começar com
//   $aact_prod_; qualquer outra é recusada.
// - Sem chave válida, a cobrança fica indisponível: não existe pagamento de
//   mentira nem de teste.
// - Cartão: número, validade e CVV só passam por aqui a caminho do Asaas.
//   Não são gravados nem registrados em log. Fica guardado só o
//   creditCardToken, para as faturas seguintes.
import { PublicError } from "./ai_contract.ts";
import { env, type Environment } from "./ai_http.ts";

export type PaymentMethod = "pix" | "boleto" | "credit_card";

export type ProviderCustomer = {
  name: string;
  cpfCnpj: string;
  email?: string | null;
  externalReference: string;
};

export type CardData = {
  holderName: string;
  number: string;
  expiryMonth: string;
  expiryYear: string;
  ccv: string;
};

export type CardHolderInfo = {
  name: string;
  email: string;
  cpfCnpj: string;
  postalCode: string;
  addressNumber: string;
  phone: string;
};

export type ChargeRequest = {
  customerId: string;
  method: PaymentMethod;
  value: number;
  dueDate: string; // AAAA-MM-DD
  description: string;
  externalReference: string; // id da fatura no MistakeMap
  /** Cartão novo (checkout) ou token salvo (faturas seguintes). */
  card?: { data: CardData; holder: CardHolderInfo } | { token: string };
  remoteIp?: string | null;
};

export type ProviderCharge = {
  id: string;
  status: ProviderStatus;
  invoiceUrl: string | null;
  bankSlipUrl: string | null;
  pixPayload: string | null;
  pixQrImage: string | null; // PNG em base64
  pixExpiresAt: string | null;
  boletoLine: string | null;
  cardToken: string | null;
  cardBrand: string | null;
  cardLast4: string | null;
};

/** Situação normalizada do pagamento no gateway. */
export type ProviderStatus =
  | "awaiting_payment"
  | "paid"
  | "overdue"
  | "canceled";

export type NfseRequest = {
  paymentId: string;
  value: number;
  description: string;
  observations: string;
  effectiveDate: string; // AAAA-MM-DD
  externalReference: string;
};

export type NfseStatus = "scheduled" | "issued" | "error" | "canceled";

export type NfseResult = {
  id: string;
  status: NfseStatus;
  number: string | null;
  pdfUrl: string | null;
};

export type PaymentEvent = {
  kind: "payment";
  eventId: string;
  event: string;
  paymentId: string | null;
  externalReference: string | null;
  status: ProviderStatus | null;
  paidAt: string | null;
  transactionId: string | null;
};

export type NfseEvent = {
  kind: "nfse";
  eventId: string;
  event: string;
  nfseId: string | null;
  paymentId: string | null;
  status: NfseStatus | null;
  number: string | null;
  pdfUrl: string | null;
  statusDescription: string | null;
};

export type ProviderEvent = PaymentEvent | NfseEvent;

export interface PaymentProvider {
  readonly name: "asaas";
  /** Serviço municipal configurado: dá para agendar a NFS-e. */
  readonly nfseEnabled: boolean;
  ensureCustomer(
    customer: ProviderCustomer,
    known: string | null,
  ): Promise<string>;
  createCharge(request: ChargeRequest): Promise<ProviderCharge>;
  getStatus(paymentId: string): Promise<ProviderStatus>;
  scheduleNfse(request: NfseRequest): Promise<NfseResult>;
}

// ---------------------------------------------------------------------------
// Asaas
// ---------------------------------------------------------------------------

export const ASAAS_PRODUCTION_URL = "https://api.asaas.com/v3";

/** Status de pagamento do Asaas → status normalizado. */
export function asaasStatus(status: unknown): ProviderStatus | null {
  switch (status) {
    case "RECEIVED":
    case "CONFIRMED":
    case "RECEIVED_IN_CASH":
    case "DUNNING_RECEIVED":
      return "paid";
    case "PENDING":
    case "AWAITING_RISK_ANALYSIS":
      return "awaiting_payment";
    case "OVERDUE":
    case "DUNNING_REQUESTED":
      return "overdue";
    case "REFUNDED":
    case "REFUND_REQUESTED":
    case "CHARGEBACK_REQUESTED":
    case "DELETED":
      return "canceled";
    default:
      return null;
  }
}

/** Status de nota fiscal do Asaas → status normalizado. */
export function asaasNfseStatus(status: unknown): NfseStatus | null {
  switch (status) {
    case "SCHEDULED":
    case "SYNCHRONIZED":
    case "PROCESSING_CANCELLATION":
    case "CANCELLATION_DENIED":
      return "scheduled";
    case "AUTHORIZED":
      return "issued";
    case "ERROR":
      return "error";
    case "CANCELED":
      return "canceled";
    default:
      return null;
  }
}

const str = (v: unknown) => typeof v === "string" && v ? v : null;
const obj = (v: unknown) =>
  v && typeof v === "object" ? v as Record<string, unknown> : {};

/** Evento de webhook do Asaas → evento normalizado (null se não for nosso). */
export function parseAsaasEvent(body: unknown): ProviderEvent | null {
  const b = obj(body);
  const event = str(b.event) ?? "";
  if (event.startsWith("INVOICE_")) {
    const n = obj(b.invoice);
    let status = asaasNfseStatus(n.status);
    if (event === "INVOICE_AUTHORIZED") status = "issued";
    else if (event === "INVOICE_ERROR") status = "error";
    else if (event === "INVOICE_CANCELED") status = "canceled";
    return {
      kind: "nfse",
      eventId: str(b.id) ??
        `${event}:${str(n.id) ?? "?"}:${str(n.status) ?? ""}`,
      event,
      nfseId: str(n.id),
      paymentId: str(n.payment),
      status,
      number: str(n.number) ??
        (typeof n.number === "number" ? String(n.number) : null),
      pdfUrl: str(n.pdfUrl),
      statusDescription: str(n.statusDescription),
    };
  }
  if (!event.startsWith("PAYMENT_")) return null;
  const p = obj(b.payment);
  let status = asaasStatus(p.status);
  if (event === "PAYMENT_RECEIVED" || event === "PAYMENT_CONFIRMED") {
    status = "paid";
  } else if (event === "PAYMENT_OVERDUE") status = "overdue";
  else if (event === "PAYMENT_DELETED" || event === "PAYMENT_REFUNDED") {
    status = "canceled";
  }
  const paymentId = str(p.id);
  return {
    kind: "payment",
    // O Asaas manda um id por evento; sem ele, o par evento+pagamento
    // ainda deduplica reenvios.
    eventId: str(b.id) ??
      `${event}:${paymentId ?? "?"}:${str(p.status) ?? ""}`,
    event,
    paymentId,
    externalReference: str(p.externalReference),
    status,
    paidAt: str(p.clientPaymentDate) ?? str(p.paymentDate) ??
      str(p.confirmedDate),
    transactionId: paymentId,
  };
}

type Fetch = typeof fetch;

/** Serviço municipal da NFS-e (secrets da Edge Function). */
export type NfseConfig = {
  municipalServiceCode: string;
  municipalServiceName: string;
  municipalServiceId: string | null;
  iss: number;
  retainIss: boolean;
};

export function nfseConfig(get: Environment = env): NfseConfig | null {
  const code = get("ASAAS_NFSE_SERVICE_CODE")?.trim();
  const name = get("ASAAS_NFSE_SERVICE_NAME")?.trim();
  if (!code || !name) return null;
  const iss = Number(get("ASAAS_NFSE_ISS")?.trim() || "2");
  return {
    municipalServiceCode: code,
    municipalServiceName: name,
    municipalServiceId: get("ASAAS_NFSE_SERVICE_ID")?.trim() || null,
    iss: Number.isFinite(iss) && iss >= 0 && iss <= 5 ? iss : 2,
    retainIss: get("ASAAS_NFSE_RETAIN_ISS")?.trim() === "true",
  };
}

export class AsaasProvider implements PaymentProvider {
  readonly name = "asaas" as const;
  readonly nfseEnabled: boolean;

  constructor(
    private readonly apiKey: string,
    private readonly baseUrl = ASAAS_PRODUCTION_URL,
    private readonly http: Fetch = fetch,
    private readonly nfse: NfseConfig | null = null,
  ) {
    this.nfseEnabled = nfse != null;
  }

  private async call(
    method: "GET" | "POST",
    path: string,
    body?: unknown,
  ): Promise<Record<string, unknown>> {
    const res = await this.http(`${this.baseUrl}${path}`, {
      method,
      headers: {
        "access_token": this.apiKey,
        "Content-Type": "application/json",
        // Exigido para contas criadas a partir de junho de 2024.
        "User-Agent": "MistakeMap",
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(25000),
    });
    const text = await res.text();
    let data: Record<string, unknown> = {};
    try {
      data = text ? JSON.parse(text) : {};
    } catch {
      data = {};
    }
    if (!res.ok) {
      const errors = Array.isArray(data.errors) ? data.errors : [];
      const description = errors.map((e) => str(obj(e).description) ?? "")
        .filter(Boolean).join(" ");
      // Log sem corpo: o pedido pode ter dados de cartão.
      console.warn(JSON.stringify({
        event: "asaas_error",
        status: res.status,
        path: path.replace(/\/(pay|cus|inv)_[A-Za-z0-9]+/, "/$1_*")
          .replace(/\?.*/, ""),
      }));
      throw new PublicError(
        res.status === 400 ? 422 : 502,
        res.status === 400 ? "gateway_refused" : "gateway_error",
        description
          ? `O Asaas recusou: ${description.slice(0, 200)}`
          : "O Asaas não respondeu. Tente de novo em instantes.",
      );
    }
    return data;
  }

  /** Reaproveita o cliente pelo CNPJ antes de criar um novo. */
  async ensureCustomer(c: ProviderCustomer, known: string | null) {
    if (known) return known;
    const found = await this.call(
      "GET",
      `/customers?cpfCnpj=${encodeURIComponent(c.cpfCnpj)}&limit=1`,
    );
    const first = Array.isArray(found.data) ? obj(found.data[0]) : {};
    const existing = str(first.id);
    if (existing && first.deleted !== true) return existing;
    const data = await this.call("POST", "/customers", {
      name: c.name,
      cpfCnpj: c.cpfCnpj,
      email: c.email ?? undefined,
      externalReference: c.externalReference,
      notificationDisabled: false,
    });
    const id = str(data.id);
    if (!id) {
      throw new PublicError(
        502,
        "gateway_error",
        "O Asaas não devolveu o cliente.",
      );
    }
    return id;
  }

  async createCharge(r: ChargeRequest): Promise<ProviderCharge> {
    const body: Record<string, unknown> = {
      customer: r.customerId,
      billingType: r.method === "pix"
        ? "PIX"
        : r.method === "boleto"
        ? "BOLETO"
        : "CREDIT_CARD",
      value: r.value,
      dueDate: r.dueDate,
      description: r.description.slice(0, 500),
      externalReference: r.externalReference,
    };
    if (r.method === "credit_card") {
      if (!r.card) {
        throw new PublicError(
          400,
          "card_required",
          "Informe os dados do cartão.",
        );
      }
      if ("token" in r.card) {
        body.creditCardToken = r.card.token;
      } else {
        body.creditCard = r.card.data;
        body.creditCardHolderInfo = r.card.holder;
      }
      if (r.remoteIp) body.remoteIp = r.remoteIp;
    }
    const data = await this.call("POST", "/payments", body);
    const id = str(data.id);
    if (!id) {
      throw new PublicError(
        502,
        "gateway_error",
        "O Asaas não devolveu a cobrança.",
      );
    }
    const card = obj(data.creditCard);
    const charge: ProviderCharge = {
      id,
      status: asaasStatus(data.status) ?? "awaiting_payment",
      invoiceUrl: str(data.invoiceUrl),
      bankSlipUrl: str(data.bankSlipUrl),
      pixPayload: null,
      pixQrImage: null,
      pixExpiresAt: null,
      boletoLine: null,
      cardToken: str(card.creditCardToken),
      cardBrand: str(card.creditCardBrand),
      cardLast4: str(card.creditCardNumber)?.replace(/\D/g, "").slice(-4) ||
        null,
    };
    if (r.method === "pix") {
      const pix = await this.call("GET", `/payments/${id}/pixQrCode`);
      charge.pixPayload = str(pix.payload);
      charge.pixQrImage = str(pix.encodedImage);
      charge.pixExpiresAt = str(pix.expirationDate);
    } else if (r.method === "boleto") {
      const line = await this.call(
        "GET",
        `/payments/${id}/identificationField`,
      );
      charge.boletoLine = str(line.identificationField);
    }
    return charge;
  }

  async getStatus(paymentId: string) {
    const data = await this.call(
      "GET",
      `/payments/${encodeURIComponent(paymentId)}`,
    );
    return asaasStatus(data.status) ?? "awaiting_payment";
  }

  async scheduleNfse(r: NfseRequest): Promise<NfseResult> {
    if (!this.nfse) {
      throw new PublicError(
        503,
        "nfse_not_configured",
        "Nota fiscal não configurada.",
      );
    }
    const data = await this.call("POST", "/invoices", {
      payment: r.paymentId,
      serviceDescription: r.description.slice(0, 500),
      observations: r.observations.slice(0, 500),
      externalReference: r.externalReference,
      value: r.value,
      deductions: 0,
      effectiveDate: r.effectiveDate,
      municipalServiceId: this.nfse.municipalServiceId ?? undefined,
      municipalServiceCode: this.nfse.municipalServiceCode,
      municipalServiceName: this.nfse.municipalServiceName,
      taxes: {
        retainIss: this.nfse.retainIss,
        iss: this.nfse.iss,
        cofins: 0,
        csll: 0,
        inss: 0,
        ir: 0,
        pis: 0,
      },
    });
    const id = str(data.id);
    if (!id) {
      throw new PublicError(
        502,
        "gateway_error",
        "O Asaas não devolveu a nota.",
      );
    }
    return {
      id,
      status: asaasNfseStatus(data.status) ?? "scheduled",
      number: str(data.number),
      pdfUrl: str(data.pdfUrl),
    };
  }
}

// ---------------------------------------------------------------------------
// Escolha do gateway
// ---------------------------------------------------------------------------

export type ProviderMode = "asaas" | "invalid_key" | "not_configured";

/**
 * Só produção: a chave precisa começar com $aact_prod_. Chave de sandbox
 * ($aact_hmlg_) ou de outro formato é recusada, para nunca haver cobrança
 * de teste no lugar da real.
 */
export function providerMode(get: Environment = env): ProviderMode {
  const key = get("ASAAS_API_KEY")?.trim();
  if (!key) return "not_configured";
  return key.startsWith("$aact_prod_") ? "asaas" : "invalid_key";
}

/** Gateway da escola: Asaas em produção. Sem chave válida, recusa. */
export function selectProvider(
  get: Environment = env,
  http: Fetch = fetch,
): PaymentProvider {
  const mode = providerMode(get);
  if (mode !== "asaas") {
    throw new PublicError(
      503,
      "billing_not_configured",
      "O pagamento pelo Asaas ainda não foi configurado no servidor.",
    );
  }
  return new AsaasProvider(
    get("ASAAS_API_KEY")!.trim(),
    ASAAS_PRODUCTION_URL,
    http,
    nfseConfig(get),
  );
}

/** Comparação em tempo constante para tokens de webhook e cron. */
export function sameSecret(
  a: string | null | undefined,
  b: string | null | undefined,
) {
  if (!a || !b) return false;
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  }
  return diff === 0;
}
