import 'package:appmistakemap/admin/model_quota_card.dart';
import 'package:appmistakemap/layout/adaptativo.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> render(
    WidgetTester tester,
    Widget child, {
    double width = 1280,
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, scale == 1 ? 720 : 1900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      FluentApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'missing and partial telemetry do not imply an available balance',
    (tester) async {
      await render(
        tester,
        const ModelQuotaCard(
          model: 'Gemini 3.8 Flash',
          telemetryAvailable: false,
        ),
      );
      expect(find.text('—'), findsNWidgets(3));
      expect(find.text('Saldo indisponível'), findsNWidgets(3));
      await render(
        tester,
        const ModelQuotaCard(
          model: 'Gemini 3.8 Flash',
          telemetryAvailable: true,
          usage: {'rpm': 3, 'tpm': 852, 'rpd': 6, 'unknown_tokens': 1},
        ),
      );
      expect(find.text('2 restantes'), findsOneWidget);
      expect(find.text('14 restantes'), findsOneWidget);
      expect(find.text('Saldo indisponível'), findsOneWidget);
    },
  );

  for (final scenario in [(320.0, 2.0), (1280.0, 1.0)]) {
    testWidgets('quotas fit ${scenario.$1}px with text scale ${scenario.$2}', (
      tester,
    ) async {
      await render(
        tester,
        const GradeAdaptativa(
          maxColunas: 2,
          children: [
            ModelQuotaCard(
              model: 'Gemini 3.8 Flash',
              telemetryAvailable: true,
              usage: {'rpm': 3, 'tpm': 852, 'rpd': 6},
            ),
            ModelQuotaCard(model: 'Gemini 3.6 Flash', telemetryAvailable: true),
          ],
        ),
        width: scenario.$1,
        scale: scenario.$2,
      );
      expect(find.text('250.000 restantes'), findsOneWidget);
    });
  }
}
