import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../ai/analysis_repository.dart';
import 'remoto_sync.dart';
import 'sobreposicao.dart' show prefixoMateriaLocal;

/// [RemotoSync] sobre o Supabase do app, com a sessão do próprio aluno (RLS).
class RemotoSupabase implements RemotoSync {
  RemotoSupabase(this.client, {SupabaseAnalysisRepository? analise})
    : _analise = analise ?? SupabaseAnalysisRepository(client);

  final SupabaseClient client;

  // Reaproveita o envio para a R2 e a análise que a tela de IA já usa.
  final SupabaseAnalysisRepository _analise;

  Future<String> _materia(String usuarioId, String nome) async {
    final existente = await client
        .from('subjects')
        .select('id')
        .eq('user_id', usuarioId)
        .eq('name', nome)
        .limit(1);
    if (existente.isNotEmpty) return existente.first['id'] as String;
    return (await client
            .from('subjects')
            .insert({'user_id': usuarioId, 'name': nome})
            .select('id')
            .single())['id']
        as String;
  }

  @override
  Future<void> criarTentativa(
    String usuarioId,
    Map<String, Object?> dados,
    Uint8List? imagem,
  ) async {
    final exercicioId = dados['exercise_id'] as String;
    final tentativaId = dados['attempt_id'] as String;
    final criadoEm = dados['criado_em'] as String;
    // Exercício de prática já existe no servidor; só a tentativa é nova.
    if (dados['pratica'] != true) {
      final materiaId = await _materia(usuarioId, dados['subject'] as String);
      await client.from('exercises').upsert({
        'id': exercicioId,
        'subject_id': materiaId,
        'prompt_text': dados['prompt'],
        'created_at': criadoEm,
      }, ignoreDuplicates: true);
    }
    final resposta = dados['answer'] as String;
    final dificuldade = (dados['difficulty'] as String? ?? '').trim();
    await client.from('attempts').upsert({
      'id': tentativaId,
      'exercise_id': exercicioId,
      'user_id': usuarioId,
      'answer': resposta,
      'solution_text': dificuldade.isEmpty
          ? resposta
          : '$resposta\n\nDificuldade relatada pelo aluno: $dificuldade',
      'status': imagem != null ? 'uploading' : 'pending',
      // A data real da tentativa, não a da reconexão: a recência pesa no
      // ranking do generate-practice.
      'attempted_at': criadoEm,
    }, ignoreDuplicates: true);
    if (imagem != null) await enviarFoto(tentativaId, imagem);
  }

  @override
  Future<void> enviarFoto(String tentativaId, Uint8List imagem) =>
      _analise.uploadImage(tentativaId, 'exercicio', imagem);

  @override
  Future<void> editarExercicio(
    String usuarioId, {
    required String exercicioId,
    required String materiaIdAtual,
    required String materiaAtual,
    required String novaMateria,
    required String novoEnunciado,
  }) async {
    String? materiaCriada;
    try {
      // O enunciado vai antes da matéria: se o banco recusar a edição
      // (guard_analyzed_exercise), nada novo foi criado ainda.
      await client
          .from('exercises')
          .update({'prompt_text': novoEnunciado})
          .eq('id', exercicioId);

      if (novaMateria == materiaAtual) return;
      final existente = await client
          .from('subjects')
          .select('id')
          .eq('user_id', usuarioId)
          .eq('name', novaMateria)
          .maybeSingle();

      final String novaMateriaId;
      if (existente != null) {
        novaMateriaId = existente['id'] as String;
      } else {
        materiaCriada =
            (await client
                    .from('subjects')
                    .insert({'user_id': usuarioId, 'name': novaMateria})
                    .select('id')
                    .single())['id']
                as String;
        novaMateriaId = materiaCriada;
      }

      await client
          .from('exercises')
          .update({'subject_id': novaMateriaId})
          .eq('id', exercicioId);
      // A matéria nova agora tem exercício: não pode mais ser desfeita.
      materiaCriada = null;
      await _apagarMateriaVazia(materiaIdAtual);
    } catch (_) {
      // practice_answer_keys também trava a matéria e o cliente não a lê:
      // desfaz a matéria recém-criada para ela não ficar órfã.
      if (materiaCriada != null) {
        try {
          await client.from('subjects').delete().eq('id', materiaCriada);
        } catch (_) {
          // Melhor esforço: o erro original é o que interessa ao usuário.
        }
      }
      rethrow;
    }
  }

  @override
  Future<void> excluirExercicio(
    String usuarioId, {
    required String exercicioId,
    required String materiaId,
    String? tentativaId,
  }) async {
    // Criação enviada em parte: a tela só conhecia a matéria pelo nome.
    if (materiaId.startsWith(prefixoMateriaLocal)) {
      final exercicio = await client
          .from('exercises')
          .select('subject_id')
          .eq('id', exercicioId)
          .maybeSingle();
      materiaId = exercicio?['subject_id'] as String? ?? '';
    }
    if (tentativaId != null) {
      await client
          .from('attempt_assets')
          .delete()
          .eq('attempt_id', tentativaId);
    }
    await client
        .from('attempts')
        .delete()
        .eq('exercise_id', exercicioId)
        .eq('user_id', usuarioId);
    await client.from('exercises').delete().eq('id', exercicioId);
    if (materiaId.isNotEmpty) await _apagarMateriaVazia(materiaId);
  }

  Future<void> _apagarMateriaVazia(String materiaId) async {
    final restantes = await client
        .from('exercises')
        .select('id')
        .eq('subject_id', materiaId);
    if (restantes.isEmpty) {
      await client.from('subjects').delete().eq('id', materiaId);
    }
  }

  @override
  Future<void> analisar(String tentativaId) => _analise.analyze(tentativaId);

  @override
  Future<void> sondar() async {
    await client.from('subjects').select('id').limit(1);
  }

  @override
  Future<void> enviarNotas(List<Map<String, Object?>> notas) async {
    if (notas.isEmpty) return;
    await client.from('error_notes').upsert(notas, onConflict: 'id');
  }

  @override
  Future<List<Map<String, dynamic>>> buscarNotas(
    String usuarioId, {
    List<String>? ids,
    DateTime? desde,
    int limite = 200,
  }) async {
    var consulta = client.from('error_notes').select().eq('user_id', usuarioId);
    if (ids != null) consulta = consulta.inFilter('id', ids);
    if (desde != null) {
      consulta = consulta.gt('synced_at', desde.toUtc().toIso8601String());
    }
    return await consulta.order('synced_at').limit(limite);
  }

  @override
  Future<List<Map<String, dynamic>>> exclusoesDesde(
    String usuarioId,
    DateTime desde,
  ) async => await client
      .from('deleted_records')
      .select('table_name, record_id, deleted_at')
      .eq('user_id', usuarioId)
      .gt('deleted_at', desde.toUtc().toIso8601String())
      .order('deleted_at')
      .limit(1000);

  @override
  void Function() ouvirAlteracoes(
    String usuarioId,
    void Function(EventoRemoto evento) aoMudar,
  ) {
    // Só INSERT e UPDATE: o Realtime não aplica RLS a eventos de DELETE. Por
    // isso as exclusões chegam como linha nova: o tombstone de error_notes
    // (UPDATE com deleted_at) e o registro em deleted_records (INSERT).
    final filtro = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'user_id',
      value: usuarioId,
    );
    var canal = client.channel('sync-$usuarioId');
    void assinar(String tabela, List<PostgresChangeEvent> eventos) {
      for (final evento in eventos) {
        canal = canal.onPostgresChanges(
          event: evento,
          schema: 'public',
          table: tabela,
          filter: filtro,
          callback: (mudanca) =>
              aoMudar(EventoRemoto(tabela, mudanca.newRecord)),
        );
      }
    }

    const gravacoes = [PostgresChangeEvent.insert, PostgresChangeEvent.update];
    for (final tabela in const [
      'subjects',
      'attempts',
      'attempt_analyses',
      'error_notes',
    ]) {
      assinar(tabela, gravacoes);
    }
    assinar('deleted_records', const [PostgresChangeEvent.insert]);
    canal.subscribe();
    return () => client.removeChannel(canal);
  }
}
