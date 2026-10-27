import 'dart:typed_data';

/// Operações que a fila executa no servidor. A implementação real é
/// [RemotoSupabase]; os testes usam uma falsa, sem rede.
abstract class RemotoSync {
  /// Cria matéria, exercício e tentativa com os ids gerados no aparelho e,
  /// com [imagem], envia a foto para a R2. Repetir a chamada não duplica.
  Future<void> criarTentativa(
    String usuarioId,
    Map<String, Object?> dados,
    Uint8List? imagem,
  );

  /// Envia a foto de uma tentativa que ficou em 'uploading'.
  Future<void> enviarFoto(String tentativaId, Uint8List imagem);

  Future<void> editarExercicio(
    String usuarioId, {
    required String exercicioId,
    required String materiaIdAtual,
    required String materiaAtual,
    required String novaMateria,
    required String novoEnunciado,
  });

  Future<void> excluirExercicio(
    String usuarioId, {
    required String exercicioId,
    required String materiaId,
    String? tentativaId,
  });

  /// Pede a análise de IA. O pg_cron também pega tentativas 'pending', então
  /// uma falha aqui não perde nada.
  Future<void> analisar(String tentativaId);

  /// Consulta mínima para saber se o Supabase voltou a responder.
  Future<void> sondar();

  /// Assina as mudanças do usuário no Supabase Realtime e devolve a função
  /// que cancela a assinatura.
  void Function() ouvirAlteracoes(String usuarioId, void Function() aoMudar);
}
