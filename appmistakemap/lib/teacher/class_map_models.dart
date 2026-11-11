import '../platform/platform_repository.dart';

/// Rótulos dos tipos de erro, na ordem em que o servidor manda a grade.
const classMapErrorLabels = <String, String>{
  'conceito': 'Conceito',
  'calculo': 'Cálculo',
  'procedimento': 'Procedimento',
  'interpretacao': 'Interpretação',
  'sinal': 'Sinal',
  'unidade': 'Unidade',
  'outro': 'Outro',
};

String classMapErrorLabel(String type) => classMapErrorLabels[type] ?? 'Outro';

int _int(Object? value) => value is num ? value.toInt() : 0;
int? _intOrNull(Object? value) => value is num ? value.toInt() : null;

/// Uma linha da grade: um conceito, com os erros por tipo e por semana.
class ClassMapConcept {
  const ClassMapConcept({
    required this.concept,
    required this.subject,
    required this.students,
    required this.errors,
    required this.byType,
    required this.weekly,
    required this.mainErrorType,
    required this.questionsAvailable,
  });

  final String concept;
  final String subject;
  final int students;
  final int errors;
  final Map<String, int> byType;

  /// Da semana mais antiga (índice 0) para a atual.
  final List<int> weekly;
  final String mainErrorType;
  final int questionsAvailable;

  bool get canTrain => questionsAvailable > 0;

  /// Diferença entre a semana atual e a anterior.
  int get lastWeekChange =>
      weekly.length < 2 ? 0 : weekly.last - weekly[weekly.length - 2];

  factory ClassMapConcept.fromJson(PlatformData json) {
    final types = platformMap(json['by_type']);
    return ClassMapConcept(
      concept: '${json['concept'] ?? ''}',
      subject: '${json['subject'] ?? ''}',
      students: _int(json['students']),
      errors: _int(json['errors']),
      byType: {for (final e in types.entries) e.key: _int(e.value)},
      weekly: [
        for (final v in (json['weekly'] is List ? json['weekly'] as List : []))
          _int(v),
      ],
      mainErrorType: '${json['main_error_type'] ?? 'outro'}',
      questionsAvailable: _int(json['questions_available']),
    );
  }
}

class ClassMapWeek {
  const ClassMapWeek(this.weeksAgo, this.errors, this.activeStudents);

  final int weeksAgo;
  final int errors;
  final int activeStudents;

  String get label => weeksAgo == 0
      ? 'Esta semana'
      : weeksAgo == 1
      ? 'Semana passada'
      : 'Há $weeksAgo semanas';
}

/// Mapa agregado da turma, sem nomes. Só vem preenchido com 5 alunos ou mais.
class ClassMap {
  const ClassMap({
    required this.eligible,
    required this.members,
    required this.studentsWithData,
    required this.minStudents,
    required this.errorTypes,
    required this.grid,
    required this.topConcepts,
    required this.trend,
    required this.message,
    required this.privacy,
  });

  final bool eligible;
  final int members;
  final int studentsWithData;
  final int minStudents;
  final List<String> errorTypes;
  final List<ClassMapConcept> grid;
  final List<ClassMapConcept> topConcepts;

  /// Da semana mais antiga para a atual.
  final List<ClassMapWeek> trend;
  final String message;
  final String privacy;

  int get maxCell =>
      grid.fold(0, (m, c) => c.byType.values.fold(m, (a, b) => b > a ? b : a));

  factory ClassMap.fromJson(PlatformData json) {
    final types = [
      for (final t
          in (json['error_types'] is List ? json['error_types'] as List : []))
        '$t',
    ];
    return ClassMap(
      eligible: json['eligible'] == true,
      members: _int(json['members']),
      studentsWithData: _int(json['students_with_data']),
      minStudents: _int(json['min_students']) == 0
          ? 5
          : _int(json['min_students']),
      errorTypes: types.isEmpty ? classMapErrorLabels.keys.toList() : types,
      grid: platformRows(json['grid']).map(ClassMapConcept.fromJson).toList(),
      topConcepts: platformRows(json['top_concepts'])
          .map(ClassMapConcept.fromJson)
          .toList(),
      trend: [
        for (final w in platformRows(json['trend']))
          ClassMapWeek(
            _int(w['weeks_ago']),
            _int(w['errors']),
            _int(w['active_students']),
          ),
      ],
      message: '${json['message'] ?? ''}',
      privacy: '${json['privacy'] ?? ''}',
    );
  }
}

const assignmentStatusLabels = <String, String>{
  'completed': 'Concluiu',
  'in_progress': 'Em andamento',
  'not_started': 'Não começou',
};

class AssignmentParticipant {
  const AssignmentParticipant({
    required this.label,
    required this.status,
    required this.answered,
    required this.correct,
  });

  final String label;
  final String status;
  final int answered;

  /// Nulo quando o aluno não autorizou compartilhar o progresso.
  final int? correct;
}

class AssignmentQuestion {
  const AssignmentQuestion({
    required this.position,
    required this.prompt,
    required this.theme,
    required this.responses,
    required this.correct,
    required this.pending,
    required this.accuracy,
  });

  final int position;
  final String prompt;
  final String theme;
  final int responses;
  final int? correct;
  final int? pending;

  /// Nulo com menos de 5 respostas ou sem nenhuma corrigida.
  final int? accuracy;
}

class AssignmentError {
  const AssignmentError(this.type, this.concept, this.count);

  final String type;
  final String concept;
  final int count;
}

/// Resultado de uma tarefa da turma: quem fez, acerto por questão e erros.
class AssignmentResult {
  const AssignmentResult({
    required this.title,
    required this.totalQuestions,
    required this.members,
    required this.respondents,
    required this.completed,
    required this.eligible,
    required this.participants,
    required this.questions,
    required this.commonErrors,
    required this.privacy,
    required this.csv,
  });

  final String title;
  final int totalQuestions;
  final int members;
  final int respondents;
  final int completed;
  final bool eligible;
  final List<AssignmentParticipant> participants;
  final List<AssignmentQuestion> questions;
  final List<AssignmentError> commonErrors;
  final String privacy;
  final String csv;

  factory AssignmentResult.fromJson(PlatformData json) => AssignmentResult(
    title: '${platformMap(json['assignment'])['title'] ?? 'Tarefa'}',
    totalQuestions: _int(json['total_questions']),
    members: _int(json['members']),
    respondents: _int(json['respondents']),
    completed: _int(json['completed']),
    eligible: json['eligible'] == true,
    participants: [
      for (final p in platformRows(json['participants']))
        AssignmentParticipant(
          label: '${p['label'] ?? 'Participante'}',
          status: '${p['status'] ?? 'not_started'}',
          answered: _int(p['answered']),
          correct: _intOrNull(p['correct']),
        ),
    ],
    questions: [
      for (final q in platformRows(json['questions']))
        AssignmentQuestion(
          position: _int(q['position']),
          prompt: '${q['prompt'] ?? ''}',
          theme: '${q['theme'] ?? ''}',
          responses: _int(q['responses']),
          correct: _intOrNull(q['correct']),
          pending: _intOrNull(q['pending']),
          accuracy: _intOrNull(q['accuracy']),
        ),
    ],
    commonErrors: [
      for (final e in platformRows(json['common_errors']))
        AssignmentError(
          '${e['error_type'] ?? 'outro'}',
          '${e['concept'] ?? ''}',
          _int(e['errors']),
        ),
    ],
    privacy: '${json['privacy'] ?? ''}',
    csv: '${json['csv'] ?? ''}',
  );
}
