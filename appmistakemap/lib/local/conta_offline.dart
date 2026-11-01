import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;
import 'package:shared_preferences/shared_preferences.dart';

import 'fabrica_banco.dart' show executandoTestes;

/// Conta do último login neste aparelho, para entrar e usar o app sem rede.
///
/// A senha nunca é guardada: fica só um hash com sal aleatório e muitas
/// rodadas, suficiente para conferir a senha digitada quando o servidor não
/// responde. O papel (estudante ou admin) também fica salvo, para o app abrir
/// na hora em vez de esperar o perfil chegar do servidor.
class ContaOffline {
  const ContaOffline();

  static const _chave = 'conta_offline_v1';
  static const _rodadas = 20000;

  // Sem o plugin a chamada pode nunca responder: o atalho offline não pode
  // travar a entrada no app. No flutter test ele fica desligado.
  static Future<SharedPreferences> _prefs() => executandoTestes()
      ? Future.error(StateError('Sem armazenamento local nos testes.'))
      : SharedPreferences.getInstance().timeout(const Duration(seconds: 2));

  Future<Map<String, Object?>?> _ler() async {
    try {
      final prefs = await _prefs();
      final bruto = prefs.getString(_chave);
      if (bruto == null) return null;
      final dados = jsonDecode(bruto);
      return dados is Map<String, Object?> ? dados : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _gravar(Map<String, Object?> dados) async {
    try {
      final prefs = await _prefs();
      await prefs.setString(_chave, jsonEncode(dados));
    } catch (_) {
      // Sem armazenamento local o app só perde o atalho offline.
    }
  }

  static String _hash(String senha, String sal) {
    List<int> bytes = utf8.encode('$sal:$senha');
    for (var i = 0; i < _rodadas; i++) {
      bytes = sha256.convert([...bytes, ...utf8.encode(sal)]).bytes;
    }
    return base64Encode(bytes);
  }

  static String _novoSal() {
    final aleatorio = Random.secure();
    return base64Encode(List<int>.generate(16, (_) => aleatorio.nextInt(256)));
  }

  /// Guarda a conta depois de um login com senha bem-sucedido.
  Future<void> lembrarLogin({
    required String id,
    required String email,
    required String senha,
  }) async {
    final atual = await _ler() ?? const <String, Object?>{};
    final sal = _novoSal();
    await _gravar({
      'id': id,
      'email': email.trim().toLowerCase(),
      // Mantém o papel já conhecido da mesma conta.
      'papel': (atual['id'] == id) ? atual['papel'] : null,
      'sal': sal,
      'hash': _hash(senha, sal),
    });
  }

  /// Guarda o papel confirmado pelo servidor para a conta [id].
  Future<void> lembrarPapel({
    required String id,
    required String email,
    required String papel,
  }) async {
    final atual = await _ler() ?? {};
    // Outra conta entrou (por exemplo, com o Google): o hash antigo não vale.
    final mesmaConta = atual['id'] == id;
    await _gravar({
      if (mesmaConta) ...atual,
      'id': id,
      'email': email.trim().toLowerCase(),
      'papel': papel,
    });
  }

  /// Papel salvo para a conta [id], ou nulo se nunca foi confirmado.
  Future<String?> papel(String id) async {
    final dados = await _ler();
    if (dados == null || dados['id'] != id) return null;
    return dados['papel'] as String?;
  }

  /// Confere e-mail e senha com a última conta que entrou neste aparelho.
  Future<({String id, String email, String papel})?> entrar(
    String email,
    String senha,
  ) async {
    final dados = await _ler();
    final sal = dados?['sal'];
    final hash = dados?['hash'];
    if (dados == null || sal is! String || hash is! String) return null;
    if (dados['email'] != email.trim().toLowerCase()) return null;
    if (_hash(senha, sal) != hash) return null;
    return (
      id: dados['id'] as String,
      email: dados['email'] as String,
      papel: dados['papel'] as String? ?? 'user',
    );
  }

  /// Existe uma conta salva que pode entrar sem rede?
  Future<String?> emailSalvo() async {
    final dados = await _ler() ?? const <String, Object?>{};
    final temHash = dados['hash'] is String;
    return temHash ? dados['email'] as String? : null;
  }

  Future<void> esquecer() async {
    try {
      final prefs = await _prefs();
      await prefs.remove(_chave);
    } catch (_) {}
  }
}
