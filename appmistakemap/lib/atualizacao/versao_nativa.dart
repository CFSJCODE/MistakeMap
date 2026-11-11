import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
// O supabase_flutter já traz e registra este plugin nos alvos do app.
// ignore: depend_on_referenced_packages
import 'package:url_launcher/url_launcher.dart';

import '../auth/team_login.dart' show kTeamBuild;
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

/// Guarda o build cujo download já foi aberto neste aparelho, para o app não
/// pedir (nem deixar disparar sem querer) o mesmo arquivo de novo a cada
/// visita.
abstract class MemoriaDownload {
  Future<int?> ler();
  Future<void> gravar(int build);
}

class MemoriaDownloadPreferencias implements MemoriaDownload {
  const MemoriaDownloadPreferencias();

  static const _chave = 'atualizacao_download_build';

  // Sem o plugin a chamada pode nunca responder; o aviso não pode travar.
  static Future<SharedPreferences> _prefs() =>
      SharedPreferences.getInstance().timeout(const Duration(seconds: 2));

  @override
  Future<int?> ler() async {
    try {
      return (await _prefs()).getInt(_chave);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> gravar(int build) async {
    try {
      await (await _prefs()).setInt(_chave, build);
    } catch (_) {
      // Sem armazenamento: vale só nesta sessão.
    }
  }
}

/// Sufixo do arquivo de cada plataforma nos assets do release, no formato
/// gerado pelo workflow `shorebird-release.yml`.
const sufixosDownload = {
  TargetPlatform.android: '-android.apk',
  TargetPlatform.windows: '-windows.zip',
};

final _tag = RegExp(r'^v?(\d+\.\d+\.\d+)\+(\d+)$');

/// Tags do app MistakeMap Equipe (`team-app.yml`): `equipe-v1.0.2+3`,
/// publicadas como pré-release para o app dos alunos nunca as ver.
final _tagEquipe = RegExp(r'^equipe-v(\d+\.\d+\.\d+)\+(\d+)$');

/// Lê a resposta de `GET /repos/{dono}/{repo}/releases/latest`.
///
/// A tag precisa seguir `v<versão>+<build>` (ex.: `v1.1.0+2`), igual ao
/// `version:` do pubspec. Rascunhos, pré-releases e tags fora do formato são
/// ignorados.
///
/// Com [equipe], só valem as tags `equipe-v<versão>+<build>` do app da
/// equipe, que são pré-releases.
VersaoPublicada? interpretarRelease(
  Map<String, dynamic> json,
  TargetPlatform plataforma, {
  bool equipe = false,
}) {
  if (json['draft'] == true) return null;
  if (!equipe && json['prerelease'] == true) return null;
  final tag = json['tag_name'];
  final pagina = Uri.tryParse('${json['html_url'] ?? ''}');
  if (tag is! String || pagina == null || !pagina.hasScheme) return null;
  final partes = (equipe ? _tagEquipe : _tag).firstMatch(tag.trim());
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
    MemoriaDownload? memoria,
    Future<bool> Function(VersaoPublicada)? abrir,
    this.equipe = kTeamBuild,
  }) : _cliente = cliente ?? http.Client(),
       _endpoint = endpoint ?? (equipe ? endpointEquipe : endpointPadrao),
       _relogio = relogio ?? DateTime.now,
       _memoria = memoria ?? const MemoriaDownloadPreferencias(),
       _abrir = abrir ?? abrirVersaoPublicada;

  static final endpointPadrao = Uri.parse(
    'https://api.github.com/repos/CFSJCODE/MistakeMap/releases/latest',
  );

  /// O app da equipe procura o release `equipe-v…` mais novo na lista, porque
  /// pré-releases nunca são o `latest`.
  static final endpointEquipe = Uri.parse(
    'https://api.github.com/repos/CFSJCODE/MistakeMap/releases?per_page=30',
  );

  /// Verdadeiro no app MistakeMap Equipe: só vê os releases da equipe.
  final bool equipe;

  final http.Client _cliente;
  final Uri _endpoint;
  final DateTime Function() _relogio;
  final MemoriaDownload _memoria;
  final Future<bool> Function(VersaoPublicada) _abrir;
  final int buildInstalado;

  /// A API do GitHub sem login aceita 60 consultas por hora por IP; uma a
  /// cada poucas horas basta para um aviso de versão nova.
  final Duration intervaloMinimo;

  /// Release mais novo que o instalado, ou null se o app está em dia.
  final novaVersao = ValueNotifier<VersaoPublicada?>(null);

  /// Build cujo download já foi aberto neste aparelho (sobrevive ao app
  /// fechar). Com ele igual ao de [novaVersao], o arquivo já está baixado e
  /// falta só instalar.
  final downloadAberto = ValueNotifier<int?>(null);

  /// Verdadeiro enquanto o navegador está sendo chamado: toques repetidos no
  /// botão não abrem vários downloads.
  final abrindo = ValueNotifier<bool>(false);

  bool _memoriaLida = false;

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

  Future<void> _lerMemoria() async {
    if (_memoriaLida) return;
    _memoriaLida = true;
    final salvo = await _memoria.ler();
    // Um toque feito enquanto a leitura corria vale mais que o valor antigo.
    downloadAberto.value ??= salvo;
  }

  /// Abre o download da versão nova uma vez por toque, ignorando toques
  /// enquanto o navegador abre, e lembra que o arquivo já foi baixado.
  /// Retorna false só quando o navegador não abriu.
  Future<bool> baixar(VersaoPublicada versao) async {
    if (abrindo.value) return true;
    abrindo.value = true;
    try {
      final abriu = await _abrir(versao);
      if (abriu) {
        downloadAberto.value = versao.build;
        await _memoria.gravar(versao.build);
      }
      return abriu;
    } finally {
      abrindo.value = false;
    }
  }

  Future<void> _executar(TargetPlatform plataforma) async {
    await _lerMemoria();
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
      final release = switch (json) {
        Map<String, dynamic>() => interpretarRelease(
          json,
          plataforma,
          equipe: equipe,
        ),
        List() => _maisNovo(
          json.whereType<Map<String, dynamic>>().map(
            (r) => interpretarRelease(r, plataforma, equipe: equipe),
          ),
        ),
        _ => null,
      };
      novaVersao.value = release != null && release.build > buildInstalado
          ? release
          : null;
    } catch (erro) {
      debugPrint('Consulta de versão nativa falhou: $erro');
    }
  }

  static VersaoPublicada? _maisNovo(Iterable<VersaoPublicada?> releases) {
    VersaoPublicada? melhor;
    for (final r in releases.whereType<VersaoPublicada>()) {
      if (melhor == null || r.build > melhor.build) melhor = r;
    }
    return melhor;
  }

  void dispose() {
    novaVersao.dispose();
    downloadAberto.dispose();
    abrindo.dispose();
    _cliente.close();
  }
}
