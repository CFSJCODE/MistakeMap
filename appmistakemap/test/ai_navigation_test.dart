import 'package:appmistakemap/ai/ai_material_shell.dart';
import 'package:appmistakemap/ai/analysis_models.dart';
import 'package:appmistakemap/ai/analysis_repository.dart';
import 'package:appmistakemap/ai/insights_view.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _EmptyRepository extends Fake implements AnalysisRepository {
  @override
  Future<List<AttemptRecord>> loadAttempts(String userId) async => [];
}

void main() {
  testWidgets('Estudar abre sem tentativas e a seleção volta ao fechar', (
    tester,
  ) async {
    final controller = ErrorMapController();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      FluentApp(
        home: ErrorMapTab(
          userId: 'student',
          repository: _EmptyRepository(),
          controller: controller,
          navigatorKey: navigator,
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.request(ErrorMapRequest.study);
    await tester.pumpAndSettle();
    expect(controller.studyOpen.value, isTrue);
    expect(navigator.currentState!.canPop(), isTrue);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(controller.studyOpen.value, isFalse);
  });
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

  testWidgets('system back pops inner AI screens before closing the shell', (
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

    // Empilha uma tela no Navigator interno, como fazem detalhe e prática.
    Navigator.of(tester.element(find.text('Sua resposta'))).push<void>(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const Center(child: Text('Tela interna')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tela interna'), findsOneWidget);

    // Primeiro Voltar do sistema: sai só a tela interna, o shell continua.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Tela interna'), findsNothing);
    expect(find.text('Adicionar exercício'), findsOneWidget);

    // Segundo Voltar: sem telas internas, fecha o shell como o botão Voltar.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Adicionar exercício'), findsNothing);
    expect(find.text('Abrir IA'), findsOneWidget);
  });

  testWidgets('correction opens straight from the exercise and returns', (
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
                    attemptId: 'attempt-1',
                    onClose: () => Navigator.of(outerContext).pop(),
                  ),
                ),
              ),
              child: const Text('Ver correção'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ver correção'));
    await tester.pumpAndSettle();
    expect(find.text('Correção e evidências'), findsOneWidget);
    expect(find.text('Adicionar exercício'), findsNothing);

    // A seta do AppBar volta direto para quem abriu, sem tela vazia no meio.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Correção e evidências'), findsNothing);
    expect(find.text('Ver correção'), findsOneWidget);

    // O Voltar do sistema também fecha a correção.
    await tester.tap(find.text('Ver correção'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Ver correção'), findsOneWidget);
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
