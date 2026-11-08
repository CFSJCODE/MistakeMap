import 'package:appmistakemap/exercicios/banco_questoes.dart';
import 'package:appmistakemap/main.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

const _user = AppUser(
  id: '11111111-1111-4111-8111-111111111111',
  email: 'estudante@example.test',
  role: 'user',
);

Map<String, dynamic> _linha(
  String id,
  String kind,
  String prompt,
  Map<String, dynamic> payload,
) => {
  'id': id,
  'kind': kind,
  'subject': 'Eletrônica',
  'topic': 'Circuitos',
  'theme': 'Lei de Ohm',
  'difficulty': 'facil',
  'prompt_text': prompt,
  'payload': payload,
};

final _questoes = [
  Questao.deJson(
    _linha('q1', 'multipla_escolha', 'Qual resistor limita o LED?', {
      'options': [
        {'id': 'a', 'text': '100 Ω'},
        {'id': 'b', 'text': '250 Ω'},
      ],
    }),
  )!,
  Questao.deJson(
    _linha('q2', 'verdadeiro_falso', 'Julgue sobre o robô.', {
      'statements': [
        {'id': '1', 'text': 'A resultante é 25 N.'},
        {'id': '2', 'text': 'A aceleração é 8 m/s².'},
      ],
    }),
    const RespostaSalva(correta: false, nota: 0.5, quando: null),
  )!,
  Questao.deJson(
    _linha('q3', 'ordenacao', 'Ordene o boot.', {
      'items': [
        {'id': 'b', 'text': 'Firmware'},
        {'id': 'a', 'text': 'Fonte'},
      ],
    }),
    const RespostaSalva(correta: true, nota: 1, quando: null),
  )!,
  Questao.deJson(
    _linha('q4', 'numerica', 'Resistência em série?', {'unit': 'Ω'}),
  )!,
  Questao.deJson(
    _linha('q5', 'lacuna', 'V = R × (1) ______.', {
      'blanks': [
        {'id': '1', 'text': 'Lacuna 1'},
      ],
    }),
  )!,
  Questao.deJson(_linha('q6', 'dissertativa', 'Explique o PID.', {}))!,
  Questao.deJson(
    _linha('q7', 'associacao', 'Associe componente e função.', {
      'left': [
        {'id': 'l1', 'text': 'Resistor'},
      ],
      'right': [
        {'id': 'r2', 'text': 'Armazena carga'},
        {'id': 'r1', 'text': 'Limita a corrente'},
      ],
    }),
  )!,
];

class _RepoFalso implements RepositorioQuestoes {
  final respostas = <(String, Map<String, dynamic>)>[];
  CorrecaoQuestao resultado = const CorrecaoQuestao(
    situacao: 'graded',
    correta: false,
    nota: 0,
    itens: {'b': false},
    respostaCorreta: 'a) 100 Ω',
    explicacao: 'R = 2 ÷ 0,020 = 100 Ω.',
    diagnosticos: [
      DiagnosticoQuestao('interpretacao', 'Você usou os 5 V inteiros.'),
    ],
  );

  @override
  Future<List<Questao>> carregar(String usuarioId) async => _questoes;

  @override
  Future<CorrecaoQuestao> responder(
    String questaoId,
    Map<String, dynamic> resposta,
  ) async {
    respostas.add((questaoId, resposta));
    return resultado;
  }
}

Future<void> _render(
  WidgetTester tester,
  Widget page, {
  Size size = const Size(390, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    LiquidGlassWidgets.wrap(
      theme: temaVidro,
      child: FluentApp(theme: temaFluent, home: page),
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
  group('modelos', () {
    test('questão lê o payload público de cada tipo', () {
      final q = _questoes.first;
      expect(q.tipo, TipoQuestao.multiplaEscolha);
      expect(q.alternativas.map((o) => o.texto), ['100 Ω', '250 Ω']);
      expect(_questoes[3].unidade, 'Ω');
      expect(Questao.deJson({'kind': 'desconhecido'}), isNull);
    });

    test('resposta segue o formato que o servidor corrige', () {
      expect(respostaPara(TipoQuestao.multiplaEscolha, escolha: 'a'), {
        'choice': 'a',
      });
      expect(respostaPara(TipoQuestao.multiplaSelecao, escolhas: {'a', 'c'}), {
        'choices': ['a', 'c'],
      });
      expect(
        respostaPara(TipoQuestao.verdadeiroFalso, verdadeiroFalso: {'1': true}),
        {
          'answers': {'1': true},
        },
      );
      expect(respostaPara(TipoQuestao.numerica, numero: ' 1020 '), {
        'value': '1020',
      });
      expect(
        respostaPara(TipoQuestao.lacuna, lacunas: {'1': ' ohm ', '2': ' '}),
        {
          'blanks': {'1': 'ohm'},
        },
      );
      expect(respostaPara(TipoQuestao.ordenacao, ordem: ['a', 'b']), {
        'order': ['a', 'b'],
      });
      expect(respostaPara(TipoQuestao.associacao, pares: {'l1': 'r1'}), {
        'pairs': {'l1': 'r1'},
      });
      expect(respostaPara(TipoQuestao.dissertativa, texto: ' P, I e D '), {
        'text': 'P, I e D',
      });
    });

    test('correção do servidor vira o modelo do app', () {
      final c = CorrecaoQuestao.deJson({
        'status': 'graded',
        'is_correct': false,
        'score': 0.5,
        'items': [
          {'id': '1', 'correct': true},
          {'id': '2', 'correct': false},
        ],
        'correct_answer': '1) V; 2) F',
        'explanation': 'x',
        'diagnoses': [
          {'category': 'conceito', 'feedback': 'y'},
        ],
      });
      expect(c.corrigida, isTrue);
      expect(c.itens, {'1': true, '2': false});
      expect(c.diagnosticos.single.categoria, 'conceito');
      final pendente = CorrecaoQuestao.deJson({
        'status': 'pending',
        'message': 'Sua resposta foi salva.',
      });
      expect(pendente.corrigida, isFalse);
      expect(pendente.mensagem, 'Sua resposta foi salva.');
    });
  });

  testWidgets('banco mostra resumo, situação e filtra por tipo', (
    tester,
  ) async {
    await _render(
      tester,
      BancoExercicios(
        user: _user,
        cabecalho: const Text('Cabeçalho'),
        repositorio: _RepoFalso(),
      ),
      // Alta o bastante para a lista inteira caber sem rolar.
      size: const Size(390, 2600),
    );
    await _settle(tester);
    expect(find.text('2 de 7 respondidos · 1 certos'), findsOneWidget);
    expect(find.text('Acertou em parte'), findsOneWidget);
    expect(find.text('Acertou'), findsOneWidget);
    expect(find.text('Não respondida'), findsNWidgets(5));

    await _tocar(tester, find.byKey(const Key('filtro-tipo-numerica')));
    expect(find.text('Resistência em série?'), findsOneWidget);
    expect(find.text('Qual resistor limita o LED?'), findsNothing);

    await _tocar(tester, find.text('Para revisar'));
    expect(find.text('Nenhum exercício com esses filtros.'), findsOneWidget);
    await _tocar(tester, find.text('Limpar filtros'));
    expect(find.text('Qual resistor limita o LED?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('múltipla escolha: pede alternativa, envia e mostra correção', (
    tester,
  ) async {
    final repo = _RepoFalso();
    await _render(
      tester,
      TelaResponderQuestao(questoes: _questoes, inicial: 0, repositorio: repo),
    );
    await _settle(tester);
    await _tocar(tester, find.byKey(const Key('questao-enviar')));
    expect(find.text('Escolha uma alternativa.'), findsOneWidget);
    expect(repo.respostas, isEmpty);

    await _tocar(tester, find.byKey(const Key('opcao-b')));
    await _tocar(tester, find.byKey(const Key('questao-enviar')));
    expect(repo.respostas.single.$1, 'q1');
    expect(repo.respostas.single.$2, {'choice': 'b'});
    expect(find.text('Resposta errada'), findsOneWidget);
    expect(find.text('Interpretação'), findsOneWidget);
    expect(find.text('Você usou os 5 V inteiros.'), findsOneWidget);
    expect(find.text('a) 100 Ω'), findsOneWidget);
    expect(
      find.text('Este erro foi registrado no seu Mapa de erros.'),
      findsOneWidget,
    );

    // Próximo exercício segue a lista e limpa a resposta.
    await _tocar(tester, find.byKey(const Key('questao-proxima')));
    expect(find.text('Exercício 2 de 7'), findsOneWidget);
    expect(find.text('Julgue sobre o robô.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('verdadeiro ou falso exige todas as afirmações', (tester) async {
    final repo = _RepoFalso()
      ..resultado = const CorrecaoQuestao(
        situacao: 'graded',
        correta: true,
        nota: 1,
        itens: {'1': true, '2': true},
        respostaCorreta: '1) V; 2) F',
      );
    await _render(
      tester,
      TelaResponderQuestao(questoes: _questoes, inicial: 1, repositorio: repo),
    );
    await _settle(tester);
    await _tocar(tester, find.byKey(const Key('vf-1-v')));
    await _tocar(tester, find.byKey(const Key('questao-enviar')));
    expect(find.text('Marque V ou F em todas as afirmações.'), findsOneWidget);
    await _tocar(tester, find.byKey(const Key('vf-2-f')));
    await _tocar(tester, find.byKey(const Key('questao-enviar')));
    expect(repo.respostas.single.$2, {
      'answers': {'1': true, '2': false},
    });
    expect(find.text('Resposta certa!'), findsOneWidget);
    expect(
      find.text('Este erro foi registrado no seu Mapa de erros.'),
      findsNothing,
    );
  });

  testWidgets('ordenação troca itens com as setas', (tester) async {
    final repo = _RepoFalso();
    await _render(
      tester,
      TelaResponderQuestao(questoes: _questoes, inicial: 2, repositorio: repo),
    );
    await _settle(tester);
    await _tocar(tester, find.byKey(const Key('ordem-desce-0')));
    await _tocar(tester, find.byKey(const Key('questao-enviar')));
    expect(repo.respostas.single.$2, {
      'order': ['a', 'b'],
    });
  });

  testWidgets('numérica e lacuna enviam o texto digitado', (tester) async {
    final repo = _RepoFalso();
    await _render(
      tester,
      TelaResponderQuestao(questoes: _questoes, inicial: 3, repositorio: repo),
    );
    await _settle(tester);
    expect(find.text('Ω'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('questao-numero')), '1020');
    await _tocar(tester, find.byKey(const Key('questao-enviar')));
    expect(repo.respostas.last.$2, {'value': '1020'});

    await _tocar(tester, find.byKey(const Key('questao-proxima')));
    await tester.enterText(find.byKey(const Key('lacuna-1')), 'corrente');
    await _tocar(tester, find.byKey(const Key('questao-enviar')));
    expect(repo.respostas.last.$1, 'q5');
    expect(repo.respostas.last.$2, {
      'blanks': {'1': 'corrente'},
    });
  });

  testWidgets('dissertativa pendente avisa que a resposta foi salva', (
    tester,
  ) async {
    final repo = _RepoFalso()
      ..resultado = const CorrecaoQuestao(
        situacao: 'pending',
        mensagem: 'Sua resposta foi salva. A correção é refeita depois.',
      );
    await _render(
      tester,
      TelaResponderQuestao(questoes: _questoes, inicial: 5, repositorio: repo),
    );
    await _settle(tester);
    await tester.enterText(
      find.byKey(const Key('questao-texto')),
      'P corrige o erro atual, I o acumulado e D a variação.',
    );
    await _tocar(tester, find.byKey(const Key('questao-enviar')));
    expect(find.text('Resposta salva'), findsOneWidget);
    expect(
      find.text('Sua resposta foi salva. A correção é refeita depois.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('associação escolhe o par de cada item', (tester) async {
    final repo = _RepoFalso();
    await _render(
      tester,
      TelaResponderQuestao(questoes: _questoes, inicial: 6, repositorio: repo),
    );
    await _settle(tester);
    await _tocar(tester, find.byKey(const Key('questao-enviar')));
    expect(find.text('Associe todos os itens.'), findsOneWidget);
    await _tocar(tester, find.byKey(const Key('par-l1')));
    await _tocar(tester, find.text('Limita a corrente').last);
    await _tocar(tester, find.byKey(const Key('questao-enviar')));
    expect(repo.respostas.single.$2, {
      'pairs': {'l1': 'r1'},
    });
  });
}
