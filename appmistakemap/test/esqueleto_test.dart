import 'package:appmistakemap/theme/esqueleto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget filho, {bool parado = false}) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: MediaQueryData(
      size: const Size(390, 844),
      disableAnimations: parado,
    ),
    child: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(width: 390, child: filho),
    ),
  ),
);

void main() {
  testWidgets('esqueleto anuncia um "Carregando" só, mesmo aninhado', (
    tester,
  ) async {
    final semantica = tester.ensureSemantics();
    await tester.pumpWidget(_app(const EsqueletoPagina()));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.bySemanticsLabel('Carregando'), findsOneWidget);
    expect(find.byType(BlocoEsqueleto), findsWidgets);
    semantica.dispose();
  });

  testWidgets('com "reduzir movimento" o brilho fica parado', (tester) async {
    await tester.pumpWidget(_app(const EsqueletoLista(), parado: true));
    // Sem animação rodando, não há quadro pendente.
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byType(BlocoEsqueleto), findsNWidgets(4 * 3));
  });
}
