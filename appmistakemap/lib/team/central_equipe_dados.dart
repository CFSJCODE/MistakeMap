import 'package:supabase_flutter/supabase_flutter.dart';

/// Dados da Central da Equipe (app MistakeMap Equipe).
///
/// Tudo vem de funções do banco com checagem de papel (`is_team_member()`):
/// o app só lê agregados técnicos e nunca vê credencial, e-mail de aluno ou
/// conteúdo de exercício.
typedef DadosEquipe = Map<String, dynamic>;

DadosEquipe mapaEquipe(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<DadosEquipe> listaEquipe(Object? v) =>
    v is List ? [for (final item in v) mapaEquipe(item)] : <DadosEquipe>[];

int inteiroEquipe(Object? v) => switch (v) {
  int n => n,
  num n => n.round(),
  String s => int.tryParse(s) ?? 0,
  _ => 0,
};

DateTime? dataEquipe(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

/// Situação de um item de diagnóstico.
enum SituacaoCheck {
  ok,
  aviso,
  falha;

  static SituacaoCheck de(Object? v) => switch (v) {
    'ok' => ok,
    'warn' => aviso,
    _ => falha,
  };

  String get rotulo => switch (this) {
    ok => 'OK',
    aviso => 'Atenção',
    falha => 'Falhou',
  };
}

class CheckDiagnostico {
  const CheckDiagnostico({
    required this.id,
    required this.titulo,
    required this.situacao,
    required this.detalhe,
    this.origem = 'Servidor',
    this.duracao,
  });

  factory CheckDiagnostico.doServidor(DadosEquipe m) => CheckDiagnostico(
    id: m['id'] as String? ?? '?',
    titulo: m['title'] as String? ?? 'Verificação',
    situacao: SituacaoCheck.de(m['status']),
    detalhe: '${m['detail'] ?? ''}',
  );

  final String id;
  final String titulo;
  final SituacaoCheck situacao;
  final String detalhe;

  /// "Servidor" (função do banco) ou "App" (feito por este aparelho).
  final String origem;
  final Duration? duracao;
}

/// Resultado de uma rodada de diagnósticos, com resumo para colar num bug.
class RodadaDiagnostico {
  const RodadaDiagnostico({required this.quando, required this.itens});

  final DateTime quando;
  final List<CheckDiagnostico> itens;

  int conta(SituacaoCheck s) => itens.where((i) => i.situacao == s).length;

  SituacaoCheck get geral => conta(SituacaoCheck.falha) > 0
      ? SituacaoCheck.falha
      : conta(SituacaoCheck.aviso) > 0
      ? SituacaoCheck.aviso
      : SituacaoCheck.ok;

  /// Texto simples para o relatório de bug (área de transferência).
  String relatorio({String? cabecalho}) {
    final linhas = <String>[
      ?cabecalho,
      'Diagnóstico MistakeMap · ${quando.toIso8601String()}',
      'Resultado: ${geral.rotulo} (${conta(SituacaoCheck.ok)} ok, '
          '${conta(SituacaoCheck.aviso)} atenção, '
          '${conta(SituacaoCheck.falha)} falha)',
      for (final i in itens)
        '- [${i.situacao.rotulo}] ${i.origem}: ${i.titulo}: ${i.detalhe}'
            '${i.duracao == null ? '' : ' (${i.duracao!.inMilliseconds} ms)'}',
    ];
    return linhas.join('\n');
  }
}

/// Acesso ao backend da Central. Testes trocam por uma versão em memória.
abstract interface class RepositorioEquipe {
  /// Retrato do sistema (`team_console_snapshot`).
  Future<DadosEquipe> retrato();

  /// Verificações do servidor (`team_run_diagnostics`).
  Future<List<CheckDiagnostico>> diagnosticosServidor();

  /// Edge Function pública `health` (banco e R2).
  Future<DadosEquipe> saudeEdge();

  /// Grava um evento de teste no registro de erros.
  Future<void> registrarSonda();

  /// Recomeça os dados de estudo da própria conta de teste.
  Future<DadosEquipe> recomecarDadosDemo();

  /// Erros do app por versão e assinatura (`team_app_errors`).
  Future<DadosEquipe> errosApp({int horas = 72});

  /// Chama uma Edge Function com a sessão atual e devolve o status HTTP e o
  /// código de erro público, sem lançar exceção por status.
  Future<RespostaFuncao> chamarFuncao(
    String nome, {
    DadosEquipe corpo = const {},
    bool get = false,
  });

  /// Tenta ler uma tabela fechada com a sessão atual (sonda de segurança).
  Future<LeituraProtegida> tentarLer(String tabela);
}

/// Resposta de uma Edge Function no teste de fumaça.
class RespostaFuncao {
  const RespostaFuncao(this.status, {this.codigo});

  /// Status HTTP; 0 quando não houve resposta (rede, CORS ou tempo).
  final int status;

  /// Campo `error` do corpo, quando houver.
  final String? codigo;
}

/// Resultado de uma tentativa de leitura de tabela fechada.
class LeituraProtegida {
  const LeituraProtegida({required this.negada, this.linhas = 0, this.codigo});

  /// O banco recusou a leitura (permissão ou tabela fora da API).
  final bool negada;

  /// Linhas devolvidas quando a leitura passou.
  final int linhas;
  final String? codigo;

  /// Fechada de verdade: recusada ou sem nenhuma linha visível.
  bool get fechada => negada || linhas == 0;
}

/// Um caso do teste de fumaça das Edge Functions: uma chamada segura (sem
/// IA, sem cobrança, sem escrita) e os status que provam que a função está
/// no ar, autentica e valida a entrada.
class CasoFumaca {
  const CasoFumaca({
    required this.funcao,
    required this.descricao,
    required this.esperado,
    this.corpo = const {},
    this.get = false,
  });

  final String funcao;
  final String descricao;
  final Set<int> esperado;
  final DadosEquipe corpo;
  final bool get;
}

/// Ação que nenhuma função conhece: a resposta tem de ser 400
/// `invalid_action`, antes de qualquer acesso ao banco, à IA ou ao gateway.
const acaoDeTeste = 'qa_smoke_test';

const casosFumaca = <CasoFumaca>[
  CasoFumaca(
    funcao: 'health',
    descricao: 'Banco e R2 respondem',
    esperado: {200},
    get: true,
  ),
  CasoFumaca(
    funcao: 'review-queue',
    descricao: 'Painel de revisão da conta (só leitura)',
    esperado: {200},
    corpo: {'action': 'dashboard'},
  ),
  CasoFumaca(
    funcao: 'school-admin',
    descricao: 'Contexto de escola da conta (só leitura)',
    esperado: {200},
    corpo: {'action': 'context'},
  ),
  CasoFumaca(
    funcao: 'school-billing',
    descricao: 'Recusa ação desconhecida',
    esperado: {400},
    corpo: {'action': acaoDeTeste},
  ),
  CasoFumaca(
    funcao: 'question-bank',
    descricao: 'Recusa ação desconhecida',
    esperado: {400},
    corpo: {'action': acaoDeTeste},
  ),
  CasoFumaca(
    funcao: 'study-platform',
    descricao: 'Recusa ação desconhecida',
    esperado: {400},
    corpo: {'action': acaoDeTeste},
  ),
  CasoFumaca(
    funcao: 'study-material',
    descricao: 'Recusa ação desconhecida',
    esperado: {400},
    corpo: {'action': acaoDeTeste},
  ),
  CasoFumaca(
    funcao: 'account-data',
    descricao: 'Recusa quem não tem o segredo do cron',
    esperado: {401},
    corpo: {'action': acaoDeTeste},
  ),
  CasoFumaca(
    funcao: 'analyze-attempt',
    descricao: 'Recusa tentativa sem id (antes da IA)',
    esperado: {400},
  ),
  CasoFumaca(
    funcao: 'generate-practice',
    descricao: 'Recusa matéria sem id (antes da IA)',
    esperado: {400},
  ),
];

/// Tabelas que nenhuma conta, nem da equipe, lê pela API.
const tabelasFechadas = [
  'question_bank_keys',
  'team_error_events',
  'app_error_events',
  'ai_api_events',
];

/// Classifica uma resposta do teste de fumaça.
CheckDiagnostico avaliarFumaca(
  CasoFumaca caso,
  RespostaFuncao resposta,
  Duration duracao,
) {
  final ms = duracao.inMilliseconds;
  final codigo = resposta.codigo == null ? '' : ' (${resposta.codigo})';
  final SituacaoCheck situacao;
  final String detalhe;
  if (caso.esperado.contains(resposta.status)) {
    situacao = ms > 4000 ? SituacaoCheck.aviso : SituacaoCheck.ok;
    detalhe =
        'HTTP ${resposta.status}$codigo em $ms ms'
        '${ms > 4000 ? ': lenta' : ''}.';
  } else if (resposta.status == 0) {
    situacao = SituacaoCheck.falha;
    detalhe = 'Sem resposta (rede, CORS ou tempo esgotado).';
  } else if (resposta.status >= 500 || resposta.status == 401) {
    situacao = SituacaoCheck.falha;
    detalhe =
        'HTTP ${resposta.status}$codigo; esperado '
        '${caso.esperado.join(' ou ')}.';
  } else {
    situacao = SituacaoCheck.aviso;
    detalhe =
        'HTTP ${resposta.status}$codigo; esperado '
        '${caso.esperado.join(' ou ')}.';
  }
  return CheckDiagnostico(
    id: 'smoke_${caso.funcao}',
    titulo: '${caso.funcao}: ${caso.descricao}',
    situacao: situacao,
    detalhe: detalhe,
    origem: 'Deploy',
    duracao: duracao,
  );
}

/// Classifica uma sonda de leitura de tabela fechada.
CheckDiagnostico avaliarSonda(
  String tabela,
  LeituraProtegida leitura,
) => CheckDiagnostico(
  id: 'probe_$tabela',
  titulo: 'Leitura de $tabela bloqueada',
  situacao: leitura.fechada ? SituacaoCheck.ok : SituacaoCheck.falha,
  detalhe: leitura.negada
      ? 'Recusada pelo banco${leitura.codigo == null ? '' : ' (${leitura.codigo})'}.'
      : leitura.linhas == 0
      ? 'Nenhuma linha visível para esta conta.'
      : 'VAZOU: ${leitura.linhas} linha(s) visível(is) pela API.',
  origem: 'Segurança',
);

/// Valida um deploy sem custo: chama cada Edge Function de forma segura e
/// tenta ler as tabelas fechadas com a sessão do app.
Future<RodadaDiagnostico> validarDeploy(
  RepositorioEquipe repo, {
  DateTime Function() agora = DateTime.now,
}) async {
  final itens = await Future.wait([
    for (final caso in casosFumaca)
      () async {
        final relogio = Stopwatch()..start();
        RespostaFuncao resposta;
        try {
          resposta = await repo.chamarFuncao(
            caso.funcao,
            corpo: caso.corpo,
            get: caso.get,
          );
        } catch (_) {
          resposta = const RespostaFuncao(0);
        }
        relogio.stop();
        return avaliarFumaca(caso, resposta, relogio.elapsed);
      }(),
    for (final tabela in tabelasFechadas)
      () async {
        try {
          return avaliarSonda(tabela, await repo.tentarLer(tabela));
        } catch (_) {
          return avaliarSonda(tabela, const LeituraProtegida(negada: true));
        }
      }(),
  ]);
  return RodadaDiagnostico(quando: agora(), itens: itens);
}

/// Resumo dos erros do app vindos de `team_app_errors`.
class ResumoErrosApp {
  ResumoErrosApp(DadosEquipe m)
    : horas = inteiroEquipe(m['hours']),
      total = inteiroEquipe(m['total']),
      usuarios = inteiroEquipe(m['users']),
      fatais = inteiroEquipe(m['fatal']),
      porVersao = listaEquipe(m['by_version']),
      principais = listaEquipe(m['top']),
      recentes = listaEquipe(m['recent']);

  final int horas;
  final int total;
  final int usuarios;
  final int fatais;
  final List<DadosEquipe> porVersao;
  final List<DadosEquipe> principais;
  final List<DadosEquipe> recentes;

  /// "1.0.2+3 · patch 62" ou "1.0.2+3 · sem patch".
  static String rotuloVersao(DadosEquipe v) {
    final patch = v['patch'];
    return '${v['version']}+${inteiroEquipe(v['build'])} · '
        '${patch == null ? 'sem patch' : 'patch ${inteiroEquipe(patch)}'}';
  }

  /// Texto para colar num bug.
  String relatorio({String? cabecalho}) => [
    ?cabecalho,
    'Erros do app nas últimas $horas h: $total ($fatais fatal(is)), '
        '$usuarios conta(s)',
    for (final v in porVersao)
      '- ${v['app']} ${rotuloVersao(v)}: ${inteiroEquipe(v['n'])} erro(s), '
          '${inteiroEquipe(v['users'])} conta(s)',
    for (final t in principais)
      '* ${t['kind']} em ${t['location']}: ${inteiroEquipe(t['n'])}x '
          '(${(t['versions'] as List?)?.join(', ') ?? ''})',
  ].join('\n');
}

class FalhaEquipe implements Exception {
  const FalhaEquipe(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}

String mensagemFalhaEquipe(Object erro) {
  if (erro is FalhaEquipe) return erro.mensagem;
  if (erro is PostgrestException) {
    if (erro.code == '42501') {
      return erro.message.contains('only_test_accounts')
          ? 'Só contas de teste (@mistakemap.dev) podem recomeçar os dados.'
          : 'Esta conta não é da equipe (admin ou desenvolvedor).';
    }
    if (erro.code == 'PGRST202') {
      return 'A Central ainda não está no servidor. Aguarde o deploy das '
          'migrations.';
    }
  }
  return 'Não foi possível falar com o servidor. Confira a conexão.';
}

class RepositorioEquipeSupabase implements RepositorioEquipe {
  RepositorioEquipeSupabase(this.cliente);
  final SupabaseClient cliente;

  static const _limite = Duration(seconds: 20);

  @override
  Future<DadosEquipe> retrato() async =>
      mapaEquipe(await cliente.rpc('team_console_snapshot').timeout(_limite));

  @override
  Future<List<CheckDiagnostico>> diagnosticosServidor() async => [
    for (final item in listaEquipe(
      await cliente.rpc('team_run_diagnostics').timeout(_limite),
    ))
      CheckDiagnostico.doServidor(item),
  ];

  @override
  Future<DadosEquipe> saudeEdge() async {
    try {
      final resposta = await cliente.functions
          .invoke('health', method: HttpMethod.get)
          .timeout(_limite);
      return {...mapaEquipe(resposta.data), 'http': resposta.status};
    } on FunctionException catch (e) {
      // 503: a função respondeu, mas o banco ou o R2 está fora.
      return {...mapaEquipe(e.details), 'http': e.status};
    }
  }

  @override
  Future<void> registrarSonda() async =>
      cliente.rpc('team_log_probe').timeout(_limite);

  @override
  Future<DadosEquipe> recomecarDadosDemo() async => mapaEquipe(
    await cliente.rpc('team_reset_own_demo_data').timeout(_limite),
  );

  @override
  Future<DadosEquipe> errosApp({int horas = 72}) async => mapaEquipe(
    await cliente
        .rpc('team_app_errors', params: {'p_hours': horas})
        .timeout(_limite),
  );

  @override
  Future<RespostaFuncao> chamarFuncao(
    String nome, {
    DadosEquipe corpo = const {},
    bool get = false,
  }) async {
    try {
      final r = await cliente.functions
          .invoke(
            nome,
            method: get ? HttpMethod.get : HttpMethod.post,
            body: get ? null : corpo,
          )
          .timeout(_limite);
      return RespostaFuncao(r.status, codigo: _codigo(r.data));
    } on FunctionException catch (e) {
      return RespostaFuncao(e.status, codigo: _codigo(e.details));
    }
  }

  static String? _codigo(Object? corpo) {
    final erro = mapaEquipe(corpo)['error'];
    return erro is String ? erro : null;
  }

  @override
  Future<LeituraProtegida> tentarLer(String tabela) async {
    try {
      final linhas = await cliente
          .from(tabela)
          .select()
          .limit(1)
          .timeout(_limite);
      return LeituraProtegida(negada: false, linhas: linhas.length);
    } on PostgrestException catch (e) {
      return LeituraProtegida(negada: true, codigo: e.code);
    }
  }
}

/// Roda os diagnósticos: os do servidor e os feitos pelo próprio app
/// (sessão, latência do banco e Edge Function de saúde).
Future<RodadaDiagnostico> rodarDiagnosticos(
  RepositorioEquipe repo, {
  required bool sessaoValida,
  DateTime Function() agora = DateTime.now,
}) async {
  final itens = <CheckDiagnostico>[
    CheckDiagnostico(
      id: 'session',
      titulo: 'Sessão da conta',
      situacao: sessaoValida ? SituacaoCheck.ok : SituacaoCheck.falha,
      detalhe: sessaoValida
          ? 'Sessão ativa e dentro da validade.'
          : 'Sem sessão válida: entre de novo.',
      origem: 'App',
    ),
  ];

  final relogio = Stopwatch()..start();
  try {
    final servidor = await repo.diagnosticosServidor();
    relogio.stop();
    final ms = relogio.elapsedMilliseconds;
    itens.add(
      CheckDiagnostico(
        id: 'rpc_latency',
        titulo: 'Latência do banco (RPC)',
        situacao: ms < 1500
            ? SituacaoCheck.ok
            : ms < 4000
            ? SituacaoCheck.aviso
            : SituacaoCheck.falha,
        detalhe: 'Diagnóstico do servidor respondeu em $ms ms.',
        origem: 'App',
        duracao: relogio.elapsed,
      ),
    );
    itens.addAll(servidor);
  } catch (e) {
    itens.add(
      CheckDiagnostico(
        id: 'server',
        titulo: 'Diagnósticos do servidor',
        situacao: SituacaoCheck.falha,
        detalhe: mensagemFalhaEquipe(e),
        origem: 'App',
      ),
    );
  }

  final edge = Stopwatch()..start();
  try {
    final saude = await repo.saudeEdge();
    edge.stop();
    final http = inteiroEquipe(saude['http']);
    final db = saude['database'] == 'ok';
    final r2 = saude['r2'] == 'ok';
    itens.add(
      CheckDiagnostico(
        id: 'edge_health',
        titulo: 'Edge Functions (health)',
        situacao: http == 200 ? SituacaoCheck.ok : SituacaoCheck.falha,
        detalhe:
            'HTTP $http · banco ${db ? 'ok' : 'fora'} · '
            'R2 ${r2 ? 'ok' : 'fora'}.',
        origem: 'App',
        duracao: edge.elapsed,
      ),
    );
  } catch (e) {
    itens.add(
      CheckDiagnostico(
        id: 'edge_health',
        titulo: 'Edge Functions (health)',
        situacao: SituacaoCheck.falha,
        detalhe: 'Sem resposta da função health.',
        origem: 'App',
      ),
    );
  }

  return RodadaDiagnostico(quando: agora(), itens: itens);
}
