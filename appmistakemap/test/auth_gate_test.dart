import 'dart:convert';

import 'package:appmistakemap/main.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _TestAuthStorage extends GotrueAsyncStorage {
  const _TestAuthStorage();

  @override
  Future<String?> getItem({required String key}) async => null;

  @override
  Future<void> setItem({required String key, required String value}) async {}

  @override
  Future<void> removeItem({required String key}) async {}
}

GoTrueClient get _auth => Supabase.instance.client.auth;

// Mesmo caminho do gotrue ao falhar o refresh ou o deep link do OAuth.
void _injetarErro(Object erro) {
  // ignore: invalid_use_of_internal_member
  _auth.notifyException(erro);
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 5),
);

Future<void> _renderApp(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    LiquidGlassWidgets.wrap(
      theme: temaVidro,
      brightnessResolver: (context) => FluentTheme.maybeOf(context)?.brightness,
      child: const MistakeMapApp(),
    ),
  );
  await _settle(tester);
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Supabase.initialize(
      url: 'https://auth-gate-tests.invalid',
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
        expect(request.url.host, 'auth-gate-tests.invalid');
        if (request.url.path == '/auth/v1/logout') {
          return http.Response('', 204, request: request);
        }
        if (!request.url.path.startsWith('/rest/v1/')) {
          throw StateError(
            'Requisição não esperada no teste: ${request.url.path}',
          );
        }
        // Telas logadas recebem listas vazias; o perfil cai no papel padrão.
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
          request: request,
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  testWidgets('Erro no stream sem sessão mantém o login e mostra o aviso', (
    tester,
  ) async {
    expect(_auth.currentSession, isNull);
    await _renderApp(tester);
    expect(find.byType(TelaCadastro), findsOneWidget);

    _injetarErro(const AuthException('Falha no retorno do OAuth.'));
    // Assenta a entrada do aviso; o timer de 3 s dele não agenda frames.
    await _settle(tester);

    expect(find.byType(TelaCadastro), findsOneWidget);
    expect(find.text('Falha no retorno do OAuth.'), findsOneWidget);
    // Deixa o aviso expirar para não sobrar timer ao fim do teste.
    await tester.pump(const Duration(seconds: 4));
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Falha de refresh por rede não derruba a sessão válida', (
    tester,
  ) async {
    await _auth.setInitialSession(
      jsonEncode({
        'access_token': 'token-de-teste',
        'token_type': 'bearer',
        'refresh_token': 'refresh-de-teste',
        'user': {
          'id': '11111111-1111-4111-8111-111111111111',
          'email': 'estudante@example.test',
          'aud': 'authenticated',
          'created_at': '2026-10-01T00:00:00Z',
        },
      }),
    );
    addTearDown(_auth.signOut);
    await _renderApp(tester);
    expect(find.byType(TelaNavegacao), findsOneWidget);
    final estadoAntes = tester.state(find.byType(TelaNavegacao));

    _injetarErro(AuthRetryableFetchException(message: 'Failed host lookup'));
    await _settle(tester);

    expect(find.byType(TelaCadastro), findsNothing);
    expect(find.byType(TelaNavegacao), findsOneWidget);
    // Mesmo State: as abas não são recriadas nem perdem o estado.
    expect(tester.state(find.byType(TelaNavegacao)), same(estadoAntes));
    expect(find.textContaining('Sem conexão com o servidor'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
