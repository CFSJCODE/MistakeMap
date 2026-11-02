import 'dart:convert';
import 'dart:io';

import 'package:appmistakemap/atualizacao/atualizacao_codigo.dart';
import 'package:appmistakemap/atualizacao/versao_app.dart';
import 'package:appmistakemap/atualizacao/versao_nativa.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

class _FonteFalsa implements FontePatch {
  _FonteFalsa({
    this.disponivel = true,
    this.status = UpdateStatus.upToDate,
    this.patch,
    this.falhaNoDownload = false,
  });

  @override
  bool disponivel;
  UpdateStatus status;
  int? patch;
  bool falhaNoDownload;
  int consultas = 0;
  int downloads = 0;

  @override
  Future<int?> patchAtual() async => patch;

  @override
  Future<UpdateStatus> verificar() async {
    consultas++;
    return status;
  }

  @override
  Future<void> baixar() async {
    downloads++;
    if (falhaNoDownload) {
      throw const UpdateException(
        message: 'sem rede',
        reason: UpdateFailureReason.downloadFailed,
      );
    }
  }
}

Map<String, dynamic> _release({
  String tag = 'v1.1.0+2',
  bool draft = false,
  bool prerelease = false,
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': prerelease,
  'html_url': 'https://github.com/CFSJCODE/MistakeMap/releases/tag/$tag',
  'body': 'Novidades',
  'assets': [
    {
      'name': 'MistakeMap-1.1.0-android.apk',
      'browser_download_url': 'https://example.com/MistakeMap-1.1.0.apk',
    },
    {
      'name': 'MistakeMap-1.1.0-windows.zip',
      'browser_download_url': 'https://example.com/MistakeMap-1.1.0.zip',
    },
  ],
};

void main() {
  test('versão embutida casa com o pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final versao = RegExp(
      r'^version:\s*(\S+)\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec)!;
    expect(versaoApp, versao.group(1));
    expect(buildApp, int.parse(versao.group(2)!));
  });

  group('AtualizadorCodigo', () {
    test('baixa o patch novo e fica pronto para o próximo início', () async {
      final fonte = _FonteFalsa(status: UpdateStatus.outdated, patch: 3);
      final atualizador = AtualizadorCodigo(fonte: fonte);
      await atualizador.verificar();
      expect(fonte.downloads, 1);
      expect(atualizador.estado.value, EstadoPatch.prontoParaReiniciar);
      expect(atualizador.patchAtual.value, 3);

      // Já baixado: não consulta de novo até o app reabrir.
      await atualizador.verificar(forcar: true);
      expect(fonte.consultas, 1);
    });

    test('sem motor do Shorebird não consulta nada', () async {
      final fonte = _FonteFalsa(disponivel: false);
      final atualizador = AtualizadorCodigo(fonte: fonte);
      await atualizador.verificar();
      expect(fonte.consultas, 0);
      expect(atualizador.estado.value, EstadoPatch.indisponivel);
    });

    test('respeita o intervalo mínimo entre consultas', () async {
      var agora = DateTime(2026, 11, 2, 10);
      final fonte = _FonteFalsa();
      final atualizador = AtualizadorCodigo(fonte: fonte, relogio: () => agora);
      await atualizador.verificar();
      agora = agora.add(const Duration(minutes: 5));
      await atualizador.verificar();
      expect(fonte.consultas, 1);
      agora = agora.add(const Duration(minutes: 30));
      await atualizador.verificar();
      expect(fonte.consultas, 2);
      expect(atualizador.estado.value, EstadoPatch.emDia);
    });

    test('consultas simultâneas viram uma só', () async {
      final fonte = _FonteFalsa();
      final atualizador = AtualizadorCodigo(fonte: fonte);
      await Future.wait([
        atualizador.verificar(forcar: true),
        atualizador.verificar(forcar: true),
      ]);
      expect(fonte.consultas, 1);
    });

    test('falha no download não derruba o app', () async {
      final fonte = _FonteFalsa(
        status: UpdateStatus.outdated,
        falhaNoDownload: true,
      );
      final atualizador = AtualizadorCodigo(fonte: fonte);
      await atualizador.verificar();
      expect(atualizador.estado.value, EstadoPatch.falhou);
    });
  });

  group('interpretarRelease', () {
    test('lê versão, build e o arquivo da plataforma', () {
      final android = interpretarRelease(_release(), TargetPlatform.android)!;
      expect(android.versao, '1.1.0');
      expect(android.build, 2);
      expect(
        android.link.toString(),
        'https://example.com/MistakeMap-1.1.0.apk',
      );
      final windows = interpretarRelease(_release(), TargetPlatform.windows)!;
      expect(windows.link.path, endsWith('.zip'));
    });

    test('sem arquivo para a plataforma cai na página do release', () {
      final linux = interpretarRelease(_release(), TargetPlatform.linux)!;
      expect(linux.download, isNull);
      expect(linux.link.path, contains('/releases/tag/'));
    });

    test('ignora rascunho, pré-release e tag fora do formato', () {
      for (final json in [
        _release(draft: true),
        _release(prerelease: true),
        _release(tag: 'v1.1.0'),
        _release(tag: 'beta'),
      ]) {
        expect(interpretarRelease(json, TargetPlatform.android), isNull);
      }
    });
  });

  group('VerificadorVersaoNativa', () {
    VerificadorVersaoNativa verificador(http.Response resposta) =>
        VerificadorVersaoNativa(
          cliente: MockClient((_) async => resposta),
          buildInstalado: 1,
        );

    test('avisa quando o build publicado é mais novo', () async {
      final v = verificador(http.Response(jsonEncodeRelease(), 200));
      await v.verificar(TargetPlatform.android);
      expect(v.novaVersao.value?.versao, '1.1.0');
    });

    test('fica quieto com o mesmo build ou sem release', () async {
      final mesmo = VerificadorVersaoNativa(
        cliente: MockClient(
          (_) async => http.Response(jsonEncodeRelease(tag: 'v1.0.0+1'), 200),
        ),
        buildInstalado: 1,
      );
      await mesmo.verificar(TargetPlatform.android);
      expect(mesmo.novaVersao.value, isNull);

      final semRelease = verificador(http.Response('{}', 404));
      await semRelease.verificar(TargetPlatform.android);
      expect(semRelease.novaVersao.value, isNull);
    });

    test('erro de rede não lança', () async {
      final v = VerificadorVersaoNativa(
        cliente: MockClient((_) async => throw const SocketException('off')),
      );
      await v.verificar(TargetPlatform.windows);
      expect(v.novaVersao.value, isNull);
    });
  });
}

String jsonEncodeRelease({String tag = 'v1.1.0+2'}) =>
    jsonEncode(_release(tag: tag));
