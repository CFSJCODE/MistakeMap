import 'dart:convert';
import 'dart:math' as math;

typedef JsonMap = Map<String, dynamic>;

JsonMap jsonMap(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
  }
  return <String, dynamic>{};
}

String textValue(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

const categoryLabels = <String, String>{
  'calculo': 'Cálculo',
  'conceito': 'Conceito',
  'sinal': 'Sinal',
  'interpretacao': 'Interpretação',
  'procedimento': 'Procedimento',
  'unidade': 'Unidade',
  'outro': 'Outro',
};

class IdentifiedError {
  final String category;
  final String concept;
  final String evidence;
  final double confidence;

  const IdentifiedError({
    required this.category,
    required this.concept,
    required this.evidence,
    required this.confidence,
  });

  factory IdentifiedError.fromJson(JsonMap value) {
    final score = value['confidence'];
    return IdentifiedError(
      category: textValue(value['category'], 'outro'),
      concept: textValue(value['concept'], 'Sem conceito informado'),
      evidence: textValue(value['evidence']),
      confidence: score is num && score.isFinite
          ? score.toDouble().clamp(0, 1)
          : 0,
    );
  }

  String get label => categoryLabels[category] ?? 'Outro';
}

class AttemptAnalysis {
  final String attemptId;
  final String subjectId;
  final bool? isCorrect;
  final String correctAnswer;
  final String explanation;
  final String transcribedPrompt;
  final String transcribedAnswer;
  final List<IdentifiedError> errors;
  final List<String> concepts;

  const AttemptAnalysis({
    required this.attemptId,
    required this.subjectId,
    required this.isCorrect,
    required this.correctAnswer,
    required this.explanation,
    this.transcribedPrompt = '',
    this.transcribedAnswer = '',
    this.errors = const [],
    this.concepts = const [],
  });

  factory AttemptAnalysis.fromJson(JsonMap value) => AttemptAnalysis(
    attemptId: textValue(value['attempt_id']),
    subjectId: textValue(value['subject_id']),
    isCorrect: value['is_correct'] is bool ? value['is_correct'] as bool : null,
    correctAnswer: textValue(value['correct_answer']),
    explanation: textValue(value['explanation']),
    transcribedPrompt: textValue(value['transcribed_prompt']),
    transcribedAnswer: textValue(value['transcribed_answer']),
    errors: (value['errors'] is List ? value['errors'] as List : const [])
        .whereType<Map>()
        .map((e) => IdentifiedError.fromJson(jsonMap(e)))
        .toList(growable: false),
    concepts: (value['concepts'] is List ? value['concepts'] as List : const [])
        .whereType<String>()
        .where((e) => e.trim().isNotEmpty)
        .toSet()
        .toList(growable: false),
  );
}

class AttemptRecord {
  final String id;
  final String exerciseId;
  final String subjectId;
  final String subjectName;
  final String prompt;
  final String answer;
  final String status;
  final DateTime attemptedAt;
  final AttemptAnalysis? analysis;

  const AttemptRecord({
    required this.id,
    required this.exerciseId,
    required this.subjectId,
    required this.subjectName,
    required this.prompt,
    required this.answer,
    required this.status,
    required this.attemptedAt,
    this.analysis,
  });

  bool get needsReview =>
      analysis?.isCorrect == false ||
      analysis?.isCorrect == null ||
      status == 'awaiting_review';

  String get statusLabel => switch (status) {
    'uploading' => 'Foto pendente de envio',
    'pending' => 'Aguardando análise',
    'queued' || 'processing' => 'Análise em andamento',
    'awaiting_review' => 'Confira os dados da análise',
    'completed' =>
      analysis == null
          ? 'Análise IA ainda não disponível'
          : 'Análise disponível',
    'retryable_failed' => 'Não foi possível analisar; tente novamente',
    'dead_letter' => 'Análise interrompida',
    'cancelled' => 'Tentativa cancelada',
    _ => 'Aguardando análise',
  };
}

/// Groups the `attempts_status_check` states shown by the Home counters and
/// the concept map, so both screens count the same attempt the same way.
enum AttemptStatusGroup { pending, review, failed, completed, none }

/// `completed` only means the analysis finished, not that the answer was
/// right. Cancelled, missing or unknown states count as no attempt.
AttemptStatusGroup attemptStatusGroup(String? status) => switch (status) {
  'uploading' ||
  'pending' ||
  'queued' ||
  'processing' => AttemptStatusGroup.pending,
  'awaiting_review' => AttemptStatusGroup.review,
  // retryable_failed: o backend reprocessa automaticamente na próxima rodada
  // do pg_cron — do ponto de vista do aluno ainda está "em andamento".
  // dead_letter: falha definitiva, sem nova tentativa automática.
  'retryable_failed' => AttemptStatusGroup.pending,
  'dead_letter' => AttemptStatusGroup.failed,
  'completed' => AttemptStatusGroup.completed,
  _ => AttemptStatusGroup.none,
};

class PracticeExercise {
  final String id;
  final String subjectId;
  final String subjectName;
  final String prompt;
  final String difficulty;
  final String focusConcept;

  const PracticeExercise({
    required this.id,
    required this.subjectId,
    required this.subjectName,
    required this.prompt,
    required this.difficulty,
    required this.focusConcept,
  });

  factory PracticeExercise.fromJson(
    JsonMap json, {
    required String subjectId,
    required String subjectName,
  }) => PracticeExercise(
    id: textValue(json['id']),
    subjectId: subjectId,
    subjectName: subjectName,
    prompt: textValue(json['prompt_text']),
    difficulty: textValue(json['difficulty']),
    focusConcept: textValue(json['focus_concept']),
  );
}

class InsightCount {
  final String key;
  final String label;
  final Set<String> attemptIds;
  int get count => attemptIds.length;

  InsightCount(this.key, this.label, this.attemptIds);
}

class GraphNode {
  final String id;
  final String label;
  final String kind;
  final Set<String> attemptIds;

  GraphNode(this.id, this.label, this.kind, this.attemptIds);
}

class GraphEdge {
  final String from;
  final String to;
  final Set<String> attemptIds;

  GraphEdge(this.from, this.to, this.attemptIds);
}

class ErrorInsights {
  final List<AttemptRecord> attempts;
  final List<InsightCount> categories;
  final List<InsightCount> subjects;
  final List<InsightCount> concepts;
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  ErrorInsights._(
    this.attempts,
    this.categories,
    this.subjects,
    this.concepts,
    this.nodes,
    this.edges,
  );

  int get analyzedCount => attempts.where((a) => a.analysis != null).length;
  int get errorsCount =>
      attempts.where((a) => a.analysis?.errors.isNotEmpty ?? false).length;

  /// Frequencies count distinct attempts, never repeated model labels or retries.
  /// Graph edges mean observed co-occurrence, not inferred prerequisites.
  factory ErrorInsights.fromAttempts(Iterable<AttemptRecord> input) {
    final unique = <String, AttemptRecord>{};
    for (final attempt in input) {
      final previous = unique[attempt.id];
      if (previous == null || attempt.analysis != null) {
        unique[attempt.id] = attempt;
      }
    }
    final attempts = unique.values.toList()
      ..sort((a, b) => b.attemptedAt.compareTo(a.attemptedAt));
    final categories = <String, InsightCount>{};
    final subjects = <String, InsightCount>{};
    final concepts = <String, InsightCount>{};
    final nodes = <String, GraphNode>{};
    final edges = <String, GraphEdge>{};
    void addCount(
      Map<String, InsightCount> map,
      String key,
      String label,
      String id,
    ) {
      (map[key] ??= InsightCount(key, label, {})).attemptIds.add(id);
    }

    void addNode(String key, String label, String kind, String id) {
      (nodes[key] ??= GraphNode(key, label, kind, {})).attemptIds.add(id);
    }

    void addEdge(String from, String to, String id) {
      (edges['$from\u0000$to'] ??= GraphEdge(from, to, {})).attemptIds.add(id);
    }

    for (final attempt in attempts) {
      for (final error in attempt.analysis?.errors ?? <IdentifiedError>[]) {
        final normalized = error.concept.trim().toLowerCase();
        if (normalized.isEmpty) continue;
        final conceptKey = '${attempt.subjectId}:$normalized';
        final subjectNode = 'subject:${attempt.subjectId}';
        final conceptNode = 'concept:$conceptKey';
        final categoryNode = 'category:${error.category}';
        addCount(categories, error.category, error.label, attempt.id);
        addCount(subjects, attempt.subjectId, attempt.subjectName, attempt.id);
        addCount(concepts, conceptKey, error.concept.trim(), attempt.id);
        addNode(subjectNode, attempt.subjectName, 'Matéria', attempt.id);
        addNode(conceptNode, error.concept.trim(), 'Conceito', attempt.id);
        addNode(categoryNode, error.label, 'Tipo de erro', attempt.id);
        addEdge(subjectNode, conceptNode, attempt.id);
        addEdge(conceptNode, categoryNode, attempt.id);
      }
    }
    List<InsightCount> sorted(Map<String, InsightCount> map) =>
        map.values.toList()..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          return byCount == 0 ? a.label.compareTo(b.label) : byCount;
        });
    return ErrorInsights._(
      attempts,
      sorted(categories),
      sorted(subjects),
      sorted(concepts),
      nodes.values.toList(),
      edges.values.toList(),
    );
  }

  List<AttemptRecord> evidence(Set<String> ids) =>
      attempts.where((a) => ids.contains(a.id)).toList(growable: false);

  double cloudFontSize(int count) {
    if (concepts.isEmpty) return 16;
    final maxCount = math.max(1, concepts.first.count);
    return 16 + 16 * math.sqrt(count / maxCount);
  }
}
