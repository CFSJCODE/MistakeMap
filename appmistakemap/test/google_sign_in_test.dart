import 'dart:async';
import 'dart:convert';

import 'package:appmistakemap/auth/google_sign_in.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Matcher failsWith(GoogleSignInFailure failure) => throwsA(
  isA<GoogleSignInException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

void main() {
  final projectUrl = Uri.parse('https://project.supabase.co');
  final webUrl = Uri.parse('http://127.0.0.1:8080/');

  group('redirect OAuth', () {
    test(
      'web preserva origem, porta e subpasta e remove parâmetros/tokens',
      () {
        expect(
          googleOAuthRedirect(
            isWeb: true,
            currentUri: Uri.parse(
              'http://127.0.0.1:8080/app/index.html?code=temporary#access_token=old',
            ),
          ),
          'http://127.0.0.1:8080/app/index.html',
        );
      },
    );

    test('web preserva HTTPS e caminhos com caracteres escapados', () {
      expect(
        googleOAuthRedirect(
          isWeb: true,
          currentUri: Uri.parse('https://example.org/meu%20app/?source=google'),
        ),
        'https://example.org/meu%20app/',
      );
    });

    test('web sem caminho usa a raiz do site', () {
      expect(
        googleOAuthRedirect(
          isWeb: true,
          currentUri: Uri.parse('https://example.org'),
        ),
        'https://example.org/',
      );
    });

    test('aplicativo nativo mantém seu deep link', () {
      expect(
        googleOAuthRedirect(
          isWeb: false,
          currentUri: Uri.parse('file:///app/'),
        ),
        'io.supabase.mistakemap://login-callback/',
      );
    });

    test('arquivo local não é aceito como retorno OAuth web', () {
      expect(
        () => googleOAuthRedirect(
          isWeb: true,
          currentUri: Uri.parse('file:///app/index.html'),
        ),
        failsWith(GoogleSignInFailure.invalidWebRedirect),
      );
    });
  });

  group('configuração pública e lançamento', () {
    test('consulta settings com chave pública antes de lançar OAuth', () async {
      var checkedSettings = false;
      final redirects = <String>[];
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          'https://project.supabase.co/auth/v1/settings',
        );
        expect(request.headers['apikey'], 'public-client-key');
        expect(request.headers.containsKey('authorization'), isFalse);
        checkedSettings = true;
        return http.Response('{"external":{"google":true}}', 200);
      });
      final service = GoogleSignInService(
        supabaseUrl: projectUrl,
        publicKey: 'public-client-key',
        httpClient: client,
        launchOAuth: (redirect) async {
          expect(checkedSettings, isTrue);
          redirects.add(redirect);
          return true;
        },
      );

      await service.signIn(
        isWeb: true,
        currentUri: Uri.parse('https://example.org/app/?code=old#token=old'),
      );

      expect(redirects, ['https://example.org/app/']);
    });

    test('provider desabilitado não abre OAuth e informa a causa', () async {
      var launchCount = 0;
      final service = GoogleSignInService(
        supabaseUrl: projectUrl,
        publicKey: 'public-client-key',
        httpClient: MockClient(
          (_) async => http.Response('{"external":{"google":false}}', 200),
        ),
        launchOAuth: (_) async {
          launchCount++;
          return true;
        },
      );

      await expectLater(
        service.signIn(isWeb: true, currentUri: webUrl),
        failsWith(GoogleSignInFailure.providerDisabled),
      );
      expect(launchCount, 0);
      expect(
        const GoogleSignInException(GoogleSignInFailure.providerDisabled)
            .message,
        contains('não está habilitado'),
      );
    });

    final invalidSettings = <String, http.Response>{
      'HTTP 500': http.Response('Internal error', 500),
      'HTTP 401': http.Response('{}', 401),
      'JSON inválido': http.Response('<html>error</html>', 200),
      'configuração ausente': http.Response('{}', 200),
      'lista em lugar de objeto': http.Response('[]', 200),
      'google ausente': http.Response('{"external":{}}', 200),
      'google com tipo inválido': http.Response(
        '{"external":{"google":"true"}}',
        200,
      ),
    };
    for (final entry in invalidSettings.entries) {
      test(
        '${entry.key} não significa provedor desabilitado nem abre OAuth',
        () async {
          var launched = false;
          final service = GoogleSignInService(
            supabaseUrl: projectUrl,
            publicKey: 'public-client-key',
            httpClient: MockClient((_) async => entry.value),
            launchOAuth: (_) async {
              launched = true;
              return true;
            },
          );

          await expectLater(
            service.signIn(isWeb: true, currentUri: webUrl),
            failsWith(GoogleSignInFailure.settingsUnavailable),
          );
          expect(launched, isFalse);
        },
      );
    }

    test('falha de transporte não abre navegador', () async {
      var launched = false;
      final service = GoogleSignInService(
        supabaseUrl: projectUrl,
        publicKey: 'public-client-key',
        httpClient: MockClient(
          (_) async => throw http.ClientException('offline'),
        ),
        launchOAuth: (_) async {
          launched = true;
          return true;
        },
      );

      await expectLater(
        service.signIn(isWeb: true, currentUri: webUrl),
        failsWith(GoogleSignInFailure.settingsUnavailable),
      );
      expect(launched, isFalse);
    });

    test('consulta que não responde é limitada pelo timeout', () async {
      var launched = false;
      final pending = Completer<http.Response>();
      final service = GoogleSignInService(
        supabaseUrl: projectUrl,
        publicKey: 'public-client-key',
        httpClient: MockClient((_) => pending.future),
        settingsTimeout: Duration.zero,
        launchOAuth: (_) async {
          launched = true;
          return true;
        },
      );

      await expectLater(
        service.signIn(isWeb: true, currentUri: webUrl),
        failsWith(GoogleSignInFailure.settingsUnavailable),
      );
      expect(launched, isFalse);
      pending.complete(http.Response('{"external":{"google":true}}', 200));
    });

    test(
      'nova tentativa refaz settings e percebe provider habilitado',
      () async {
        var requests = 0;
        var launches = 0;
        final service = GoogleSignInService(
          supabaseUrl: projectUrl,
          publicKey: 'public-client-key',
          httpClient: MockClient((_) async {
            requests++;
            return http.Response(
              jsonEncode({
                'external': {'google': requests > 1},
              }),
              200,
            );
          }),
          launchOAuth: (redirect) async {
            launches++;
            expect(redirect, googleNativeRedirect);
            return true;
          },
        );

        await expectLater(
          service.signIn(isWeb: false, currentUri: webUrl),
          failsWith(GoogleSignInFailure.providerDisabled),
        );
        await service.signIn(isWeb: false, currentUri: webUrl);

        expect(requests, 2);
        expect(launches, 1);
      },
    );

    for (final throwsException in [false, true]) {
      test(
        'lançador ${throwsException ? 'com exceção' : 'retornando false'} informa falha',
        () async {
          final service = GoogleSignInService(
            supabaseUrl: projectUrl,
            publicKey: 'public-client-key',
            httpClient: MockClient(
              (_) async => http.Response('{"external":{"google":true}}', 200),
            ),
            launchOAuth: (_) async {
              if (throwsException) throw Exception('Cannot open browser');
              return false;
            },
          );

          await expectLater(
            service.signIn(isWeb: true, currentUri: webUrl),
            failsWith(GoogleSignInFailure.launchFailed),
          );
        },
      );
    }
  });
}
