import 'package:appmistakemap/billing/billing_repository.dart';
import 'package:appmistakemap/billing/checkout_models.dart';
import 'package:appmistakemap/billing/checkout_page.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

CheckoutPlan _plan(String id) => checkoutPlans.firstWhere((p) => p.id == id);

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pump(const Duration(milliseconds: 600));
}

/// Servidor falso: responde como a Edge Function school-billing.
class _FakeBilling implements BillingRepository {
  final calls = <Map<String, dynamic>>[];
  bool paid = false;
  bool refuseCard = false;

  Map<String, dynamic> _invoice(Map<String, dynamic> d, String status) {
    final quote = CheckoutQuote.estimate(
      plan: _plan('${d['plan'] ?? 'escola'}'),
      students: (d['students'] as int?) ?? 30,
      cycle: d['cycle'] == 'monthly'
          ? CheckoutCycle.monthly
          : CheckoutCycle.annual,
      method: CheckoutMethod.fromWire(d['method']),
    );
    return {
      'id': 'inv-1',
      'plan': quote.plan.id,
      'cycle': quote.cycle.wire,
      'students': quote.students,
      'method': quote.method.wire,
      'price_per_student': quote.pricePerStudent,
      'gross': quote.gross,
      'volume_discount_percent': quote.volumeDiscountPercent,
      'discount': quote.discount,
      'minimum_applied': quote.minimumApplied,
      'total': quote.total,
      'status': status,
      'reference_month': '2026-11-01',
      'pix_payload': '00020126BR.GOV.BCB.PIX-ASAAS',
      'boleto_line': '00190.00009 01234.567891 23456.789012 1 99990000015325',
      'receipt_number': status == 'paid' ? 'MM-2026-ABCDEF12' : null,
      'paid_at': status == 'paid' ? '2026-11-12T15:00:00Z' : null,
      'transaction_id': 'pay_1',
      'card_last4': quote.method == CheckoutMethod.creditCard ? '1111' : null,
    };
  }

  Map<String, dynamic>? _last;

  @override
  Future<BillingData> run(String action, [BillingData data = const {}]) async {
    calls.add({...data, 'action': action});
    switch (action) {
      case 'checkout':
        if (data['method'] == 'credit_card' && refuseCard) {
          throw const CheckoutFailure('O Asaas recusou: Cartão recusado.');
        }
        _last = data;
        final card = data['method'] == 'credit_card';
        return {'invoice': _invoice(data, card ? 'paid' : 'awaiting_payment')};
      case 'invoice_status':
        return {
          'invoice': _invoice(
            _last ?? const {},
            paid || _last?['method'] == 'credit_card'
                ? 'paid'
                : 'awaiting_payment',
          ),
        };
    }
    return {};
  }
}

Widget _app(_FakeBilling billing) => FluentApp(
  home: SchoolCheckoutPage(
    schoolName: 'Colégio Nexo — Unidade Vale do Ferro',
    gateway: ServerCheckoutGateway(repository: billing, schoolId: 'sch-1'),
    pollEvery: const Duration(seconds: 1),
  ),
);

void main() {
  group('Estimativa (mesma conta do banco)', () {
    test('Escola anual cobra R\$ 9,90 por aluno', () {
      final quote = CheckoutQuote.estimate(
        plan: _plan('escola'),
        students: 30,
        cycle: CheckoutCycle.annual,
        method: CheckoutMethod.pix,
      );
      expect(quote.total, closeTo(297, .001));
      expect(formatBrl(quote.total), r'R$ 297,00');
      expect(quote.analysesQuota, 1800);
      expect(_plan('escola').annualDiscountPercent, 18);
    });

    test('1.935 alunos no Escola anual: −20% por volume', () {
      final quote = CheckoutQuote.estimate(
        plan: _plan('escola'),
        students: 1935,
        cycle: CheckoutCycle.annual,
        method: CheckoutMethod.boleto,
      );
      expect(quote.volumeDiscountPercent, 20);
      expect(quote.total, closeTo(15325.2, .001));
      expect(volumeDiscountFor(150), 10);
      expect(volumeDiscountFor(100), 0);
    });

    test('Planos pagos respeitam o mínimo de R\$ 99', () {
      final quote = CheckoutQuote.estimate(
        plan: _plan('plus'),
        students: 5,
        cycle: CheckoutCycle.monthly,
        method: CheckoutMethod.boleto,
      );
      expect(quote.total, paidPlanMinimum);
      expect(quote.atMinimum, isTrue);
    });

    test('Cartão: Luhn, validade e CVV antes de ir ao servidor', () {
      final now = DateTime(2026, 11, 12);
      const ok = CheckoutCard(
        holderName: 'Rede Nexo',
        number: '4111 1111 1111 1111',
        expiryMonth: '03',
        expiryYear: '31',
        ccv: '123',
      );
      expect(ok.problem(now), isNull);
      expect(ok.brand, 'VISA');
      expect(ok.last4, '1111');
      expect(ok.toJson()['number'], '4111111111111111');
      const wrong = CheckoutCard(
        holderName: 'Rede Nexo',
        number: '4111 1111 1111 1112',
        expiryMonth: '03',
        expiryYear: '31',
        ccv: '123',
      );
      expect(wrong.problem(now), contains('número'));
      const expired = CheckoutCard(
        holderName: 'Rede Nexo',
        number: '4111111111111111',
        expiryMonth: '10',
        expiryYear: '26',
        ccv: '123',
      );
      expect(expired.problem(now), contains('vencido'));
    });

    test('Formata reais com milhar', () {
      expect(formatBrl(1234.5), r'R$ 1.234,50');
      expect(formatThousands(12000), '12.000');
    });
  });

  testWidgets('Pix: só mostra pago quando o servidor confirma', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final billing = _FakeBilling();

    await tester.pumpWidget(_app(billing));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Escolha o plano'), findsOneWidget);
    expect(find.text('Prévia'), findsNothing);

    await _tap(tester, const Key('checkout-choose'));
    expect(find.text('Confirmar assinatura'), findsOneWidget);
    expect(find.text(r'R$ 297,00'), findsOneWidget);

    // Mensal: 30 × R$ 12,00.
    await _tap(tester, const Key('checkout-monthly'));
    expect(find.text(r'R$ 360,00'), findsOneWidget);

    await _tap(tester, const Key('checkout-pay'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Pague com Pix'), findsOneWidget);
    expect(find.text('Aguardando pagamento'), findsOneWidget);
    final sent = billing.calls.firstWhere((c) => c['action'] == 'checkout');
    expect(sent['method'], 'pix');
    expect(sent['students'], 30);
    expect(sent.containsKey('card'), isFalse);

    // Ainda não pago: a consulta não muda a tela.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Aguardando pagamento'), findsOneWidget);

    // O Asaas confirmou: a próxima consulta mostra o pago.
    billing.paid = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Pagamento confirmado'), findsWidgets);
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 1400));
    expect(find.textContaining('Plano Escola ativo'), findsOneWidget);

    await _tap(tester, const Key('checkout-receipt'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('PAGO'), findsOneWidget);
    expect(find.text('Recibo pronto'), findsOneWidget);
    expect(find.text('MM-2026-ABCDEF12'), findsOneWidget);
  });

  testWidgets('Cartão aprovado vai direto para a maquininha', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final billing = _FakeBilling();

    await tester.pumpWidget(_app(billing));
    await tester.pump(const Duration(milliseconds: 600));
    await _tap(tester, const Key('checkout-choose'));
    await _tap(tester, const Key('checkout-card'));
    await tester.enterText(
      find.byKey(const Key('checkout-card-name')),
      'Rede Nexo',
    );
    await tester.enterText(
      find.byKey(const Key('checkout-card-number')),
      '4111 1111 1111 1111',
    );
    await tester.enterText(
      find.byKey(const Key('checkout-card-expiry')),
      '03/31',
    );
    await tester.enterText(find.byKey(const Key('checkout-card-ccv')), '123');
    await tester.pump();
    await _tap(tester, const Key('checkout-pay'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 1400));

    final sent = billing.calls.firstWhere((c) => c['action'] == 'checkout');
    expect(sent['method'], 'credit_card');
    expect((sent['card'] as Map)['number'], '4111111111111111');
    expect(find.text('Pagamento confirmado'), findsOneWidget);
    expect(find.textContaining('Cartão final 1111'), findsOneWidget);
  });

  testWidgets('Cartão inválido nem chega ao servidor; recusa mostra o motivo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final billing = _FakeBilling()..refuseCard = true;

    await tester.pumpWidget(_app(billing));
    await tester.pump(const Duration(milliseconds: 600));
    await _tap(tester, const Key('checkout-choose'));
    await _tap(tester, const Key('checkout-card'));
    await tester.enterText(
      find.byKey(const Key('checkout-card-name')),
      'Rede Nexo',
    );
    await tester.enterText(
      find.byKey(const Key('checkout-card-number')),
      '4111 1111 1111 1112',
    );
    await tester.enterText(
      find.byKey(const Key('checkout-card-expiry')),
      '03/31',
    );
    await tester.enterText(find.byKey(const Key('checkout-card-ccv')), '123');
    await _tap(tester, const Key('checkout-pay'));
    expect(find.text('Confira o número do cartão.'), findsOneWidget);
    expect(billing.calls, isEmpty);

    await tester.enterText(
      find.byKey(const Key('checkout-card-number')),
      '4111 1111 1111 1111',
    );
    await tester.enterText(find.byKey(const Key('checkout-card-ccv')), '123');
    await _tap(tester, const Key('checkout-pay'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('O Asaas recusou: Cartão recusado.'), findsOneWidget);
    // Número e código não ficam na tela depois da tentativa.
    final number = tester.widget<TextBox>(
      find.byKey(const Key('checkout-card-number')),
    );
    expect(number.controller!.text, isEmpty);
  });

  testWidgets('Alunos vão até 20.000 e o desconto por volume aparece', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(_FakeBilling()));
    await tester.pump(const Duration(milliseconds: 600));
    await _tap(tester, const Key('checkout-choose'));
    await tester.enterText(find.byKey(const Key('checkout-students')), '1935');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('checkout-volume')), findsOneWidget);
    expect(find.text(r'R$ 15.325,20'), findsOneWidget);
  });

  testWidgets('Plano Grátis não gera cobrança', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final billing = _FakeBilling();

    await tester.pumpWidget(_app(billing));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.drag(find.byType(PageView), const Offset(320, 0));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Escolher Grátis'), findsOneWidget);

    await _tap(tester, const Key('checkout-choose'));
    expect(find.text('Continuar no Grátis'), findsOneWidget);
    await _tap(tester, const Key('checkout-pay'));
    expect(billing.calls, isEmpty);
  });
}
