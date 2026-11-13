import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

/// Relato de erros do app (aluno e equipe) para a Central da Equipe.
///
/// Envia só o tipo da exceção, o primeiro ponto do código do próprio app
/// (arquivo:linha), a versão/build/patch e a plataforma. Nunca a mensagem da
/// exceção: ela pode trazer texto do aluno. O servidor grava pela RPC
/// `report_app_error`, que limita o volume por conta.
class AssinaturaErro {
  const AssinaturaErro(this.tipo, this.local);

  final String tipo;
  final String local;

  String get chave => '$tipo@$local';
}

final _quadroDoApp = RegExp(r'package:appmistakemap/([^\s:)]+\.dart):(\d+)');
final _quadroQualquer = RegExp(r'(package:[^\s:)]+\.dart|dart:[a-z_]+)');

/// Tipo e local de um erro. O local é o primeiro quadro do pacote do app; se
/// não houver, o primeiro pacote da pilha (ex.: um widget do fluent_ui).
AssinaturaErro assinaturaDe(Object erro, StackTrace? pilha) {
  var tipo = erro.runtimeType.toString();
  // Tipos privados ou genéricos longos não ajudam a agrupar.
  tipo = tipo.replaceAll(RegExp(r'<.*>'), '');
  if (tipo.isEmpty) tipo = 'Erro';
  final texto = pilha?.toString() ?? '';
  final doApp = _quadroDoApp.firstMatch(texto);
  final String local;
  if (doApp != null) {
    local = '${doApp.group(1)}:${doApp.group(2)}';
  } else {
    local = _quadroQualquer.firstMatch(texto)?.group(1) ?? 'desconhecido';
  }
  return AssinaturaErro(
    tipo.length > 80 ? tipo.substring(0, 80) : tipo,
    local.length > 160 ? local.substring(local.length - 160) : local,
  );
}

/// Um erro pronto para envio.
class ErroApp {
  const ErroApp({required this.assinatura, required this.fatal});

  final AssinaturaErro assinatura;
  final bool fatal;
}

typedef EnviarErro = Future<void> Function(ErroApp erro);

/// Filtra e envia os erros: cada assinatura no máximo [porAssinatura] vezes
/// e no máximo [porSessao] erros por abertura do app. Falhas no envio são
/// engolidas: o relato nunca derruba o app.
class RelatorErros {
  RelatorErros({
    required this.enviar,
    this.porAssinatura = 3,
    this.porSessao = 20,
  });

  final EnviarErro enviar;
  final int porAssinatura;
  final int porSessao;

  final _vistos = <String, int>{};
  int _enviados = 0;

  int get enviados => _enviados;

  /// Registra um erro; devolve true se ele foi para envio.
  bool registrar(Object erro, StackTrace? pilha, {bool fatal = false}) {
    if (_enviados >= porSessao) return false;
    final assinatura = assinaturaDe(erro, pilha);
    final vezes = _vistos[assinatura.chave] ?? 0;
    if (vezes >= porAssinatura) return false;
    _vistos[assinatura.chave] = vezes + 1;
    _enviados++;
    unawaited(
      enviar(ErroApp(assinatura: assinatura, fatal: fatal))
          .catchError((Object _) {}),
    );
    return true;
  }

  /// Liga o relato nos ganchos globais do Flutter, mantendo o comportamento
  /// anterior (log no console e tela de erro).
  void instalar() {
    final anterior = FlutterError.onError;
    FlutterError.onError = (detalhes) {
      // Erros de layout em modo debug não interessam em produção.
      if (!detalhes.silent) {
        registrar(detalhes.exception, detalhes.stack);
      }
      anterior?.call(detalhes);
    };
    final plataforma = WidgetsBinding.instance.platformDispatcher;
    final anteriorPlataforma = plataforma.onError;
    plataforma.onError = (erro, pilha) {
      registrar(erro, pilha, fatal: true);
      return anteriorPlataforma?.call(erro, pilha) ?? false;
    };
  }
}
