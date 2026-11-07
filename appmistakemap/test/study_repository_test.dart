import 'dart:async';
import 'dart:convert';

import 'package:appmistakemap/study/study_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MemoryStore implements StudyStore {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

StudyJson _session({bool answered = false}) => {
  'id': 'session-1',
  'status': answered ? 'completed' : 'active',
  'items': [
    {
      'id': 'review-1',
      'subject_id': 'subject-1',
      'subject_name': 'Eletrônica',
      'concept_name': 'Resistência',
      'prompt_text':
          'Um sensor recebe 12 V e consome 0,2 A. Qual é a resistência?',
      'evidence': 'A relação entre tensão e corrente precisa ser revista.',
      'answered': answered,
    },
  ],
};

StudyJson _dashboard() => {
  'profile': {
    'stage': 'superior',
    'daily_minutes': 15,
    'goal': 'Entender circuitos',
  },
  'due_count': 1,
  'pending_diagnostics': 1,
  'estimated_minutes': 3,
  'reviewed_today': 0,
  'progress': {'reviews': 0, 'recall_rate': null, 'period_days': 7},
};

void main() {
  test('adaptador Supabase envia autenticação e decodifica JSON com transporte HTTP real', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://study-adapter-tests.invalid',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        expect(request.url.path, '/functions/v1/review-queue');
        expect(request.headers['authorization'], 'Bearer test-access-token');
        expect(jsonDecode(request.body)['action'], 'dashboard');
        return http.Response(
          jsonEncode(_dashboard()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
          request: request,
        );
      }),
    );
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'test-access-token',
        'token_type': 'bearer',
        'refresh_token': 'test-refresh-token',
        'expires_in': 3600,
        'expires_at':
            DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
        'user': {
          'id': '11111111-1111-4111-8111-111111111111',
          'email': 'aluno@example.test',
          'aud': 'authenticated',
          'created_at': '2026-10-01T00:00:00Z',
        },
      }),
    );
    final repository = SupabaseStudyRepository(client, store: _MemoryStore());
    try {
      final dashboard = await repository.loadDashboard(
        '11111111-1111-4111-8111-111111111111',
      );
      expect(dashboard.profile!.goal, 'Entender circuitos');
      expect(dashboard.dueCount, 1);
      expect(requests.length, 1);
    } finally {
      repository.dispose();
      await client.dispose();
    }
  });

  test('resposta sobrevive a reinício e reenvio após confirmação perdida mantém o mesmo evento', () async {
    final store = _MemoryStore();
    var online = true;
    var loseAcknowledgement = true;
    final events = <String>{};
    final received = <String>[];
    Future<StudyJson> transport(String userId, StudyJson body) async {
      if (!online) throw TimeoutException('offline');
      switch (body['action']) {
        case 'dashboard':
          return _dashboard();
        case 'start_session':
          return {'session': _session()};
        case 'session':
          return {
            'session': _session(answered: events.isNotEmpty),
            'reference_text': 'R = 12 / 0,2 = 60 Ω.',
          };
        case 'answer':
          final id = body['event_id'] as String;
          received.add(id);
          final duplicate = !events.add(id);
          if (loseAcknowledgement) {
            loseAcknowledgement = false;
            throw TimeoutException('ack perdido');
          }
          return {
            'duplicate': duplicate,
            'session': _session(answered: true),
            'feedback': {
              'reference_text': '60 Ω',
              'next_due_at': '2026-11-08T12:00:00Z',
            },
          };
      }
      throw StateError('action inesperada');
    }

    final repo = SupabaseStudyRepository.withTransport(transport, store: store);
    await repo.loadDashboard('aluno-a');
    await repo.startSession('aluno-a', minutes: 15);
    await repo.revealReference('aluno-a', 'session-1', 'review-1');
    final result = await repo.answer(
      'aluno-a',
      sessionId: 'session-1',
      itemId: 'review-1',
      rating: 'good',
      elapsedSeconds: 40,
    );
    expect(result.queued, isTrue);
    expect(result.session.remaining, isEmpty);
    final id = (await repo.pendingAnswers('aluno-a')).single.eventId;
    expect(repo.syncState.value.pending, 1);
    expect(repo.syncState.value.offline, isTrue);
    repo.dispose();

    online = false;
    final reopened = SupabaseStudyRepository.withTransport(
      transport,
      store: store,
    );
    expect(
      await reopened.revealReference('aluno-a', 'session-1', 'review-1'),
      contains('60 Ω'),
    );
    expect((await reopened.loadSession('aluno-a'))!.remaining, isEmpty);
    online = true;
    await reopened.loadDashboard('aluno-a');
    expect(received, [id, id]);
    expect(events.length, 1);
    expect(await reopened.pendingAnswers('aluno-a'), isEmpty);
    expect(reopened.syncState.value.offline, isFalse);
    reopened.dispose();
  });

  test(
    'recusa fica visível e não vira falha de rede ou reenvio automático',
    () async {
      final store = _MemoryStore();
      var answerCalls = 0;
      final repo = SupabaseStudyRepository.withTransport((userId, body) async {
        switch (body['action']) {
          case 'dashboard':
            return _dashboard();
          case 'start_session':
            return {'session': _session()};
          case 'answer':
            answerCalls++;
            throw const StudyFailure(
              'Esta revisão foi alterada em outro aparelho.',
              code: 'item_unavailable',
            );
        }
        throw StateError('action inesperada');
      }, store: store);
      await repo.startSession('aluno-a', minutes: 15);
      await expectLater(
        repo.answer(
          'aluno-a',
          sessionId: 'session-1',
          itemId: 'review-1',
          rating: 'good',
          elapsedSeconds: 15,
        ),
        throwsA(
          isA<StudyFailure>().having(
            (error) => error.network,
            'network',
            false,
          ),
        ),
      );
      expect(repo.syncState.value.offline, isFalse);
      expect(repo.syncState.value.rejected, 1);
      await repo.loadDashboard('aluno-a');
      expect(answerCalls, 1);
      final pending = (await repo.pendingAnswers('aluno-a')).single;
      expect(pending.failure, contains('outro aparelho'));
      await repo.discardAnswer('aluno-a', pending.eventId);
      expect(await repo.pendingAnswers('aluno-a'), isEmpty);
      repo.dispose();
    },
  );

  test(
    'cache nunca esconde recusa de autenticação e fica isolado por usuário',
    () async {
      final store = _MemoryStore();
      var mode = 'online';
      final repo = SupabaseStudyRepository.withTransport((userId, body) async {
        if (mode == 'offline') throw TimeoutException('offline');
        if (mode == 'refused') {
          throw const StudyFailure('Acesso negado.', code: 'auth_required');
        }
        return _dashboard();
      }, store: store);
      await repo.loadDashboard('aluno-a');
      await repo.saveDraft('aluno-a', 'review-1', 'rascunho pessoal');
      mode = 'offline';
      expect((await repo.loadDashboard('aluno-a')).dueCount, 1);
      await expectLater(
        repo.loadDashboard('aluno-b'),
        throwsA(isA<StudyFailure>()),
      );
      expect(await repo.loadDraft('aluno-b', 'review-1'), isEmpty);
      mode = 'refused';
      await expectLater(
        repo.loadDashboard('aluno-a'),
        throwsA(
          isA<StudyFailure>().having(
            (error) => error.code,
            'code',
            'auth_required',
          ),
        ),
      );
      expect(repo.syncState.value.offline, isFalse);
      repo.dispose();
    },
  );

  test('toques repetidos sem rede preservam um único evento durável', () async {
    final store = _MemoryStore();
    var offline = false;
    final repo = SupabaseStudyRepository.withTransport((userId, body) async {
      if (offline) throw TimeoutException('offline');
      return {'session': _session()};
    }, store: store);
    await repo.startSession('aluno-a', minutes: 15);
    offline = true;
    await Future.wait([
      repo.answer(
        'aluno-a',
        sessionId: 'session-1',
        itemId: 'review-1',
        rating: 'good',
        elapsedSeconds: 15,
      ),
      repo.answer(
        'aluno-a',
        sessionId: 'session-1',
        itemId: 'review-1',
        rating: 'good',
        elapsedSeconds: 15,
      ),
    ]);
    expect((await repo.pendingAnswers('aluno-a')).length, 1);
    repo.dispose();
  });

  test('sessão sem conceitos não inventa uma revisão; referência inédita requer rede', () async {
    final store = _MemoryStore();
    var offline = false;
    final repo = SupabaseStudyRepository.withTransport((userId, body) async {
      if (offline) throw TimeoutException('offline');
      return {'session': null};
    }, store: store);
    expect(await repo.startSession('aluno-a', minutes: 15), isNull);
    offline = true;
    await expectLater(
      repo.revealReference('aluno-a', 'session-1', 'review-1'),
      throwsA(
        isA<StudyFailure>().having((error) => error.network, 'network', true),
      ),
    );
    repo.dispose();
  });
}
