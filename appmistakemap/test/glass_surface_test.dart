import 'package:appmistakemap/layout/navigation_shell.dart';
import 'package:appmistakemap/theme/glass_surface.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

Widget _app(Widget child, {required bool highContrast}) => FluentApp(
  builder: (context, page) => MediaQuery(
    data: MediaQuery.of(context).copyWith(highContrast: highContrast),
    child: page!,
  ),
  home: child,
);

void main() {
  for (final highContrast in [false, true]) {
    testWidgets('Vidro com alto contraste $highContrast', (tester) async {
      await tester.pumpWidget(
        _app(
          const GlassSurface(
            blur: true,
            accent: Color(0xFF36D6C3),
            child: Text('Conteúdo'),
          ),
          highContrast: highContrast,
        ),
      );
      expect(find.text('Conteúdo'), findsOneWidget);
      // Alto contraste: superfície sólida, sem desfoque por trás do texto.
      expect(
        find.byType(BackdropFilter),
        highContrast ? findsNothing : findsOneWidget,
      );
    });
  }

  testWidgets('Barra inferior troca o vidro líquido por sólido no alto '
      'contraste', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        AppNavigationShell(
          selectedIndex: 0,
          onSelected: (_) {},
          onAbout: () {},
          hasAdmin: false,
          child: const SizedBox.expand(),
        ),
        highContrast: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LiquidGlass), findsNothing);
    expect(find.byType(GlassSurface), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
