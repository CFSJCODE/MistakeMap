import 'package:appmistakemap/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Primeiros bytes (magic numbers) de cada formato.
const _jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
const _png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
// 'RIFF', tamanho do contêiner, 'WEBP'.
final _webp = [...'RIFF'.codeUnits, 0x24, 0, 0, 0, ...'WEBP'.codeUnits];
const _gif = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61];

// Espelha as regras de supabase/functions/upload-url/handler.ts e da política
// RLS attempt_assets_owner_insert (migração 20260929052429).
void main() {
  group('tipoMimeImagem', () {
    test('usa o Content-Type que a upload-url assina', () {
      expect(tipoMimeImagem('foto.jpg'), 'image/jpeg');
      expect(tipoMimeImagem('FOTO.JPEG'), 'image/jpeg');
      expect(tipoMimeImagem('scan.png'), 'image/png');
      expect(tipoMimeImagem('a.b.webp'), 'image/webp');
    });

    test('recorre ao mimeType quando o nome não tem extensão aceita', () {
      expect(tipoMimeImagem('blob', mimeType: 'image/png'), 'image/png');
      expect(tipoMimeImagem('blob', mimeType: 'image/heic'), isNull);
    });

    test('recusa formatos que o backend não aceita', () {
      expect(tipoMimeImagem('prova.pdf'), isNull);
      expect(tipoMimeImagem('foto.heic'), isNull);
      expect(tipoMimeImagem('sem_extensao'), isNull);
    });

    // O image_picker_android reencoda a foto e mantém o nome original.
    test('com bytes, a assinatura do arquivo decide o tipo', () {
      expect(tipoMimeImagem('scaled_x.heic', bytes: _jpeg), 'image/jpeg');
      expect(tipoMimeImagem('foto.jpg', bytes: _png), 'image/png');
      expect(tipoMimeImagem('blob', bytes: _webp), 'image/webp');
      expect(
        tipoMimeImagem('foto.png', mimeType: 'image/png', bytes: _gif),
        isNull,
      );
    });

    test('assinaturas incompletas não são aceitas', () {
      expect(tipoMimeImagem('a.png', bytes: _png.sublist(0, 4)), isNull);
      expect(tipoMimeImagem('a.jpg', bytes: _jpeg.sublist(0, 2)), isNull);
      // RIFF sem a marca WEBP (ex.: WAV) não é imagem.
      expect(
        tipoMimeImagem('a.webp', bytes: 'RIFF\x00\x00\x00\x00WAVE'.codeUnits),
        isNull,
      );
    });

    test('sem bytes, recorre ao nome do arquivo', () {
      expect(tipoMimeImagem('foto.jpg', bytes: const []), 'image/jpeg');
    });
  });

  group('pedidoDeUpload', () {
    test('monta o corpo esperado pela upload-url', () {
      expect(pedidoDeUpload('IMG_0001.JPG', 1024), {
        'filename': 'exercicio.jpg',
        'content_type': 'image/jpeg',
        'size_bytes': 1024,
      });
      expect(
        pedidoDeUpload('x.webp', kMaxBytesImagem)?['content_type'],
        'image/webp',
      );
    });

    test('não envia o nome original do arquivo', () {
      final pedido = pedidoDeUpload('Prova do João.png', 10)!;
      expect(pedido['filename'], 'exercicio.png');
    });

    test('JPEG com nome .heic vira exercicio.jpg em image/jpeg', () {
      expect(pedidoDeUpload('scaled_x.heic', _jpeg.length, bytes: _jpeg), {
        'filename': 'exercicio.jpg',
        'content_type': 'image/jpeg',
        'size_bytes': _jpeg.length,
      });
      // A extensão do nome sintético segue os bytes, não o nome original.
      expect(
        pedidoDeUpload('foto.jpg', _png.length, bytes: _png)?['filename'],
        'exercicio.png',
      );
      expect(pedidoDeUpload('foto.jpg', _gif.length, bytes: _gif), isNull);
    });

    test('recusa tamanho vazio, acima de 8 MB ou formato inválido', () {
      expect(pedidoDeUpload('a.jpg', 0), isNull);
      expect(pedidoDeUpload('a.jpg', kMaxBytesImagem + 1), isNull);
      expect(pedidoDeUpload('a.gif', 10), isNull);
    });
  });

  test('sha256Hex gera 64 caracteres hexadecimais minúsculos', () {
    final hash = sha256Hex('abc'.codeUnits);
    expect(
      hash,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash), isTrue);
  });

  group('mensagemDeErro', () {
    test('repassa a mensagem pública das Edge Functions', () {
      const erro = FunctionsHttpException(
        status: 400,
        details: {
          'error': 'invalid_upload',
          'message': 'Envie uma foto JPG, PNG ou WebP de até 8 MB.',
        },
      );
      expect(
        mensagemDeErro(erro),
        'Envie uma foto JPG, PNG ou WebP de até 8 MB.',
      );
    });

    test('traduz cota esgotada e falta de conexão', () {
      expect(
        mensagemDeErro(
          const FunctionsHttpException(
            status: 429,
            details: {'error': 'storage_quota_exceeded'},
          ),
        ),
        contains('limite de armazenamento'),
      );
      expect(
        mensagemDeErro(const FunctionsFetchException(details: 'offline')),
        contains('Sem conexão'),
      );
    });

    test('explica o bloqueio de edição após a análise', () {
      const erro = PostgrestException(
        message: 'create a new exercise to change a submitted prompt',
        code: '42501',
      );
      expect(mensagemDeErro(erro), contains('Registre um novo exercício'));
    });

    test('devolve null para erros desconhecidos', () {
      expect(mensagemDeErro(Exception('x')), isNull);
      expect(
        mensagemDeErro(const PostgrestException(message: 'x', code: '42501')),
        isNull,
      );
      expect(mensagemDeErro(const ErroDeEnvio('pronta')), 'pronta');
    });
  });
}
