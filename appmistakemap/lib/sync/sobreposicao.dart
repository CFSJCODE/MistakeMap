import 'armazem_sync.dart';

/// Status das tentativas que ainda estão só no aparelho.
const statusOffline = 'offline';

/// Tentativa da fila que o servidor recusou; espera o aluno excluir.
const statusRecusado = 'offline_recusado';

/// Prefixo do id de uma matéria criada sem rede (o Supabase ainda não deu id).
const prefixoMateriaLocal = 'local:';

Map<String, dynamic> _linha(Object? valor) =>
    Map<String, dynamic>.from(valor as Map);

/// Aplica a fila sobre as linhas que vieram do Supabase (ou do cache), no
/// mesmo formato do PostgREST: `subjects` = {id, name} e `exercises` =
/// {id, subject_id, prompt_text, created_at, attempts: [...]}. Assim a tela
/// mostra o que o aluno fez offline sem conhecer a fila.
({List<Map<String, dynamic>> materias, List<Map<String, dynamic>> exercicios})
sobreporExercicios(
  List<Object?> materias,
  List<Object?> exercicios,
  List<OperacaoFila> fila,
  String usuarioId,
) {
  final listaMaterias = materias.map(_linha).toList();
  final listaExercicios = exercicios.map(_linha).toList();
  final idPorNome = {
    for (final m in listaMaterias) m['name'] as String: m['id'] as String,
  };

  String materia(String nome) => idPorNome.putIfAbsent(nome, () {
    final id = '$prefixoMateriaLocal$nome';
    listaMaterias.add({'id': id, 'name': nome});
    return id;
  });

  for (final op in fila) {
    final d = op.dados;
    switch (op.operacao) {
      case OperacaoFila.criarTentativa:
        final tentativa = {
          'id': op.tentativaId,
          'status': op.comErro ? statusRecusado : statusOffline,
          'user_id': usuarioId,
          'attempted_at': d['criado_em'],
        };
        final existente = listaExercicios
            .where((e) => e['id'] == op.exercicioId)
            .firstOrNull;
        if (existente != null) {
          // Prática (ou criação já enviada em parte): só falta a tentativa.
          final tentativas = [...?(existente['attempts'] as List?)];
          if (!tentativas.any((t) => (t as Map)['id'] == op.tentativaId)) {
            existente['attempts'] = [...tentativas, tentativa];
          }
        } else {
          listaExercicios.insert(0, {
            'id': op.exercicioId,
            'subject_id': materia(d['subject'] as String),
            'prompt_text': d['prompt'],
            'created_at': d['criado_em'],
            'attempts': [tentativa],
          });
        }
      case OperacaoFila.editarExercicio:
        for (final e in listaExercicios) {
          if (e['id'] != op.exercicioId) continue;
          e['prompt_text'] = d['prompt'];
          e['subject_id'] = materia(d['subject'] as String);
        }
      case OperacaoFila.excluirExercicio:
        listaExercicios.removeWhere((e) => e['id'] == op.exercicioId);
    }
  }
  return (materias: listaMaterias, exercicios: listaExercicios);
}

/// Mesma ideia para a contagem do Início: linhas {status, exercise_id}.
List<Map<String, dynamic>> sobreporTentativas(
  List<Object?> tentativas,
  List<OperacaoFila> fila,
) {
  final excluidos = {
    for (final op in fila)
      if (op.operacao == OperacaoFila.excluirExercicio) op.exercicioId,
  };
  final ids = <Object?>{};
  final lista = <Map<String, dynamic>>[];
  for (final t in tentativas.map(_linha)) {
    if (excluidos.contains(t['exercise_id'])) continue;
    ids.add(t['id']);
    lista.add(t);
  }
  for (final op in fila) {
    if (op.operacao != OperacaoFila.criarTentativa) continue;
    if (ids.contains(op.tentativaId)) continue;
    lista.add({
      'id': op.tentativaId,
      'status': op.comErro ? statusRecusado : statusOffline,
      'exercise_id': op.exercicioId,
    });
  }
  return lista;
}
