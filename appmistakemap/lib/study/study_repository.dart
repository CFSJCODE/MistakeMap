import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ai/analysis_repository.dart' show notifyAnalysisChanged;
import '../sync/conexao.dart';
import 'study_models.dart';

export 'study_models.dart';

abstract class StudyRepository {
  ValueListenable<StudySyncState> get syncState;
  Future<StudyDashboard> loadDashboard(String userId);
  Future<StudyProfileData> loadProfile(String userId);
  Future<void> saveProfile(String userId, StudyProfile profile);
  Future<StudySession?> loadSession(String userId);
  Future<StudySession?> startSession(String userId, {required int minutes});
  Future<String> revealReference(
    String userId,
    String sessionId,
    String itemId,
  );
  Future<StudyAnswerResult> answer(
    String userId, {
    required String sessionId,
    required String itemId,
    required String rating,
    required int elapsedSeconds,
  });
  Future<List<StudyDiagnostic>> loadDiagnostics(String userId);
  Future<void> decide(
    String userId,
    String diagnosticId, {
    required String decision,
    String? category,
    double? importance,
  });
  Future<void> flush(String userId);
  Future<List<StudyPendingAnswer>> pendingAnswers(String userId);
  Future<void> discardAnswer(String userId, String eventId);
  Future<String> loadDraft(String userId, String itemId);
  Future<void> saveDraft(String userId, String itemId, String text);
  void dispose();
}

abstract class StudyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class PreferencesStudyStore implements StudyStore {
  const PreferencesStudyStore();

  Future<SharedPreferences> _preferences() async {
    try {
      // A platform storage channel can be unavailable or never respond. Keep
      // the rest of Início usable and report the local failure accurately.
      return await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 2),
      );
    } catch (_) {
      throw const StudyFailure(
        'Não foi possível abrir o estudo salvo neste aparelho. Tente novamente ou reinicie o aplicativo.',
        code: 'local_storage_unavailable',
      );
    }
  }

  @override
  Future<String?> read(String key) async =>
      (await _preferences()).getString(key);
  @override
  Future<void> write(String key, String value) async {
    if (!await (await _preferences()).setString(key, value)) {
      throw const StudyFailure(
        'Não foi possível salvar neste aparelho. Tente novamente antes de fechar.',
      );
    }
  }
}

typedef StudyTransport = Future<StudyJson> Function(
  String userId,
  StudyJson body,
);

/// The server owns scheduling, selection, evidence and progress. This client
/// only caches its replies and durably records self-reports before sending.
class SupabaseStudyRepository implements StudyRepository {
  SupabaseStudyRepository(SupabaseClient client, {StudyStore? store})
    : this.withTransport((userId, body) async {
        if (client.auth.currentUser == null) {
          throw const StudyFailure(
            'Entre com internet para enviar o estudo salvo neste aparelho.',
            network: true,
            code: 'local_session_missing',
          );
        }
        if (client.auth.currentUser?.id != userId) {
          throw const StudyFailure(
            'Entre novamente com a sua conta para enviar as revisões.',
            code: 'auth_required',
          );
        }
        try {
          final response = await client.functions
              .invoke('review-queue', body: body)
              .timeout(const Duration(seconds: 12));
          if (response.status >= 400) {
            throw _serverFailure(response.status, response.data);
          }
          final data = studyMap(response.data);
          if (data.containsKey('error')) throw _serverFailure(400, data);
          return data;
        } on FunctionException catch (error) {
          if (error.status == 0) {
            throw const StudyFailure(
              'Sem conexão com o serviço de estudos.',
              network: true,
            );
          }
          throw _serverFailure(error.status, error.details);
        } catch (error) {
          if (ehFalhaDeRede(error)) {
            throw const StudyFailure(
              'Sem conexão com o serviço de estudos.',
              network: true,
            );
          }
          rethrow;
        }
      }, store: store);

  SupabaseStudyRepository.withTransport(this.transport, {StudyStore? store})
    : store = store ?? const PreferencesStudyStore();

  final StudyTransport transport;
  final StudyStore store;
  final _sync = ValueNotifier(const StudySyncState());
  final _states = <String, StudyJson>{};
  Future<void> _tail = Future.value();
  bool _disposed = false;

  @override
  ValueListenable<StudySyncState> get syncState => _sync;

  static StudyFailure _serverFailure(int status, Object? body) {
    final data = studyMap(body);
    final code = data['error'] as String?;
    final String message;
    if (status == 401 || status == 403) {
      message = 'Sua sessão não autoriza esta alteração. Entre novamente com sua conta.';
    } else if ((status == 404 && (code == null || code == 'NOT_FOUND')) ||
        code == '42P01' ||
        code == 'PGRST205') {
      message = 'O estudo diário ainda não foi ativado neste servidor. Seus exercícios continuam disponíveis.';
    } else if (code == 'event_conflict') {
      message = 'Esta resposta já foi registrada de outra forma. Confira a sessão antes de continuar.';
    } else if (code == 'item_unavailable' || code == 'session_conflict') {
      message = 'Esta revisão mudou em outro aparelho. Atualize a sessão para conferir.';
    } else {
      message = data['message'] as String? ?? 'O servidor não aceitou esta operação. Atualize os dados e tente novamente.';
    }
    return StudyFailure(message, code: code ?? 'http_$status');
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  String _key(String userId) => 'mistakemap.study.v1.$userId';
  Future<StudyJson> _state(String userId) async {
    if (_states.containsKey(userId)) return _states[userId]!;
    final saved = await store.read(_key(userId));
    try {
      return _states[userId] = saved == null ? {} : studyMap(jsonDecode(saved));
    } on FormatException {
      throw const StudyFailure(
        'Os dados locais de estudo não puderam ser lidos. Seus dados no servidor continuam disponíveis.',
      );
    }
  }

  Future<void> _save(String userId, StudyJson state) =>
      store.write(_key(userId), jsonEncode(state));

  List<StudyJson> _queue(StudyJson state) => [...studyRows(state['queue'])];

  void _publish(
    StudyJson state, {
    bool? offline,
    String? message,
    DateTime? updatedAt,
  }) {
    if (_disposed) return;
    final queue = _queue(state);
    _sync.value = StudySyncState(
      offline: offline ?? _sync.value.offline,
      pending: queue.where((item) => item['failure'] == null).length,
      rejected: queue.where((item) => item['failure'] != null).length,
      message:
          message ??
          queue
              .where((item) => item['failure'] != null)
              .map((item) => item['failure'] as String)
              .firstOrNull,
      updatedAt:
          updatedAt ?? DateTime.tryParse(state['updated_at'] as String? ?? ''),
    );
  }

  Future<StudyJson> _call(
    String userId,
    String action, [
    StudyJson body = const {},
  ]) async {
    try {
      final result = await transport(userId, {'action': action, ...body});
      if ((action == 'dashboard' && !result.containsKey('due_count')) ||
          (action == 'session' && !result.containsKey('session'))) {
        throw const StudyFailure(
          'O estudo diário ainda não está disponível neste servidor. Seus exercícios continuam disponíveis.',
          code: 'invalid_service_response',
        );
      }
      return result;
    } catch (error) {
      if (error is StudyFailure) rethrow;
      if (ehFalhaDeRede(error)) {
        throw const StudyFailure(
          'Sem conexão com o serviço de estudos.',
          network: true,
        );
      }
      throw const StudyFailure(
        'Não foi possível carregar o estudo. Tente novamente.',
      );
    }
  }

  Future<StudyJson> _read(String userId, String action) async {
    final state = await _state(userId);
    try {
      final result = await _call(userId, action);
      state[action] = result;
      state['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await _save(userId, state);
      _publish(state, offline: false);
      return result;
    } on StudyFailure catch (error) {
      _publish(
        state,
        offline: error.network,
        message: error.network ? null : error.message,
      );
      if (!error.network) rethrow;
      if (state[action] is! Map) {
        throw const StudyFailure(
          'Sem conexão e sem estudo salvo neste aparelho. Conecte-se para preparar sua primeira sessão.',
          network: true,
        );
      }
      return studyMap(state[action]);
    }
  }

  @override
  Future<StudyDashboard> loadDashboard(String userId) => _serial(() async {
    await _flush(userId);
    return StudyDashboard.fromJson(await _read(userId, 'dashboard'));
  });

  @override
  Future<StudyProfileData> loadProfile(String userId) => _serial(
    () async => StudyProfileData.fromJson(await _read(userId, 'profile')),
  );

  @override
  Future<void> saveProfile(String userId, StudyProfile profile) =>
      _serial(() async {
        final response = await _call(userId, 'save_profile', {
          'profile': profile.toJson(),
        });
        final state = await _state(userId);
        state['profile'] = response;
        await _save(userId, state);
        _publish(state, offline: false);
      });

  StudySession? _sessionWithPending(StudyJson state, StudyJson response) {
    if (response['session'] is! Map) return null;
    final session = studyMap(response['session']);
    final pendingIds = _queue(state)
        .where(
          (event) =>
              event['failure'] == null && event['session_id'] == session['id'],
        )
        .map((event) => event['item_id'])
        .toSet();
    return StudySession.fromJson({
      ...session,
      'items': [
        for (final item in studyRows(session['items']))
          {...item, if (pendingIds.contains(item['id'])) 'answered': true},
      ],
    });
  }

  @override
  Future<StudySession?> loadSession(String userId) => _serial(() async {
    final response = await _read(userId, 'session');
    return _sessionWithPending(await _state(userId), response);
  });

  @override
  Future<StudySession?> startSession(String userId, {required int minutes}) =>
      _serial(() async {
        final state = await _state(userId);
        try {
          final result = await _call(userId, 'start_session', {
            'minutes': minutes,
          });
          state['session'] = result;
          await _save(userId, state);
          _publish(state, offline: false);
          return _sessionWithPending(state, result);
        } on StudyFailure catch (error) {
          if (!error.network) rethrow;
          final cached = _sessionWithPending(state, studyMap(state['session']));
          _publish(state, offline: true);
          if (cached == null || cached.status != 'active') {
            throw const StudyFailure(
              'Conecte-se para preparar uma sessão. Uma sessão já aberta pode ser retomada sem internet.',
              network: true,
            );
          }
          return cached;
        }
      });

  @override
  Future<String> revealReference(
    String userId,
    String sessionId,
    String itemId,
  ) => _serial(() async {
    final state = await _state(userId);
    final key = 'reference:$sessionId:$itemId';
    try {
      final result = await _call(userId, 'session', {
        'session_id': sessionId,
        'reveal_item_id': itemId,
      });
      final reference = result['reference_text'] as String? ?? '';
      state[key] = reference;
      await _save(userId, state);
      _publish(state, offline: false);
      return reference;
    } on StudyFailure catch (error) {
      if (!error.network) rethrow;
      _publish(state, offline: true);
      // Only previously revealed references are available offline. A
      // suggested error's evidence is not an answer key for the prompt.
      if (state[key] is String) return state[key] as String;
      throw const StudyFailure(
        'Esta referência ainda não foi salva no aparelho. Conecte-se para conferi-la antes da autoavaliação.',
        network: true,
      );
    }
  });

  @override
  Future<StudyAnswerResult> answer(
    String userId, {
    required String sessionId,
    required String itemId,
    required String rating,
    required int elapsedSeconds,
  }) => _serial(() async {
    final state = await _state(userId);
    final queue = _queue(state);
    // A double tap or resumed form reuses the durable event rather than
    // issuing a second answer while the first acknowledgement is in doubt.
    final previous = queue
        .where(
          (event) =>
              event['session_id'] == sessionId && event['item_id'] == itemId,
        )
        .firstOrNull;
    if (previous != null && previous['failure'] != null) {
      throw StudyFailure(previous['failure'] as String);
    }
    final event =
        previous ??
        {
          'session_id': sessionId,
          'item_id': itemId,
          'event_id': novoUuid(),
          'rating': rating,
          'answered_at': DateTime.now().toUtc().toIso8601String(),
          'elapsed_seconds': elapsedSeconds.clamp(0, 1800),
        };
    if (previous == null) queue.add(event);
    state['queue'] = queue;
    await _save(userId, state);
    final results = await _flush(userId);
    final rejected = _queue(state)
        .where(
          (row) =>
              row['event_id'] == event['event_id'] && row['failure'] != null,
        )
        .firstOrNull;
    if (rejected != null) throw StudyFailure(rejected['failure'] as String);
    final result = results[event['event_id']];
    if (result != null) return StudyAnswerResult.fromJson(result);
    final session = _sessionWithPending(state, studyMap(state['session']));
    if (session == null) {
      throw const StudyFailure(
        'A resposta ficou salva, mas a sessão precisa ser atualizada.',
      );
    }
    return StudyAnswerResult(session: session, queued: true);
  });

  Future<Map<String, StudyJson>> _flush(String userId) async {
    final state = await _state(userId);
    final queue = _queue(state);
    final results = <String, StudyJson>{};
    for (final event in queue.toList()) {
      if (event['failure'] != null) continue;
      try {
        final result = await _call(userId, 'answer', event);
        results[event['event_id'] as String] = result;
        state['session'] = {'session': result['session']};
        queue.removeWhere((row) => row['event_id'] == event['event_id']);
        state['drafts'] = studyMap(state['drafts'])..remove(event['item_id']);
        state['queue'] = queue;
        await _save(userId, state);
        _publish(state, offline: false);
      } on StudyFailure catch (error) {
        if (error.network) {
          _publish(state, offline: true);
          return results;
        }
        event['failure'] = error.message;
        state['queue'] = queue;
        await _save(userId, state);
        _publish(state, offline: false, message: error.message);
      }
    }
    _publish(state);
    return results;
  }

  @override
  Future<void> flush(String userId) => _serial(() async {
    await _flush(userId);
  });

  @override
  Future<List<StudyPendingAnswer>> pendingAnswers(String userId) => _serial(
    () async => [
      for (final row in _queue(await _state(userId)))
        StudyPendingAnswer(
          eventId: row['event_id'] as String,
          itemId: row['item_id'] as String,
          sessionId: row['session_id'] as String,
          failure: row['failure'] as String?,
        ),
    ],
  );

  @override
  Future<void> discardAnswer(String userId, String eventId) =>
      _serial(() async {
        final state = await _state(userId);
        final queue = _queue(state)
          ..removeWhere((row) => row['event_id'] == eventId);
        state['queue'] = queue;
        await _save(userId, state);
        _publish(state);
      });

  @override
  Future<List<StudyDiagnostic>> loadDiagnostics(String userId) => _serial(
    () async =>
        studyRows((await _read(userId, 'diagnostics'))['items'])
            .map(StudyDiagnostic.fromJson)
            .toList(),
  );

  @override
  Future<void> decide(
    String userId,
    String diagnosticId, {
    required String decision,
    String? category,
    double? importance,
  }) => _serial(() async {
    await _call(userId, 'decide', {
      'error_event_id': diagnosticId,
      'decision': decision,
      'category': ?category,
      'importance': ?importance,
    });
    notifyAnalysisChanged();
  });

  @override
  Future<String> loadDraft(String userId, String itemId) => _serial(
    () async =>
        studyMap((await _state(userId))['drafts'])[itemId] as String? ?? '',
  );

  @override
  Future<void> saveDraft(String userId, String itemId, String text) =>
      _serial(() async {
        final state = await _state(userId);
        state['drafts'] = {...studyMap(state['drafts']), itemId: text};
        await _save(userId, state);
      });

  @override
  void dispose() {
    _disposed = true;
    _sync.dispose();
  }
}
