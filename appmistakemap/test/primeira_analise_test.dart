import 'package:appmistakemap/exercicios/banco_questoes.dart';
import 'package:appmistakemap/main.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uid = '11111111-1111-4111-8111-111111111111';

Questao _q(
  String id,
  String kind, {
  String dificuldade = 'facil',
  RespostaSalva? ultima,
}) => Questao.deJson({
  'id': id,
  'kind': kind,
  'subject': 'Eletrônica',
  'topic': 'Circuitos',
  'theme': 'Lei de Ohm',
  'difficulty': dificuldade,
  'prompt_text': 'Qual resistor limita o LED?',
  'payload': {
    'options': [
      {'id': 'a', 'text': '100 Ω'},
      {'id': 'b', 'text': '250 Ω'},
    ],
  },
}, ultima)!;

class _RepoFalso implements RepositorioQuestoes {
  final respostas = <String>[];

  @override
  Future<List<Questao>> carregar(String usuarioId) async => [
    _q('q1', 'multipla_escolha'),
  ];

  @override
  Future<CorrecaoQuestao> responder(
    String questaoId,
    Map<String, dynamic> resposta,
  ) async {
    respostas.add(questaoId);
    return const CorrecaoQuestao(
      situacao: 'graded',
      correta: false,
      nota: 0,
      respostaCorreta: 'a) 100 Ω',
      diagnosticos: [DiagnosticoQuestao('conceito', 'Reveja a Lei de Ohm.')],
    );
  }
}

Future<void> _render(WidgetTester tester, Widget corpo) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    LiquidGlassWidgets.wrap(
      theme: temaVidro,
      child: FluentApp(theme: temaFluent, home: corpo),
    ),
  );
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 5),
);

Future<void> _tocar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await _settle(tester);
  await tester.tap(alvo);
  await _settle(tester);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('escolherQuestaoInicial', () {
    test('prefere múltipla escolha fácil ainda não respondida', () {
      final escolhida = escolherQuestaoInicial([
        _q('vf', 'verdadeiro_falso'),
        _q('me-media', 'multipla_escolha', dificuldade: 'media'),
        _q(
          'me-feita',
          'multipla_escolha',
          ultima: const RespostaSalva(correta: true, nota: 1, quando: null),
        ),
        _q('me-facil', 'multipla_escolha'),
      ]);
      expect(escolhida?.id, 'me-facil');
    });

    test('sem múltipla escolha, usa outra objetiva; nunca dissertativa', () {
      expect(
        escolherQuestaoInicial([_q('d', 'dissertativa'), _q('n', 'numerica')])
            ?.id,
        'n',
      );
      expect(escolherQuestaoInicial([_q('d', 'dissertativa')]), isNull);
      expect(escolherQuestaoInicial(const []), isNull);
    });
  });

  testWidgets('cartão aparece, começa e some depois de "Agora não"', (
    tester,
  ) async {
    var comecou = 0;
    await _render(
      tester,
      ScaffoldPage(
        content: GuiaPrimeiraAnalise(
          usuarioId: _uid,
          onComecar: () async => comecou++,
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('Sua primeira análise'), findsOneWidget);
    expect(find.text('Leva 2 minutos'), findsOneWidget);

    await _tocar(tester, find.byKey(const Key('primeira-analise-comecar')));
    expect(comecou, 1);

    await _tocar(tester, find.byKey(const Key('primeira-analise-dispensar')));
    expect(find.text('Sua primeira análise'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PreferenciaPrimeiraAnalise.chave(_uid)), isTrue);
  });

  testWidgets('cartão não aparece para quem já dispensou', (tester) async {
    SharedPreferences.setMockInitialValues({
      PreferenciaPrimeiraAnalise.chave(_uid): true,
    });
    await _render(
      tester,
      ScaffoldPage(
        content: GuiaPrimeiraAnalise(usuarioId: _uid, onComecar: () async {}),
      ),
    );
    await _settle(tester);
    expect(find.text('Sua primeira análise'), findsNothing);
  });

  testWidgets('primeira análise abre a questão e leva ao Mapa', (tester) async {
    final repo = _RepoFalso();
    var mapa = 0;
    await _render(
      tester,
      Builder(
        builder: (context) => ScaffoldPage(
          content: Center(
            child: Button(
              key: const Key('abrir'),
              onPressed: () => abrirPrimeiraAnalise(
                context,
                usuarioId: _uid,
                repositorio: repo,
                semear: false,
                onVerMapa: () => mapa++,
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await _tocar(tester, find.byKey(const Key('abrir')));
    expect(find.text('Qual resistor limita o LED?'), findsOneWidget);
    expect(find.byKey(const Key('questao-ver-mapa')), findsNothing);

    await _tocar(tester, find.byKey(const Key('opcao-b')));
    await _tocar(tester, find.byKey(const Key('questao-enviar')));
    expect(repo.respostas, ['q1']);
    expect(find.text('Resposta errada'), findsOneWidget);

    await _tocar(tester, find.byKey(const Key('questao-ver-mapa')));
    expect(mapa, 1);
    expect(find.text('Qual resistor limita o LED?'), findsNothing);
  });
}
