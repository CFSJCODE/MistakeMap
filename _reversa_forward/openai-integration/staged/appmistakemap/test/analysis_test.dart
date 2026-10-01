import 'dart:typed_data';

import 'package:appmistakemap/ai/analysis_models.dart';
import 'package:appmistakemap/ai/analysis_repository.dart';
import 'package:appmistakemap/ai/exercise_submission_view.dart';
import 'package:appmistakemap/ai/insights_view.dart';
import 'package:appmistakemap/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AttemptRecord sample({
  String id = 'a1',
  String subjectId = 'math',
  String subjectName = 'Matemática',
  String category = 'calculo',
  String concept = 'Frações',
  String status = 'completed',
  bool analyzed = true,
  bool duplicateError = false,
}) {
  final error = IdentifiedError(
    category: category,
    concept: concept,
    evidence: 'Somou denominadores na tentativa.',
    confidence: .9,
  );
  return AttemptRecord(
    id: id,
    exerciseId: 'e1',
    subjectId: subjectId,
    subjectName: subjectName,
    prompt: 'Calcule 1/2 + 1/3',
    answer: '2/5',
    status: status,
    attemptedAt: DateTime(2026, 9, 29),
    analysis: analyzed
        ? AttemptAnalysis(
            attemptId: id,
            subjectId: subjectId,
            isCorrect: false,
            correctAnswer: '5/6',
            explanation: 'Use um denominador comum.',
            errors: [error, if (duplicateError) error],
          )
        : null,
  );
}

class FakeRepository implements AnalysisRepository {
  List<AttemptRecord> attempts = [];
  List<PracticeExercise> practice = [];
  bool failLoad = false;
  bool failAnalyze = false;
  int created = 0;
  int analyzed = 0;
  String? savedPrompt;
  String? savedAnswer;
  String? savedDifficulty;
  PracticeExercise? savedPractice;
  @override
  Future<List<AttemptRecord>> loadAttempts(String userId) async {
    if (failLoad) {
      throw const AnalysisFailure(
        'A IA ainda não foi configurada no servidor.',
      );
    }
    return attempts;
  }

  @override
  Future<String> createAttempt({
    required String userId,
    required String subject,
    required String prompt,
    required String answer,
    required String difficulty,
    required bool hasImage,
    PracticeExercise? practice,
  }) async {
    created++;
    savedPrompt = prompt;
    savedAnswer = answer;
    savedDifficulty = difficulty;
    savedPractice = practice;
    attempts = [sample()];
    return 'a1';
  }

  @override
  Future<void> uploadImage(
    String attemptId,
    String filename,
    Uint8List bytes,
  ) async {}
  @override
  Future<void> analyze(String attemptId) async {
    analyzed++;
    if (failAnalyze) {
      throw const AnalysisFailure(
        'A IA ainda não foi configurada no servidor. Seu exercício está salvo.',
      );
    }
  }

  @override
  Future<List<PracticeExercise>> generatePractice(
    String subjectId,
    String subjectName,
    int count,
  ) async => practice;
  @override
  Future<List<PracticeExercise>> loadPractice(String userId) async => practice;
}

void main() {
  test('existing app model still compiles', () {
    expect(const AppUser(id: 'u', email: '', role: 'user').isAdmin, isFalse);
  });

  test('counts attempts once across duplicate events and repeated loading', () {
    final first = sample(duplicateError: true);
    final insights = ErrorInsights.fromAttempts([
      first,
      first,
      sample(id: 'a2'),
    ]);
    expect(insights.attempts.length, 2);
    expect(insights.categories.single.count, 2);
    expect(insights.concepts.single.count, 2);
    expect(insights.edges.every((e) => e.attemptIds.length == 2), isTrue);
    expect(insights.evidence(insights.concepts.single.attemptIds).length, 2);
  });

  test('same concept label in different subjects stays separate', () {
    final insights = ErrorInsights.fromAttempts([
      sample(),
      sample(id: 'a2', subjectId: 'physics', subjectName: 'Física'),
    ]);
    expect(insights.concepts.length, 2);
    expect(insights.subjects.length, 2);
    expect(insights.nodes.where((n) => n.kind == 'Conceito').length, 2);
    expect(insights.categories.single.count, 2);
  });

  test('case and surrounding spaces do not duplicate a concept', () {
    final insights = ErrorInsights.fromAttempts([
      sample(),
      sample(id: 'a2', concept: ' frações '),
    ]);
    expect(insights.concepts.single.count, 2);
  });

  test(
    'pending and legacy completed rows do not become analyzed successes',
    () {
      final insights = ErrorInsights.fromAttempts([
        sample(analyzed: false),
        sample(id: 'pending', analyzed: false, status: 'pending'),
      ]);
      expect(insights.analyzedCount, 0);
      expect(insights.errorsCount, 0);
      expect(insights.nodes, isEmpty);
      expect(insights.categories, isEmpty);
    },
  );

  test('JSON parser bounds confidence and accepts uncertain result', () {
    final analysis = AttemptAnalysis.fromJson({
      'attempt_id': 'a1',
      'subject_id': 's1',
      'is_correct': null,
      'errors': [
        {'category': 'conceito', 'concept': 'Frações', 'confidence': 4},
        {'category': 'outro', 'concept': 'Unidades', 'confidence': double.nan},
      ],
    });
    expect(analysis.isCorrect, isNull);
    expect(analysis.errors.first.confidence, 1);
    expect(analysis.errors.last.confidence, 0);
  });

  test('image upload MIME matches extension accepted by backend', () {
    expect(imageContentType('foto.JPEG'), 'image/jpeg');
    expect(imageContentType('foto.png'), 'image/png');
    expect(imageContentType('foto.webp'), 'image/webp');
    expect(() => imageContentType('foto.svg'), throwsA(isA<AnalysisFailure>()));
  });

  test('unexpected errors never expose server details', () {
    expect(
      friendlyFailure(Exception('SENSITIVE_RESPONSE')),
      isNot(contains('SENSITIVE_RESPONSE')),
    );
  });

  testWidgets('empty map explains how to start without invented data', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ErrorMapView(userId: 'u', repository: FakeRepository()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Seu mapa ainda está vazio'), findsOneWidget);
    expect(find.textContaining('Matemática'), findsNothing);
  });

  testWidgets('server not configured is an explicit retryable state', (
    tester,
  ) async {
    final repository = FakeRepository()..failLoad = true;
    await tester.pumpWidget(
      MaterialApp(
        home: ErrorMapView(userId: 'u', repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('não foi configurada'), findsOneWidget);
    repository.failLoad = false;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Seu mapa ainda está vazio'), findsOneWidget);
  });

  testWidgets('map charts cloud connections and evidence fit narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeRepository()..attempts = [sample()];
    await tester.pumpWidget(
      MaterialApp(
        home: ErrorMapView(userId: 'u', repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tipos de erro'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Nuvem'));
    await tester.pumpAndSettle();
    expect(find.text('Frações (1)'), findsOneWidget);
    await tester.tap(find.text('Frações (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Frações · 1 tentativa(s)'), findsOneWidget);
    await tester.tap(find.text('Calcule 1/2 + 1/3'));
    await tester.pumpAndSettle();
    expect(find.text('Resposta sugerida'), findsOneWidget);
    expect(find.text('5/6'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('separate inputs and retry reuse the saved attempt', (
    tester,
  ) async {
    final repository = FakeRepository()..failAnalyze = true;
    await tester.pumpWidget(
      MaterialApp(
        home: ExerciseSubmissionView(userId: 'u', repository: repository),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('exercise-subject')),
      'Matemática',
    );
    await tester.enterText(
      find.byKey(const Key('exercise-prompt')),
      'Quanto é 2 + 2?',
    );
    await tester.enterText(find.byKey(const Key('exercise-answer')), '5');
    await tester.enterText(
      find.byKey(const Key('exercise-difficulty')),
      'Somei errado',
    );
    await tester.ensureVisible(find.byKey(const Key('submit-exercise')));
    await tester.tap(find.byKey(const Key('submit-exercise')));
    await tester.pumpAndSettle();
    expect(repository.created, 1);
    expect(repository.savedPrompt, 'Quanto é 2 + 2?');
    expect(repository.savedAnswer, '5');
    expect(repository.savedDifficulty, 'Somei errado');
    expect(find.textContaining('já está salva'), findsOneWidget);
    repository.failAnalyze = false;
    await tester.ensureVisible(find.byKey(const Key('submit-exercise')));
    await tester.tap(find.byKey(const Key('submit-exercise')));
    await tester.pumpAndSettle();
    expect(repository.created, 1);
    expect(repository.analyzed, 2);
    expect(find.text('Correção e evidências'), findsOneWidget);
  });

  testWidgets('generated practice is reloadable and exposes no answer key', (
    tester,
  ) async {
    final repository = FakeRepository()
      ..practice = [
        const PracticeExercise(
          id: 'generated-1',
          subjectId: 'math',
          subjectName: 'Matemática',
          prompt: 'Calcule 1/4 + 1/2',
          difficulty: 'facil',
          focusConcept: 'Frações',
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: PracticeView(
          userId: 'u',
          repository: repository,
          subjects: const {'math': 'Matemática'},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Calcule 1/4 + 1/2'), findsOneWidget);
    expect(find.text('3/4'), findsNothing);
    await tester.tap(find.text('Resolver'));
    await tester.pumpAndSettle();
    expect(find.text('Resolver exercício'), findsOneWidget);
    expect(find.text('Resposta sugerida'), findsNothing);
    await tester.enterText(find.byKey(const Key('exercise-answer')), '2/6');
    await tester.ensureVisible(find.byKey(const Key('submit-exercise')));
    await tester.tap(find.byKey(const Key('submit-exercise')));
    await tester.pumpAndSettle();
    expect(repository.savedPractice?.id, 'generated-1');
    expect(repository.savedAnswer, '2/6');
  });
}
