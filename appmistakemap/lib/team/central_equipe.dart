import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';

import '../school/escola_ui.dart';
import '../theme/control_styles.dart';
import '../theme/design_tokens.dart';
import 'central_equipe_dados.dart';

// ─── Central da Equipe ───────────────────────────────────────────────────────
// Só no app MistakeMap Equipe (admin e desenvolvedor). Mostra o trabalho de
// quem mantém o MistakeMap: saúde do sistema, erros do backend, diagnósticos
// de ponta a ponta, ferramentas de QA e a identidade da build instalada. O
// papel é conferido no servidor em cada chamada.

/// O que identifica a build instalada (vem do main, sem depender do
/// serviço de atualização aqui dentro).
class InfoBuild {
  const InfoBuild({
    required this.versao,
    required this.build,
    required this.equipe,
    required this.release,
    required this.plataforma,
    required this.servidor,
    this.patch,
  });

  final String versao;
  final int build;
  final bool equipe;
  final bool release;
  final String plataforma;
  final String servidor;
  final ValueListenable<int?>? patch;

  String texto() {
    final p = patch?.value;
    return [
      'App: ${equipe ? 'MistakeMap Equipe' : 'MistakeMap'}',
      'Versão: $versao (build $build)${p == null ? '' : ' · patch $p'}',
      'Modo: ${release ? 'release' : 'debug'}',
      'Plataforma: $plataforma',
      'Servidor: $servidor',
    ].join('\n');
  }
}

enum SecaoEquipe {
  saude('Saúde', WindowsIcons.health),
  erros('Erros', WindowsIcons.bug),
  diagnostico('Diagnóstico', WindowsIcons.diagnostic),
  ferramentas('Ferramentas de QA', WindowsIcons.developer_tools),
  build('Build', WindowsIcons.code);

  const SecaoEquipe(this.rotulo, this.icone);
  final String rotulo;
  final IconData icone;
}

class CentralEquipe extends StatefulWidget {
  const CentralEquipe({
    super.key,
    required this.repositorio,
    required this.info,
    required this.papel,
    required this.email,
    required this.sessaoValida,
    this.active = true,
    this.onAbrirAdministracao,
    this.onVoltarAosPerfis,
  });

  final RepositorioEquipe repositorio;
  final InfoBuild info;

  /// `admin` ou `developer`.
  final String papel;
  final String email;
  final bool Function() sessaoValida;
  final bool active;
  final VoidCallback? onAbrirAdministracao;
  final VoidCallback? onVoltarAosPerfis;

  @override
  State<CentralEquipe> createState() => _CentralEquipeState();
}

class _CentralEquipeState extends State<CentralEquipe> {
  SecaoEquipe _secao = SecaoEquipe.saude;
  DadosEquipe? _retrato;
  String? _erro;
  bool _carregando = false;
  RodadaDiagnostico? _rodada;
  bool _diagnosticando = false;
  String? _avisoQa;
  bool _avisoQaOk = true;
  bool _qaOcupado = false;
  Timer? _relogio;

  bool get _contaDeTeste => widget.email.endsWith('@mistakemap.dev');

  @override
  void initState() {
    super.initState();
    if (widget.active) _carregar();
    // Atualiza sozinha a cada minuto enquanto a aba está à vista.
    _relogio = Timer.periodic(const Duration(minutes: 1), (_) {
      if (widget.active && mounted) _carregar(silencioso: true);
    });
  }

  @override
  void didUpdateWidget(CentralEquipe antigo) {
    super.didUpdateWidget(antigo);
    if (widget.active && !antigo.active) _carregar(silencioso: true);
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  Future<void> _carregar({bool silencioso = false}) async {
    if (_carregando) return;
    setState(() {
      _carregando = true;
      if (!silencioso) _erro = null;
    });
    try {
      final retrato = await widget.repositorio.retrato();
      if (!mounted) return;
      setState(() {
        _retrato = retrato;
        _erro = null;
      });
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemFalhaEquipe(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _diagnosticar() async {
    setState(() => _diagnosticando = true);
    final rodada = await rodarDiagnosticos(
      widget.repositorio,
      sessaoValida: widget.sessaoValida(),
    );
    if (!mounted) return;
    setState(() {
      _rodada = rodada;
      _diagnosticando = false;
    });
  }

  Future<void> _copiar(String texto, String aviso) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    setState(() {
      _avisoQa = aviso;
      _avisoQaOk = true;
    });
  }

  Future<void> _qa(Future<String> Function() acao) async {
    setState(() {
      _qaOcupado = true;
      _avisoQa = null;
    });
    try {
      final msg = await acao();
      if (mounted) {
        setState(() {
          _avisoQa = msg;
          _avisoQaOk = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _avisoQa = mensagemFalhaEquipe(e);
          _avisoQaOk = false;
        });
      }
    } finally {
      if (mounted) setState(() => _qaOcupado = false);
    }
  }

  Future<void> _sonda() => _qa(() async {
    await widget.repositorio.registrarSonda();
    await _carregar(silencioso: true);
    return 'Evento de teste gravado. Ele aparece em Erros como qa_probe.';
  });

  Future<void> _recomecar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Recomeçar os dados desta conta?'),
        content: const Text(
          'Apaga os exercícios, tentativas e análises desta conta de teste, '
          'arquiva o caderno e cria de novo os exercícios de exemplo. Escolas, '
          'turmas e cobrança não mudam.',
        ),
        actions: [
          Button(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          FilledButton(
            child: const Text('Recomeçar'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _qa(() async {
      final r = await widget.repositorio.recomecarDadosDemo();
      await _carregar(silencioso: true);
      return '${inteiroEquipe(r['exercises_removed'])} exercício(s) '
          'removido(s), ${inteiroEquipe(r['notes_archived'])} nota(s) do '
          'caderno arquivada(s), ${inteiroEquipe(r['examples_created'])} '
          'exemplo(s) criado(s). Recarregue as abas para ver.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in SecaoEquipe.values)
              Semantics(
                selected: _secao == s,
                child: MistakeMapButton(
                  key: ValueKey('equipe-secao-${s.name}'),
                  style: MistakeMapControls.button(
                    background: _secao == s ? MistakeMapDesign.aqua : null,
                    foreground: _secao == s ? MistakeMapDesign.abyss : null,
                  ),
                  onPressed: () => setState(() => _secao = s),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(s.icone, size: 16),
                      const SizedBox(width: 8),
                      Text(s.rotulo),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: switch (_secao) {
              SecaoEquipe.saude => _saude(),
              SecaoEquipe.erros => _erros(),
              SecaoEquipe.diagnostico => _diagnostico(),
              SecaoEquipe.ferramentas => _ferramentas(),
              SecaoEquipe.build => _build(),
            },
          ),
        ),
      ],
    );
  }

  // ─── Estado de carga comum ────────────────────────────────────────────────
  List<Widget> _cabecalhoCarga(String titulo) {
    final capturado = dataEquipe(_retrato?['captured_at']);
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              capturado == null
                  ? titulo
                  : '$titulo · atualizado às ${_hora(capturado)}',
              style: const TextStyle(color: MistakeMapDesign.steel),
            ),
          ),
          if (_carregando)
            const SizedBox(width: 20, height: 20, child: ProgressRing())
          else
            Tooltip(
              message: 'Atualizar',
              child: IconButton(
                key: const ValueKey('equipe-atualizar'),
                icon: const Icon(WindowsIcons.refresh, size: 18),
                onPressed: _carregar,
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (_erro != null) AvisoEscola(_erro!),
    ];
  }

  // ─── Saúde ──────────────────────────────────────────────────────────────
  List<Widget> _saude() {
    final r = _retrato;
    if (r == null) {
      return [
        ..._cabecalhoCarga('Saúde do sistema'),
        if (_erro == null) const Center(child: ProgressRing()),
      ];
    }
    final uso = mapaEquipe(r['usage']);
    final ia = mapaEquipe(r['ai']);
    final fila = mapaEquipe(r['pipeline']);
    final banco = mapaEquipe(r['database']);
    final cobranca = mapaEquipe(r['billing']);
    final cron = listaEquipe(r['cron']);
    final papeis = mapaEquipe(uso['profiles_by_role']);
    final pedidos = mapaEquipe(ia['requests_today']);
    final cronFalhas = cron.fold<int>(
      0,
      (s, j) => s + inteiroEquipe(j['failures_24h']),
    );
    final erros24 = inteiroEquipe(mapaEquipe(r['errors'])['total_24h']);

    return [
      ..._cabecalhoCarga('Saúde do sistema'),
      CartaoEscola(
        titulo: 'Semáforo',
        subtitulo: 'Resumo do que precisa de atenção agora.',
        children: [
          _Semaforo(
            itens: [
              (
                'Rotinas agendadas',
                cronFalhas == 0
                    ? SituacaoCheck.ok
                    : cronFalhas < 3
                    ? SituacaoCheck.aviso
                    : SituacaoCheck.falha,
                '$cronFalhas falha(s) em 24 h',
              ),
              (
                'Erros do backend',
                erros24 == 0
                    ? SituacaoCheck.ok
                    : erros24 < 10
                    ? SituacaoCheck.aviso
                    : SituacaoCheck.falha,
                '$erros24 em 24 h',
              ),
              (
                'Fila de análises',
                inteiroEquipe(fila['failures_24h']) == 0
                    ? SituacaoCheck.ok
                    : SituacaoCheck.aviso,
                '${inteiroEquipe(fila['failures_24h'])} falha(s) em 24 h',
              ),
              (
                'Exclusões de conta',
                inteiroEquipe(banco['deletion_jobs_pending']) == 0
                    ? SituacaoCheck.ok
                    : SituacaoCheck.aviso,
                '${inteiroEquipe(banco['deletion_jobs_pending'])} pendente(s)',
              ),
            ],
          ),
        ],
      ),
      CartaoEscola(
        titulo: 'Uso',
        subtitulo: 'Contas e atividade de estudo (sem dados pessoais).',
        children: [
          _Numeros(
            itens: [
              ('Contas', inteiroEquipe(uso['profiles'])),
              ('Novas em 7 dias', inteiroEquipe(uso['new_profiles_7d'])),
              ('Ativas em 24 h', inteiroEquipe(uso['active_users_24h'])),
              ('Ativas em 7 dias', inteiroEquipe(uso['active_users_7d'])),
              ('Tentativas em 7 dias', inteiroEquipe(uso['attempts_7d'])),
              ('Análises em 7 dias', inteiroEquipe(uso['analyses_7d'])),
              (
                'Respostas do banco (7 d)',
                inteiroEquipe(uso['question_responses_7d']),
              ),
              (
                'Sessões de estudo (7 d)',
                inteiroEquipe(uso['study_sessions_7d']),
              ),
              ('Exercícios', inteiroEquipe(uso['exercises'])),
              ('Notas no caderno', inteiroEquipe(uso['error_notes'])),
              ('Escolas', inteiroEquipe(uso['schools'])),
              ('Membros de escola', inteiroEquipe(uso['school_members'])),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Papéis: ${inteiroEquipe(papeis['admin'])} admin · '
            '${inteiroEquipe(papeis['developer'])} desenvolvedor · '
            '${inteiroEquipe(papeis['user'])} usuário',
            style: const TextStyle(color: MistakeMapDesign.steel),
          ),
        ],
      ),
      CartaoEscola(
        titulo: 'Inteligência artificial',
        subtitulo:
            'Modelos usados nas análises e chamadas às APIs (o roteador '
            'escolhe o modelo por tarefa).',
        children: [
          _Linha(
            'Pedidos hoje',
            pedidos.isEmpty
                ? 'nenhum'
                : pedidos.entries
                      .map((e) => '${e.key}: ${inteiroEquipe(e.value)}')
                      .join(' · '),
          ),
          _Linha('Última análise', _quando(dataEquipe(ia['last_analysis_at']))),
          _Linha('Último modelo', '${ia['last_model'] ?? '—'}'),
          const SizedBox(height: 8),
          for (final m in listaEquipe(ia['models_7d']))
            _Linha(
              '${m['model']}',
              '${inteiroEquipe(m['analyses'])} análise(s) em 7 dias',
            ),
          for (final a in listaEquipe(ia['api_24h']))
            _Linha(
              'API ${a['model']}',
              '${inteiroEquipe(a['calls'])} chamada(s) · '
                  '${inteiroEquipe(a['failures'])} falha(s) · '
                  '${inteiroEquipe(a['throttled'])} limite · '
                  'mediana ${inteiroEquipe(a['median_ms'])} ms',
            ),
        ],
      ),
      CartaoEscola(
        titulo: 'Rotinas agendadas (pg_cron)',
        subtitulo: 'Cada job, a última execução e as falhas em 24 horas.',
        children: [
          for (final j in cron)
            _LinhaSituacao(
              situacao: j['active'] != true
                  ? SituacaoCheck.aviso
                  : inteiroEquipe(j['failures_24h']) > 0 ||
                        j['last_status'] == 'failed'
                  ? SituacaoCheck.falha
                  : SituacaoCheck.ok,
              titulo: '${j['jobname']}',
              detalhe:
                  '${j['schedule']} · última: '
                  '${_quando(dataEquipe(j['last_run_at']))}'
                  '${j['last_status'] == null ? '' : ' (${j['last_status']})'}'
                  ' · ${inteiroEquipe(j['runs_24h'])} execução(ões), '
                  '${inteiroEquipe(j['failures_24h'])} falha(s) em 24 h'
                  '${j['active'] == true ? '' : ' · INATIVO'}',
            ),
        ],
      ),
      CartaoEscola(
        titulo: 'Fila, banco e cobrança',
        children: [
          _Linha(
            'Fila de processamento',
            _resumoMapa(mapaEquipe(fila['by_status']), vazio: 'vazia'),
          ),
          _Linha(
            'Em processamento agora',
            '${inteiroEquipe(fila['leased_now'])}',
          ),
          _Linha('Última migration', '${banco['last_migration'] ?? '—'}'),
          _Linha(
            'Tamanho do banco',
            _bytes(inteiroEquipe(banco['size_bytes'])),
          ),
          _Linha(
            'Faturas',
            listaEquipe(cobranca['invoices']).isEmpty
                ? 'nenhuma'
                : listaEquipe(cobranca['invoices'])
                      .map(
                        (i) =>
                            '${i['status']}${i['demo'] == true ? ' (demo)' : ''}: '
                            '${inteiroEquipe(i['n'])}',
                      )
                      .join(' · '),
          ),
          _Linha(
            'Escolas demo (nunca cobradas)',
            '${inteiroEquipe(cobranca['demo_schools'])}',
          ),
        ],
      ),
    ];
  }

  // ─── Erros ──────────────────────────────────────────────────────────────
  List<Widget> _erros() {
    final r = _retrato;
    final erros = mapaEquipe(r?['errors']);
    final porCodigo = listaEquipe(erros['by_code_24h']);
    final recentes = listaEquipe(erros['recent']);
    return [
      ..._cabecalhoCarga('Erros do backend'),
      if (r == null && _erro == null) const Center(child: ProgressRing()),
      if (r != null) ...[
        CartaoEscola(
          titulo: 'Últimas 24 horas',
          subtitulo:
              'Falhas das Edge Functions (limite 429 e erros 5xx). Só o código '
              'público, a função e o status: nada do aluno.',
          children: [
            _Numeros(
              itens: [
                ('Erros em 24 h', inteiroEquipe(erros['total_24h'])),
                (
                  'invalid_ai_output',
                  inteiroEquipe(erros['invalid_ai_output_24h']),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (porCodigo.isEmpty)
              const Text('Nenhum erro registrado em 24 horas.')
            else
              for (final e in porCodigo)
                _LinhaSituacao(
                  situacao: e['code'] == 'qa_probe'
                      ? SituacaoCheck.ok
                      : SituacaoCheck.falha,
                  titulo: '${e['code']} · ${e['function_name']}',
                  detalhe:
                      '${inteiroEquipe(e['n'])} vez(es), a última '
                      '${_quando(dataEquipe(e['last_at']))}',
                ),
          ],
        ),
        CartaoEscola(
          titulo: 'Registro recente',
          subtitulo: 'Os 20 eventos mais novos (guardados por 30 dias).',
          children: [
            if (recentes.isEmpty)
              const Text('Registro vazio.')
            else
              for (final e in recentes)
                _LinhaSituacao(
                  situacao: e['source'] == 'qa_probe'
                      ? SituacaoCheck.ok
                      : SituacaoCheck.falha,
                  titulo: '${e['function_name']} → ${e['code']}',
                  detalhe:
                      'HTTP ${inteiroEquipe(e['status'])} · '
                      '${_quando(dataEquipe(e['occurred_at']))}'
                      '${e['source'] == 'qa_probe' ? ' · teste' : ''}',
                ),
          ],
        ),
      ],
    ];
  }

  // ─── Diagnóstico ────────────────────────────────────────────────────────
  List<Widget> _diagnostico() {
    final rodada = _rodada;
    return [
      CartaoEscola(
        titulo: 'Executor de diagnósticos',
        subtitulo:
            'Confere o app e o servidor de ponta a ponta: sessão, latência, '
            'Edge Functions, RLS, gabaritos fechados, pg_cron, fila, '
            'exclusões, cobrança da escola demo e respostas da IA.',
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              BotaoEscola(
                _diagnosticando ? 'Rodando…' : 'Rodar diagnósticos',
                principal: true,
                onPressed: _diagnosticando ? null : _diagnosticar,
              ),
              if (rodada != null)
                BotaoEscola(
                  'Copiar relatório',
                  onPressed: () => _copiar(
                    rodada.relatorio(cabecalho: widget.info.texto()),
                    'Relatório copiado. Cole no bug ou no chat.',
                  ),
                ),
            ],
          ),
          if (_avisoQa != null && _secao == SecaoEquipe.diagnostico) ...[
            const SizedBox(height: 12),
            AvisoEscola(_avisoQa!, sucesso: _avisoQaOk),
          ],
        ],
      ),
      if (_diagnosticando) const Center(child: ProgressRing()),
      if (rodada != null)
        CartaoEscola(
          titulo: 'Resultado: ${rodada.geral.rotulo}',
          subtitulo:
              '${rodada.conta(SituacaoCheck.ok)} ok · '
              '${rodada.conta(SituacaoCheck.aviso)} atenção · '
              '${rodada.conta(SituacaoCheck.falha)} falha · às '
              '${_hora(rodada.quando)}',
          children: [
            for (final i in rodada.itens)
              _LinhaSituacao(
                situacao: i.situacao,
                titulo: '${i.titulo} (${i.origem})',
                detalhe: i.detalhe,
              ),
          ],
        ),
    ];
  }

  // ─── Ferramentas de QA ──────────────────────────────────────────────────
  List<Widget> _ferramentas() => [
    if (_avisoQa != null && _secao == SecaoEquipe.ferramentas)
      AvisoEscola(_avisoQa!, sucesso: _avisoQaOk),
    CartaoEscola(
      titulo: 'Conta em uso',
      children: [
        _Linha('Conta', widget.email),
        _Linha(
          'Papel',
          widget.papel == 'admin' ? 'Administrador' : 'Desenvolvedor',
        ),
        _Linha('Conta de teste', _contaDeTeste ? 'sim' : 'não'),
        const SizedBox(height: 8),
        const Text(
          'Para testar outro perfil (estudante, professor, dono, coordenação, '
          'TI ou responsável), use o seletor "Perfil" no topo: as contas '
          'dev.demo e admin.demo têm os 6 papéis da escola demo.',
          style: TextStyle(color: MistakeMapDesign.steel),
        ),
        if (widget.onVoltarAosPerfis != null) ...[
          const SizedBox(height: 12),
          BotaoEscola(
            'Voltar à escolha de perfil',
            onPressed: widget.onVoltarAosPerfis,
          ),
        ],
      ],
    ),
    CartaoEscola(
      titulo: 'Dados de demonstração',
      subtitulo:
          'Volta esta conta ao estado de conta nova com os exercícios de '
          'exemplo. Só em contas @mistakemap.dev.',
      children: [
        BotaoEscola(
          _qaOcupado ? 'Aguarde…' : 'Recomeçar meus dados de teste',
          onPressed: _qaOcupado || !_contaDeTeste ? null : _recomecar,
        ),
      ],
    ),
    CartaoEscola(
      titulo: 'Registro de erros',
      subtitulo:
          'Grava um evento qa_probe para conferir que o registro e a aba '
          'Erros funcionam de ponta a ponta.',
      children: [
        BotaoEscola(
          _qaOcupado ? 'Aguarde…' : 'Gravar evento de teste',
          onPressed: _qaOcupado ? null : _sonda,
        ),
      ],
    ),
    const CartaoEscola(
      titulo: 'Cobrança',
      subtitulo:
          'A escola demo nunca gera fatura real (o diagnóstico confere). O '
          'botão de cobrança de teste de R\$ 5 fica no painel do dono, só '
          'neste app.',
      children: [],
    ),
    if (widget.onAbrirAdministracao != null)
      CartaoEscola(
        titulo: 'Administração',
        subtitulo: 'Usuários, papéis e funcionamento detalhado.',
        children: [
          BotaoEscola(
            'Abrir Administração',
            onPressed: widget.onAbrirAdministracao,
          ),
        ],
      ),
  ];

  // ─── Build ──────────────────────────────────────────────────────────────
  List<Widget> _build() {
    final info = widget.info;
    Widget conteudo(int? patch) => CartaoEscola(
      titulo: 'Build instalada',
      subtitulo:
          'O app da equipe tem release e patches próprios no Shorebird e '
          'pré-releases equipe-v… no GitHub.',
      children: [
        _Linha('App', info.equipe ? 'MistakeMap Equipe' : 'MistakeMap'),
        _Linha('Versão', '${info.versao} (build ${info.build})'),
        _Linha('Patch Shorebird', patch == null ? 'sem patch' : '$patch'),
        _Linha('Modo', info.release ? 'release' : 'debug'),
        _Linha('Plataforma', info.plataforma),
        _Linha('Servidor', info.servidor),
        const SizedBox(height: 12),
        BotaoEscola(
          'Copiar dados da build',
          onPressed: () => _copiar(info.texto(), 'Dados da build copiados.'),
        ),
        if (_avisoQa != null && _secao == SecaoEquipe.build) ...[
          const SizedBox(height: 12),
          AvisoEscola(_avisoQa!, sucesso: _avisoQaOk),
        ],
      ],
    );
    final patch = info.patch;
    return [
      if (patch == null)
        conteudo(null)
      else
        ValueListenableBuilder<int?>(
          valueListenable: patch,
          builder: (context, valor, _) => conteudo(valor),
        ),
    ];
  }

  static String _hora(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  static String _quando(DateTime? d) {
    if (d == null) return 'nunca';
    final dif = DateTime.now().difference(d);
    if (dif.inMinutes < 1) return 'agora';
    if (dif.inMinutes < 60) return 'há ${dif.inMinutes} min';
    if (dif.inHours < 48) return 'há ${dif.inHours} h';
    return 'há ${dif.inDays} dias';
  }

  static String _bytes(int b) {
    if (b <= 0) return '—';
    final mb = b / (1024 * 1024);
    return mb >= 1024
        ? '${(mb / 1024).toStringAsFixed(1)} GB'
        : '${mb.toStringAsFixed(1)} MB';
  }

  static String _resumoMapa(DadosEquipe m, {required String vazio}) => m.isEmpty
      ? vazio
      : m.entries.map((e) => '${e.key}: ${inteiroEquipe(e.value)}').join(' · ');
}

// ─── Peças ──────────────────────────────────────────────────────────────────
Color _corSituacao(SituacaoCheck s) => switch (s) {
  SituacaoCheck.ok => MistakeMapDesign.ok,
  SituacaoCheck.aviso => MistakeMapDesign.warn,
  SituacaoCheck.falha => MistakeMapDesign.bad,
};

IconData _iconeSituacao(SituacaoCheck s) => switch (s) {
  SituacaoCheck.ok => WindowsIcons.completed,
  SituacaoCheck.aviso => WindowsIcons.warning,
  SituacaoCheck.falha => WindowsIcons.error_badge,
};

class _Linha extends StatelessWidget {
  const _Linha(this.rotulo, this.valor);
  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Wrap(
      spacing: 8,
      children: [
        Text(
          '$rotulo:',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: MistakeMapDesign.deep,
          ),
        ),
        SelectableText(
          valor,
          style: const TextStyle(color: MistakeMapDesign.slate),
        ),
      ],
    ),
  );
}

class _LinhaSituacao extends StatelessWidget {
  const _LinhaSituacao({
    required this.situacao,
    required this.titulo,
    required this.detalhe,
  });

  final SituacaoCheck situacao;
  final String titulo;
  final String detalhe;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${situacao.rotulo}: $titulo. $detalhe',
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _iconeSituacao(situacao),
            size: 18,
            color: _corSituacao(situacao),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: MistakeMapDesign.deep,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detalhe,
                  style: const TextStyle(color: MistakeMapDesign.steel),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            situacao.rotulo,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: _corSituacao(situacao),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Semaforo extends StatelessWidget {
  const _Semaforo({required this.itens});
  final List<(String, SituacaoCheck, String)> itens;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (titulo, situacao, detalhe) in itens)
        _LinhaSituacao(situacao: situacao, titulo: titulo, detalhe: detalhe),
    ],
  );
}

class _Numeros extends StatelessWidget {
  const _Numeros({required this.itens});
  final List<(String, int)> itens;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, limites) {
      // Grade regular: 2 colunas no celular, mais conforme a largura.
      final colunas = (limites.maxWidth / 170).floor().clamp(2, 6);
      final largura = (limites.maxWidth - 12 * (colunas - 1)) / colunas;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final (rotulo, valor) in itens)
            SizedBox(width: largura, child: _tile(rotulo, valor)),
        ],
      );
    },
  );

  Widget _tile(String rotulo, int valor) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: MistakeMapDesign.well,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: MistakeMapDesign.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$valor',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: MistakeMapDesign.abyss,
          ),
        ),
        Text(
          rotulo,
          style: const TextStyle(fontSize: 12, color: MistakeMapDesign.steel),
        ),
      ],
    ),
  );
}
