import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Modelos do checkout da escola (plano → confirmação → cobrança → recibo).
///
/// As telas falam só com [CheckoutGateway]. No app, o gateway é o
/// [ServerCheckoutGateway] (billing_repository.dart): o valor que vale é o
/// calculado no banco (school_billing_quote) e a cobrança é criada no Asaas
/// pela Edge Function school-billing. Aqui só há a estimativa mostrada
/// enquanto a escola ajusta alunos, ciclo e forma de pagamento.

enum CheckoutCycle {
  monthly('monthly'),
  annual('annual');

  const CheckoutCycle(this.wire);
  final String wire;
}

enum CheckoutMethod {
  pix('pix', 'Pix'),
  boleto('boleto', 'Boleto'),
  creditCard('credit_card', 'Cartão');

  const CheckoutMethod(this.wire, this.label);
  final String wire;
  final String label;

  static CheckoutMethod fromWire(Object? value) => CheckoutMethod.values
      .firstWhere((m) => m.wire == value, orElse: () => CheckoutMethod.pix);
}

/// Plano exibido no carrossel.
class CheckoutPlan {
  const CheckoutPlan({
    required this.id,
    required this.name,
    required this.priceLabel,
    required this.priceNote,
    required this.features,
    required this.monthlyPerStudent,
    required this.annualPerStudent,
    required this.analysesPerStudent,
  });

  final String id;
  final String name;
  final String priceLabel;
  final String priceNote;
  final List<String> features;
  final double monthlyPerStudent;
  final double annualPerStudent;
  final int analysesPerStudent;

  bool get isFree => monthlyPerStudent == 0 && annualPerStudent == 0;

  double pricePerStudent(CheckoutCycle cycle) =>
      cycle == CheckoutCycle.annual ? annualPerStudent : monthlyPerStudent;

  /// Desconto do anual sobre o mensal, em pontos percentuais inteiros.
  int get annualDiscountPercent {
    if (isFree) return 0;
    // Em centavos inteiros: 1 − 9,90/12 dá 17,5% e arredonda para 18%.
    final monthly = (monthlyPerStudent * 100).round();
    final annual = (annualPerStudent * 100).round();
    return ((monthly - annual) * 100 / monthly).round();
  }
}

/// Planos da tabela school_plan_prices (por aluno ativo).
const checkoutPlans = <CheckoutPlan>[
  CheckoutPlan(
    id: 'free',
    name: 'Grátis',
    priceLabel: r'R$ 0',
    priceNote: 'até 5 usuários',
    features: [
      '1 professor + 4 alunos',
      '20 análises por aluno/mês',
      '1 turma',
    ],
    monthlyPerStudent: 0,
    annualPerStudent: 0,
    analysesPerStudent: 20,
  ),
  CheckoutPlan(
    id: 'escola',
    name: 'Escola',
    priceLabel: r'R$ 9,90',
    priceNote: 'por aluno ativo/mês no anual',
    features: [
      'Professores ilimitados',
      '60 análises por aluno ativo',
      'Mapa da turma e relatórios',
    ],
    monthlyPerStudent: 12,
    annualPerStudent: 9.9,
    analysesPerStudent: 60,
  ),
  CheckoutPlan(
    id: 'plus',
    name: 'Plus',
    priceLabel: r'R$ 13,90',
    priceNote: 'por aluno ativo/mês no anual',
    features: [
      '100 análises por aluno ativo',
      'IA premium (Claude)',
      'Banco de questões da escola',
    ],
    monthlyPerStudent: 16,
    annualPerStudent: 13.9,
    analysesPerStudent: 100,
  ),
];

CheckoutPlan checkoutPlan(String id) =>
    checkoutPlans.firstWhere((p) => p.id == id, orElse: () => checkoutPlans[1]);

/// Alunos que o Grátis libera (1 professor + 4 alunos).
const freePlanStudents = 4;

/// Mínimo mensal dos planos pagos.
const paidPlanMinimum = 99.0;

/// Maior número de alunos numa contratação (mesmo limite do servidor).
const maxCheckoutStudents = 20000;

/// Desconto por volume (school_volume_discounts): a partir de N alunos.
const volumeDiscounts = <({int minStudents, int percent})>[
  (minStudents: 301, percent: 20),
  (minStudents: 101, percent: 10),
];

int volumeDiscountFor(int students) {
  for (final d in volumeDiscounts) {
    if (students >= d.minStudents) return d.percent;
  }
  return 0;
}

/// Orçamento da assinatura mostrado na confirmação.
class CheckoutQuote {
  const CheckoutQuote({
    required this.plan,
    required this.students,
    required this.cycle,
    required this.method,
    required this.pricePerStudent,
    required this.total,
    this.gross = 0,
    this.volumeDiscountPercent = 0,
    this.discount = 0,
    this.minimumApplied = false,
  });

  /// Mesma conta de public.school_billing_quote, para a estimativa na tela.
  factory CheckoutQuote.estimate({
    required CheckoutPlan plan,
    required int students,
    required CheckoutCycle cycle,
    required CheckoutMethod method,
  }) {
    final price = plan.pricePerStudent(cycle);
    final gross = _cents(price * students);
    final pct = plan.isFree ? 0 : volumeDiscountFor(students);
    final discount = _cents(gross * pct / 100);
    var net = gross - discount;
    var minimum = false;
    if (!plan.isFree && net < paidPlanMinimum) {
      net = paidPlanMinimum;
      minimum = true;
    }
    return CheckoutQuote(
      plan: plan,
      students: students,
      cycle: cycle,
      method: method,
      pricePerStudent: price,
      gross: gross,
      volumeDiscountPercent: pct,
      discount: discount,
      minimumApplied: minimum,
      total: _cents(net),
    );
  }

  final CheckoutPlan plan;
  final int students;
  final CheckoutCycle cycle;
  final CheckoutMethod method;
  final double pricePerStudent;
  final double gross;
  final int volumeDiscountPercent;
  final double discount;
  final bool minimumApplied;
  final double total;

  /// O total foi elevado ao mínimo mensal.
  bool get atMinimum => minimumApplied;

  int get releasedStudents => plan.isFree ? freePlanStudents : students;

  int get analysesQuota => plan.analysesPerStudent * releasedStudents;

  static double _cents(double value) => (value * 100).roundToDouble() / 100;
}

/// Cartão digitado na confirmação. Vai direto para a Edge Function, que o
/// repassa ao Asaas; o app não guarda nada disso.
class CheckoutCard {
  const CheckoutCard({
    required this.holderName,
    required this.number,
    required this.expiryMonth,
    required this.expiryYear,
    required this.ccv,
  });

  final String holderName;
  final String number;
  final String expiryMonth;
  final String expiryYear;
  final String ccv;

  String get digits => number.replaceAll(RegExp(r'\D'), '');

  String get last4 =>
      digits.length >= 4 ? digits.substring(digits.length - 4) : digits;

  Map<String, String> toJson() => {
    'holder_name': holderName.trim(),
    'number': digits,
    'expiry_month': expiryMonth.trim(),
    'expiry_year': expiryYear.trim(),
    'ccv': ccv.trim(),
  };

  /// Conferência local (o servidor confere de novo): Luhn, validade e CVV.
  /// Devolve a mensagem do primeiro problema, ou null.
  String? problem(DateTime now) {
    if (holderName.trim().length < 2) {
      return 'Informe o nome impresso no cartão.';
    }
    if (digits.length < 13 || digits.length > 19 || !luhnValid(digits)) {
      return 'Confira o número do cartão.';
    }
    final month = int.tryParse(expiryMonth.trim());
    var year = int.tryParse(expiryYear.trim());
    if (year != null && year < 100) year += 2000;
    if (month == null || month < 1 || month > 12 || year == null) {
      return 'Confira a validade (MM/AA).';
    }
    if (year < now.year || (year == now.year && month < now.month)) {
      return 'O cartão está vencido.';
    }
    if (!RegExp(r'^\d{3,4}$').hasMatch(ccv.trim())) {
      return 'Confira o código de segurança.';
    }
    return null;
  }

  /// Bandeira pelo prefixo, só para o desenho do cartão.
  String get brand {
    final d = digits;
    if (d.startsWith('4')) return 'VISA';
    if (RegExp(r'^(5[1-5]|2[2-7])').hasMatch(d)) return 'MASTERCARD';
    if (RegExp(r'^3[47]').hasMatch(d)) return 'AMEX';
    if (RegExp(r'^(636368|438935|504175|451416|636297|5067|4576|4011|506699)')
        .hasMatch(d)) {
      return 'ELO';
    }
    if (d.startsWith('606282') || d.startsWith('3841')) return 'HIPERCARD';
    return '';
  }
}

bool luhnValid(String digits) {
  if (digits.isEmpty) return false;
  var sum = 0;
  for (var i = 0; i < digits.length; i++) {
    var d = int.parse(digits[digits.length - 1 - i]);
    if (i.isOdd) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
  }
  return sum % 10 == 0;
}

/// Cobrança criada no Asaas: Pix (QR + copia e cola), boleto (linha
/// digitável) ou cartão (já aprovado ou recusado na hora).
class CheckoutCharge {
  const CheckoutCharge({
    required this.quote,
    required this.code,
    required this.expiresIn,
    this.invoiceId = '',
    this.qrImage,
    this.invoiceUrl,
    this.bankSlipUrl,
    this.paid = false,
    this.cardLast4,
  });

  final CheckoutQuote quote;
  final String invoiceId;

  /// Pix copia e cola ou linha digitável do boleto.
  final String code;

  /// PNG do QR do Pix devolvido pelo Asaas.
  final Uint8List? qrImage;
  final String? invoiceUrl;
  final String? bankSlipUrl;

  /// Validade do Pix. O boleto vence em dias, não em minutos.
  final Duration expiresIn;

  /// Cartão aprovado na hora.
  final bool paid;
  final String? cardLast4;
}

/// Recibo do pagamento confirmado pelo Asaas.
class CheckoutReceipt {
  const CheckoutReceipt({
    required this.quote,
    required this.number,
    required this.invoiceNumber,
    required this.paidAt,
    required this.periodStart,
    required this.periodEnd,
    required this.nextInvoice,
    required this.transactionId,
    this.cardLast4,
  });

  final CheckoutQuote quote;
  final String number;

  /// Número da NFS-e; vazio enquanto a prefeitura não autoriza.
  final String invoiceNumber;
  final DateTime paidAt;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime nextInvoice;
  final String transactionId;
  final String? cardLast4;
}

/// Falha com mensagem para mostrar à escola.
class CheckoutFailure implements Exception {
  const CheckoutFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// O que as telas do checkout precisam do backend.
abstract interface class CheckoutGateway {
  /// Estimativa mostrada enquanto a escola ajusta alunos, ciclo e forma de
  /// pagamento. O valor que vale é o de [CheckoutCharge.quote], devolvido
  /// pelo servidor ao gerar a cobrança.
  CheckoutQuote quote({
    required CheckoutPlan plan,
    required int students,
    required CheckoutCycle cycle,
    required CheckoutMethod method,
  });

  /// Cria a cobrança no Asaas. Cartão recusado vira [CheckoutFailure].
  Future<CheckoutCharge> createCharge(
    CheckoutQuote quote, {
    CheckoutCard? card,
  });

  /// Consulta a cobrança: o recibo quando o Asaas confirmou o pagamento,
  /// null enquanto aguarda. Cobrança cancelada vira [CheckoutFailure].
  Future<CheckoutReceipt?> check(CheckoutCharge charge);
}

/// Monta o recibo a partir da fatura paga devolvida pela Edge Function.
CheckoutReceipt receiptFromInvoice(
  Map<String, dynamic> invoice,
  CheckoutQuote fallback,
) {
  final quote = quoteFromInvoice(invoice, fallback);
  final paidAt =
      DateTime.tryParse('${invoice['paid_at']}')?.toLocal() ?? DateTime.now();
  final month =
      DateTime.tryParse('${invoice['reference_month']}') ??
      DateTime(paidAt.year, paidAt.month);
  final start = DateTime(month.year, month.month);
  final months = quote.cycle == CheckoutCycle.annual ? 12 : 1;
  final end = DateTime(start.year, start.month + months);
  return CheckoutReceipt(
    quote: quote,
    number: '${invoice['receipt_number'] ?? ''}',
    invoiceNumber: '${invoice['nfse_number'] ?? ''}',
    paidAt: paidAt,
    periodStart: start,
    periodEnd: end.subtract(const Duration(days: 1)),
    // A fatura do uso real sai no fechamento do mês seguinte.
    nextInvoice: DateTime(start.year, start.month + 1),
    transactionId: '${invoice['transaction_id'] ?? invoice['id'] ?? ''}',
    cardLast4: invoice['card_last4'] as String?,
  );
}

/// Valores que o servidor gravou na fatura (o que vale de verdade).
CheckoutQuote quoteFromInvoice(
  Map<String, dynamic> invoice,
  CheckoutQuote fallback,
) {
  double money(Object? v, double alt) => v is num ? v.toDouble() : alt;
  final plan = invoice['plan'] is String
      ? checkoutPlan(invoice['plan'] as String)
      : fallback.plan;
  return CheckoutQuote(
    plan: plan,
    students: invoice['students'] is int
        ? invoice['students'] as int
        : fallback.students,
    cycle: invoice['cycle'] == 'monthly'
        ? CheckoutCycle.monthly
        : invoice['cycle'] == 'annual'
        ? CheckoutCycle.annual
        : fallback.cycle,
    method: invoice['method'] == null
        ? fallback.method
        : CheckoutMethod.fromWire(invoice['method']),
    pricePerStudent: money(
      invoice['price_per_student'],
      fallback.pricePerStudent,
    ),
    gross: money(invoice['gross'], fallback.gross),
    volumeDiscountPercent: invoice['volume_discount_percent'] is int
        ? invoice['volume_discount_percent'] as int
        : fallback.volumeDiscountPercent,
    discount: money(invoice['discount'], fallback.discount),
    minimumApplied: invoice['minimum_applied'] == true,
    total: money(invoice['total'], fallback.total),
  );
}

/// Cobrança a partir da fatura recém-criada.
CheckoutCharge chargeFromInvoice(
  Map<String, dynamic> invoice,
  CheckoutQuote fallback,
) {
  final quote = quoteFromInvoice(invoice, fallback);
  final pix = quote.method == CheckoutMethod.pix;
  Uint8List? qr;
  final image = invoice['pix_qr_image'];
  if (image is String && image.isNotEmpty) {
    try {
      qr = base64Decode(image);
    } catch (_) {
      qr = null;
    }
  }
  final expires = DateTime.tryParse('${invoice['pix_expires_at']}');
  final due = DateTime.tryParse('${invoice['due_date']}');
  final now = DateTime.now();
  return CheckoutCharge(
    quote: quote,
    invoiceId: '${invoice['id']}',
    code: pix
        ? '${invoice['pix_payload'] ?? ''}'
        : '${invoice['boleto_line'] ?? ''}',
    qrImage: qr,
    invoiceUrl: invoice['invoice_url'] as String?,
    bankSlipUrl: invoice['bank_slip_url'] as String?,
    expiresIn: pix
        ? (expires != null && expires.isAfter(now)
              ? expires.difference(now)
              : const Duration(hours: 24))
        : Duration(days: math.max(1, due?.difference(now).inDays ?? 3)),
    paid: invoice['status'] == 'paid',
    cardLast4: invoice['card_last4'] as String?,
  );
}

/// R$ 1.234,56 sem depender do pacote intl.
String formatBrl(double value) {
  final cents = (value * 100).round();
  final negative = cents < 0;
  final abs = cents.abs();
  final reais = (abs ~/ 100).toString();
  final buffer = StringBuffer();
  for (var i = 0; i < reais.length; i++) {
    if (i > 0 && (reais.length - i) % 3 == 0) buffer.write('.');
    buffer.write(reais[i]);
  }
  final centavos = (abs % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}R\$ $buffer,$centavos';
}

/// 1.800 sem depender do pacote intl.
String formatThousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

String formatDate(DateTime date) =>
    '${_two(date.day)}/${_two(date.month)}/${date.year}';

String formatDateTime(DateTime date) =>
    '${formatDate(date)} ${_two(date.hour)}:${_two(date.minute)}';

String _two(int value) => value.toString().padLeft(2, '0');
