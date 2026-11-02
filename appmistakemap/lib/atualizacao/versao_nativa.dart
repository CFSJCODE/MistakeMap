import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
// O supabase_flutter já traz e registra este plugin nos alvos do app.
// ignore: depend_on_referenced_packages
import 'package:url_launcher/url_launcher.dart';

import 'versao_app.dart';

/// Release nativo publicado no GitHub (APK do Android, ZIP do Windows).
@immutable
class VersaoPublicada {
  const VersaoPublicada({
    required this.versao,
    required this.build,
    required this.pagina,
    this.download,
    this.notas,
  });

  final String versao;
  final int build;

  /// Página do release, usada quando não há arquivo para esta plataforma.
  final Uri pagina;

  /// Arquivo para instalar nesta plataforma, se o release trouxer um.
  final Uri? download;
  final String? notas;

  Uri get link => download ?? pagina;
}

/// Abre o download (ou a página do release) fora do app.
Future<bool> abrirVersaoPublicada(VersaoPublicada versao) => launchUrl(
  versao.link,
  mode: LaunchMode.externalApplication,
  webOnlyWindowName: '_blank',
);

/// Sufixo do arquivo de cada plataforma nos assets do release, no formato
/// gerado pelo workflow `shorebird-release.yml`.
const sufixosDownload = {
  TargetPlatform.android: '-android.apk',
  TargetPlatform.windows: '-windows.zip',
};

final _tag = RegExp(r'^v?(\d+\.\d+\.\d+)\+(\d+)$');

/// Lê a resposta de `GET /repos/{dono}/{repo}/releases/latest`.
///
/// A tag precisa seguir `v<versão>+<build>` (ex.: `v1.1.0+2`), igual ao
/// `version:` do pubspec. Rascunhos, pré-releases e tags fora do formato são
/// ignorados.
VersaoPublicada? interpretarRelease(
  Map<String, dynamic> json,
  TargetPlatform plataforma,
) {
  if (json['draft'] == true || json['prerelease'] == true) return null;
  final tag = json['tag_name'];
  final pagina = Uri.tryParse('${json['html_url'] ?? ''}');
  if (tag is! String || pagina == null || !pagina.hasScheme) return null;
  final partes = _tag.firstMatch(tag.trim());
  if (partes == null) return null;

  Uri? download;
  final sufixo = sufixosDownload[plataforma];
  final assets = json['assets'];
  if (sufixo != null && assets is List) {
    for (final asset in assets.whereType<Map<String, dynamic>>()) {
      final nome = asset['name'];
      final url = asset['browser_download_url'];
      if (nome is String && url is String && nome.endsWith(sufixo)) {
        download = Uri.tryParse(url);
        break;
      }
    }
  }
  final notas = json['body'];
  return VersaoPublicada(
    versao: partes.group(1)!,
    build: int.parse(partes.group(2)!),
    pagina: pagina,
    download: download,
    notas: notas is String && notas.trim().isNotEmpty ? notas.trim() : null,
  );
}

/// Avisa quando há um release nativo mais novo que o instalado. Mudanças
/// nativas (plugins, AndroidManifest, versão do Flutter) não chegam por
/// patch e pedem instalar o arquivo novo.
class VerificadorVersaoNativa {
  VerificadorVersaoNativa({
    http.Client? cliente,
    Uri? endpoint,
    this.buildInstalado = buildApp,
    this.intervaloMinimo = const Duration(hours: 6),
    DateTime Function()? relogio,
  }) : _cliente = cliente ?? http.Client(),
       _endpoint = endpoint ?? endpointPadrao,
       _relogio = relogio ?? DateTime.now;

  static final endpointPadrao = Uri.parse(
    'https://api.github.com/repos/CFSJCODE/MistakeMap/releases/latest',
  );

  final http.Client _cliente;
  final Uri _endpoint;
  final DateTime Function() _relogio;
  final int buildInstalado;

  /// A API do GitHub sem login aceita 60 consultas por hora por IP; uma a
  /// cada poucas horas basta para um aviso de versão nova.
  final Duration intervaloMinimo;

  /// Release mais novo que o instalado, ou null se o app está em dia.
  final novaVersao = ValueNotifier<VersaoPublicada?>(null);

  DateTime? _ultimaConsulta;
  Future<void>? _emCurso;

  Future<void> verificar(TargetPlatform plataforma, {bool forcar = false}) {
    final emCurso = _emCurso;
    if (emCurso != null) return emCurso;
    final agora = _relogio();
    final ultima = _ultimaConsulta;
    if (!forcar &&
        ultima != null &&
        agora.difference(ultima) < intervaloMinimo) {
      return Future.value();
    }
    _ultimaConsulta = agora;
    return _emCurso = _executar(plataforma).whenComplete(() => _emCurso = null);
  }

  Future<void> _executar(TargetPlatform plataforma) async {
    try {
      final resposta = await _cliente
          .get(
            _endpoint,
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 15));
      // 404 = ainda não há release publicado.
      if (resposta.statusCode != 200) return;
      final json = jsonDecode(resposta.body);
      if (json is! Map<String, dynamic>) return;
      final release = interpretarRelease(json, plataforma);
      novaVersao.value = release != null && release.build > buildInstalado
          ? release
          : null;
    } catch (erro) {
      debugPrint('Consulta de versão nativa falhou: $erro');
    }
  }

  void dispose() {
    novaVersao.dispose();
    _cliente.close();
  }
}
