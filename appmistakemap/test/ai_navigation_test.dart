import 'package:appmistakemap/ai/ai_material_shell.dart';
import 'package:appmistakemap/ai/analysis_models.dart';
import 'package:appmistakemap/ai/analysis_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _EmptyRepository extends Fake implements AnalysisRepository {
  @override
  Future<List<AttemptRecord>> loadAttempts(String userId) async => [];
}

void main() {
  testWidgets('analysis opens from Fluent navigation and returns to it', (
    tester,
  ) async {
    final repository = _EmptyRepository();
    await tester.pumpWidget(
      FluentApp(
        home: Builder(
          builder: (outerContext) => Center(
            child: Button(
              onPressed: () => Navigator.of(outerContext).push<void>(
                FluentPageRoute(
                  builder: (_) => AiMaterialShell(
                    userId: 'student',
                    repository: repository,
                    showMap: false,
                    onClose: () => Navigator.of(outerContext).pop(),
                  ),
                ),
              ),
              child: const Text('Abrir IA'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir IA'));
    await tester.pumpAndSettle();
    expect(find.text('Adicionar exercício'), findsOneWidget);
    expect(find.text('Sua resposta'), findsOneWidget);
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(find.text('Abrir IA'), findsOneWidget);
  });

  testWidgets('empty error map opens with a helpful state and closes', (
    tester,
  ) async {
    final repository = _EmptyRepository();
    await tester.pumpWidget(
      FluentApp(
        home: Builder(
          builder: (outerContext) => Center(
            child: Button(
              onPressed: () => Navigator.of(outerContext).push<void>(
                FluentPageRoute(
                  builder: (_) => AiMaterialShell(
                    userId: 'student',
                    repository: repository,
                    showMap: true,
                    onClose: () => Navigator.of(outerContext).pop(),
                  ),
                ),
              ),
              child: const Text('Abrir mapa'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir mapa'));
    await tester.pumpAndSettle();
    expect(find.text('Mapa de erros'), findsOneWidget);
    expect(find.text('Seu mapa ainda está vazio'), findsOneWidget);
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(find.text('Abrir mapa'), findsOneWidget);
  });
}
