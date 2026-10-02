import 'dart:convert';
import 'dart:io';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:appmistakemap/layout/navigation_shell.dart';
import 'package:appmistakemap/main.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'analysis_test.dart' show FakeRepository;

const _user = AppUser(
  id: '11111111-1111-4111-8111-111111111111',
  email: 'estudante.com.nome.longo@example.test',
  role: 'user',
);
const _admin = AppUser(
  id: '11111111-1111-4111-8111-111111111111',
  email: 'administrador@example.test',
  role: 'admin',
);

class _TestAuthStorage extends GotrueAsyncStorage {
  const _TestAuthStorage();

  @override
  Future<String?> getItem({required String key}) async => null;

  @override
  Future<void> setItem({required String key, required String value}) async {}

  @override
  Future<void> removeItem({required String key}) async {}
}

Future<void> _render(
  WidgetTester tester,
  Widget page, {
  required Size size,
  double scale = 1,
  double keyboard = 0,
  List<DisplayFeature> features = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    LiquidGlassWidgets.wrap(
      theme: temaVidro,
      brightnessResolver: (context) => FluentTheme.maybeOf(context)?.brightness,
      child: FluentApp(
        theme: const bool.fromEnvironment('GENERATE_PREVIEWS')
            ? temaFluent.copyWith(
                typography: temaFluent.typography.apply(fontFamily: 'Segoe UI'),
              )
            : temaFluent,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
            displayFeatures: features,
          ),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
  expect(tester.takeException(), isNull);
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 5),
);

void _expectOutsideTopFade(WidgetTester tester, Finder content) {
  final edgeFinder = find.ancestor(
    of: content,
    matching: find.byType(GlassScrollEdgeEffect),
  );
  expect(edgeFinder, findsNothing);
  final bar = find.byType(GlassAppBar);
  expect(
    tester.getTopLeft(content).dy,
    greaterThanOrEqualTo(tester.getBottomLeft(bar).dy),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (const bool.fromEnvironment('GENERATE_PREVIEWS')) {
      await (FontLoader('Segoe UI')..addFont(
            Future.value(
              ByteData.sublistView(
                await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes(),
              ),
            ),
          ))
          .load();
      await (FontLoader('packages/fluent_ui/SegoeIcons')..addFont(
            rootBundle.load('packages/fluent_ui/fonts/SegoeIcons.ttf'),
          ))
          .load();
    }
    await Supabase.initialize(
      url: 'https://responsive-tests.invalid',
      publishableKey: 'public-test-key',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUri: false,
        pkceAsyncStorage: _TestAuthStorage(),
      ),
      httpClient: MockClient((request) async {
        // Nenhuma requisição deixa o processo de teste.
        expect(request.url.host, 'responsive-tests.invalid');
        final Object body;
        switch (request.url.path) {
          case '/rest/v1/attempts':
            body = [
              {'status': 'completed'},
              {'status': 'pending'},
              {'status': 'completed'},
            ];
          case '/rest/v1/subjects':
            body = [
              {'id': 'subject-1', 'name': 'Equações e raciocínio algébrico'},
              {'id': 'subject-2', 'name': 'Geometria plana e espacial'},
            ];
          case '/rest/v1/exercises':
            body = [
              for (var i = 1; i <= 4; i++)
                {
                  'id': 'exercise-$i',
                  'subject_id': i < 3 ? 'subject-1' : 'subject-2',
                  'prompt_text': 'Descrição longa de um exercício para validar a quebra de linha sem cortes.',
                  'created_at': '2026-09-29T00:00:00Z',
                  'attempts': [
                    // Prática acumula tentativas; a antiga vem primeiro para
                    // provar que a tela escolhe pela data, não pela posição.
                    if (i == 1)
                      {
                        'id': 'attempt-1-antiga',
                        'user_id': _user.id,
                        'status': 'dead_letter',
                        'attempted_at': '2026-09-28T00:00:00Z',
                      },
                    {
                      'id': 'attempt-$i',
                      'user_id': _user.id,
                      'status': i.isEven ? 'completed' : 'pending',
                      'attempted_at': '2026-09-29T00:00:00Z',
                    },
                  ],
                },
            ];
          case '/rest/v1/profiles':
            body = [
              {
                'id': _admin.id,
                'role': 'admin',
                'institution_name': 'Instituição com nome extenso',
                'course': 'Análise e Desenvolvimento de Sistemas',
              },
              {
                'id': '22222222-2222-4222-8222-222222222222',
                'role': 'user',
                'institution_name': 'Escola de teste',
                'course': 'Ensino médio',
              },
            ];
          default:
            throw StateError(
              'Requisição não esperada no teste: ${request.url.path}',
            );
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
          request: request,
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  testWidgets(
    'Navegação inicia sob demanda e não empilha IA por clique duplo',
    (tester) async {
      await _render(
        tester,
        TelaNavegacao(user: _admin, analysisRepository: FakeRepository()),
        size: const Size(1280, 900),
      );
      expect(find.byType(TelaPrincipal, skipOffstage: false), findsNothing);
      expect(
        find.byType(TelaAdicionarExercicio, skipOffstage: false),
        findsNothing,
      );
      expect(find.byType(TelaAdmin, skipOffstage: false), findsNothing);
      // Dois taps seguidos não servem: o segundo é absorvido pelo
      // AbsorbPointer do Navigator durante a transição e a guarda contra
      // clique duplo nunca roda. Chamar o callback duas vezes no mesmo frame
      // reproduz o clique duplo que chega antes da rota bloquear a entrada.
      final shell = tester.widget<AppNavigationShell>(
        find.byType(AppNavigationShell),
      );
      shell.onAnalysis!();
      shell.onAnalysis!();
      await _settle(tester);
      expect(find.text('Sua resposta'), findsOneWidget);
      await tester.tap(find.byTooltip('Voltar'));
      await _settle(tester);
      expect(find.text('Início — Resumo'), findsOneWidget);
      expect(find.text('Sua resposta', skipOffstage: false), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [390.0, 1280.0]) {
    testWidgets('Navegação real abre análise e mapa IA em ${width.toInt()}px', (
      tester,
    ) async {
      await _render(
        tester,
        TelaNavegacao(user: _user, analysisRepository: FakeRepository()),
        size: Size(width, 900),
      );
      expect(find.text('Analisar exercício com IA'), findsNothing);
      if (width < 840) {
        await tester.tap(find.byKey(const ValueKey('navigation-more')));
        await _settle(tester);
      }
      await tester.tap(find.text('Analisar com IA'));
      await _settle(tester);
      expect(find.text('Sua resposta'), findsOneWidget);
      await tester.tap(find.byTooltip('Voltar'));
      await _settle(tester);
      expect(find.text('Início — Resumo'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('navigation-2')));
      await _settle(tester);
      expect(find.text('Seu mapa ainda está vazio'), findsOneWidget);
      await tester.tap(find.byTooltip('Voltar'));
      await _settle(tester);
      expect(find.text('Início — Resumo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets('Prévias do início e Sobre em ${width.toInt()}px', (
      tester,
    ) async {
      for (final entry in <String, Widget>{
        'inicio': const TelaInicial(user: _user),
        'sobre': const TelaSobre(),
        'navegacao': const TelaNavegacao(user: _user),
      }.entries) {
        await _render(
          tester,
          RepaintBoundary(key: const Key('design-preview'), child: entry.value),
          size: Size(width, 900),
        );
        await expectLater(
          find.byKey(const Key('design-preview')),
          matchesGoldenFile(
            'previews/${entry.key}-${width.toInt()}-synthetic.png',
          ),
        );
      }
    }, skip: !const bool.fromEnvironment('GENERATE_PREVIEWS'));
  }

  for (final width in [320.0, 390.0, 768.0, 1280.0, 1440.0]) {
    testWidgets('Login acessível em ${width.toInt()}px', (tester) async {
      await _render(tester, const TelaCadastro(), size: Size(width, 800));
      await tester.ensureVisible(find.text('Continue com Google'));
      expect(find.text('Continue com Google').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Login compacto com fonte 2x e teclado permite chegar aos botões',
    (tester) async {
      await _render(
        tester,
        const TelaCadastro(),
        size: const Size(320, 480),
        scale: 2,
        keyboard: 180,
      );
      await tester.ensureVisible(find.text('Continue com Google'));
      expect(find.text('Continue com Google').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scenario in [(320.0, 2.0), (1440.0, 1.5)]) {
    testWidgets(
      'Sobre em ${scenario.$1}px e fonte ${scenario.$2}x mantém conteúdo rolável',
      (tester) async {
        await _render(
          tester,
          const TelaSobre(),
          size: Size(scenario.$1, 800),
          scale: scenario.$2,
        );
        await tester.ensureVisible(find.text('LLM'));
        expect(find.text('LLM').hitTestable(), findsOneWidget);
        expect(
          find.text('PUC Minas · Projeto Integrado I · 2026'),
          findsNothing,
        );
        expect(find.text('v1.0.0 — Sprint 2'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Resumo em 320px e fonte 1.5x empilha os três indicadores', (
    tester,
  ) async {
    await _render(
      tester,
      const TelaInicial(user: _user),
      size: const Size(320, 640),
      scale: 1.5,
    );
    final exercises = tester.getTopLeft(find.text('Exercícios'));
    final review = tester.getTopLeft(find.text('Para revisar'));
    final progress = tester.getTopLeft(find.text('Evolução'));
    expect(exercises.dy, lessThan(review.dy));
    expect(review.dy, lessThan(progress.dy));
    await tester.ensureVisible(find.text('Sobre o App'));
    expect(find.text('Sobre o App').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Resumo desktop mantém três colunas e largura de leitura', (
    tester,
  ) async {
    await _render(
      tester,
      const TelaInicial(user: _user),
      size: const Size(1440, 1000),
      scale: 2,
    );
    final exercises = tester.getTopLeft(find.text('Exercícios'));
    final review = tester.getTopLeft(find.text('Para revisar'));
    final progress = tester.getTopLeft(find.text('Evolução'));
    expect(exercises.dy, closeTo(review.dy, 1));
    expect(review.dy, closeTo(progress.dy, 1));
    expect(
      tester.getSize(find.byType(SingleChildScrollView)).width,
      lessThanOrEqualTo(1120),
    );
    final cards = find
        .ancestor(of: find.text('Exercícios'), matching: find.byType(Container))
        .first;
    expect(tester.getSize(cards).width, lessThanOrEqualTo(360));
    final aboutButton = find.ancestor(
      of: find.text('Sobre o App'),
      matching: find.byWidgetPredicate((widget) => widget is Button),
    );
    expect(tester.getSize(aboutButton).width, lessThanOrEqualTo(480));
    expect(find.text('3'), findsOneWidget);
  });

  for (final scenario in [(320.0, 1.0), (1440.0, 2.0)]) {
    testWidgets(
      'Título e demonstração fora do desfoque em ${scenario.$1}px e fonte ${scenario.$2}x',
      (tester) async {
        await _render(
          tester,
          const TelaInicial(user: _user),
          size: Size(scenario.$1, 900),
          scale: scenario.$2,
        );
        _expectOutsideTopFade(tester, find.text('MistakeMap'));
        await _render(
          tester,
          const TelaMapaConceitual(user: _user),
          size: Size(scenario.$1, 900),
          scale: scenario.$2,
        );
        _expectOutsideTopFade(tester, find.textContaining('Demonstração'));
      },
    );
  }

  testWidgets('Admin em 320px e fonte 2x preserva badges e menu acessível', (
    tester,
  ) async {
    await _render(
      tester,
      const TelaAdmin(user: _admin),
      size: const Size(320, 800),
      scale: 2,
    );
    expect(find.textContaining('Falha ao carregar'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('admin-section-1')));
    await _settle(tester);
    await tester.scrollUntilVisible(
      find.text('(você)'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('(você)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byTooltip('Gerenciar papel'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byTooltip('Gerenciar papel')),
      alignment: 0.5,
    );
    await _settle(tester);
    expect(find.byTooltip('Gerenciar papel').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final user in [_user, _admin]) {
    testWidgets(
      'Navegação ${user.role} em 320px mantém abas e mapa sem overflow',
      (tester) async {
        await _render(
          tester,
          TelaNavegacao(user: user, analysisRepository: FakeRepository()),
          size: const Size(320, 740),
          scale: user.isAdmin ? 1.5 : 1,
        );
        await tester.tap(find.text('Mapa'));
        await _settle(tester);
        expect(find.text('Seu mapa ainda está vazio'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Voltar'));
        await _settle(tester);
        if (user.isAdmin) {
          await tester.tap(find.byKey(const ValueKey('navigation-more')));
          await _settle(tester);
          await tester.tap(find.text('Admin').hitTestable().first);
          await _settle(tester);
          expect(find.text('Painel Administrativo'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('Adicionar em 320px e fonte 2x mantém ações acessíveis', (
    tester,
  ) async {
    await _render(
      tester,
      const TelaAdicionarExercicio(user: _user),
      size: const Size(320, 640),
      scale: 2,
    );
    await tester.ensureVisible(find.text('Registrar exercício'));
    expect(find.text('Registrar exercício').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  group('layout adaptativo nas telas', () {
    const prompt =
        'Descrição longa de um exercício para validar a quebra de linha sem cortes.';
    const placeholder = 'Selecione um exercício para ver os detalhes.';

    testWidgets('Exercícios em 1280px: lista e detalhe lado a lado', (
      tester,
    ) async {
      await _render(
        tester,
        const TelaPrincipal(user: _user),
        size: const Size(1280, 800),
      );
      await _settle(tester);
      expect(find.text(placeholder), findsOneWidget);
      await tester.tap(find.text(prompt).first);
      await _settle(tester);
      expect(find.text(placeholder), findsNothing);
      expect(find.text('DESCRIÇÃO DO ERRO'), findsOneWidget);
      // A lista continua visível ao lado do detalhe.
      expect(find.text(prompt), findsWidgets);
      expect(find.text('Meus Exercícios'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Exercícios usam a tentativa mais recente e não oferecem '
        'Editar depois do envio', (tester) async {
      await _render(
        tester,
        const TelaPrincipal(user: _user),
        size: const Size(1280, 800),
      );
      await _settle(tester);
      // A tentativa antiga de exercise-1 ('dead_letter') não aparece.
      expect(find.text('Erro'), findsNothing);
      expect(find.text('Pendente'), findsNWidgets(2));
      await tester.tap(find.text(prompt).first);
      await _settle(tester);
      expect(find.text('Editar exercício'), findsNothing);
      expect(find.byTooltip('Editar'), findsNothing);
      await tester.tap(find.byTooltip('Opções').first);
      await _settle(tester);
      expect(find.text('Ver detalhes'), findsOneWidget);
      expect(find.text('Editar'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Exercícios em 390px: o detalhe abre em outra página', (
      tester,
    ) async {
      await _render(
        tester,
        const TelaPrincipal(user: _user),
        size: const Size(390, 800),
      );
      await _settle(tester);
      expect(find.text(placeholder), findsNothing);
      await tester.tap(find.text(prompt).first);
      await _settle(tester);
      expect(find.text('DESCRIÇÃO DO ERRO'), findsOneWidget);
      expect(find.byTooltip('Voltar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Exercícios em tela dupla: um painel de cada lado da dobradiça',
      (tester) async {
        // Duas telas de 360 px e dobradiça de 34 px: classe "média", mas a
        // dobra separa a tela, então lista e detalhe ficam um de cada lado.
        const hinge = Rect.fromLTWH(360, 0, 34, 720);
        await _render(
          tester,
          const TelaPrincipal(user: _user),
          size: const Size(754, 720),
          features: const [
            DisplayFeature(
              bounds: hinge,
              type: DisplayFeatureType.hinge,
              state: DisplayFeatureState.postureFlat,
            ),
          ],
        );
        await _settle(tester);
        final aviso = tester.getRect(find.text(placeholder));
        expect(aviso.left, greaterThanOrEqualTo(hinge.right));
        expect(
          tester.getRect(find.text(prompt).first).right,
          lessThanOrEqualTo(hinge.left),
        );
        expect(tester.takeException(), isNull);
      },
    );

    for (final (largura, colunas) in [(1280.0, 4), (320.0, 1)]) {
      testWidgets(
        'Admin em ${largura.toInt()}px mostra as métricas em $colunas coluna(s)',
        (tester) async {
          await _render(
            tester,
            const TelaAdmin(user: _admin),
            size: Size(largura, 900),
          );
          final titulos = [
            'Total Usuários',
            'Exercícios Criados',
            'Tentativas & Envios',
          ];
          final topos = {
            for (final t in titulos) tester.getTopLeft(find.text(t)).dy,
          };
          expect(topos, hasLength(colunas == 1 ? 3 : 1));
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
