import 'package:appmistakemap/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
