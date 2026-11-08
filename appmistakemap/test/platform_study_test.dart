import 'package:appmistakemap/platform/platform_hub.dart';
import 'package:appmistakemap/platform/platform_repository.dart';
import 'package:appmistakemap/platform/platform_session.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePlatform extends PlatformRepository {
  final calls = <(String, PlatformData)>[];
  bool saveFails = false;
  bool startFails = false;
  PlatformData overview = {
    'goals': <PlatformData>[],
    'sessions': <PlatformData>[],
    'classes': <PlatformData>[],
    'materials': <PlatformData>[],
    'notes': <PlatformData>[],
    'assignments': <PlatformData>[],
    'entitlements': {
      'plan': 'free',
      'sessions_per_day': 10,
      'sessions_used_today': 0,
    },
  };
  @override
  Future<PlatformData> execute(
    String action, [
    PlatformData input = const {},
  ]) async {
    calls.add((action, Map.of(input)));
    if (action == 'start_session') {
      if (startFails) {
        throw const PlatformFailure('A resposta não chegou. Tente novamente.');
      }
      return {
        'session': {
          'id': 'session',
          'title': 'Prática',
          'status': 'active',
          'mode': 'practice',
          'items': <PlatformData>[],
        },
      };
    }
    if (action == 'overview') return overview;
    if (action == 'catalog') {
      return {
        'exercises': [
          {
            'id': 'question-1',
            'subject': 'Física',
            'topic': 'Circuitos',
            'theme': 'Lei de Ohm',
            'difficulty': 'facil',
            'prompt_text': 'Um circuito tem 12 V e 6 Ω. Qual é a corrente?',
          },
        ],
      };
    }
    if (action == 'save_answer' && saveFails) {
      throw const PlatformFailure('Sem conexão. Sua resposta não foi enviada.');
    }
    if (action == 'export_data') {
      return {
        'table': input['table'],
        'data': [],
        'next_cursor': null,
        'tables': ['profiles', 'attempts'],
      };
    }
    return {'saved': true};
  }
}

Future<void> render(
  WidgetTester tester,
  Widget page, {
  double width = 800,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    FluentApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: page,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'repetir início após resposta perdida mantém idempotência e foco',
    (tester) async {
      final repo = FakePlatform()..startFails = true;
      repo.overview['goals'] = [
        {
          'id': 'goal-1',
          'title': 'Minha prova',
          'exam_date': '2026-11-20',
          'minutes_per_day': 15,
          'subjects': ['Física'],
          'weekly_plan': [
            {
              'subject': 'Física',
              'theme': 'Lei de Ohm',
              'date': '2026-11-06',
              'minutes': 15,
              'activity': 'Praticar',
            },
          ],
        },
      ];
      await render(tester, PlatformHubPage(userId: 'user', repository: repo));
      await tester.tap(find.text('Plano'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Praticar agora'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Praticar agora'));
      await tester.pumpAndSettle();
      repo.startFails = false;
      await tester.scrollUntilVisible(
        find.text('Praticar agora'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Praticar agora'));
      await tester.pumpAndSettle();
      final starts = repo.calls
          .where((entry) => entry.$1 == 'start_session')
          .toList();
      expect(starts, hasLength(2));
      expect(starts[0].$2['request_id'], starts[1].$2['request_id']);
      expect(starts[1].$2['subject'], 'Física');
      expect(starts[1].$2['theme'], 'Lei de Ohm');
      expect(starts[1].$2['goal_id'], 'goal-1');
    },
  );

  testWidgets('simulado não oferece pistas e preserva resposta recusada', (
    tester,
  ) async {
    final repo = FakePlatform()..saveFails = true;
    await render(
      tester,
      PlatformSessionPage(
        repository: repo,
        session: {
          'id': 'session',
          'title': 'Circuitos',
          'mode': 'exam',
          'status': 'active',
          'items': [
            {
              'id': 'item',
              'theme': 'Lei de Ohm',
              'prompt': 'Um circuito tem 12 V e 6 Ω. Qual é a corrente?',
              'answer': '',
            },
          ],
        },
      ),
    );
    expect(find.text('Preciso de uma pista'), findsNothing);
    await tester.enterText(find.byType(TextBox), 'I = 2 A');
    await tester.tap(find.text('Salvar resposta'));
    await tester.pumpAndSettle();
    expect(
      find.text('Sem conexão. Sua resposta não foi enviada.'),
      findsOneWidget,
    );
    expect(find.text('I = 2 A'), findsOneWidget);
    expect(repo.calls.single.$1, 'save_answer');
    expect(repo.calls.single.$2['answer'], 'I = 2 A');
    expect(tester.takeException(), isNull);
  });

  testWidgets('materiais exigem confirmação explícita de autorização', (
    tester,
  ) async {
    PlatformData? saved;
    await render(
      tester,
      Builder(
        builder: (context) => Button(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => PlatformFormDialog(
              title: 'Material',
              fields: const [PlatformField('title', 'Título')],
              requireRights: true,
              onSave: (values) async {
                saved = values;
              },
            ),
          ),
          child: const Text('Abrir'),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox), 'Minha apostila');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(
      find.text('Confirme que você pode usar este material.'),
      findsOneWidget,
    );
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(saved?['rights_confirmed'], 'true');
  });

  testWidgets('plano renderiza agenda retornada pelo servidor', (tester) async {
    final repo = FakePlatform();
    repo.overview['goals'] = [
      {
        'title': 'Prova de circuitos',
        'exam_date': '2026-11-20',
        'minutes_per_day': 15,
        'subjects': ['Física'],
        'weekly_plan': [
          {
            'date': '2026-11-06',
            'minutes': 15,
            'subject': 'Física',
            'theme': 'Lei de Ohm',
            'activity': 'Praticar',
          },
        ],
      },
    ];
    await render(tester, PlatformHubPage(userId: 'user', repository: repo));
    await tester.tap(find.text('Plano'));
    await tester.pumpAndSettle();
    expect(find.text('Prova de circuitos'), findsOneWidget);
    expect(find.textContaining('2026-11-06 · 15 min'), findsOneWidget);
    expect(find.textContaining('Física · Lei de Ohm'), findsOneWidget);
  });

  testWidgets('exportação permite escolher todos os conjuntos', (tester) async {
    final repo = FakePlatform();
    await render(
      tester,
      PlatformExportDialog(
        repository: repo,
        initial: {
          'table': 'profiles',
          'data': [],
          'next_cursor': null,
          'tables': ['profiles', 'attempts'],
        },
      ),
    );
    await tester.tap(find.byType(ComboBox<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('attempts').last);
    await tester.pumpAndSettle();
    expect(repo.calls.last.$2['table'], 'attempts');
    expect(repo.calls.last.$2['cursor'], 0);
  });

  testWidgets('lista atribuída usa seleção explícita do professor', (
    tester,
  ) async {
    final repo = FakePlatform();
    await render(
      tester,
      PlatformAssignmentDialog(
        repository: repo,
        classId: 'class',
        catalog: const [
          {
            'id': 'first',
            'subject': 'Física',
            'theme': 'Ohm',
            'prompt_text': 'Questão um',
          },
          {
            'id': 'second',
            'subject': 'Física',
            'theme': 'Ohm',
            'prompt_text': 'Questão dois',
          },
        ],
      ),
    );
    await tester.enterText(find.byType(TextBox).first, 'Lista de circuitos');
    await tester.tap(find.byType(Checkbox).last);
    await tester.tap(find.text('Atribuir lista'));
    await tester.pumpAndSettle();
    expect(repo.calls.last.$1, 'create_assignment');
    expect(repo.calls.last.$2['catalog_ids'], ['second']);
  });

  testWidgets('espaço de estudos suporta celular estreito e fonte ampliada', (
    tester,
  ) async {
    await render(
      tester,
      PlatformHubPage(userId: 'user', repository: FakePlatform()),
      width: 320,
      scale: 2,
    );
    expect(find.text('Seu espaço de estudos'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Praticar este tema'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });
}
