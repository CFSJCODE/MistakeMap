import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:appmistakemap/ai/analysis_models.dart';
import 'package:appmistakemap/ai/analysis_repository.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

http.Response jsonResponse(Object? value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

MockClient mockTransport(
  Future<http.Response> Function(http.Request) handler,
) => MockClient((request) async {
  final response = await handler(request);
  return http.Response.bytes(
    response.bodyBytes,
    response.statusCode,
    headers: response.headers,
    request: request,
  );
});

void main() {
  test(
    'concurrent analyses of the same attempt share a single request',
    () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      var calls = 0;
      final client = SupabaseClient(
        'https://database.invalid',
        'public-test-key',
        httpClient: mockTransport((_) {
          calls++;
          started.complete();
          return response.future;
        }),
      );
      addTearDown(client.dispose);
      final repository = SupabaseAnalysisRepository(client);
      final first = repository.analyze('attempt');
      final second = repository.analyze('attempt');
      await started.future.timeout(const Duration(seconds: 5));
      expect(calls, 1);
      response.complete(jsonResponse({'status': 'completed'}));
      await Future.wait([first, second]);
    },
  );
  test('practice failure describes generation rather than analysis', () async {
    final client = SupabaseClient(
      'https://database.invalid',
      'public-test-key',
      httpClient: MockClient(
        (_) async => jsonResponse({'error': 'internal_error'}, 500),
      ),
    );
    addTearDown(client.dispose);
    await expectLater(
      SupabaseAnalysisRepository(client)
          .generatePractice('subject', 'Física', 3),
      throwsA(
        isA<AnalysisFailure>().having(
          (error) => error.message,
          'message',
          'Não foi possível gerar os exercícios. Tente novamente.',
        ),
      ),
    );
  });

  test('practice transport failure explains inaccessible service', () async {
    final client = SupabaseClient(
      'https://database.invalid',
      'public-test-key',
      httpClient: MockClient(
        (_) async => throw http.ClientException('blocked'),
      ),
    );
    addTearDown(client.dispose);
    await expectLater(
      SupabaseAnalysisRepository(client)
          .generatePractice('subject', 'Física', 3),
      throwsA(
        isA<AnalysisFailure>().having(
          (error) => error.message,
          'message',
          contains('Não foi possível acessar o serviço de geração'),
        ),
      ),
    );
  });

  test(
    'upload sends filename MIME exact size SHA256 and conditional finalization',
    () async {
      final bytes = Uint8List.fromList([137, 80, 78, 71]);
      final requests = <http.Request>[];
      final transport = mockTransport((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/upload-url')) {
          expect(jsonDecode(request.body), {
            'filename': 'foto.png',
            'content_type': 'image/png',
            'size_bytes': 4,
          });
          return jsonResponse({
            'upload_url': 'https://storage.invalid/photo',
            'object_path': 'uploads/u/photo.png',
            'content_type': 'image/png',
          });
        }
        if (request.url.host == 'storage.invalid') {
          expect(request.method, 'PUT');
          expect(request.headers['content-type'], 'image/png');
          expect(request.bodyBytes, bytes);
          return http.Response('', 200);
        }
        if (request.url.path.endsWith('/attempt_assets') &&
            request.method == 'GET') {
          return jsonResponse([]);
        }
        if (request.url.path.endsWith('/attempt_assets') &&
            request.method == 'POST') {
          expect(jsonDecode(request.body), {
            'attempt_id': 'attempt',
            'object_path': 'uploads/u/photo.png',
            'sha256': sha256.convert(bytes).toString(),
          });
          return jsonResponse(null, 201);
        }
        expect(request.url.path, endsWith('/attempts'));
        expect(request.method, 'PATCH');
        expect(request.url.queryParameters['status'], 'eq.uploading');
        return jsonResponse(null);
      });
      final client = SupabaseClient(
        'https://database.invalid',
        'public-test-key',
        httpClient: transport,
      );
      addTearDown(client.dispose);
      await SupabaseAnalysisRepository(
        client,
        uploadTransport: transport,
      ).uploadImage('attempt', 'foto.png', bytes);
      expect(requests.where((r) => r.method == 'PUT').length, 1);
    },
  );

  test(
    'repeat upload with existing asset only finalizes uploading conditionally',
    () async {
      final requests = <http.Request>[];
      final transport = mockTransport((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return jsonResponse([
            {'id': 'existing'},
          ]);
        }
        expect(request.method, 'PATCH');
        expect(request.url.queryParameters['status'], 'eq.uploading');
        return jsonResponse(null);
      });
      final client = SupabaseClient(
        'https://database.invalid',
        'public-test-key',
        httpClient: transport,
      );
      addTearDown(client.dispose);
      await SupabaseAnalysisRepository(
        client,
        uploadTransport: transport,
      ).uploadImage('attempt', 'photo.jpg', Uint8List.fromList([1]));
      expect(requests.length, 2);
    },
  );

  test(
    'retry limit maps a safe reason without revealing provider text',
    () async {
      final transport = MockClient(
        (_) async => jsonResponse({
          'error': 'retry_limit',
          'details': 'PRIVATE PROVIDER RESPONSE',
        }, 409),
      );
      final client = SupabaseClient(
        'https://database.invalid',
        'public-test-key',
        httpClient: transport,
      );
      addTearDown(client.dispose);
      await expectLater(
        SupabaseAnalysisRepository(client).analyze('attempt'),
        throwsA(
          isA<AnalysisFailure>().having(
            (e) => e.message,
            'message',
            allOf(contains('limite de reanálises'), isNot(contains('PRIVATE'))),
          ),
        ),
      );
    },
  );

  test(
    'generated exercise uses saved ID and only student response in attempt',
    () async {
      final requests = <http.Request>[];
      final transport = mockTransport((request) async {
        requests.add(request);
        expect(request.url.path, endsWith('/attempts'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['exercise_id'], 'generated');
        expect(body['answer'], 'resposta do aluno');
        expect(body.containsKey('correct_answer'), isFalse);
        expect(body['status'], 'pending');
        return jsonResponse({'id': 'attempt'}, 201);
      });
      final client = SupabaseClient(
        'https://database.invalid',
        'public-test-key',
        httpClient: transport,
      );
      addTearDown(client.dispose);
      await SupabaseAnalysisRepository(client).createAttempt(
        userId: 'u',
        subject: 'Matemática',
        prompt: 'Enunciado',
        answer: 'resposta do aluno',
        difficulty: '',
        hasImage: false,
        practice: const PracticeExercise(
          id: 'generated',
          subjectId: 'math',
          subjectName: 'Matemática',
          prompt: 'Enunciado',
          difficulty: 'facil',
          focusConcept: 'Frações',
        ),
      );
      expect(requests.length, 1);
    },
  );
}
