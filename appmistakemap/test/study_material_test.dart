import 'package:appmistakemap/ai/study_material.dart';
import 'package:appmistakemap/ai/study_material_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

StudyMaterial _material({String id = 'm1'}) => StudyMaterial.fromJson({
  'id': id,
  'subject_id': 's1',
  'created_at': '2026-10-30T12:00:00Z',
  'source_count': 4,
  'summary': {
    'title': 'Funções do 1º grau',
    'overview': 'Uma função afim tem a forma f(x) = ax + b.',
    'key_points': ['a é a taxa de variação', '  ', 'b é o valor em x = 0'],
    'common_mistakes': ['Trocar o sinal de b ao isolar x'],
  },
  'flashcards': [
    {'front': 'O que é o coeficiente angular?', 'back': 'A taxa a.'},
    {'front': 'Raiz de 2x - 4', 'back': 'x = 2', 'concept': 'Raiz'},
    {'front': '', 'back': 'descartado'},
  ],
  'quiz': [
    {
      'id': 'q1',
      'prompt': 'Raiz de f(x) = 2x - 6?',
      'options': ['2', '3', '-3', '6'],
      'concept': 'Raiz',
    },
    {
      'id': 'q2',
      'prompt': 'Coeficiente linear de 5x + 1?',
      'options': ['5', '1'],
      'concept': 'Coeficientes',
    },
    {
      'id': 'q3',
      'prompt': 'Sem opções suficientes',
      'options': ['a'],
    },
  ],
}, subjectName: 'Matemática');

class _FakeStudyRepository implements StudyMaterialRepository {
  final List<StudyMaterial> existing;
  Map<String, int>? graded;
  int generated = 0;

  _FakeStudyRepository({this.existing = const []});

  @override
  Future<StudyMaterial> generate(String subjectId, String subjectName) async {
    generated++;
    return _material(id: 'novo');
  }

  @override
  Future<List<StudyMaterial>> loadMaterials(
    Map<String, String> subjects,
  ) async => existing;

  @override
  Future<QuizRoundResult> gradeQuiz(
    String materialId,
    Map<String, int> answers,
  ) async {
    graded = answers;
    const key = {'q1': 1, 'q2': 1};
    return QuizRoundResult([
      for (final entry in key.entries)
        QuizQuestionResult(
          questionId: entry.key,
          choice: answers[entry.key],
          correctChoice: entry.value,
          explanation: 'Explicação de ${entry.key}',
        ),
    ]);
  }
}

Future<void> _pump(WidgetTester tester, StudyMaterialRepository repo) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      home: StudyMaterialView(
        repository: repo,
        subjects: const {'s1': 'Matemática'},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('StudyMaterial.fromJson', () {
    test('descarta itens vazios e questões sem alternativas', () {
      final material = _material();
      expect(material.summary.keyPoints, hasLength(2));
      expect(material.flashcards, hasLength(2));
      expect(material.quiz.map((q) => q.id), ['q1', 'q2']);
      expect(material.sourceCount, 4);
      expect(material.subjectName, 'Matemática');
    });

    test('gabarito não faz parte da questão', () {
      final question = QuizQuestion.fromJson({
        'id': 'q',
        'prompt': 'p',
        'options': ['a', 'b'],
        'correct_choice': 1,
      });
      expect(question.options, ['a', 'b']);
    });
  });

  group('QuizRoundResult', () {
    test('calcula acertos, percentual e conceitos errados', () {
      const result = QuizRoundResult([
        QuizQuestionResult(
          questionId: 'q1',
          choice: 1,
          correctChoice: 1,
          explanation: '',
        ),
        QuizQuestionResult(
          questionId: 'q2',
          choice: 0,
          correctChoice: 1,
          explanation: '',
        ),
      ]);
      expect(result.correctCount, 1);
      expect(result.incorrectCount, 1);
      expect(result.correctPercentage, 50);
      final missed = result.missedConcepts(_material().quiz);
      expect(missed.single.label, 'Coeficientes');
    });

    test('rodada vazia não tem percentual', () {
      expect(const QuizRoundResult([]).correctPercentage, isNull);
    });
  });

  test('mensagens de falha do serviço de estudo', () {
    expect(
      studyFailureMessage(422, {'error': 'no_study_sources'}),
      contains('Registre ao menos um exercício'),
    );
    expect(studyFailureMessage(404, null), contains('ainda não está'));
    expect(studyFailureMessage(500, {'message': 'Servidor'}), 'Servidor');
  });

  group('StudyMaterialView', () {
    testWidgets('sem material mostra o estado vazio e gera um novo', (
      tester,
    ) async {
      final repo = _FakeStudyRepository();
      await _pump(tester, repo);
      expect(find.byKey(const Key('study-empty')), findsOneWidget);

      await tester.tap(find.byKey(const Key('study-generate')));
      await tester.pumpAndSettle();
      expect(repo.generated, 1);
      expect(find.text('Funções do 1º grau'), findsOneWidget);
      expect(find.text('Onde você costuma errar'), findsOneWidget);
      expect(find.text('Baseado em 4 exercício(s) seus.'), findsOneWidget);
    });

    testWidgets('sem matérias explica como começar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StudyMaterialView(
            repository: _FakeStudyRepository(),
            subjects: const {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('study-no-subjects')), findsOneWidget);
      expect(find.byKey(const Key('study-generate')), findsNothing);
    });

    testWidgets('cartões viram e contam o que o estudante já sabia', (
      tester,
    ) async {
      await _pump(tester, _FakeStudyRepository(existing: [_material()]));
      await tester.tap(find.textContaining('Cartões'));
      await tester.pumpAndSettle();

      expect(find.text('O que é o coeficiente angular?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('flashcard-face')));
      await tester.pumpAndSettle();
      expect(find.text('A taxa a.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('flashcard-known')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('flashcard-face')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flashcard-unknown')));
      await tester.pumpAndSettle();

      expect(find.text('Você já sabia 1 de 2 cartão(ões).'), findsOneWidget);
      await tester.tap(find.byKey(const Key('flashcards-review-unknown')));
      await tester.pumpAndSettle();
      expect(find.text('Cartão 1 de 1 · Raiz'), findsOneWidget);
    });

    testWidgets('quiz só corrige no fim e mostra o resultado da rodada', (
      tester,
    ) async {
      final repo = _FakeStudyRepository(existing: [_material()]);
      await _pump(tester, repo);
      await tester.tap(find.textContaining('Quiz'));
      await tester.pumpAndSettle();

      final next = find.byKey(const Key('quiz-next'));
      expect(tester.widget<ElevatedButton>(next).onPressed, isNull);
      await tester.tap(find.byKey(const Key('quiz-option-1')));
      await tester.pump();
      await tester.tap(next);
      await tester.pumpAndSettle();

      expect(find.text('Coeficiente linear de 5x + 1?'), findsOneWidget);
      expect(repo.graded, isNull);
      await tester.tap(find.byKey(const Key('quiz-option-0')));
      await tester.pump();
      await tester.tap(next);
      await tester.pumpAndSettle();

      expect(repo.graded, {'q1': 1, 'q2': 0});
      expect(find.byKey(const Key('study-quiz-summary')), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('Coeficientes (1)'), findsOneWidget);
      expect(find.text('Resposta correta: 1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('quiz-restart')));
      await tester.pumpAndSettle();
      expect(find.text('Raiz de f(x) = 2x - 6?'), findsOneWidget);
    });
  });
}
