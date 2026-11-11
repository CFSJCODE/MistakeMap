import 'package:appmistakemap/exercicios/banco_questoes.dart';
import 'package:appmistakemap/platform/platform_hub.dart';
import 'package:appmistakemap/platform/platform_repository.dart';
import 'package:appmistakemap/teacher/assignment_result_page.dart';
import 'package:appmistakemap/teacher/class_map_models.dart';
import 'package:appmistakemap/teacher/class_map_page.dart';
import 'package:fluent_ui/fluent_ui.dart' show ValueKey;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'platform_study_test.dart' show render;

PlatformData concept(String name, int students, int questions) => {
  'concept_key': name.toLowerCase(),
  'concept': name,
  'subject': 'Eletrônica',
  'students': students,
  'errors': students * 2,
  'by_type': {'conceito': 1, 'calculo': students, 'unidade': students - 1},
  'weekly': [1, 2, 3, 5],
  'main_error_type': 'calculo',
  'questions_available': questions,
};

final eligibleMap = <String, dynamic>{
  'eligible': true,
  'members': 8,
  'students_with_data': 6,
  'min_students': 5,
  'error_types': [
    'conceito',
    'calculo',
    'procedimento',
    'interpretacao',
    'sinal',
    'unidade',
    'outro',
  ],
  'grid': [concept('Lei de Ohm', 5, 3), concept('Controle PID', 2, 0)],
  'top_concepts': [concept('Lei de Ohm', 5, 3), concept('Controle PID', 2, 0)],
  'trend': [
    for (final (i, e) in [3, 2, 4, 6].indexed)
      {'weeks_ago': 3 - i, 'errors': e, 'active_students': 5},
  ],
  'privacy': 'Agregado sem nomes.',
  'message': null,
};

class FakeTeacher extends PlatformRepository {
  FakeTeacher({this.map, this.result, this.overview});
  final calls = <(String, PlatformData)>[];
  PlatformData? map;
  PlatformData? result;
  PlatformData? overview;

  @override
  Future<PlatformData> execute(
    String action, [
    PlatformData input = const {},
  ]) async {
    calls.add((action, Map.of(input)));
    return switch (action) {
      'class_map' => map ?? eligibleMap,
      'create_concept_assignment' => {
        'assignment': {'id': 'a1'},
        'questions': 3,
      },
      'assignment_result' => result!,
      'overview' => overview!,
      _ => {'exercises': <PlatformData>[]},
    };
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('modelo do mapa lê grade, tendência e variação da semana', () {
    final map = ClassMap.fromJson(eligibleMap);
    expect(map.eligible, isTrue);
    expect(map.grid.first.byType['calculo'], 5);
    expect(map.maxCell, 5);
    expect(map.topConcepts.first.lastWeekChange, 2);
    expect(map.topConcepts.last.canTrain, isFalse);
    expect(map.trend.last.label, 'Esta semana');
  });

  test('tarefa segue a ordem do professor e ignora questão removida', () {
    Questao q(String id) => Questao.deJson({
      'id': id,
      'kind': 'numerica',
      'subject': 'Eletrônica',
      'topic': 'Circuitos',
      'theme': 'Lei de Ohm',
      'difficulty': 'facil',
      'prompt_text': 'Qual a corrente no motor?',
    })!;
    final banco = [q('a'), q('b'), q('c')];
    expect(questoesDaTarefa(banco, ['c', 'x', 'a']).map((q) => q.id), [
      'c',
      'a',
    ]);
  });

  testWidgets('mapa abaixo de 5 alunos explica a regra e não mostra grade', (
    tester,
  ) async {
    final repo = FakeTeacher(
      map: {
        'eligible': false,
        'members': 3,
        'students_with_data': 3,
        'grid': [],
        'top_concepts': [],
        'trend': [],
        'message': 'O mapa da turma aparece quando 5 alunos ou mais estudarem.',
        'privacy': 'Agregado sem nomes.',
      },
    );
    await render(
      tester,
      ClassMapPage(repository: repo, classId: 'c1', classTitle: 'Robótica 1A'),
    );
    expect(find.text('O mapa ainda não pode aparecer'), findsOneWidget);
    expect(find.text('Treinar este conceito'), findsNothing);
    expect(find.text('Conceito × tipo de erro'), findsNothing);
  });

  testWidgets('"Treinar este conceito" cria a tarefa do conceito', (
    tester,
  ) async {
    final repo = FakeTeacher();
    await render(
      tester,
      ClassMapPage(repository: repo, classId: 'c1', classTitle: 'Robótica 1A'),
      width: 1280,
    );
    expect(find.text('Conceitos que mais travam'), findsOneWidget);
    expect(find.text('Conceito × tipo de erro'), findsOneWidget);
    expect(find.text('Tendência em 4 semanas'), findsOneWidget);
    expect(
      find.text('Ainda sem questões no banco para este conceito'),
      findsOneWidget,
    );
    await tester.tap(find.text('Treinar este conceito').first);
    await tester.pumpAndSettle();
    final call = repo.calls.lastWhere(
      (c) => c.$1 == 'create_concept_assignment',
    );
    expect(call.$2, {'class_id': 'c1', 'concept': 'Lei de Ohm'});
    expect(find.textContaining('Treinar: Lei de Ohm'), findsOneWidget);
  });

  testWidgets('mapa cabe no celular estreito', (tester) async {
    await render(
      tester,
      ClassMapPage(
        repository: FakeTeacher(),
        classId: 'c1',
        classTitle: 'Robótica 1A',
      ),
      width: 360,
      scale: 1.3,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('resultado mostra quem fez, acerto e copia CSV', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    final repo = FakeTeacher(
      result: {
        'assignment': {'id': 'a1', 'title': 'Treinar: Lei de Ohm'},
        'total_questions': 2,
        'members': 6,
        'respondents': 5,
        'completed': 4,
        'eligible': true,
        'participants': [
          {
            'label': 'Participante 1',
            'status': 'completed',
            'answered': 2,
            'correct': 1,
          },
          {
            'label': 'Participante 2',
            'status': 'not_started',
            'answered': 0,
            'correct': null,
          },
        ],
        'questions': [
          {
            'position': 1,
            'prompt': 'Qual resistor limita o LED do robô?',
            'theme': 'Lei de Ohm',
            'responses': 5,
            'correct': 2,
            'pending': 0,
            'accuracy': 40,
          },
          {
            'position': 2,
            'prompt': 'Explique por que o LED queima.',
            'theme': 'Lei de Ohm',
            'responses': 2,
            'correct': null,
            'pending': null,
            'accuracy': null,
          },
        ],
        'common_errors': [
          {'error_type': 'unidade', 'concept': 'Lei de Ohm', 'errors': 3},
        ],
        'privacy': 'Acerto individual só de quem autorizou.',
        'csv': '"Tarefa";"Treinar: Lei de Ohm"',
      },
    );
    await render(
      tester,
      AssignmentResultPage(repository: repo, assignmentId: 'a1', title: 'T'),
    );
    expect(find.text('Treinar: Lei de Ohm'), findsOneWidget);
    expect(
      find.textContaining('Não começou', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('acerto não compartilhado', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('40% de acerto'), findsOneWidget);
    expect(
      find.textContaining('o acerto aparece com 5 respostas ou mais'),
      findsOneWidget,
    );
    expect(find.text('Unidade em Lei de Ohm · 3 vezes'), findsOneWidget);
    await tester.tap(find.text('Copiar CSV'));
    await tester.pumpAndSettle();
    expect(copied, '"Tarefa";"Treinar: Lei de Ohm"');
  });

  testWidgets('aluno responde a tarefa do banco; professor vê o resultado', (
    tester,
  ) async {
    PlatformData overview(bool teacher) => {
      'classes': [
        {'id': 'c1', 'title': 'Robótica 1A', 'is_teacher': teacher},
      ],
      'assignments': [
        {
          'id': 'a1',
          'class_id': 'c1',
          'title': 'Treinar: Lei de Ohm',
          'catalog_ids': [],
          'question_ids': ['q1', 'q2'],
        },
      ],
      'entitlements': {'teacher_enabled': teacher},
    };
    final opened = <(String, List<String>)>[];
    await render(
      tester,
      PlatformHubPage(
        userId: 'aluno',
        repository: FakeTeacher(overview: overview(false)),
        onOpenQuestionAssignment: (_, id, ids) async {
          opened.add((id, ids));
          return null;
        },
      ),
    );
    await tester.tap(find.text('Turmas'));
    await tester.pumpAndSettle();
    expect(find.text('Responder lista'), findsNothing);
    await tester.tap(find.text('Responder tarefa'));
    await tester.pumpAndSettle();
    expect(opened.single.$1, 'a1');
    expect(opened.single.$2, ['q1', 'q2']);

    final teacherRepo = FakeTeacher(overview: overview(true));
    await render(
      tester,
      PlatformHubPage(
        key: const ValueKey('prof'),
        userId: 'prof',
        repository: teacherRepo,
      ),
    );
    await tester.tap(find.text('Turmas'));
    await tester.pumpAndSettle();
    expect(find.text('Mapa da turma'), findsOneWidget);
    expect(find.text('Ver resultado'), findsOneWidget);
    expect(find.text('Responder tarefa'), findsNothing);
  });
}
