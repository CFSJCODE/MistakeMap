import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'atualizacao_codigo.dart';
import 'versao_nativa.dart';

/// Orquestra as duas vias de atualização dos apps instalados:
///
/// 1. Patch de código (Shorebird): verifica ao abrir, ao voltar para o app e
///    ao ir para segundo plano; o download acontece em segundo plano e o
///    patch vale a partir do próximo início.
/// 2. Release nativo (GitHub Releases): quando o build publicado é mais novo
///    que o instalado, avisa e oferece o link do APK/ZIP.
///
/// A web não usa nada disto: cada deploy na Vercel já é a versão nova.
class ServicoAtualizacao {
  ServicoAtualizacao({
    AtualizadorCodigo? codigo,
    VerificadorVersaoNativa? nativa,
    this.intervaloPeriodico = const Duration(hours: 1),
  }) : codigo = codigo ?? AtualizadorCodigo(),
       nativa = nativa ?? VerificadorVersaoNativa();

  final AtualizadorCodigo codigo;
  final VerificadorVersaoNativa nativa;

  /// Verificação enquanto o app fica aberto por muito tempo (ex.: Windows).
  final Duration intervaloPeriodico;

  AppLifecycleListener? _ouvinte;
  Timer? _timer;

  /// Só Android e Windows recebem patches e releases nativos.
  static bool get suportado =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows);

  bool get iniciado => _ouvinte != null;

  /// Começa a observar o ciclo de vida. Chame depois do `runApp`.
  void iniciar() {
    if (!suportado || iniciado) return;
    _ouvinte = AppLifecycleListener(
      onResume: verificarAgora,
      // Indo para segundo plano: o download continua enquanto o sistema
      // mantiver o processo vivo, e o patch fica pronto para o próximo início.
      onPause: () => codigo.verificar(),
      onHide: () => codigo.verificar(),
    );
    _timer = Timer.periodic(intervaloPeriodico, (_) => verificarAgora());
    verificarAgora();
  }

  void verificarAgora() {
    unawaited(codigo.verificar());
    unawaited(nativa.verificar(defaultTargetPlatform));
  }

  void parar() {
    _ouvinte?.dispose();
    _ouvinte = null;
    _timer?.cancel();
    _timer = null;
  }
}

/// Instância única do app: o `main` inicia, as telas só leem os estados.
final atualizacoes = ServicoAtualizacao();
