typedef StudyJson = Map<String, dynamic>;

StudyJson studyMap(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : <String, dynamic>{};

List<StudyJson> studyRows(Object? value) =>
    value is List ? value.map(studyMap).toList() : const [];

int _number(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

class StudyProfile {
  const StudyProfile({
    required this.stage,
    required this.dailyMinutes,
    required this.goal,
    this.timezone = 'America/Sao_Paulo',
    this.subjectIds = const [],
    this.examDate,
    this.remindersEnabled = false,
  });

  factory StudyProfile.fromJson(StudyJson json) => StudyProfile(
    stage: json['stage'] as String? ?? 'autodidata',
    dailyMinutes: _number(json['daily_minutes'], 15),
    goal: json['goal'] as String? ?? '',
    timezone: json['timezone'] as String? ?? 'America/Sao_Paulo',
    subjectIds: (json['subject_ids'] as List? ?? const []).cast<String>(),
    examDate: json['exam_date'] as String?,
    remindersEnabled: json['reminders_enabled'] == true,
  );

  final String stage;
  final int dailyMinutes;
  final String goal;
  final String timezone;
  final List<String> subjectIds;
  final String? examDate;
  final bool remindersEnabled;

  StudyJson toJson() => {
    'stage': stage,
    'daily_minutes': dailyMinutes,
    'goal': goal,
    'timezone': timezone,
    'subject_ids': subjectIds,
    'exam_date': examDate,
    'reminders_enabled': remindersEnabled,
  };
}

class StudySubject {
  const StudySubject(this.id, this.name);
  final String id;
  final String name;
}

class StudyProfileData {
  const StudyProfileData({this.profile, this.subjects = const []});

  factory StudyProfileData.fromJson(StudyJson json) => StudyProfileData(
    profile: json['profile'] is Map
        ? StudyProfile.fromJson(studyMap(json['profile']))
        : null,
    subjects: [
      for (final row in studyRows(json['subjects']))
        StudySubject(row['id'] as String, row['name'] as String? ?? 'Matéria'),
    ],
  );

  final StudyProfile? profile;
  final List<StudySubject> subjects;
}

class StudyDashboard {
  const StudyDashboard({
    this.profile,
    this.dueCount = 0,
    this.pendingDiagnostics = 0,
    this.estimatedMinutes = 0,
    this.reviewedToday = 0,
    this.activeSessionId,
    this.progress = const StudyProgress(),
    this.items = const [],
  });

  factory StudyDashboard.fromJson(StudyJson json) => StudyDashboard(
    profile: json['profile'] is Map
        ? StudyProfile.fromJson(studyMap(json['profile']))
        : null,
    dueCount: _number(json['due_count']),
    pendingDiagnostics: _number(json['pending_diagnostics']),
    estimatedMinutes: _number(json['estimated_minutes']),
    reviewedToday: _number(json['reviewed_today']),
    activeSessionId: json['active_session_id'] as String?,
    progress: StudyProgress.fromJson(studyMap(json['progress'])),
    items: studyRows(json['items']).map(StudyReviewItem.fromJson).toList(),
  );

  final StudyProfile? profile;
  final int dueCount;
  final int pendingDiagnostics;
  final int estimatedMinutes;
  final int reviewedToday;
  final String? activeSessionId;
  final StudyProgress progress;
  final List<StudyReviewItem> items;
}

class StudyProgress {
  const StudyProgress({this.reviews = 0, this.recallRate, this.periodDays = 7});

  factory StudyProgress.fromJson(StudyJson json) => StudyProgress(
    reviews: _number(json['reviews']),
    recallRate: (json['recall_rate'] as num?)?.toDouble(),
    periodDays: _number(json['period_days'], 7),
  );

  final int reviews;
  final double? recallRate;
  final int periodDays;
}

class StudyReviewItem {
  const StudyReviewItem({
    required this.id,
    required this.subjectName,
    required this.conceptName,
    required this.prompt,
    this.subjectId = '',
    this.category = '',
    this.evidence = '',
    this.reason = '',
    this.answered = false,
  });

  factory StudyReviewItem.fromJson(StudyJson json) => StudyReviewItem(
    id: json['id'] as String,
    subjectName: json['subject_name'] as String? ?? 'Matéria',
    conceptName: json['concept_name'] as String? ?? 'Revisão',
    prompt: json['prompt_text'] as String? ?? '',
    subjectId: json['subject_id'] as String? ?? '',
    category: json['category'] as String? ?? '',
    evidence: json['evidence'] as String? ?? '',
    reason: json['reason'] as String? ?? '',
    answered: json['answered'] == true,
  );

  final String id;
  final String subjectId;
  final String subjectName;
  final String conceptName;
  final String category;
  final String prompt;
  final String evidence;
  final String reason;
  final bool answered;
}

class StudySession {
  const StudySession({
    required this.id,
    required this.status,
    required this.items,
  });

  factory StudySession.fromJson(StudyJson json) => StudySession(
    id: json['id'] as String,
    status: json['status'] as String? ?? 'active',
    items: studyRows(json['items']).map(StudyReviewItem.fromJson).toList(),
  );

  final String id;
  final String status;
  final List<StudyReviewItem> items;
  List<StudyReviewItem> get remaining =>
      items.where((item) => !item.answered).toList();
}

class StudyAnswerResult {
  const StudyAnswerResult({
    required this.session,
    this.reference,
    this.nextDueAt,
    this.queued = false,
  });

  factory StudyAnswerResult.fromJson(StudyJson json) {
    final feedback = studyMap(json['feedback']);
    return StudyAnswerResult(
      session: StudySession.fromJson(studyMap(json['session'])),
      reference: feedback['reference_text'] as String?,
      nextDueAt: DateTime.tryParse(feedback['next_due_at'] as String? ?? ''),
    );
  }

  final StudySession session;
  final String? reference;
  final DateTime? nextDueAt;
  final bool queued;
}

class StudyDiagnostic {
  const StudyDiagnostic({
    required this.id,
    required this.subjectName,
    required this.conceptName,
    required this.category,
    required this.evidence,
    this.prompt = '',
    this.status = 'pending',
    this.importance = 1,
  });

  factory StudyDiagnostic.fromJson(StudyJson json) => StudyDiagnostic(
    id: json['id'] as String,
    subjectName: json['subject_name'] as String? ?? 'Matéria',
    conceptName: json['concept_name'] as String? ?? 'Conceito',
    category: json['category'] as String? ?? '',
    evidence: json['evidence'] as String? ?? '',
    prompt: json['prompt_text'] as String? ?? '',
    status: json['status'] as String? ?? 'pending',
    importance: (json['importance'] as num?)?.toDouble() ?? 1,
  );

  final String id;
  final String subjectName;
  final String conceptName;
  final String category;
  final String evidence;
  final String prompt;
  final String status;
  final double importance;
}

class StudySyncState {
  const StudySyncState({
    this.offline = false,
    this.pending = 0,
    this.rejected = 0,
    this.message,
    this.updatedAt,
  });
  final bool offline;
  final int pending;
  final int rejected;
  final String? message;
  final DateTime? updatedAt;
}

class StudyPendingAnswer {
  const StudyPendingAnswer({
    required this.eventId,
    required this.itemId,
    required this.sessionId,
    this.failure,
  });
  final String eventId;
  final String itemId;
  final String sessionId;
  final String? failure;
}

class StudyFailure implements Exception {
  const StudyFailure(this.message, {this.network = false, this.code});
  final String message;
  final bool network;
  final String? code;
  @override
  String toString() => message;
}
