import 'dart:async';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Verdadeiro quando o erro veio da falta de rede (sem internet, DNS, tempo
/// esgotado), e não de uma recusa do servidor. Só esses casos caem no cache
/// local e na fila; um erro de RLS ou de validação continua sendo erro.
bool ehFalhaDeRede(Object erro) {
  if (erro is TimeoutException || erro is http.ClientException) return true;
  if (erro is AuthRetryableFetchException) return true;
  if (erro is FunctionException) return erro.status == 0;
  // dart:io não existe na Web; o nome do tipo basta para reconhecer.
  return const {
    'SocketException',
    'HandshakeException',
    'HttpException',
  }.contains(erro.runtimeType.toString());
}

final _aleatorio = Random.secure();

/// UUID v4 gerado no aparelho. Com o id definido antes do envio, reenviar a
/// mesma operação depois de uma queda não duplica a linha no Supabase.
String novoUuid() {
  final b = List<int>.generate(16, (_) => _aleatorio.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
