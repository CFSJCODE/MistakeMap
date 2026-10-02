import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'analysis_models.dart';

/// Local invalidation only. No student data or keys are cached here.
final analysisChanges = ValueNotifier<int>(0);
void notifyAnalysisChanged() => analysisChanges.value++;

class AnalysisFailure implements Exception {
  final String message;
  const AnalysisFailure(this.message);
  @override
  String toString() => message;
}

String friendlyFailure(Object error) => error is AnalysisFailure
    ? error.message
    : 'Não foi possível concluir. Verifique sua conexão e tente novamente.';

const _imageExtensions = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

/// MIME type read from the file signature (magic numbers), or null when the
/// bytes are not JPEG, PNG or WebP. image_picker_android re-encodes the photo
/// as JPEG/PNG but keeps the original name (e.g. scaled_x.heic), so the
/// extension alone would reject valid photos.
String? imageTypeFromBytes(List<int> bytes) {
  bool hasAt(int offset, List<int> signature) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  if (hasAt(0, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (hasAt(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  // 'RIFF', 4 bytes of container size, then 'WEBP'.
  if (hasAt(0, const [0x52, 0x49, 0x46, 0x46]) &&
      hasAt(8, const [0x57, 0x45, 0x42, 0x50])) {
    return 'image/webp';
  }
  return null;
}

/// Content-Type accepted by upload-url. When [bytes] are given the signature
/// decides; the extension is only a fallback when there is nothing to inspect.
String imageContentType(String filename, [List<int>? bytes]) {
  if (bytes != null && bytes.isNotEmpty) {
    final detected = imageTypeFromBytes(bytes);
    if (detected == null) {
      throw const AnalysisFailure('Use uma imagem JPG, PNG ou WebP.');
    }
    return detected;
  }
  final extension = filename.split('.').last.toLowerCase();
  return switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => throw const AnalysisFailure('Use uma imagem JPG, PNG ou WebP.'),
  };
}

abstract class AnalysisRepository {
  Future<List<AttemptRecord>> loadAttempts(String userId);
  Future<String> createAttempt({
    required String userId,
    required String subject,
    required String prompt,
    required String answer,
    required String difficulty,
    required bool hasImage,
    PracticeExercise? practice,
  });
  Future<void> uploadImage(String attemptId, String filename, Uint8List bytes);
  Future<void> analyze(String attemptId);
  Future<List<PracticeExercise>> generatePractice(
    String subjectId,
    String subjectName,
    int count,
  );
  Future<List<PracticeExercise>> loadPractice(String userId);
}

class SupabaseAnalysisRepository implements AnalysisRepository {
  final Map<String, Future<void>> _inFlightAnalyses = {};
  final SupabaseClient client;
  final http.Client? uploadTransport;
  SupabaseAnalysisRepository(this.client, {this.uploadTransport});

  @override
  Future<List<AttemptRecord>> loadAttempts(String userId) async {
    final rows = <JsonMap>[];
    final analyses = <String, AttemptAnalysis>{};
    const pageSize = 200;
    for (var offset = 0; ; offset += pageSize) {
      final page = await client
          .from('attempts')
          .select(
            'id,exercise_id,solution_text,answer,status,attempted_at,exercises(subject_id,prompt_text,subjects(name))',
          )
          .eq('user_id', userId)
          .order('attempted_at', ascending: false)
          .order('id')
          .range(offset, offset + pageSize - 1);
      rows.addAll(page.map(jsonMap));
      if (page.length < pageSize) break;
    }
    try {
      for (var offset = 0; ; offset += pageSize) {
        final page = await client
            .from('attempt_analyses')
            .select('attempt_id,subject_id,analysis')
            .eq('user_id', userId)
            .order('attempt_id')
            .range(offset, offset + pageSize - 1);
        for (final row in page) {
          final data = jsonMap(row['analysis']);
          data['attempt_id'] = row['attempt_id'];
          data['subject_id'] = row['subject_id'];
          analyses[textValue(row['attempt_id'])] = AttemptAnalysis.fromJson(
            data,
          );
        }
        if (page.length < pageSize) break;
      }
    } on PostgrestException catch (error) {
      if (error.code == '42P01' || error.code == 'PGRST205') {
        throw const AnalysisFailure(
          'A integração de IA ainda não foi ativada no servidor. Os exercícios continuam salvos.',
        );
      }
      rethrow;
    }
    return rows
        .map((row) {
          final exercise = jsonMap(row['exercises']);
          return AttemptRecord(
            id: textValue(row['id']),
            exerciseId: textValue(row['exercise_id']),
            subjectId: textValue(exercise['subject_id']),
            subjectName: textValue(
              jsonMap(exercise['subjects'])['name'],
              'Matéria',
            ),
            prompt: textValue(exercise['prompt_text']),
            answer: textValue(row['answer'], textValue(row['solution_text'])),
            status: textValue(row['status'], 'pending'),
            attemptedAt:
                DateTime.tryParse(textValue(row['attempted_at'])) ??
                DateTime.fromMillisecondsSinceEpoch(0),
            analysis: analyses[row['id']],
          );
        })
        .toList(growable: false);
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
    var exerciseId = practice?.id;
    if (exerciseId == null) {
      final subjects = await client
          .from('subjects')
          .select('id')
          .eq('user_id', userId)
          .eq('name', subject)
          .limit(1);
      final subjectId = subjects.isNotEmpty
          ? subjects.first['id'] as String
          : (await client
                    .from('subjects')
                    .insert({'user_id': userId, 'name': subject})
                    .select('id')
                    .single())['id']
                as String;
      exerciseId =
          (await client
                  .from('exercises')
                  .insert({'subject_id': subjectId, 'prompt_text': prompt})
                  .select('id')
                  .single())['id']
              as String;
    }
    // A generated answer key never enters this payload or the client model.
    final result = await client
        .from('attempts')
        .insert({
          'exercise_id': exerciseId,
          'user_id': userId,
          'answer': answer,
          'solution_text': difficulty.trim().isEmpty
              ? answer
              : '$answer\n\nDificuldade relatada pelo aluno: $difficulty',
          'status': hasImage ? 'uploading' : 'pending',
        })
        .select('id')
        .single();
    notifyAnalysisChanged();
    return result['id'] as String;
  }

  @override
  Future<void> uploadImage(
    String attemptId,
    String filename,
    Uint8List bytes,
  ) async {
    final contentType = imageContentType(filename, bytes);
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
      throw const AnalysisFailure(
        'A imagem deve ter conteúdo e no máximo 8 MB.',
      );
    }
    // A retry after the final status update failed must not create a second asset.
    final existing = await client
        .from('attempt_assets')
        .select('id')
        .eq('attempt_id', attemptId)
        .limit(1);
    if (existing.isEmpty) {
      // upload-url requires the extension to match the Content-Type, and the
      // original file name never leaves the device.
      final data = await _invoke('upload-url', {
        'filename': 'exercicio.${_imageExtensions[contentType]}',
        'content_type': contentType,
        'size_bytes': bytes.length,
      });
      final put = uploadTransport?.put ?? http.put;
      final response = await put(
        Uri.parse(textValue(data['upload_url'])),
        headers: {'Content-Type': textValue(data['content_type'], contentType)},
        body: bytes,
      ).timeout(const Duration(seconds: 90));
      if (response.statusCode >= 400) {
        throw const AnalysisFailure(
          'A foto não foi enviada. Sua tentativa foi salva; tente enviar novamente.',
        );
      }
      await client.from('attempt_assets').insert({
        'attempt_id': attemptId,
        'object_path': data['object_path'],
        'sha256': sha256.convert(bytes).toString(),
      });
    }
    await client
        .from('attempts')
        .update({'status': 'pending'})
        .eq('id', attemptId)
        .eq('status', 'uploading');
  }

  Future<JsonMap> _invoke(String name, JsonMap body) async {
    try {
      final response = await client.functions
          .invoke(name, body: body)
          .timeout(const Duration(seconds: 120));
      if (response.status >= 400) {
        throw AnalysisFailure(_message(name, response.status, response.data));
      }
      return jsonMap(response.data);
    } on FunctionException catch (error) {
      throw AnalysisFailure(_message(name, error.status, error.details));
    } on TimeoutException {
      throw const AnalysisFailure(
        'A análise está demorando. O exercício está salvo; atualize o mapa antes de tentar novamente.',
      );
    }
  }

  String _message(String function, int status, Object? details) {
    final practice = function == 'generate-practice';
    if (details is String &&
        details.trim().isNotEmpty &&
        !details.trim().startsWith('{')) {
      return details.trim();
    }
    final map = jsonMap(details);
    final serverMessage = textValue(map['message']).trim();
    if (serverMessage.isNotEmpty) {
      return serverMessage;
    }
    final code = textValue(map['error']);
    if (code == 'no_error_history') {
      return 'Analise ao menos uma tentativa com erro nesta matéria para gerar exercícios direcionados.';
    }
    if (code == 'daily_limit_reached') {
      return 'Você atingiu o limite diário de análises de IA. Tente novamente amanhã.';
    }
    if (code == 'retry_limit') {
      return 'Esta tentativa atingiu o limite de reanálises. Registre uma nova tentativa após revisar sua resposta.';
    }
    if (code == 'attempt_not_ready') {
      return 'Conclua o envio da foto antes de solicitar a análise.';
    }
    if (code == 'attempt_changed' || code == 'analysis_superseded') {
      return 'A tentativa foi atualizada. Atualize o mapa para consultar o resultado atual.';
    }
    return switch (status) {
      0 =>
        practice
            ? 'Não foi possível acessar o serviço de geração. Verifique a conexão e tente novamente.'
            : 'Não foi possível acessar o serviço de análise. Verifique a conexão e tente novamente.',
      401 || 403 => 'Sua sessão expirou ou você não tem acesso a esta tentativa. Entre novamente.',
      404 => 'A integração de IA ainda não está disponível no servidor.',
      409 => 'Esta tentativa está em processamento. Aguarde e atualize o mapa.',
      429 => 'O limite temporário de análises foi atingido. Aguarde antes de tentar novamente.',
      503 =>
        practice
            ? 'A geração de exercícios ainda não está configurada no servidor.'
            : 'A IA ainda não foi configurada no servidor. Seu exercício está salvo.',
      502 || 504 =>
        practice
            ? 'A geração de exercícios está indisponível no momento. Tente novamente.'
            : 'O serviço de IA está indisponível no momento. Seu exercício está salvo; tente novamente.',
      _ => practice ? 'Não foi possível gerar os exercícios. Tente novamente.' : 'Não foi possível concluir a análise. Seu exercício está salvo; tente novamente.',
    };
  }

  @override
  Future<void> analyze(String attemptId) async {
    final existing = _inFlightAnalyses[attemptId];
    if (existing != null) return existing;
    final operation = _analyzeOnce(attemptId);
    _inFlightAnalyses[attemptId] = operation;
    try {
      await operation;
    } finally {
      _inFlightAnalyses.remove(attemptId);
    }
  }

  Future<void> _analyzeOnce(String attemptId) async {
    await _invoke('analyze-attempt', {'attempt_id': attemptId});
    notifyAnalysisChanged();
  }

  @override
  Future<List<PracticeExercise>> generatePractice(
    String subjectId,
    String subjectName,
    int count,
  ) async {
    if (count < 3 || count > 5) {
      throw const AnalysisFailure('Escolha de 3 a 5 exercícios.');
    }
    // Historic submissions may be marked completed by the old pipeline without
    // an AI analysis. Process them before generating practice so their mistakes
    // can become the concepts used by generate-practice.
    final user = client.auth.currentUser;
    if (user != null) {
      final attempts = await loadAttempts(user.id);
      final unanalysed = attempts
          .where(
            (attempt) =>
                attempt.subjectId == subjectId &&
                (attempt.status == 'completed' ||
                    attempt.status == 'retryable_failed') &&
                attempt.analysis == null,
          )
          .take(5)
          .toList(growable: false);
      Object? firstFailure;
      for (final attempt in unanalysed) {
        try {
          await analyze(attempt.id);
        } catch (error) {
          firstFailure ??= error;
        }
      }
      if (firstFailure != null) {
        final refreshed = await loadAttempts(user.id);
        final hasMistake = refreshed.any(
          (attempt) =>
              attempt.subjectId == subjectId &&
              attempt.analysis?.isCorrect == false,
        );
        if (!hasMistake) {
          throw AnalysisFailure(
            'Não foi possível analisar suas respostas anteriores nesta matéria. '
            '${friendlyFailure(firstFailure)}',
          );
        }
      }
    }
    final result = await _invoke('generate-practice', {
      'subject_id': subjectId,
      'count': count,
    });
    final exercises = result['exercises'];
    if (exercises is! List) {
      throw const AnalysisFailure(
        'Não foi possível carregar os exercícios gerados.',
      );
    }
    return exercises
        .whereType<Map>()
        .map(
          (e) => PracticeExercise.fromJson(
            jsonMap(e),
            subjectId: subjectId,
            subjectName: subjectName,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<PracticeExercise>> loadPractice(String userId) async {
    final exercises = <PracticeExercise>[];
    const pageSize = 200;
    for (var offset = 0; ; offset += pageSize) {
      final page = await client
          .from('exercises')
          .select(
            'id,subject_id,prompt_text,difficulty,subjects!inner(name,user_id)',
          )
          .eq('source', 'ai_practice')
          .eq('subjects.user_id', userId)
          .order('created_at', ascending: false)
          .order('id')
          .range(offset, offset + pageSize - 1);
      for (final item in page) {
        exercises.add(
          PracticeExercise.fromJson(
            item,
            subjectId: textValue(item['subject_id']),
            subjectName: textValue(
              jsonMap(item['subjects'])['name'],
              'Matéria',
            ),
          ),
        );
      }
      if (page.length < pageSize) return exercises;
    }
  }
}
