import 'dart:convert';

import 'package:appmistakemap/main.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _user = AppUser(
  id: '11111111-1111-4111-8111-111111111111',
  email: 'estudante@example.test',
  role: 'user',
);
const _outroUsuario = '22222222-2222-4222-8222-222222222222';

// Exercício ainda sem tentativa: o único caso em que a edição é oferecida.
const _semTentativa = Exercicio(
  id: 'exercise-1',
  subjectId: 'subject-1',
  subjectName: 'Equações',
  promptText: 'Errei o sinal ao isolar x.',
  status: 'sem_tentativa',
);
const _enviado = Exercicio(
  id: 'exercise-1',
  subjectId: 'subject-1',
  subjectName: 'Equações',
  promptText: 'Errei o sinal ao isolar x.',
  status: 'pending',
  attemptId: 'attempt-1',
);

class _TestAuthStorage extends GotrueAsyncStorage {
  const _TestAuthStorage();

  @override
  Future<String?> getItem({required String key}) async => null;

  @override
  Future<void> setItem({required String key, required String value}) async {}

  @override
  Future<void> removeItem({required String key}) async {}
}

// Requisições recebidas pelo cliente falso, na ordem em que chegaram.
final _requisicoes = <http.Request>[];

http.Response _responder(http.Request request) {
  final vazio = http.Response('', 204, request: request);
  switch ((request.method, request.url.path)) {
    case ('PATCH', '/rest/v1/exercises'):
      // Mesmo erro de guard_analyzed_exercise para quem troca a matéria.
      if (request.body.contains('subject_id')) {
        return http.Response(
          jsonEncode({
            'code': '42501',
            'message': 'create a new exercise to change a submitted prompt',
            'details': null,
            'hint': null,
          }),
          403,
          headers: {'content-type': 'application/json; charset=utf-8'},
          request: request,
        );
      }
      return vazio;
    case ('GET', '/rest/v1/subjects'):
      return http.Response(
        '[]',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
        request: request,
      );
    case ('POST', '/rest/v1/subjects'):
      return http.Response(
        jsonEncode({'id': 'subject-nova'}),
        201,
        headers: {'content-type': 'application/json; charset=utf-8'},
        request: request,
      );
    case ('DELETE', '/rest/v1/subjects'):
      return vazio;
  }
  throw StateError('Requisição não esperada no teste: ${request.url}');
}

Future<void> _render(WidgetTester tester, Widget page) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    LiquidGlassWidgets.wrap(
      theme: temaVidro,
      child: FluentApp(theme: temaFluent, home: page),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Supabase.initialize(
      url: 'https://editar-tests.invalid',
      publishableKey: 'public-test-key',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUri: false,
        pkceAsyncStorage: _TestAuthStorage(),
      ),
      httpClient: MockClient((request) async {
        // Nenhuma requisição deixa o processo de teste.
        expect(request.url.host, 'editar-tests.invalid');
        _requisicoes.add(request);
        return _responder(request);
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(_requisicoes.clear);

  group('tentativaMaisRecente', () {
    test('escolhe a maior attempted_at, sem depender da ordem', () {
      final tentativas = [
        {'id': 'a', 'user_id': _user.id, 'attempted_at': '2026-09-28T10:00Z'},
        // 01:00 em -03:00 é 04:00 UTC: mais recente que a das 03:00 UTC.
        {
          'id': 'b',
          'user_id': _user.id,
          'attempted_at': '2026-09-30T01:00:00-03:00',
        },
        {
          'id': 'c',
          'user_id': _user.id,
          'attempted_at': '2026-09-30T03:00:00.123456+00:00',
        },
      ];
      expect(tentativaMaisRecente(tentativas, _user.id)?['id'], 'b');
    });

    test('ignora tentativas de outro usuário', () {
      final tentativas = [
        {'id': 'x', 'user_id': _outroUsuario, 'attempted_at': '2026-10-01'},
        {'id': 'a', 'user_id': _user.id, 'attempted_at': '2026-09-01'},
      ];
      expect(tentativaMaisRecente(tentativas, _user.id)?['id'], 'a');
    });

    test('tentativa datada vence a que veio sem data', () {
      final tentativas = [
        {'id': 'a', 'user_id': _user.id},
        {'id': 'b', 'user_id': _user.id, 'attempted_at': '2026-09-01'},
      ];
      expect(tentativaMaisRecente(tentativas, _user.id)?['id'], 'b');
    });

    test('sem tentativa do usuário devolve null', () {
      expect(tentativaMaisRecente(null, _user.id), isNull);
      expect(tentativaMaisRecente(<Object>[], _user.id), isNull);
      expect(
        tentativaMaisRecente([
          {'id': 'x', 'user_id': _outroUsuario},
        ], _user.id),
        isNull,
      );
    });
  });

  testWidgets('detalhe oferece Editar antes do envio', (tester) async {
    await _render(
      tester,
      TelaDetalheExercicio(
        exercicio: _semTentativa,
        user: _user,
        onAtualizar: () {},
      ),
    );
    expect(find.text('Editar exercício'), findsOneWidget);
    expect(find.byTooltip('Editar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detalhe esconde Editar depois do envio', (tester) async {
    await _render(
      tester,
      TelaDetalheExercicio(
        exercicio: _enviado,
        user: _user,
        onAtualizar: () {},
      ),
    );
    expect(find.text('Editar exercício'), findsNothing);
    expect(find.byTooltip('Editar'), findsNothing);
    expect(find.text('Excluir exercício'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('troca de matéria recusada desfaz a matéria recém-criada', (
    tester,
  ) async {
    await _render(
      tester,
      const TelaEditarExercicio(exercicio: _semTentativa, user: _user),
    );
    await tester.enterText(find.byType(TextFormBox).first, 'Funções');
    await tester.tap(find.text('Salvar alterações'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      [for (final r in _requisicoes) '${r.method} ${r.url.path}'],
      [
        'PATCH /rest/v1/exercises',
        'GET /rest/v1/subjects',
        'POST /rest/v1/subjects',
        'PATCH /rest/v1/exercises',
        'DELETE /rest/v1/subjects',
      ],
    );
    expect(_requisicoes.last.url.queryParameters['id'], 'eq.subject-nova');
    expect(find.textContaining('Registre um novo exercício'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Deixa o aviso expirar para não sobrar timer pendente.
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });

  testWidgets('exercício já enviado não chega a tocar o banco', (tester) async {
    await _render(
      tester,
      const TelaEditarExercicio(exercicio: _enviado, user: _user),
    );
    await tester.enterText(find.byType(TextFormBox).first, 'Funções');
    await tester.tap(find.text('Salvar alterações'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(_requisicoes, isEmpty);
    expect(find.textContaining('Registre um novo exercício'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });
}
