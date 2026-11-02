// Modelos do caderno de erros local (SQLite). Cada classe converte de/para o
// Map<String, Object?> que o sqflite usa em insert, update e query.

/// Classificação do erro, gravada como texto na coluna tipo_erro.
enum TipoErro {
  conceitual('Conceitual'),
  calculo('Cálculo'),
  interpretacao('Interpretação'),
  atencao('Atenção');

  const TipoErro(this.rotulo);

  final String rotulo;

  static TipoErro porNome(String? nome) => TipoErro.values.firstWhere(
    (t) => t.name == nome,
    orElse: () => TipoErro.conceitual,
  );
}

/// Linha da tabela disciplinas.
class Disciplina {
  const Disciplina({this.id, required this.usuarioId, required this.nome});

  final int? id;
  final String usuarioId;
  final String nome;

  factory Disciplina.fromMap(Map<String, Object?> mapa) => Disciplina(
    id: mapa['id'] as int?,
    usuarioId: mapa['usuario_id'] as String,
    nome: mapa['nome'] as String,
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'usuario_id': usuarioId,
    'nome': nome,
  };
}

/// Linha da tabela registros_erro, com o nome da disciplina vindo do JOIN.
class RegistroErro {
  const RegistroErro({
    this.id,
    this.uid,
    required this.usuarioId,
    required this.disciplina,
    required this.titulo,
    required this.descricao,
    required this.tipo,
    this.revisado = false,
    required this.criadoEm,
    required this.atualizadoEm,
  });

  final int? id;

  /// Id do registro no servidor (`error_notes.id`), igual em todos os
  /// aparelhos. Nulo antes da primeira gravação: o DAO gera um.
  final String? uid;
  final String usuarioId;
  final String disciplina;
  final String titulo;
  final String descricao;
  final TipoErro tipo;
  final bool revisado;
  final DateTime criadoEm;
  final DateTime atualizadoEm;

  factory RegistroErro.fromMap(Map<String, Object?> mapa) => RegistroErro(
    id: mapa['id'] as int?,
    uid: mapa['uid'] as String?,
    usuarioId: mapa['usuario_id'] as String,
    disciplina: mapa['disciplina'] as String? ?? '',
    titulo: mapa['titulo'] as String,
    descricao: mapa['descricao'] as String,
    tipo: TipoErro.porNome(mapa['tipo_erro'] as String?),
    // O SQLite não tem BOOLEAN: 0 = pendente, 1 = revisado.
    revisado: (mapa['revisado'] as int? ?? 0) == 1,
    criadoEm: DateTime.parse(mapa['criado_em'] as String),
    atualizadoEm: DateTime.parse(mapa['atualizado_em'] as String),
  );

  /// Colunas de registros_erro; disciplina_id é resolvido pelo DAO.
  Map<String, Object?> toMap({required int disciplinaId}) => {
    if (id != null) 'id': id,
    if (uid != null) 'uid': uid,
    'usuario_id': usuarioId,
    'disciplina_id': disciplinaId,
    'titulo': titulo,
    'descricao': descricao,
    'tipo_erro': tipo.name,
    'revisado': revisado ? 1 : 0,
    // Datas em ISO 8601 (TEXT) ordenam corretamente como texto.
    'criado_em': criadoEm.toIso8601String(),
    'atualizado_em': atualizadoEm.toIso8601String(),
  };

  RegistroErro copyWith({
    int? id,
    String? disciplina,
    String? titulo,
    String? descricao,
    TipoErro? tipo,
    bool? revisado,
    DateTime? atualizadoEm,
  }) => RegistroErro(
    id: id ?? this.id,
    uid: uid,
    usuarioId: usuarioId,
    disciplina: disciplina ?? this.disciplina,
    titulo: titulo ?? this.titulo,
    descricao: descricao ?? this.descricao,
    tipo: tipo ?? this.tipo,
    revisado: revisado ?? this.revisado,
    criadoEm: criadoEm,
    atualizadoEm: atualizadoEm ?? this.atualizadoEm,
  );
}
