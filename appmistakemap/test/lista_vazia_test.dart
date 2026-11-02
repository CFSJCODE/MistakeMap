import 'package:appmistakemap/main.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

Future<void> _render(WidgetTester tester, Widget corpo) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    LiquidGlassWidgets.wrap(
      theme: temaVidro,
      child: FluentApp(
        theme: temaFluent,
        home: ScaffoldPage(content: corpo),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('lista vazia oferece começar com exemplos', (tester) async {
    var chamadas = 0;
    await _render(
      tester,
      ListaVazia(onAdicionarExemplos: () async => chamadas++),
    );

    expect(find.text('Seu mapa ainda está vazio'), findsOneWidget);
    await tester.tap(find.text('Começar com exemplos'));
    await tester.pumpAndSettle();
    expect(chamadas, 1);
  });

  testWidgets('botão fica desativado enquanto adiciona', (tester) async {
    var chamadas = 0;
    await _render(
      tester,
      ListaVazia(
        onAdicionarExemplos: () async => chamadas++,
        adicionando: true,
      ),
    );

    expect(find.text('Começar com exemplos'), findsNothing);
    expect(find.byType(ProgressRing), findsOneWidget);
    await tester.tap(find.byKey(const Key('lista-vazia-exemplos')));
    await tester.pump();
    expect(chamadas, 0);
  });

  testWidgets('sem callback não mostra o botão', (tester) async {
    await _render(tester, const ListaVazia());

    expect(find.byKey(const Key('lista-vazia-exemplos')), findsNothing);
  });
}
