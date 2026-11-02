import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Situação do patch de código (Shorebird) neste aparelho.
enum EstadoPatch {
  /// Build sem o motor do Shorebird: debug, `flutter run` ou web.
  indisponivel,
  verificando,
  emDia,
  baixando,

  /// Patch baixado: entra em vigor na próxima vez que o app abrir.
  prontoParaReiniciar,
  falhou,
}

/// Fonte dos patches, separada do Shorebird para os testes.
abstract class FontePatch {
  bool get disponivel;
  Future<int?> patchAtual();
  Future<UpdateStatus> verificar();
  Future<void> baixar();
}

class FonteShorebird implements FontePatch {
  FonteShorebird([ShorebirdUpdater? updater])
    : _updater = updater ?? ShorebirdUpdater();

  final ShorebirdUpdater _updater;

  @override
  bool get disponivel => _updater.isAvailable;

  @override
  Future<int?> patchAtual() async =>
      (await _updater.readCurrentPatch())?.number;

  @override
  Future<UpdateStatus> verificar() => _updater.checkForUpdate();

  @override
  Future<void> baixar() => _updater.update();
}

/// Procura e baixa patches de código sem bloquear o app.
///
/// O patch baixado fica guardado e é aplicado pelo motor do Shorebird no
/// próximo início do app; o código em execução nunca é trocado no meio do uso.
class AtualizadorCodigo {
  AtualizadorCodigo({
    FontePatch? fonte,
    this.intervaloMinimo = const Duration(minutes: 30),
    DateTime Function()? relogio,
  }) : _fonte = fonte ?? FonteShorebird(),
       _relogio = relogio ?? DateTime.now;

  final FontePatch _fonte;
  final DateTime Function() _relogio;

  /// Menor espaço entre duas consultas ao servidor (sair e voltar ao app
  /// várias vezes seguidas não repete a consulta).
  final Duration intervaloMinimo;

  final estado = ValueNotifier<EstadoPatch>(EstadoPatch.indisponivel);

  /// Número do patch rodando agora (null = binário original do release).
  final patchAtual = ValueNotifier<int?>(null);

  DateTime? _ultimaConsulta;
  Future<void>? _emCurso;

  Future<void> verificar({bool forcar = false}) {
    final emCurso = _emCurso;
    if (emCurso != null) return emCurso;
    final agora = _relogio();
    final ultima = _ultimaConsulta;
    if (!forcar &&
        ultima != null &&
        agora.difference(ultima) < intervaloMinimo) {
      return Future.value();
    }
    // Patch já baixado: nada a fazer até o app reabrir.
    if (estado.value == EstadoPatch.prontoParaReiniciar) return Future.value();
    _ultimaConsulta = agora;
    return _emCurso = _executar().whenComplete(() => _emCurso = null);
  }

  Future<void> _executar() async {
    if (!_fonte.disponivel) {
      estado.value = EstadoPatch.indisponivel;
      return;
    }
    estado.value = EstadoPatch.verificando;
    try {
      patchAtual.value = await _fonte.patchAtual();
      switch (await _fonte.verificar()) {
        case UpdateStatus.upToDate:
          estado.value = EstadoPatch.emDia;
        case UpdateStatus.restartRequired:
          estado.value = EstadoPatch.prontoParaReiniciar;
        case UpdateStatus.unavailable:
          estado.value = EstadoPatch.indisponivel;
        case UpdateStatus.outdated:
          estado.value = EstadoPatch.baixando;
          await _fonte.baixar();
          estado.value = EstadoPatch.prontoParaReiniciar;
      }
    } catch (erro) {
      // Sem rede ou download interrompido: tenta de novo na próxima volta ao
      // app. O uso normal não é afetado.
      debugPrint('Atualização de código falhou: $erro');
      estado.value = EstadoPatch.falhou;
    }
  }

  void dispose() {
    estado.dispose();
    patchAtual.dispose();
  }
}
