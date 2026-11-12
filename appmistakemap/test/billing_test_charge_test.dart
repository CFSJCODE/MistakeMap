import 'package:appmistakemap/billing/billing_panel.dart';
import 'package:appmistakemap/billing/billing_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Servidor falso da school-billing para o cartão de cobrança.
class _FakeBilling implements BillingRepository {
  _FakeBilling({this.demo = false});
  final bool demo;
  final calls = <Map<String, dynamic>>[];
  bool testIssued = false;

  @override
  Future<BillingData> run(String action, [BillingData data = const {}]) async {
    calls.add({...data, 'action': action});
    if (action == 'test_charge') testIssued = true;
    return {
      'school': {'plan': 'free', 'cnpj': '54497959000103'},
      'settings': {'payer_role': 'owner', 'demo': demo},
      'my_roles': ['owner'],
      'is_payer': true,
      'provider': 'asaas',
      'quota': {'active_students': 0},
      'invoices': [
        if (testIssued)
          {
            'id': 'inv-t',
            'kind': 'test',
            'status': 'awaiting_payment',
            'method': 'pix',
            'total': 5,
            'reference_month': '2026-11-01',
            'pix_payload': '00020126BR.GOV.BCB.PIX-ASAAS',
          },
      ],
    };
  }
}

Future<void> _render(
  WidgetTester tester,
  _FakeBilling billing, {
  bool appEquipe = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 1600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    FluentApp(
      home: ScaffoldPage(
        content: SingleChildScrollView(
          child: CartaoCobranca(
            escolaId: 'sch-1',
            escolaNome: 'Escola Teste de Cobrança (real)',
            papel: 'owner',
            repositorio: billing,
            mostrarCobrancaTeste: appEquipe,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('escola real: cobrança de teste de R\$ 5 em Pix', (tester) async {
    final billing = _FakeBilling();
    await _render(tester, billing);
    final botao = find.text(r'Cobrança de teste (R$ 5)');
    expect(botao, findsOneWidget);
    await tester.tap(botao);
    await tester.pumpAndSettle();
    final pedido = billing.calls.firstWhere(
      (c) => c['action'] == 'test_charge',
    );
    expect(pedido['school_id'], 'sch-1');
    expect(pedido['method'], 'pix');
    expect(find.text('Cobrança de teste'), findsOneWidget);
    expect(find.text('Copiar Pix copia e cola'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('escola demo não mostra a cobrança de teste', (tester) async {
    await _render(tester, _FakeBilling(demo: true));
    expect(find.text(r'Cobrança de teste (R$ 5)'), findsNothing);
  });

  testWidgets('app de produção não mostra a cobrança de teste', (tester) async {
    await _render(tester, _FakeBilling(), appEquipe: false);
    expect(find.text(r'Cobrança de teste (R$ 5)'), findsNothing);
    expect(find.text('Escolher plano e pagar'), findsOneWidget);
  });
}
