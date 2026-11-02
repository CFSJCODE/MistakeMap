import 'dart:typed_data';

/// Mudança avisada pelo Supabase Realtime: a tabela e a linha nova.
class EventoRemoto {
  const EventoRemoto(this.tabela, [this.registro = const {}]);

  final String tabela;
  final Map<String, dynamic> registro;
}

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

  /// Grava notas do caderno (`error_notes`) com upsert pelo id. O servidor
  /// decide quem vence: exclusão é definitiva e edição mais velha que a
  /// gravada é ignorada, sem erro.
  Future<void> enviarNotas(List<Map<String, Object?>> notas);

  /// Notas do caderno do usuário, incluindo tombstones (`deleted_at`). Com
  /// [ids], só essas; com [desde], só as gravadas no servidor depois disso
  /// (`synced_at`), em ordem crescente.
  Future<List<Map<String, dynamic>>> buscarNotas(
    String usuarioId, {
    List<String>? ids,
    DateTime? desde,
    int limite = 200,
  });

  /// Exercícios e tentativas excluídos depois de [desde]
  /// (`deleted_records`: table_name, record_id, deleted_at).
  Future<List<Map<String, dynamic>>> exclusoesDesde(
    String usuarioId,
    DateTime desde,
  );

  /// Assina as mudanças do usuário no Supabase Realtime e devolve a função
  /// que cancela a assinatura.
  void Function() ouvirAlteracoes(
    String usuarioId,
    void Function(EventoRemoto evento) aoMudar,
  );
}
