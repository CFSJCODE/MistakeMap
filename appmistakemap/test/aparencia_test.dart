import 'package:appmistakemap/theme/aparencia.dart';
import 'package:appmistakemap/theme/aparencia_dialogo.dart';
import 'package:appmistakemap/theme/design_tokens.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widget const que lê um token no build, como os do app.
class _Amostra extends StatelessWidget {
  const _Amostra();

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const Key('amostra'),
    color: MistakeMapDesign.canvas,
    child: const SizedBox.square(dimension: 10),
  );
}

Color _cor(WidgetTester tester) =>
    tester.widget<ColoredBox>(find.byKey(const Key('amostra'))).color;

void main() {
  tearDown(() => MistakeMapDesign.paleta = PaletaMistakeMap.claro);

  test('o padrão continua claro', () {
    expect(Aparencia().value, ModoAparencia.claro);
    expect(MistakeMapDesign.paleta, same(PaletaMistakeMap.claro));
    expect(MistakeMapDesign.canvas, const Color(0xFFEEF1F2));
    expect(MistakeMapDesign.abyss, const Color(0xFF06141B));
  });

  testWidgets('trocar a aparência reconstrói até os widgets const', (
    tester,
  ) async {
    final aparencia = Aparencia();
    await tester.pumpWidget(
      AparenciaApp(aparencia: aparencia, builder: (_) => const _Amostra()),
    );
    expect(_cor(tester), PaletaMistakeMap.claro.canvas);

    aparencia.value = ModoAparencia.escuro;
    await tester.pump();
    expect(MistakeMapDesign.escuro, isTrue);
    expect(_cor(tester), PaletaMistakeMap.escuro.canvas);

    aparencia.value = ModoAparencia.claro;
    await tester.pump();
    expect(_cor(tester), PaletaMistakeMap.claro.canvas);
  });

  testWidgets('"Igual ao aparelho" segue o brilho do sistema', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final aparencia = Aparencia(ModoAparencia.sistema);
    await tester.pumpWidget(
      AparenciaApp(aparencia: aparencia, builder: (_) => const _Amostra()),
    );
    expect(_cor(tester), PaletaMistakeMap.escuro.canvas);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pump();
    expect(_cor(tester), PaletaMistakeMap.claro.canvas);
  });

  test('tintas do escuro têm contraste AA sobre a superfície escura', () {
    double contraste(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return la > lb ? (la + .05) / (lb + .05) : (lb + .05) / (la + .05);
    }

    const p = PaletaMistakeMap.escuro;
    for (final tinta in [
      p.abyss,
      p.deep,
      p.slate,
      p.steel,
      p.aquaInk,
      p.azureInk,
      p.violetInk,
      p.amberInk,
      p.mintInk,
      p.coralInk,
    ]) {
      for (final fundo in [p.canvas, p.raised, p.hover]) {
        expect(contraste(tinta, fundo), greaterThanOrEqualTo(4.5));
      }
    }
  });

  testWidgets('Mais > Aparência troca o tema na hora e salva a escolha', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final aparencia = Aparencia();
    await tester.pumpWidget(
      AparenciaApp(
        aparencia: aparencia,
        builder: (_) => FluentApp(
          home: Builder(
            builder: (context) => Center(
              child: Button(
                child: const Text('abrir'),
                onPressed: () =>
                    mostrarAparencia(context, aparencia: aparencia),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Igual ao aparelho'), findsOneWidget);
    await tester.tap(find.byKey(const Key('aparencia-escuro')));
    await tester.pumpAndSettle();
    expect(aparencia.value, ModoAparencia.escuro);
    expect(MistakeMapDesign.escuro, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('mistakemap.aparencia'), 'escuro');
    await tester.tap(find.text('Pronto'));
    await tester.pumpAndSettle();
    expect(find.text('Aparência'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('alternar vai para o oposto do que está na tela e salva', () async {
    SharedPreferences.setMockInitialValues({});
    final a = Aparencia(ModoAparencia.sistema);
    await a.alternar(Brightness.dark);
    expect(a.value, ModoAparencia.claro);
    await a.alternar(Brightness.dark);
    expect(a.value, ModoAparencia.escuro);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('mistakemap.aparencia'), 'escuro');
    a.value = ModoAparencia.sistema;
    await a.alternar(Brightness.light);
    expect(a.value, ModoAparencia.escuro);
  });
}
