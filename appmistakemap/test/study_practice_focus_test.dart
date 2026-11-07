import 'dart:convert';

import 'package:appmistakemap/ai/analysis_repository.dart';
import 'package:appmistakemap/sync/sincronizador.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('recarregar prática preserva conceito e inclui rodadas do catálogo sem ler gabarito', () async {
    final requests = <Uri>[];
    final client = SupabaseClient(
      'https://practice-tests.invalid',
      'public-test-key',
      httpClient: MockClient((request) async {
        requests.add(request.url);
        expect(request.url.path, '/rest/v1/exercises');
        return http.Response(
          jsonEncode([
            {
              'id': 'ai-1',
              'subject_id': 'subject-1',
              'prompt_text':
                  'Um robô percorre 12 m em 3 s. Calcule a velocidade.',
              'difficulty': 'facil',
              'focus_concept': 'Velocidade média',
              'subjects': {'name': 'Física', 'user_id': 'aluno-a'},
            },
            {
              'id': 'catalog-1',
              'subject_id': 'subject-2',
              'prompt_text': 'Um sensor recebe 12 V e consome 0,2 A. Calcule a resistência.',
              'difficulty': 'media',
              'focus_concept': 'Lei de Ohm',
              'subjects': {'name': 'Eletrônica', 'user_id': 'aluno-a'},
            },
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    final repo = SupabaseAnalysisRepository(
      client,
      sincronizador: Sincronizador(habilitado: false),
    );
    final exercises = await repo.loadPractice('aluno-a');
    expect(exercises.map((item) => item.focusConcept), [
      'Velocidade média',
      'Lei de Ohm',
    ]);
    expect(exercises.map((item) => item.subjectName), ['Física', 'Eletrônica']);
    final query = requests.single.queryParameters;
    expect(query['source'], 'in.("ai_practice","catalog")');
    expect(query['subjects.user_id'], 'eq.aluno-a');
    expect(query['select'], contains('focus_concept'));
    expect(query['select'], isNot(contains('correct_answer')));
    expect(query['select'], isNot(contains('practice_answer_keys')));
  });
}
