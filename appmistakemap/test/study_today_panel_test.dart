import 'package:appmistakemap/study/study_today_panel.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements StudyStore {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

StudyJson _dashboard({bool withProfile = true}) => {
  'profile': withProfile
      ? {
          'stage': 'superior',
          'daily_minutes': 15,
          'goal': 'Entender os circuitos de sensores',
        }
      : null,
  'due_count': 1,
  'pending_diagnostics': 1,
  'estimated_minutes': 3,
  'reviewed_today': 2,
  'progress': {'reviews': 6, 'recall_rate': .5, 'period_days': 7},
};

StudyJson _session({bool answered = false}) => {
  'id': 'session-1',
  'status': answered ? 'completed' : 'active',
  'items': [
    {
      'id': 'review-1',
      'subject_name': 'Eletrônica',
      'concept_name': 'Resistência',
      'prompt_text':
          'Um sensor recebe 12 V e consome 0,2 A. Calcule a resistência.',
      'answered': answered,
    },
  ],
};

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 800,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1400);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    FluentApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 1400),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Hoje mostra próxima ação e amostra honesta em celular com texto ampliado',
    (tester) async {
      final repo = SupabaseStudyRepository.withTransport(
        (userId, body) async =>
            body['action'] == 'dashboard' ? _dashboard() : {'session': null},
        store: _MemoryStore(),
      );
      await _pump(
        tester,
        ScaffoldPage(
          content: SingleChildScrollView(
            child: StudyTodayPanel(userId: 'aluno-a', repository: repo),
          ),
        ),
        width: 320,
        textScale: 2,
      );
      expect(find.text('Seu estudo de hoje'), findsOneWidget);
      expect(find.text('Começar revisão'), findsOneWidget);
      expect(
        find.text('6 autoavaliação(ões) nos últimos 7 dias.'),
        findsOneWidget,
      );
      expect(find.textContaining('não representa nota'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );

  testWidgets('primeiro acesso salva objetivo escolhido no servidor', (
    tester,
  ) async {
    StudyJson? saved;
    final repo = SupabaseStudyRepository.withTransport((userId, body) async {
      switch (body['action']) {
        case 'dashboard':
          return saved == null
              ? _dashboard(withProfile: false)
              : {..._dashboard(), 'profile': saved};
        case 'session':
          return {'session': null};
        case 'profile':
          return {'profile': saved, 'subjects': []};
        case 'save_profile':
          saved = studyMap(body['profile']);
          return {'profile': saved, 'subjects': []};
      }
      throw StateError('action inesperada');
    }, store: _MemoryStore());
    await _pump(
      tester,
      ScaffoldPage(
        content: SingleChildScrollView(
          child: StudyTodayPanel(userId: 'aluno-a', repository: repo),
        ),
      ),
    );
    await tester.tap(find.text('Definir meu objetivo'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('study-goal')),
      'Aprender circuitos elétricos',
    );
    await tester.tap(find.text('Salvar objetivo'));
    await tester.pumpAndSettle();
    expect(saved?['goal'], 'Aprender circuitos elétricos');
    expect(saved?['stage'], 'autodidata');
    expect(saved?['daily_minutes'], 15);
    expect(find.text('Aprender circuitos elétricos'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
  });

  testWidgets(
    'revisão pede referência antes da autoavaliação e salva só um rating',
    (tester) async {
      final answers = <StudyJson>[];
      final repo = SupabaseStudyRepository.withTransport((userId, body) async {
        if (body['action'] == 'session') {
          return {
            'session': _session(),
            'reference_text': 'R = 12 / 0,2 = 60 Ω.',
          };
        }
        if (body['action'] == 'answer') {
          answers.add(body);
          return {
            'session': _session(answered: true),
            'feedback': {
              'reference_text': '60 Ω',
              'next_due_at': '2026-11-08T12:00:00Z',
            },
          };
        }
        throw StateError('action inesperada');
      }, store: _MemoryStore());
      await _pump(
        tester,
        StudyReviewPage(
          userId: 'aluno-a',
          repository: repo,
          initialSession: StudySession.fromJson(_session()),
        ),
      );
      expect(find.text('Lembrei'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('study-review-draft')),
        'R = V / I = 60 ohms',
      );
      await tester.tap(find.text('Ver referência'));
      await tester.pumpAndSettle();
      expect(find.text('R = 12 / 0,2 = 60 Ω.'), findsOneWidget);
      expect(
        find.textContaining('não é uma correção automática'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Lembrei'));
      await tester.tap(find.text('Lembrei'));
      await tester.pumpAndSettle();
      expect(answers.length, 1);
      expect(answers.single['rating'], 'good');
      expect(find.text('Autoavaliação registrada'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );

  testWidgets('conferência confirma a sugestão sem decisão automática', (
    tester,
  ) async {
    StudyJson? decision;
    final repo = SupabaseStudyRepository.withTransport((userId, body) async {
      if (body['action'] == 'diagnostics') {
        return {
          'items': decision == null
              ? [
                  {
                    'id': 'error-1',
                    'subject_name': 'Eletrônica',
                    'concept_name': 'Resistência',
                    'category': 'unidade',
                    'evidence':
                        'A resposta não informou a unidade da resistência.',
                  },
                ]
              : [],
        };
      }
      if (body['action'] == 'decide') {
        decision = body;
        return {
          'diagnostic': {'status': 'confirmed'},
        };
      }
      throw StateError('action inesperada');
    }, store: _MemoryStore());
    await _pump(
      tester,
      StudyDiagnosticsPage(userId: 'aluno-a', repository: repo),
    );
    expect(decision, isNull);
    expect(find.text('Sugestão: Unidade'), findsOneWidget);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(decision?['decision'], 'confirmed');
    expect(decision?['error_event_id'], 'error-1');
    expect(find.text('Tudo conferido'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
  });

  for (final (width, sideBySide) in const [(1000.0, true), (360.0, false)]) {
    testWidgets(
      'atalhos ficam ${sideBySide ? 'lado a lado' : 'empilhados'} e centralizados em ${width.toInt()} px',
      (tester) async {
        final repo = SupabaseStudyRepository.withTransport(
          (userId, body) async =>
              body['action'] == 'dashboard' ? _dashboard() : {'session': null},
          store: _MemoryStore(),
        );
        await _pump(
          tester,
          ScaffoldPage(
            content: SingleChildScrollView(
              child: StudyTodayPanel(
                userId: 'aluno-a',
                repository: repo,
                onExplore: () {},
                onAnalyze: () {},
              ),
            ),
          ),
          width: width,
        );
        final explore = tester.getRect(find.byKey(const Key('study-explore')));
        final analyze = tester.getRect(find.byKey(const Key('study-analyze')));
        final panel = tester.getRect(find.byType(StudyTodayPanel));
        if (sideBySide) {
          expect(explore.center.dy, moreOrLessEquals(analyze.center.dy));
          expect(analyze.left - explore.right, moreOrLessEquals(16));
          expect(
            (explore.left + analyze.right) / 2,
            moreOrLessEquals(panel.center.dx),
          );
        } else {
          expect(analyze.top, greaterThan(explore.bottom));
          expect(explore.center.dx, moreOrLessEquals(panel.center.dx));
          expect(analyze.center.dx, moreOrLessEquals(panel.center.dx));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        repo.dispose();
      },
    );
  }
}
