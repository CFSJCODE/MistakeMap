import 'dart:convert';

import 'package:appmistakemap/ai/analysis_repository.dart';
import 'package:appmistakemap/study/study_repository.dart';
import 'package:appmistakemap/sync/sincronizador.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('mapa recarrega classificação efetiva da view e nunca consulta o diagnóstico bruto', () async {
    final paths = <String>[];
    final client = SupabaseClient(
      'https://decisions-tests.invalid',
      'public-test-key',
      httpClient: MockClient((request) async {
        paths.add(request.url.path);
        final Object rows;
        if (request.url.path == '/rest/v1/attempts') {
          rows = [
            {
              'id': 'attempt-1',
              'exercise_id': 'exercise-1',
              'status': 'awaiting_review',
              'attempted_at': '2026-11-06T12:00:00Z',
              'solution_text': '60',
              'exercises': {
                'subject_id': 'subject-1',
                'prompt_text': 'Calcule a resistência do sensor.',
                'subjects': {'name': 'Eletrônica'},
              },
            },
          ];
        } else if (request.url.path == '/rest/v1/student_attempt_analyses') {
          expect(request.url.queryParameters['user_id'], 'eq.aluno-a');
          rows = [
            {
              'attempt_id': 'attempt-1',
              'subject_id': 'subject-1',
              'analysis': {
                'is_correct': false,
                'correct_answer': '60 Ω',
                'explanation': 'Divida a tensão pela corrente.',
                'errors': [
                  {
                    'id': 'confirmed-1',
                    'status': 'confirmed',
                    'category': 'unidade',
                    'concept': 'Lei de Ohm',
                    'evidence': 'Faltou a unidade.',
                    'confidence': .9,
                  },
                ],
              },
            },
          ];
        } else {
          throw StateError('Consulta inesperada: ${request.url.path}');
        }
        return http.Response(
          jsonEncode(rows),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    final repository = SupabaseAnalysisRepository(
      client,
      sincronizador: Sincronizador(habilitado: false),
    );
    final attempts = await repository.loadAttempts('aluno-a');
    expect(paths, ['/rest/v1/attempts', '/rest/v1/student_attempt_analyses']);
    expect(attempts.single.analysis!.errors.single.category, 'unidade');
    expect(
      attempts.single.analysis!.errors.single.evidence,
      'Faltou a unidade.',
    );
    expect(attempts.single.analysis!.correctAnswer, '60 Ω');
  });

  test('decisão aceita invalida o mapa; recusa não anuncia mudança', () async {
    final before = analysisChanges.value;
    final repository = SupabaseStudyRepository.withTransport((
      userId,
      body,
    ) async {
      if (body['error_event_id'] == 'recusado') {
        throw const StudyFailure('Recusado.');
      }
      return {
        'diagnostic': {'status': 'confirmed'},
      };
    }, store: _MemoryStore());
    await repository.decide('aluno-a', 'confirmado', decision: 'confirmed');
    expect(analysisChanges.value, before + 1);
    await expectLater(
      repository.decide('aluno-a', 'recusado', decision: 'rejected'),
      throwsA(isA<StudyFailure>()),
    );
    expect(analysisChanges.value, before + 1);
    repository.dispose();
  });
}

class _MemoryStore implements StudyStore {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}
