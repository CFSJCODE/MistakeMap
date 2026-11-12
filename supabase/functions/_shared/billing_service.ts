// Operações da cobrança da escola (Edge Functions school-billing e
// billing-webhook).
//
// Quem pode o quê é decidido no banco: leituras rodam como o usuário (RLS) e
// a permissão de pagar é public.school_is_payer(). As escritas de fatura usam
// a conexão do backend, sempre depois dessa conferência. O gateway fica atrás
// de PaymentProvider (payment_provider.ts).
import { PublicError } from "./ai_contract.ts";
import type { Database } from "./ai_service.ts";
import {
  type BillingAction,
  billingAction,
  type CardInput,
  cardInput,
  chargeDescription,
  cycle,
  dueDate,
  method,
  optionalBillingEmail,
  optionalCnpj,
  optionalDigits,
  optionalDueDays,
  optionalMethod,
  optionalPayer,
  optionalText,
  paidPlan,
  students,
  TEST_CHARGE_BRL,
} from "./billing_contract.ts";
import {
  type ChargeRequest,
  type PaymentProvider,
  type ProviderEvent,
  providerMode,
  selectProvider,
} from "./payment_provider.ts";
import { id, type Input } from "./platform_contract.ts";
import { asUser } from "./school_admin_service.ts";

/** Colunas da fatura que o app recebe (sem a imagem do QR na lista). */
const INVOICE_COLUMNS =
  `id, school_id, kind, reference_month::text AS reference_month,
  plan, cycle, students, price_per_student::float8 AS price_per_student,
  gross::float8 AS gross, volume_discount_percent, discount::float8 AS discount,
  minimum_applied, extra_analyses, extra_amount::float8 AS extra_amount,
  credit::float8 AS credit, total::float8 AS total, method, status,
  due_date::text AS due_date, purchase_order, cost_center, provider,
  provider_payment_id, pix_payload, pix_expires_at, boleto_line, invoice_url,
  bank_slip_url, card_brand, card_last4, nfse_status, nfse_number, nfse_url, receipt_number,
  transaction_id, failure_reason, demo, created_at, issued_at, paid_at`;

type Invoice = Record<string, unknown> & {
  id: string;
  school_id: string;
  provider: "asaas";
  status: string;
  provider_payment_id: string | null;
};

const ROLE_LABELS: Record<string, string> = {
  owner: "o dono da escola",
  finance: "o Financeiro/Compras",
};

export type ProviderFactory = () => PaymentProvider;

/** Dados do pedido que não vêm do app: o IP de quem paga (exigido no cartão). */
export type RequestContext = { remoteIp?: string | null };

/** Colunas de configuração que o app recebe (o token do cartão nunca vai). */
const SETTINGS_COLUMNS = `payer_role, default_method, due_days, legal_name,
  billing_email, purchase_order, cost_center, postal_code, address_number,
  phone, card_brand, card_last4, demo`;

async function settingsOf(sql: Database, school: string) {
  const [row] = await sql`SELECT s.id, s.name, s.cnpj, s.plan, s.billing_cycle,
      s.status, b.payer_role, b.default_method, b.due_days, b.legal_name,
      b.billing_email, b.purchase_order, b.cost_center, b.provider_customer_id,
      b.postal_code, b.address_number, b.phone, b.card_token, b.card_brand,
      b.card_last4, coalesce(b.demo, false) AS demo
    FROM public.schools s
    LEFT JOIN public.school_billing_settings b ON b.school_id = s.id
    WHERE s.id = ${school}`;
  if (!row) {
    throw new PublicError(404, "not_found", "Escola não encontrada.");
  }
  return row;
}

async function requirePayer(sql: Database, user: string, school: string) {
  const [row] = await asUser(
    sql,
    user,
    (tx) =>
      tx`SELECT public.school_is_payer(${school}::uuid) AS payer,
      public.is_school_member(${school}::uuid, array['owner']) AS owner,
      (SELECT payer_role FROM public.school_billing_settings
        WHERE school_id = ${school}) AS payer_role`,
  );
  if (!row?.payer) {
    const who = ROLE_LABELS[row?.payer_role ?? "owner"] ?? "quem paga";
    throw new PublicError(
      403,
      "not_payer",
      `Nesta escola quem escolhe o plano e paga é ${who}.`,
    );
  }
  return row;
}

async function invoiceFor(sql: Database, user: string, invoice: string) {
  // RLS: só dono e financeiro da escola enxergam a fatura.
  const [row] = await asUser(
    sql,
    user,
    (tx) =>
      tx.unsafe(
        `SELECT ${INVOICE_COLUMNS}, pix_qr_image FROM public.school_invoices WHERE id = $1`,
        [invoice],
      ),
  );
  if (!row) {
    throw new PublicError(404, "not_found", "Fatura não encontrada.");
  }
  return row as unknown as Invoice;
}

async function reload(sql: Database, invoice: string) {
  const [row] = await sql.unsafe(
    `SELECT ${INVOICE_COLUMNS}, pix_qr_image FROM public.school_invoices WHERE id = $1`,
    [invoice],
  );
  return row as unknown as Invoice;
}

/** Confirma o pagamento no banco (idempotente) e agenda a nota fiscal. */
export async function markPaid(
  sql: Database,
  invoice: string,
  paidAt: string | null,
  transaction: string | null,
  providers?: ProviderFactory,
) {
  await sql`SELECT public.school_invoice_paid(${invoice}::uuid,
    coalesce(${paidAt}::timestamptz, now()), ${transaction})`;
  if (providers) await scheduleNfse(sql, invoice, providers);
}

const isoDate = (value: unknown) =>
  String(value instanceof Date ? value.toISOString() : value).slice(0, 10);

/**
 * NFS-e da fatura paga, agendada no Asaas (POST /v3/invoices). Sem serviço
 * municipal configurado fica 'not_configured'. Uma falha aqui nunca desfaz o
 * pagamento: a nota fica 'error' para reenvio manual.
 */
export async function scheduleNfse(
  sql: Database,
  invoiceId: string,
  providers: ProviderFactory,
) {
  const [inv] = await sql`SELECT i.*, s.name AS school_name, b.legal_name
    FROM public.school_invoices i
    JOIN public.schools s ON s.id = i.school_id
    LEFT JOIN public.school_billing_settings b ON b.school_id = i.school_id
    WHERE i.id = ${invoiceId}`;
  if (
    // A cobrança de teste não gera nota fiscal.
    !inv || inv.kind === "test" || inv.status !== "paid" ||
    inv.nfse_status != null ||
    !inv.provider_payment_id || Number(inv.total) <= 0
  ) return;
  let provider: PaymentProvider;
  try {
    provider = providers();
  } catch {
    return;
  }
  if (!provider.nfseEnabled) {
    await sql`UPDATE public.school_invoices SET nfse_status = 'not_configured'
      WHERE id = ${invoiceId} AND nfse_status IS NULL`;
    return;
  }
  // Reserva antes de chamar o gateway: webhook e consulta podem chegar juntos.
  const [claimed] = await sql`UPDATE public.school_invoices
    SET nfse_status = 'scheduled' WHERE id = ${invoiceId} AND nfse_status IS NULL
    RETURNING id`;
  if (!claimed) return;
  try {
    const nfse = await provider.scheduleNfse({
      paymentId: inv.provider_payment_id,
      value: Number(inv.total),
      description: chargeDescription({
        kind: inv.kind,
        plan: inv.plan,
        cycle: inv.cycle,
        students: Number(inv.students),
        reference_month: inv.reference_month,
        purchase_order: inv.purchase_order,
        cost_center: inv.cost_center,
        school_name: inv.legal_name ?? inv.school_name,
      }),
      observations: inv.receipt_number
        ? `Recibo ${inv.receipt_number}`
        : "MistakeMap",
      effectiveDate: isoDate(inv.paid_at ?? new Date()),
      externalReference: inv.id,
    });
    await sql`UPDATE public.school_invoices SET nfse_provider_id = ${nfse.id},
        nfse_status = ${nfse.status}, nfse_number = ${nfse.number},
        nfse_url = ${nfse.pdfUrl}
      WHERE id = ${invoiceId}`;
  } catch {
    await sql`UPDATE public.school_invoices SET nfse_status = 'error'
      WHERE id = ${invoiceId}`;
  }
}

const missing = (field: string) =>
  new PublicError(
    409,
    "billing_data_required",
    `Preencha ${field} nos dados de cobrança antes de pagar com cartão.`,
  );

/** Cartão novo (dados + titular) ou o token salvo da escola. */
function cardFor(
  school: Record<string, unknown>,
  card: CardInput | null,
): ChargeRequest["card"] {
  if (!card || card.kind === "saved") {
    if (!school.card_token) {
      throw new PublicError(
        409,
        "card_required",
        "Não há cartão salvo. Escolha Pix ou boleto, ou informe um cartão.",
      );
    }
    return { token: String(school.card_token) };
  }
  if (!school.billing_email) throw missing("o e-mail de cobrança");
  if (!school.postal_code) throw missing("o CEP");
  if (!school.address_number) throw missing("o número do endereço");
  if (!school.phone) throw missing("o telefone");
  return {
    data: {
      holderName: card.holderName,
      number: card.number,
      expiryMonth: card.expiryMonth,
      expiryYear: card.expiryYear,
      ccv: card.ccv,
    },
    holder: {
      name: String(school.legal_name ?? school.name),
      email: String(school.billing_email),
      cpfCnpj: String(school.cnpj),
      postalCode: String(school.postal_code),
      addressNumber: String(school.address_number),
      phone: String(school.phone),
    },
  };
}

/**
 * Emite no gateway uma fatura 'pending': cria o cliente se preciso, gera o
 * Pix, o boleto ou a cobrança no cartão e grava o resultado. Em falha, Pix e
 * boleto ficam 'pending' com o motivo (o cron tenta de novo); cartão recusado
 * fica 'failed', para não repetir a tentativa sozinho.
 */
export async function issueInvoice(
  sql: Database,
  invoiceId: string,
  providers: ProviderFactory,
  options: { card?: CardInput | null; remoteIp?: string | null } = {},
): Promise<Invoice> {
  const [inv] =
    await sql`SELECT * FROM public.school_invoices WHERE id = ${invoiceId}`;
  if (!inv) throw new PublicError(404, "not_found", "Fatura não encontrada.");
  if (inv.status !== "pending") return await reload(sql, invoiceId);
  const school = await settingsOf(sql, inv.school_id);
  if (school.demo || inv.demo) {
    // Escola de demonstração nunca gera cobrança no Asaas.
    await sql`UPDATE public.school_invoices SET status = 'canceled',
        failure_reason = 'Escola de demonstração: sem cobrança.'
      WHERE id = ${inv.id} AND status = 'pending'`;
    throw new PublicError(
      409,
      "demo_school",
      "Escola de demonstração: nenhuma cobrança é gerada.",
    );
  }
  const isCard = inv.method === "credit_card";
  try {
    const provider = providers();
    if (!school.cnpj) {
      throw new PublicError(
        409,
        "cnpj_required",
        "Informe o CNPJ da escola nos dados de cobrança antes de gerar a cobrança.",
      );
    }
    const card = isCard ? cardFor(school, options.card ?? null) : undefined;
    const customer = await provider.ensureCustomer({
      name: school.legal_name ?? school.name,
      cpfCnpj: school.cnpj,
      email: school.billing_email,
      externalReference: school.id,
    }, school.provider_customer_id);
    if (customer !== school.provider_customer_id) {
      await sql`INSERT INTO public.school_billing_settings(school_id, provider, provider_customer_id)
        VALUES (${school.id}, 'asaas', ${customer})
        ON CONFLICT (school_id) DO UPDATE SET provider_customer_id = excluded.provider_customer_id,
          provider = 'asaas', updated_at = now()`;
    }
    const charge = await provider.createCharge({
      customerId: customer,
      method: inv.method,
      value: Number(inv.total),
      dueDate: isoDate(inv.due_date),
      description: chargeDescription({
        kind: inv.kind,
        plan: inv.plan,
        cycle: inv.cycle,
        students: Number(inv.students),
        reference_month: inv.reference_month,
        purchase_order: inv.purchase_order,
        cost_center: inv.cost_center,
        school_name: school.legal_name ?? school.name,
      }),
      externalReference: inv.id,
      card,
      remoteIp: options.remoteIp ?? null,
    });
    if (charge.cardToken) {
      // Só o token do Asaas fica guardado, para as próximas faturas.
      await sql`UPDATE public.school_billing_settings SET card_token = ${charge.cardToken},
          card_brand = ${charge.cardBrand}, card_last4 = ${charge.cardLast4},
          updated_at = now()
        WHERE school_id = ${school.id}`;
    }
    await sql`UPDATE public.school_invoices SET
        status = 'awaiting_payment', provider = ${provider.name},
        provider_payment_id = ${charge.id}, pix_payload = ${charge.pixPayload},
        pix_qr_image = ${charge.pixQrImage},
        pix_expires_at = ${charge.pixExpiresAt}::timestamptz,
        boleto_line = ${charge.boletoLine}, invoice_url = ${charge.invoiceUrl},
        bank_slip_url = ${charge.bankSlipUrl},
        card_brand = ${isCard ? charge.cardBrand ?? school.card_brand : null},
        card_last4 = ${isCard ? charge.cardLast4 ?? school.card_last4 : null},
        issued_at = now(), failure_reason = null
      WHERE id = ${inv.id}`;
    if (charge.status === "paid") {
      await markPaid(sql, inv.id, null, charge.id, providers);
    }
  } catch (error) {
    const reason = error instanceof PublicError
      ? error.publicMessage
      : "Gateway indisponível.";
    const refused = isCard && error instanceof PublicError &&
      error.status < 500;
    await sql`UPDATE public.school_invoices SET failure_reason = ${reason},
        status = ${refused ? "failed" : "pending"}
      WHERE id = ${inv.id} AND status = 'pending'`;
    throw error;
  }
  return await reload(sql, invoiceId);
}

/** Consulta o gateway quando o webhook ainda não chegou. */
async function refreshStatus(
  sql: Database,
  inv: Invoice,
  providers: ProviderFactory,
): Promise<Invoice> {
  if (
    inv.provider !== "asaas" || !inv.provider_payment_id ||
    !["awaiting_payment", "overdue"].includes(inv.status)
  ) return inv;
  const status = await providers().getStatus(inv.provider_payment_id);
  if (status === "paid") {
    await markPaid(sql, inv.id, null, inv.provider_payment_id, providers);
  } else if (status === "overdue" && inv.status !== "overdue") {
    await sql`UPDATE public.school_invoices SET status = 'overdue' WHERE id = ${inv.id}`;
  }
  return await reload(sql, inv.id);
}

async function overview(
  sql: Database,
  user: string,
  school: string,
) {
  const data = await asUser(sql, user, async (tx) => {
    const [row] = await tx`SELECT id, name, plan, status, billing_cycle, cnpj
      FROM public.schools WHERE id = ${school}`;
    if (!row) {
      throw new PublicError(
        404,
        "not_found",
        "Escola não encontrada na sua conta.",
      );
    }
    const [mine] = await tx`SELECT coalesce(array_agg(role), '{}') AS roles,
        public.school_is_payer(${school}::uuid) AS payer
      FROM public.school_members WHERE school_id = ${school} AND user_id = ${user}
        AND status = 'active'`;
    const roles: string[] = mine?.roles ?? [];
    if (!roles.some((r) => ["owner", "finance", "coordinator"].includes(r))) {
      throw new PublicError(
        403,
        "access_denied",
        "A cobrança é vista pelo dono e pelo financeiro.",
      );
    }
    const [settings] = await tx.unsafe(
      `SELECT ${SETTINGS_COLUMNS} FROM public.school_billing_settings
        WHERE school_id = $1`,
      [school],
    );
    const [quota] = await tx`SELECT month::text AS month, plan, plan_label,
        active_students, analyses_pot, analyses_used, extra_analyses,
        extra_analyses_brl::float8 AS extra_analyses_brl, practices_pot, practices_used
      FROM public.school_quota(${school}::uuid)`;
    const usage = await tx`SELECT month::text AS month, plan, active_students,
        analyses, extra_analyses, practices, closed_at
      FROM public.school_usage_months WHERE school_id = ${school}
      ORDER BY month DESC LIMIT 12`;
    const invoices = await tx.unsafe(
      `SELECT ${INVOICE_COLUMNS} FROM public.school_invoices
        WHERE school_id = $1 ORDER BY created_at DESC LIMIT 36`,
      [school],
    );
    const prices =
      await tx`SELECT p.plan, l.label, p.monthly_brl::float8 AS monthly_brl,
        p.annual_brl::float8 AS annual_brl, p.minimum_brl::float8 AS minimum_brl,
        l.analyses_per_active, l.practices_per_active,
        l.extra_analysis_brl::float8 AS extra_analysis_brl, l.ai_tier
      FROM public.school_plan_prices p JOIN public.school_plan_limits l USING (plan)
      ORDER BY p.monthly_brl`;
    const discounts = await tx`SELECT min_students, percent
      FROM public.school_volume_discounts ORDER BY min_students`;
    const members = await tx`SELECT role, count(*)::int AS total
      FROM public.school_members WHERE school_id = ${school} AND status = 'active'
      GROUP BY role`;
    return {
      school: {
        ...row,
        cnpj: roles.includes("owner") || mine?.payer ? row.cnpj : null,
      },
      my_roles: roles,
      is_payer: mine?.payer === true,
      settings: settings ??
        {
          payer_role: "owner",
          default_method: "pix",
          due_days: 5,
          demo: false,
        },
      quota: quota ?? null,
      usage,
      invoices,
      prices,
      volume_discounts: discounts,
      members,
    };
  });
  const row = data.school as Record<string, unknown>;
  // Previsão da fatura do mês com os ativos de agora.
  let forecast = null;
  const q = data.quota as Record<string, unknown> | null;
  if (q && ["escola", "plus"].includes(String(q.plan))) {
    const [f] = await sql`SELECT price_per_student::float8 AS price_per_student,
        gross::float8 AS gross, volume_discount_percent, discount::float8 AS discount,
        minimum_applied, extra_amount::float8 AS extra_amount, total::float8 AS total
      FROM public.school_billing_quote(${String(q.plan)}, ${
      String(row.billing_cycle)
    },
        ${Number(q.active_students ?? 0)}, ${Number(q.extra_analyses ?? 0)})`;
    forecast = f ?? null;
  }
  return {
    ...data,
    forecast,
    provider: providerMode(),
  };
}

export async function billingOperation(
  sql: Database,
  user: string,
  input: Input,
  providers: ProviderFactory = () => selectProvider(),
  context: RequestContext = {},
): Promise<unknown> {
  const action: BillingAction = billingAction(input.action);
  switch (action) {
    case "overview":
      return await overview(sql, user, id(input, "school_id"));
    case "quote": {
      const [row] = await asUser(
        sql,
        user,
        (tx) =>
          tx`SELECT price_per_student::float8 AS price_per_student, gross::float8 AS gross,
            volume_discount_percent, discount::float8 AS discount, minimum_applied,
            total::float8 AS total
          FROM public.school_billing_quote(${paidPlan(input)}, ${cycle(input)},
            ${students(input)})`,
      );
      return row;
    }
    case "save_settings": {
      const school = id(input, "school_id");
      const cnpj = optionalCnpj(input);
      const row = await asUser(sql, user, async (tx) => {
        await tx`SELECT public.save_school_billing_settings(${school}::uuid,
          ${optionalPayer(input)}, ${optionalMethod(input)},
          ${optionalDueDays(input)}, ${optionalText(input, "legal_name", 160)},
          ${optionalBillingEmail(input)},
          ${optionalText(input, "purchase_order", 60)},
          ${optionalText(input, "cost_center", 60)},
          ${optionalDigits(input, "postal_code", [8])},
          ${optionalText(input, "address_number", 20)},
          ${optionalDigits(input, "phone", [10, 11])})`;
        const [saved] = await tx.unsafe(
          `SELECT ${SETTINGS_COLUMNS} FROM public.school_billing_settings
            WHERE school_id = $1`,
          [school],
        );
        return saved;
      });
      if (cnpj) {
        // A função acima já conferiu que é o dono ou quem paga.
        await sql`UPDATE public.schools SET cnpj = ${cnpj} WHERE id = ${school}`;
      }
      return { settings: row, cnpj_saved: cnpj != null };
    }
    case "checkout": {
      const school = id(input, "school_id");
      const plan = paidPlan(input);
      const chosenCycle = cycle(input);
      const count = students(input);
      const chosenMethod = method(input);
      const card = chosenMethod === "credit_card" ? cardInput(input) : null;
      await requirePayer(sql, user, school);
      const settings = await settingsOf(sql, school);
      if (settings.demo) {
        throw new PublicError(
          409,
          "demo_school",
          "Escola de demonstração: nenhuma cobrança é gerada.",
        );
      }
      // Cobrança de contratação anterior ainda em aberto deixa de valer.
      await sql`UPDATE public.school_invoices SET status = 'canceled',
          failure_reason = 'Substituída por nova contratação.'
        WHERE school_id = ${school} AND kind = 'checkout'
          AND status IN ('pending','awaiting_payment')`;
      const days = chosenMethod === "boleto"
        ? Math.max(3, settings.due_days ?? 5)
        : 1;
      const [created] = await sql`INSERT INTO public.school_invoices(
          school_id, kind, reference_month, plan, cycle, students, price_per_student,
          gross, volume_discount_percent, discount, minimum_applied, total, method,
          due_date, purchase_order, cost_center, provider, demo, created_by)
        SELECT ${school}, 'checkout', public.school_usage_month(), q.plan, q.cycle,
          q.students, q.price_per_student, q.gross, q.volume_discount_percent,
          q.discount, q.minimum_applied, q.total, ${chosenMethod},
          ${
        dueDate(days)
      }::date, ${settings.purchase_order}, ${settings.cost_center},
          'asaas', ${settings.demo}, ${user}
        FROM public.school_billing_quote(${plan}, ${chosenCycle}, ${count}) q
        RETURNING id`;
      const invoice = await issueInvoice(sql, created.id, providers, {
        card,
        remoteIp: context.remoteIp,
      });
      return { invoice, provider: providerMode() };
    }
    case "test_charge": {
      // R$ 5 sem plano, só para provar Pix/boleto + webhook numa escola real.
      // Pago não muda o plano nem gera NFS-e; não entra no fechamento do mês.
      const school = id(input, "school_id");
      const chosenMethod = method(input);
      if (chosenMethod === "credit_card") {
        throw new PublicError(
          400,
          "invalid_method",
          "A cobrança de teste é só por Pix ou boleto.",
        );
      }
      await requirePayer(sql, user, school);
      const settings = await settingsOf(sql, school);
      if (settings.demo) {
        throw new PublicError(
          409,
          "demo_school",
          "Escola de demonstração: nenhuma cobrança é gerada.",
        );
      }
      await sql`UPDATE public.school_invoices SET status = 'canceled',
          failure_reason = 'Substituída por nova cobrança de teste.'
        WHERE school_id = ${school} AND kind = 'test'
          AND status IN ('pending','awaiting_payment')`;
      const days = chosenMethod === "boleto" ? 3 : 1;
      const [created] = await sql`INSERT INTO public.school_invoices(
          school_id, kind, reference_month, plan, cycle, students, price_per_student,
          gross, total, method, due_date, provider, demo, created_by)
        VALUES (${school}, 'test', public.school_usage_month(), 'escola', 'monthly',
          0, 0, ${TEST_CHARGE_BRL}, ${TEST_CHARGE_BRL}, ${chosenMethod},
          ${dueDate(days)}::date, 'asaas', false, ${user})
        RETURNING id`;
      const invoice = await issueInvoice(sql, created.id, providers, {
        remoteIp: context.remoteIp,
      });
      return { invoice, provider: providerMode() };
    }
    case "invoice_status": {
      const inv = await invoiceFor(sql, user, id(input, "invoice_id"));
      return { invoice: await refreshStatus(sql, inv, providers) };
    }
    case "issue_invoice": {
      // Reemite uma fatura que ficou pendente ou foi recusada, podendo trocar
      // a forma de pagamento (ex.: cartão recusado → Pix).
      const inv = await invoiceFor(sql, user, id(input, "invoice_id"));
      await requirePayer(sql, user, inv.school_id);
      const newMethod = optionalMethod({ default_method: input.method });
      const card = (newMethod ?? inv.method) === "credit_card"
        ? cardInput(input)
        : null;
      if (["pending", "failed"].includes(inv.status)) {
        await sql`UPDATE public.school_invoices SET status = 'pending',
            method = coalesce(${newMethod}, method)
          WHERE id = ${inv.id} AND status IN ('pending','failed')`;
      }
      return {
        invoice: await issueInvoice(sql, inv.id, providers, {
          card,
          remoteIp: context.remoteIp,
        }),
      };
    }
  }
}

/**
 * Evento do gateway (webhook). Idempotente: o mesmo evento gravado duas
 * vezes não é reprocessado. Devolve o que foi feito, para o log.
 */
export async function applyProviderEvent(
  sql: Database,
  provider: "asaas",
  event: ProviderEvent,
  payload: unknown,
  providers: ProviderFactory = () => selectProvider(),
): Promise<string> {
  const [inserted] = await sql`INSERT INTO public.school_payment_events(
      provider, event_id, event, provider_payment_id, payload)
    VALUES (${provider}, ${event.eventId}, ${event.event}, ${event.paymentId},
      ${sql.json(payload as never)})
    ON CONFLICT (provider, event_id) DO NOTHING RETURNING id`;
  if (!inserted) return "duplicate";
  let result = "ignored";
  let invoiceId: string | null = null;
  if (event.kind === "nfse") {
    const [inv] = await sql`SELECT id FROM public.school_invoices
      WHERE (${event.nfseId}::text IS NOT NULL AND nfse_provider_id = ${event.nfseId})
         OR (provider = ${provider} AND provider_payment_id = ${event.paymentId})
      LIMIT 1`;
    if (inv && event.status) {
      await sql`UPDATE public.school_invoices SET nfse_status = ${event.status},
          nfse_provider_id = coalesce(${event.nfseId}, nfse_provider_id),
          nfse_number = coalesce(${event.number}, nfse_number),
          nfse_url = coalesce(${event.pdfUrl}, nfse_url)
        WHERE id = ${inv.id}`;
      result = `nfse_${event.status}`;
    }
    invoiceId = inv?.id ?? null;
  } else {
    const ref = event.externalReference;
    const [inv] = await sql`SELECT id, status FROM public.school_invoices
      WHERE (provider = ${provider} AND provider_payment_id = ${event.paymentId})
         OR (${ref}::text IS NOT NULL
             AND ${ref} ~ '^[0-9a-f-]{36}$' AND id = ${ref}::uuid)
      LIMIT 1`;
    if (inv) {
      if (event.status === "paid") {
        await markPaid(
          sql,
          inv.id,
          event.paidAt,
          event.transactionId,
          providers,
        );
        result = "paid";
      } else if (
        event.status === "overdue" && inv.status === "awaiting_payment"
      ) {
        await sql`UPDATE public.school_invoices SET status = 'overdue' WHERE id = ${inv.id}`;
        result = "overdue";
      } else if (event.status === "canceled" && inv.status !== "paid") {
        await sql`UPDATE public.school_invoices SET status = 'canceled',
            failure_reason = ${`Cancelada no gateway (${event.event}).`}
          WHERE id = ${inv.id}`;
        result = "canceled";
      }
    }
    invoiceId = inv?.id ?? null;
  }
  await sql`UPDATE public.school_payment_events
    SET processed_at = now(), invoice_id = ${invoiceId}, error = null
    WHERE id = ${inserted.id}`;
  return result;
}

/** Cron: emite as faturas 'pending' (fechamento do mês e reenvios). */
export async function issuePending(
  sql: Database,
  providers: ProviderFactory = () => selectProvider(),
  limit = 50,
) {
  const rows = await sql`SELECT id FROM public.school_invoices
    WHERE status = 'pending' ORDER BY created_at LIMIT ${limit}`;
  let issued = 0;
  let failed = 0;
  for (const row of rows) {
    try {
      await issueInvoice(sql, row.id, providers);
      issued++;
    } catch {
      failed++;
    }
  }
  return { issued, failed };
}
