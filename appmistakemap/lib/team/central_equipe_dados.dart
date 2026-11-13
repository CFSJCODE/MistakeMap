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
