import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const googleNativeRedirect = 'io.supabase.mistakemap://login-callback/';

enum GoogleSignInFailure {
  providerDisabled,
  settingsUnavailable,
  launchFailed,
  invalidWebRedirect,
}

class GoogleSignInException implements Exception {
  const GoogleSignInException(this.failure);

  final GoogleSignInFailure failure;

  String get message => switch (failure) {
    GoogleSignInFailure.providerDisabled =>
      'O login com Google não está habilitado neste aplicativo. '
          'Entre com e-mail e senha.',
    GoogleSignInFailure.settingsUnavailable =>
      'Não foi possível verificar a disponibilidade do login com Google. '
          'Tente novamente ou entre com e-mail e senha.',
    GoogleSignInFailure.launchFailed =>
      'Não foi possível abrir o login com Google. Tente novamente.',
    GoogleSignInFailure.invalidWebRedirect =>
      'Abra o aplicativo por um endereço HTTP ou HTTPS para entrar com Google.',
  };

  @override
  String toString() => message;
}

/// Retorna ao site atual na web, sem transportar códigos ou tokens da URL.
/// O caminho é preservado para instalações publicadas em uma subpasta.
String googleOAuthRedirect({required bool isWeb, required Uri currentUri}) {
  if (!isWeb) return googleNativeRedirect;

  if (!['http', 'https'].contains(currentUri.scheme) ||
      currentUri.host.isEmpty) {
    throw const GoogleSignInException(GoogleSignInFailure.invalidWebRedirect);
  }

  return Uri(
    scheme: currentUri.scheme,
    host: currentUri.host,
    port: currentUri.hasPort ? currentUri.port : null,
    path: currentUri.path.isEmpty ? '/' : currentUri.path,
  ).toString();
}

typedef GoogleOAuthLauncher = Future<bool> Function(String redirectTo);

/// Verifica as configurações públicas antes de sair do aplicativo para OAuth.
/// O SDK Flutter abre a URL, mas não observa o HTTP 400 da página seguinte.
class GoogleSignInService {
  GoogleSignInService({
    required Uri supabaseUrl,
    required this.publicKey,
    required this.launchOAuth,
    this.httpClient,
    this.settingsTimeout = const Duration(seconds: 8),
  }) : _settingsUri = supabaseUrl.resolve('/auth/v1/settings');

  final Uri _settingsUri;
  final String publicKey;
  final GoogleOAuthLauncher launchOAuth;
  final http.Client? httpClient;
  final Duration settingsTimeout;

  Future<void> signIn({required bool isWeb, required Uri currentUri}) async {
    final redirectTo = googleOAuthRedirect(
      isWeb: isWeb,
      currentUri: currentUri,
    );
    await _checkProvider();

    try {
      if (!await launchOAuth(redirectTo)) {
        throw const GoogleSignInException(GoogleSignInFailure.launchFailed);
      }
    } on GoogleSignInException {
      rethrow;
    } on Exception {
      throw const GoogleSignInException(GoogleSignInFailure.launchFailed);
    }
  }

  Future<void> _checkProvider() async {
    final client = httpClient ?? http.Client();
    try {
      final response = await client
          .get(_settingsUri, headers: {'apikey': publicKey})
          .timeout(settingsTimeout);
      if (response.statusCode != 200) {
        throw const GoogleSignInException(
          GoogleSignInFailure.settingsUnavailable,
        );
      }

      final settings = jsonDecode(response.body);
      final providers = settings is Map<String, dynamic>
          ? settings['external']
          : null;
      final enabled = providers is Map<String, dynamic>
          ? providers['google']
          : null;
      if (enabled is! bool) {
        throw const GoogleSignInException(
          GoogleSignInFailure.settingsUnavailable,
        );
      }
      if (!enabled) {
        throw const GoogleSignInException(GoogleSignInFailure.providerDisabled);
      }
    } on GoogleSignInException {
      rethrow;
    } on http.ClientException {
      throw const GoogleSignInException(
        GoogleSignInFailure.settingsUnavailable,
      );
    } on TimeoutException {
      throw const GoogleSignInException(
        GoogleSignInFailure.settingsUnavailable,
      );
    } on FormatException {
      throw const GoogleSignInException(
        GoogleSignInFailure.settingsUnavailable,
      );
    } finally {
      if (httpClient == null) client.close();
    }
  }
}
