import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../sync/sincronizador.dart';

/// Tipos de questão do banco (question_bank.kind no Supabase).
enum TipoQuestao {
  multiplaEscolha('multipla_escolha', 'Múltipla escolha'),
  multiplaSelecao('multipla_selecao', 'Várias corretas'),
  verdadeiroFalso('verdadeiro_falso', 'Verdadeiro ou falso'),
  numerica('numerica', 'Numérica'),
  lacuna('lacuna', 'Lacunas'),
  ordenacao('ordenacao', 'Ordenação'),
  associacao('associacao', 'Associação'),
  dissertativa('dissertativa', 'Dissertativa');

  const TipoQuestao(this.chave, this.rotulo);

  final String chave;
  final String rotulo;

  static TipoQuestao? daChave(Object? chave) {
    for (final t in values) {
      if (t.chave == chave) return t;
    }
    return null;
  }
}

const rotulosDificuldade = {
  'facil': 'Fácil',
  'media': 'Média',
  'dificil': 'Difícil',
};

/// Item público de uma questão: alternativa, afirmação, lacuna ou item.
class ItemQuestao {
  const ItemQuestao(this.id, this.texto);

  final String id;
  final String texto;

  static List<ItemQuestao> lista(Object? valor) => [
    for (final v in (valor is List ? valor : const []))
      if (v is Map) ItemQuestao('${v['id']}', '${v['text'] ?? ''}'),
  ];
}

/// Última resposta do aluno a uma questão (question_responses).
class RespostaSalva {
  const RespostaSalva({
    required this.correta,
    required this.nota,
    required this.quando,
  });

  /// Nulo enquanto a dissertativa espera a correção da IA.
  final bool? correta;
  final double? nota;
  final DateTime? quando;
}

/// Questão do banco sem gabarito: o servidor só entrega o que é público.
class Questao {
  const Questao({
    required this.id,
    required this.tipo,
    required this.materia,
    required this.assunto,
    required this.tema,
    required this.dificuldade,
    required this.enunciado,
    this.alternativas = const [],
    this.afirmacoes = const [],
    this.lacunas = const [],
    this.itens = const [],
    this.colunaA = const [],
    this.colunaB = const [],
    this.unidade = '',
    this.ultima,
  });

  final String id;
  final TipoQuestao tipo;
  final String materia;
  final String assunto;
  final String tema;
  final String dificuldade;
  final String enunciado;
  final List<ItemQuestao> alternativas;
  final List<ItemQuestao> afirmacoes;
  final List<ItemQuestao> lacunas;
  final List<ItemQuestao> itens;
  final List<ItemQuestao> colunaA;
  final List<ItemQuestao> colunaB;
  final String unidade;
  final RespostaSalva? ultima;

  static Questao? deJson(Map<String, dynamic> linha, [RespostaSalva? ultima]) {
    final tipo = TipoQuestao.daChave(linha['kind']);
    if (tipo == null) return null;
    final p = linha['payload'] is Map
        ? Map<String, dynamic>.from(linha['payload'] as Map)
        : const <String, dynamic>{};
    return Questao(
      id: '${linha['id']}',
      tipo: tipo,
      materia: '${linha['subject'] ?? ''}',
      assunto: '${linha['topic'] ?? ''}',
      tema: '${linha['theme'] ?? ''}',
      dificuldade: '${linha['difficulty'] ?? ''}',
      enunciado: '${linha['prompt_text'] ?? ''}',
      alternativas: ItemQuestao.lista(p['options']),
      afirmacoes: ItemQuestao.lista(p['statements']),
      lacunas: ItemQuestao.lista(p['blanks']),
      itens: ItemQuestao.lista(p['items']),
      colunaA: ItemQuestao.lista(p['left']),
      colunaB: ItemQuestao.lista(p['right']),
      unidade: '${p['unit'] ?? ''}',
      ultima: ultima,
    );
  }
}

/// Hipótese de causa do erro, como na análise da IA.
class DiagnosticoQuestao {
  const DiagnosticoQuestao(this.categoria, this.explicacao);

  final String categoria;
  final String explicacao;
}

/// Resultado devolvido pela Edge Function question-bank.
class CorrecaoQuestao {
  const CorrecaoQuestao({
    required this.situacao,
    this.correta,
    this.nota,
    this.itens = const {},
    this.respostaCorreta = '',
    this.explicacao = '',
    this.diagnosticos = const [],
    this.mensagem = '',
  });

  /// `graded` (corrigida), `pending` ou `processing` (dissertativa na IA).
  final String situacao;
  final bool? correta;
  final double? nota;

  /// Acerto item a item (alternativa, afirmação, lacuna, posição ou par).
  final Map<String, bool> itens;
  final String respostaCorreta;
  final String explicacao;
  final List<DiagnosticoQuestao> diagnosticos;
  final String mensagem;

  bool get corrigida => situacao == 'graded' && correta != null;

  factory CorrecaoQuestao.deJson(Map<String, dynamic> j) => CorrecaoQuestao(
    situacao: '${j['status'] ?? ''}',
    correta: j['is_correct'] is bool ? j['is_correct'] as bool : null,
    nota: j['score'] is num ? (j['score'] as num).toDouble() : null,
    itens: {
      for (final i in (j['items'] is List ? j['items'] as List : const []))
        if (i is Map) '${i['id']}': i['correct'] == true,
    },
    respostaCorreta: '${j['correct_answer'] ?? ''}',
    explicacao: '${j['explanation'] ?? ''}',
    diagnosticos: [
      for (final d
          in (j['diagnoses'] is List ? j['diagnoses'] as List : const []))
        if (d is Map)
          DiagnosticoQuestao(
            '${d['category'] ?? ''}',
            '${d['feedback'] ?? ''}',
          ),
    ],
    mensagem: '${j['message'] ?? ''}',
  );
}

class FalhaQuestao implements Exception {
  const FalhaQuestao(this.mensagem);

  final String mensagem;

  @override
  String toString() => mensagem;
}

abstract class RepositorioQuestoes {
  Future<List<Questao>> carregar(String usuarioId);

  /// [resposta] segue o formato de cada tipo (ver [respostaPara]).
  Future<CorrecaoQuestao> responder(
    String questaoId,
    Map<String, dynamic> resposta,
  );
}

/// Leitura direta (questões públicas + respostas do próprio aluno, sob RLS);
/// a correção é sempre da Edge Function, que guarda o gabarito.
class RepositorioQuestoesSupabase implements RepositorioQuestoes {
  RepositorioQuestoesSupabase(
    this.client, {
    Sincronizador? sincronizador,
    this.tarefaId,
  }) : _sync = sincronizador;

  final SupabaseClient client;
  final Sincronizador? _sync;

  /// Tarefa da turma sendo respondida (nulo na prática livre). O servidor
  /// confere se a questão é da tarefa e se o aluno é da turma.
  final String? tarefaId;

  Sincronizador get _sincronizador => _sync ?? Sincronizador.instancia;

  @override
  Future<List<Questao>> carregar(String usuarioId) async {
    final dados = await _sincronizador.consultar(
      usuarioId,
      'banco_questoes_v1',
      () async {
        final questoes = await client
            .from('question_bank')
            .select(
              'id,kind,subject,topic,theme,difficulty,prompt_text,payload,position',
            )
            .order('position');
        final respostas = await client
            .from('question_responses')
            .select('question_id,is_correct,score,created_at')
            .eq('user_id', usuarioId)
            .order('created_at', ascending: false)
            .limit(1000);
        return {'questoes': questoes, 'respostas': respostas};
      },
    );
    final mapa = dados is Map ? dados : const {};
    final ultimas = <String, RespostaSalva>{};
    for (final r
        in (mapa['respostas'] is List ? mapa['respostas'] as List : const [])) {
      if (r is! Map) continue;
      // Ordenado do mais recente: a primeira de cada questão é a última.
      ultimas.putIfAbsent(
        '${r['question_id']}',
        () => RespostaSalva(
          correta: r['is_correct'] is bool ? r['is_correct'] as bool : null,
          nota: r['score'] is num ? (r['score'] as num).toDouble() : null,
          quando: DateTime.tryParse('${r['created_at'] ?? ''}'),
        ),
      );
    }
    return [
      for (final q
          in (mapa['questoes'] is List ? mapa['questoes'] as List : const []))
        if (q is Map)
          ?Questao.deJson(Map<String, dynamic>.from(q), ultimas['${q['id']}']),
    ];
  }

  @override
  Future<CorrecaoQuestao> responder(
    String questaoId,
    Map<String, dynamic> resposta,
  ) async {
    if (!_sincronizador.online.value || _sincronizador.semSessao) {
      throw const FalhaQuestao(
        'A correção é feita no servidor e precisa de internet. Conecte-se e '
        'envie de novo.',
      );
    }
    try {
      final r = await client.functions
          .invoke(
            'question-bank',
            body: {
              'action': 'answer',
              'question_id': questaoId,
              'response': resposta,
              'assignment_id': ?tarefaId,
            },
          )
          .timeout(const Duration(seconds: 120));
      if (r.status >= 400) throw FalhaQuestao(_mensagem(r.data));
      return CorrecaoQuestao.deJson(
        r.data is Map ? Map<String, dynamic>.from(r.data as Map) : const {},
      );
    } on FunctionException catch (e) {
      throw FalhaQuestao(
        e.status == 0
            ? 'Sem conexão com o servidor. Tente de novo.'
            : _mensagem(e.details),
      );
    } on TimeoutException {
      throw const FalhaQuestao(
        'A correção está demorando. Sua resposta pode ter sido salva; '
        'atualize a lista antes de enviar de novo.',
      );
    }
  }

  String _mensagem(Object? dados) {
    if (dados is Map && dados['message'] is String) {
      return dados['message'] as String;
    }
    return 'Não foi possível corrigir agora. Tente de novo.';
  }
}

/// Monta o corpo da resposta no formato que o servidor espera para o tipo.
/// Só organiza o que o aluno marcou; quem decide se está certo é o servidor.
Map<String, dynamic> respostaPara(
  TipoQuestao tipo, {
  String? escolha,
  Set<String> escolhas = const {},
  Map<String, bool> verdadeiroFalso = const {},
  String numero = '',
  Map<String, String> lacunas = const {},
  List<String> ordem = const [],
  Map<String, String> pares = const {},
  String texto = '',
}) => switch (tipo) {
  TipoQuestao.multiplaEscolha => {'choice': escolha},
  TipoQuestao.multiplaSelecao => {'choices': escolhas.toList()},
  TipoQuestao.verdadeiroFalso => {'answers': verdadeiroFalso},
  TipoQuestao.numerica => {'value': numero.trim()},
  TipoQuestao.lacuna => {
    'blanks': {
      for (final e in lacunas.entries)
        if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
    },
  },
  TipoQuestao.ordenacao => {'order': ordem},
  TipoQuestao.associacao => {'pairs': pares},
  TipoQuestao.dissertativa => {'text': texto.trim()},
};

/// Questões de uma tarefa, na ordem definida pelo professor. Ignora as que
/// não estão mais no banco.
List<Questao> questoesDaTarefa(List<Questao> banco, List<String> ids) {
  final porId = {for (final q in banco) q.id: q};
  return [for (final id in ids) ?porId[id]];
}
