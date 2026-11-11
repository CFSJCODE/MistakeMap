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

void main() {
  group('Orçamento simulado', () {
    final gateway = SimulatedCheckoutGateway(
      clock: () => DateTime(2026, 11, 11, 0, 3),
      latency: Duration.zero,
    );

    test('Escola anual cobra R\$ 9,90 por aluno', () {
      final quote = gateway.quote(
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

    test('Planos pagos respeitam o mínimo de R\$ 99', () {
      final quote = gateway.quote(
        plan: _plan('plus'),
        students: 5,
        cycle: CheckoutCycle.monthly,
        method: CheckoutMethod.boleto,
      );
      expect(quote.total, paidPlanMinimum);
      expect(quote.atMinimum, isTrue);
    });

    test('Grátis libera 4 alunos e não cobra', () {
      final quote = gateway.quote(
        plan: _plan('free'),
        students: 30,
        cycle: CheckoutCycle.annual,
        method: CheckoutMethod.pix,
      );
      expect(quote.total, 0);
      expect(quote.releasedStudents, freePlanStudents);
    });

    test('Recibo cobre o mês corrente e aponta a próxima fatura', () async {
      final quote = gateway.quote(
        plan: _plan('escola'),
        students: 30,
        cycle: CheckoutCycle.annual,
        method: CheckoutMethod.pix,
      );
      final receipt = await gateway.confirm(await gateway.createCharge(quote));
      expect(formatDate(receipt.periodStart), '01/11/2026');
      expect(formatDate(receipt.periodEnd), '30/11/2026');
      expect(formatDate(receipt.nextInvoice), '01/12/2026');
    });

    test('Formata reais com milhar', () {
      expect(formatBrl(1234.5), r'R$ 1.234,50');
      expect(formatThousands(12000), '12.000');
    });
  });

  testWidgets('Fluxo completo: plano, Pix, ativação e recibo', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      FluentApp(
        home: SchoolCheckoutPage(
          gateway: SimulatedCheckoutGateway(latency: Duration.zero),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Escolha o plano'), findsOneWidget);
    expect(find.text('Escolher Escola'), findsOneWidget);

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

    await _tap(tester, const Key('checkout-simulate'));
    expect(find.text('Pagamento confirmado'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Plano Escola ativo'), findsOneWidget);

    await _tap(tester, const Key('checkout-receipt'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('PAGO'), findsOneWidget);
    expect(find.text('Recibo e NFS-e prontos'), findsOneWidget);
  });

  testWidgets('Plano Grátis pula a cobrança', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      FluentApp(
        home: SchoolCheckoutPage(
          gateway: SimulatedCheckoutGateway(latency: Duration.zero),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.drag(find.byType(PageView), const Offset(320, 0));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Escolher Grátis'), findsOneWidget);

    await _tap(tester, const Key('checkout-choose'));
    await _tap(tester, const Key('checkout-pay'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Plano Grátis ativo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });
}
