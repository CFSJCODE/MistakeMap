import 'dart:math' as math;

/// Modelos do checkout da escola (plano → confirmação → cobrança → recibo).
///
/// As telas falam só com [CheckoutGateway]. Hoje o app usa
/// [SimulatedCheckoutGateway], que inventa a cobrança localmente para a
/// prévia. A cobrança de verdade (item D da onda 1) vai trocar o gateway por
/// um que pede o orçamento, o Pix/boleto e o recibo à Edge Function, que
/// calcula o valor e fala com o Asaas. Nenhum valor daqui vale como cobrança.

enum CheckoutCycle { monthly, annual }

enum CheckoutMethod { pix, boleto }

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

/// Planos da proposta comercial (valores de exemplo, por aluno ativo).
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

/// Alunos que o Grátis libera (1 professor + 4 alunos).
const freePlanStudents = 4;

/// Mínimo mensal dos planos pagos.
const paidPlanMinimum = 99.0;

/// Orçamento da assinatura mostrado na confirmação.
class CheckoutQuote {
  const CheckoutQuote({
    required this.plan,
    required this.students,
    required this.cycle,
    required this.method,
    required this.pricePerStudent,
    required this.total,
  });

  final CheckoutPlan plan;
  final int students;
  final CheckoutCycle cycle;
  final CheckoutMethod method;
  final double pricePerStudent;
  final double total;

  /// O total foi elevado ao mínimo mensal.
  bool get atMinimum => !plan.isFree && total == paidPlanMinimum;

  int get releasedStudents => plan.isFree ? freePlanStudents : students;

  int get analysesQuota => plan.analysesPerStudent * releasedStudents;
}

/// Cobrança gerada (Pix copia e cola ou linha digitável do boleto).
class CheckoutCharge {
  const CheckoutCharge({
    required this.quote,
    required this.code,
    required this.expiresIn,
  });

  final CheckoutQuote quote;
  final String code;

  /// Validade do Pix. O boleto vence em dias, não em minutos.
  final Duration expiresIn;
}

/// Recibo do pagamento confirmado.
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
  });

  final CheckoutQuote quote;
  final String number;
  final String invoiceNumber;
  final DateTime paidAt;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime nextInvoice;
  final String transactionId;
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

  Future<CheckoutCharge> createCharge(CheckoutQuote quote);

  /// Espera a confirmação do pagamento (webhook do gateway).
  Future<CheckoutReceipt> confirm(CheckoutCharge charge);
}

/// Gateway da prévia: calcula e confirma localmente, sem cobrar ninguém.
class SimulatedCheckoutGateway implements CheckoutGateway {
  SimulatedCheckoutGateway({
    DateTime Function()? clock,
    this.latency = const Duration(milliseconds: 1200),
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Duration latency;

  @override
  CheckoutQuote quote({
    required CheckoutPlan plan,
    required int students,
    required CheckoutCycle cycle,
    required CheckoutMethod method,
  }) {
    final price = plan.pricePerStudent(cycle);
    final total = plan.isFree
        ? 0.0
        : math.max(paidPlanMinimum, _cents(price * students));
    return CheckoutQuote(
      plan: plan,
      students: students,
      cycle: cycle,
      method: method,
      pricePerStudent: price,
      total: total,
    );
  }

  @override
  Future<CheckoutCharge> createCharge(CheckoutQuote quote) async {
    await Future<void>.delayed(latency);
    final cents = (quote.total * 100).round();
    final code = quote.method == CheckoutMethod.pix
        ? '00020126580014br.gov.bcb.pix0136mistakemap-previa-'
              '${quote.plan.id}-${quote.students}5204000053039865406'
              '${(cents / 100).toStringAsFixed(2)}5802BR6304PREV'
        : '34191.79001 01043.510047 91020.150008 1 '
              '${cents.toString().padLeft(10, '0')}';
    return CheckoutCharge(
      quote: quote,
      code: code,
      expiresIn: quote.method == CheckoutMethod.pix
          ? const Duration(minutes: 30)
          : const Duration(days: 3),
    );
  }

  @override
  Future<CheckoutReceipt> confirm(CheckoutCharge charge) async {
    final now = _clock();
    final start = DateTime(now.year, now.month);
    final next = DateTime(now.year, now.month + 1);
    final seq = (now.millisecondsSinceEpoch ~/ 1000 % 1000000)
        .toString()
        .padLeft(6, '0');
    return CheckoutReceipt(
      quote: charge.quote,
      number: 'MM-${now.year}-$seq',
      invoiceNumber: '${now.year}/$seq',
      paidAt: now,
      periodStart: start,
      periodEnd: next.subtract(const Duration(days: 1)),
      nextInvoice: next,
      transactionId: 'E2E-PREVIA-${now.year}$seq',
    );
  }

  static double _cents(double value) => (value * 100).roundToDouble() / 100;
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
