import 'dart:convert';
import 'dart:typed_data';

import '../local/banco_local.dart';

/// Alteração feita sem rede, guardada em `fila_sync` até ser enviada.
class OperacaoFila {
  static const criarTentativa = 'criar_tentativa';
  static const enviarFoto = 'enviar_foto';
  static const editarExercicio = 'editar_exercicio';
  static const excluirExercicio = 'excluir_exercicio';

  final int? id;
  final String usuarioId;
  final String operacao;
  final Map<String, Object?> dados;
  final Uint8List? imagem;

  /// 'pendente' entra no próximo envio; 'erro' foi recusada pelo servidor e
  /// fica visível até o aluno excluir.
  final String situacao;
  final int tentativas;
  final String? ultimoErro;
  final DateTime criadoEm;

  const OperacaoFila({
    this.id,
    required this.usuarioId,
    required this.operacao,
    required this.dados,
    this.imagem,
    this.situacao = 'pendente',
    this.tentativas = 0,
    this.ultimoErro,
    required this.criadoEm,
  });

  String? get exercicioId => dados['exercise_id'] as String?;
  String? get tentativaId => dados['attempt_id'] as String?;
  bool get comErro => situacao == 'erro';

  Map<String, Object?> toMap() => {
    'id': ?id,
    'usuario_id': usuarioId,
    'operacao': operacao,
    'dados': jsonEncode(dados),
    'imagem': imagem,
    'situacao': situacao,
    'tentativas': tentativas,
    'ultimo_erro': ultimoErro,
    'criado_em': criadoEm.toUtc().toIso8601String(),
  };

  factory OperacaoFila.fromMap(Map<String, Object?> m) => OperacaoFila(
    id: m['id'] as int,
    usuarioId: m['usuario_id'] as String,
    operacao: m['operacao'] as String,
    dados: Map<String, Object?>.from(jsonDecode(m['dados'] as String) as Map),
    imagem: m['imagem'] as Uint8List?,
    situacao: m['situacao'] as String,
    tentativas: m['tentativas'] as int,
    ultimoErro: m['ultimo_erro'] as String?,
    criadoEm: DateTime.parse(m['criado_em'] as String),
  );
}

/// Acesso às tabelas `cache_consultas` e `fila_sync` (BancoLocal v2).
class ArmazemSync {
  ArmazemSync(this._banco);
  final BancoLocal _banco;

  Future<void> gravarCache(
    String usuarioId,
    String chave,
    Object? dados,
  ) async {
    final db = await _banco.banco;
    await db.rawInsert(
      'INSERT OR REPLACE INTO cache_consultas '
      '(usuario_id, chave, dados, atualizado_em) VALUES (?, ?, ?, ?)',
      [
        usuarioId,
        chave,
        jsonEncode(dados),
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  /// Última resposta guardada, ou null quando a tela nunca carregou online.
  Future<({Object? dados, DateTime quando})?> lerCache(
    String usuarioId,
    String chave,
  ) async {
    final db = await _banco.banco;
    final linhas = await db.query(
      'cache_consultas',
      columns: ['dados', 'atualizado_em'],
      where: 'usuario_id = ? AND chave = ?',
      whereArgs: [usuarioId, chave],
    );
    if (linhas.isEmpty) return null;
    return (
      dados: jsonDecode(linhas.first['dados'] as String),
      quando: DateTime.parse(linhas.first['atualizado_em'] as String),
    );
  }

  Future<int> enfileirar(OperacaoFila operacao) async {
    final db = await _banco.banco;
    final mapa = operacao.toMap()..remove('id');
    return db.insert('fila_sync', mapa);
  }

  /// Fila do usuário em ordem de criação. Sem [comImagem] as fotos não são
  /// lidas: as telas só precisam saber o que está pendente.
  Future<List<OperacaoFila>> fila(
    String usuarioId, {
    bool comImagem = false,
  }) async {
    final db = await _banco.banco;
    final linhas = await db.query(
      'fila_sync',
      columns: [
        'id',
        'usuario_id',
        'operacao',
        'dados',
        if (comImagem) 'imagem',
        'situacao',
        'tentativas',
        'ultimo_erro',
        'criado_em',
      ],
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
      orderBy: 'id',
    );
    return linhas.map(OperacaoFila.fromMap).toList(growable: false);
  }

  Future<void> atualizarDados(int id, Map<String, Object?> dados) async {
    final db = await _banco.banco;
    await db.update(
      'fila_sync',
      {'dados': jsonEncode(dados)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> registrarFalha(
    int id,
    String erro, {
    bool definitiva = false,
  }) async {
    final db = await _banco.banco;
    await db.rawUpdate(
      'UPDATE fila_sync SET tentativas = tentativas + 1, ultimo_erro = ?, '
      'situacao = ? WHERE id = ?',
      [erro, definitiva ? 'erro' : 'pendente', id],
    );
  }

  Future<void> remover(int id) async {
    final db = await _banco.banco;
    await db.delete('fila_sync', where: 'id = ?', whereArgs: [id]);
  }

  /// Valor guardado em `estado_sync` (cursores da leitura incremental).
  Future<String?> lerEstado(String usuarioId, String chave) async {
    final db = await _banco.banco;
    final linhas = await db.query(
      'estado_sync',
      columns: ['valor'],
      where: 'usuario_id = ? AND chave = ?',
      whereArgs: [usuarioId, chave],
    );
    return linhas.isEmpty ? null : linhas.first['valor'] as String;
  }

  Future<void> gravarEstado(
    String usuarioId,
    String chave,
    String valor,
  ) async {
    final db = await _banco.banco;
    await db.rawInsert(
      'INSERT OR REPLACE INTO estado_sync (usuario_id, chave, valor) '
      'VALUES (?, ?, ?)',
      [usuarioId, chave, valor],
    );
  }
}
