import 'package:appmistakemap/theme/glass_surface.dart';
import 'package:appmistakemap/theme/rolagem.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _lista({double topo = 0}) => FluentApp(
  scrollBehavior: const RolagemVidro(),
  home: ScrollConfiguration(
    behavior: RolagemVidro(topo: topo),
    child: ListView(
      children: [
        for (var i = 0; i < 80; i++) SizedBox(height: 40, child: Text('$i')),
      ],
    ),
  ),
);

void main() {
  testWidgets('Barra de rolagem fica visível e colada na borda direita', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_lista(topo: 80));
    await tester.pumpAndSettle();

    final barra = tester.widget<Scrollbar>(find.byType(Scrollbar).first);
    // Sempre visível, sem esperar o ponteiro ou a rolagem.
    expect(barra.thumbVisibility, isTrue);
    final estilo = barra.style!;
    expect(estilo.crossAxisMargin, BarraRolagem.margem);
    expect(estilo.hoveringCrossAxisMargin, BarraRolagem.margem);
    // Sem recuo lateral: só a folga de 1 px até a borda da janela.
    final recuo = estilo.padding!.resolve(TextDirection.ltr);
    expect(recuo.right, 0);
    // O trilho começa abaixo da barra superior de vidro.
    expect(recuo.top, greaterThanOrEqualTo(80));
    expect(tester.getTopRight(find.byType(Scrollbar).first).dx, 1280);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Celular nativo continua sem barra de rolagem', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(_lista());
    expect(find.byType(Scrollbar), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Vidro com reflexo e aresta pintada por cima', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: PreferenciaVidro(
          child: GlassSurface(blur: true, child: Text('Vidro')),
        ),
      ),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.foregroundPainter is GlassRimPainter,
      ),
      findsOneWidget,
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
  });
}
