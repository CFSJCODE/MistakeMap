import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'analysis_models.dart';
import 'analysis_repository.dart' show AnalysisFailure;
import '../sync/sincronizador.dart';

/// Resumo teórico gerado a partir dos erros e exercícios da matéria.
class StudySummary {
  final String title;
  final String overview;
  final List<String> keyPoints;
  final List<String> commonMistakes;

  const StudySummary({
    required this.title,
    required this.overview,
    required this.keyPoints,
    required this.commonMistakes,
  });

  factory StudySummary.fromJson(JsonMap value) => StudySummary(
    title: textValue(value['title'], 'Resumo da matéria').trim(),
    overview: textValue(value['overview']).trim(),
    keyPoints: _texts(value['key_points']),
    commonMistakes: _texts(value['common_mistakes']),
  );

  bool get isEmpty =>
      overview.isEmpty && keyPoints.isEmpty && commonMistakes.isEmpty;
}

class Flashcard {
  final String front;
  final String back;
  final String concept;

  const Flashcard({
    required this.front,
    required this.back,
    required this.concept,
  });

  factory Flashcard.fromJson(JsonMap value) => Flashcard(
    front: textValue(value['front']).trim(),
    back: textValue(value['back']).trim(),
    concept: textValue(value['concept']).trim(),
  );
}

/// Questão de múltipla escolha. O gabarito fica no servidor e só volta na
/// correção, depois que o estudante respondeu.
class QuizQuestion {
  final String id;
  final String prompt;
  final List<String> options;
  final String concept;

  const QuizQuestion({
    required this.id,
    required this.prompt,
    required this.options,
    required this.concept,
  });

  factory QuizQuestion.fromJson(JsonMap value) => QuizQuestion(
    id: textValue(value['id']),
    prompt: textValue(value['prompt']).trim(),
    options: _texts(value['options']),
    concept: textValue(value['concept']).trim(),
  );
}

class StudyMaterial {
  final String id;
  final String subjectId;
  final String subjectName;
  final DateTime createdAt;
  final StudySummary summary;
  final List<Flashcard> flashcards;
  final List<QuizQuestion> quiz;

  /// Quantos exercícios e erros do estudante fundamentaram o material.
  final int sourceCount;

  const StudyMaterial({
    required this.id,
    required this.subjectId,
    required this.subjectName,
    required this.createdAt,
    required this.summary,
    required this.flashcards,
    required this.quiz,
    required this.sourceCount,
  });

  factory StudyMaterial.fromJson(JsonMap value, {required String subjectName}) {
    final sources = value['source_count'];
    return StudyMaterial(
      id: textValue(value['id']),
      subjectId: textValue(value['subject_id']),
      subjectName: subjectName,
      createdAt:
          DateTime.tryParse(textValue(value['created_at']))?.toLocal() ??
          DateTime.now(),
      summary: StudySummary.fromJson(jsonMap(value['summary'])),
      flashcards: _maps(value['flashcards'])
          .map(Flashcard.fromJson)
          .where((card) => card.front.isNotEmpty)
          .toList(),
      quiz: _maps(value['quiz'])
          .map(QuizQuestion.fromJson)
          .where((q) => q.id.isNotEmpty && q.options.length >= 2)
          .toList(),
      sourceCount: sources is num ? sources.toInt() : 0,
    );
  }
}

class QuizQuestionResult {
  final String questionId;
  final int? choice;
  final int correctChoice;
  final String explanation;

  const QuizQuestionResult({
    required this.questionId,
    required this.choice,
    required this.correctChoice,
    required this.explanation,
  });

  factory QuizQuestionResult.fromJson(JsonMap value) {
    final choice = value['choice'];
    final correct = value['correct_choice'];
    return QuizQuestionResult(
      questionId: textValue(value['question_id']),
      choice: choice is num ? choice.toInt() : null,
      correctChoice: correct is num ? correct.toInt() : -1,
      explanation: textValue(value['explanation']).trim(),
    );
  }

  bool get isCorrect => choice != null && choice == correctChoice;
}

/// Resultado de uma rodada de quiz corrigida no servidor.
class QuizRoundResult {
  final List<QuizQuestionResult> results;

  const QuizRoundResult(this.results);

  int get total => results.length;
  int get correctCount => results.where((r) => r.isCorrect).length;
  int get incorrectCount => total - correctCount;
  double? get correctPercentage =>
      total == 0 ? null : correctCount * 100 / total;

  /// Conceitos das questões erradas, do mais errado para o menos.
  List<InsightCount> missedConcepts(List<QuizQuestion> quiz) {
    final byId = {for (final q in quiz) q.id: q};
    final missed = <String, Set<String>>{};
    for (final result in results) {
      if (result.isCorrect) continue;
      final concept = byId[result.questionId]?.concept ?? '';
      if (concept.isEmpty) continue;
      (missed[concept] ??= {}).add(result.questionId);
    }
    return [
      for (final entry in missed.entries)
        InsightCount(entry.key, entry.key, entry.value),
    ]..sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : a.label.compareTo(b.label);
    });
  }
}

abstract class StudyMaterialRepository {
  Future<StudyMaterial> generate(String subjectId, String subjectName);
  Future<StudyMaterial> regenerateQuiz(StudyMaterial previous);

  Future<List<StudyMaterial>> loadMaterials(Map<String, String> subjects);

  /// [answers] liga o id de cada questão ao índice escolhido.
  Future<QuizRoundResult> gradeQuiz(
    String materialId,
    Map<String, int> answers,
  );
}

/// Fala com a Edge Function `study-material`; a IA e o gabarito do quiz
/// ficam no servidor.
class SupabaseStudyMaterialRepository implements StudyMaterialRepository {
  final SupabaseClient client;

  SupabaseStudyMaterialRepository(this.client);

  static const _function = 'study-material';

  @override
  Future<StudyMaterial> regenerateQuiz(StudyMaterial previous) async {
    final data = await _invoke({
      'action': 'generate',
      'subject_id': previous.subjectId,
      'previous_material_id': previous.id,
    });
    final material = jsonMap(data['material']);
    if (textValue(material['id']).isEmpty) {
      throw const AnalysisFailure(
        'Não foi possível carregar o novo quiz. Tente novamente.',
      );
    }
    return StudyMaterial.fromJson(material, subjectName: previous.subjectName);
  }

  @override
  Future<StudyMaterial> generate(String subjectId, String subjectName) async {
    final data = await _invoke({'action': 'generate', 'subject_id': subjectId});
    final material = jsonMap(data['material']);
    if (textValue(material['id']).isEmpty) {
      throw const AnalysisFailure(
        'Não foi possível carregar o material gerado. Tente novamente.',
      );
    }
    return StudyMaterial.fromJson(material, subjectName: subjectName);
  }

  @override
  Future<List<StudyMaterial>> loadMaterials(
    Map<String, String> subjects,
  ) async {
    Future<Object?> remoto() => client
        .from('study_materials')
        .select('id,subject_id,created_at,summary,flashcards,quiz,source_count')
        .order('created_at', ascending: false)
        .limit(30);
    // Sem rede, o material já gerado continua disponível pelo cache local.
    final sync = Sincronizador.instancia;
    final usuario = sync.usuarioId;
    final dados = usuario == null
        ? await remoto()
        : await sync.consultar(usuario, 'estudo_materiais', remoto);
    final rows = _maps(dados);
    return [
      for (final row in rows)
        StudyMaterial.fromJson(
          row,
          subjectName: subjects[textValue(row['subject_id'])] ?? 'Matéria',
        ),
    ];
  }

  @override
  Future<QuizRoundResult> gradeQuiz(
    String materialId,
    Map<String, int> answers,
  ) async {
    final data = await _invoke({
      'action': 'grade',
      'material_id': materialId,
      'answers': [
        for (final entry in answers.entries)
          {'question_id': entry.key, 'choice': entry.value},
      ],
    });
    final results = data['results'];
    if (results is! List) {
      throw const AnalysisFailure('Não foi possível corrigir o quiz agora.');
    }
    return QuizRoundResult(
      _maps(results).map(QuizQuestionResult.fromJson).toList(growable: false),
    );
  }

  Future<JsonMap> _invoke(JsonMap body) async {
    // Gerar e corrigir dependem da IA no servidor: sem rede, avisa na hora em
    // vez de deixar o estudante olhando um carregamento.
    final sync = Sincronizador.instancia;
    if (!sync.online.value || sync.semSessao) {
      throw const AnalysisFailure(
        'Gerar e corrigir o material precisa de internet. O material que você '
        'já gerou continua disponível aqui, mesmo offline.',
        network: true,
      );
    }
    try {
      final response = await client.functions
          .invoke(_function, body: body)
          .timeout(const Duration(seconds: 120));
      if (response.status >= 400) {
        throw AnalysisFailure(
          studyFailureMessage(response.status, response.data),
        );
      }
      return jsonMap(response.data);
    } on FunctionException catch (error) {
      throw AnalysisFailure(
        studyFailureMessage(error.status, error.details),
        network: error.status == 0,
      );
    } on TimeoutException {
      throw const AnalysisFailure(
        'A IA está demorando para montar o material. Tente novamente em instantes.',
        network: true,
      );
    }
  }
}

String studyFailureMessage(int status, Object? details) {
  final map = jsonMap(details);
  final server = textValue(map['message']).trim();
  if (server.isNotEmpty) return server;
  return switch (textValue(map['error'])) {
    'no_study_sources' => 'Registre ao menos um exercício nesta matéria para gerar material de estudo.',
    'daily_limit_reached' =>
      'Você atingiu o limite diário de uso da IA. Tente novamente amanhã.',
    _ => switch (status) {
      0 => 'Sem conexão com o serviço de estudo. Verifique a internet.',
      401 || 403 => 'Sua sessão expirou. Entre novamente.',
      404 => 'O material de estudo ainda não está disponível no servidor.',
      429 => 'Muitas solicitações seguidas. Aguarde um pouco e tente de novo.',
      503 => 'A IA ainda não foi configurada no servidor.',
      _ => 'Não foi possível gerar o material de estudo. Tente novamente.',
    },
  };
}

List<String> _texts(Object? value) => value is List
    ? value
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false)
    : const [];

List<JsonMap> _maps(Object? value) =>
    value is List ? value.whereType<Map>().map(jsonMap).toList() : const [];
