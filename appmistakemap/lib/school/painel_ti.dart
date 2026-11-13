import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../theme/design_tokens.dart';
import '../theme/glass_surface.dart';
import '../theme/motion.dart';
import 'escola_repositorio.dart';
import 'escola_ui.dart';
import 'perfil_modelos.dart';
import 'ti_modelos.dart';

// ─── Painel de TI da escola ──────────────────────────────────────────────────
// Contas e acessos: licenças do plano, pessoas e aparelhos, convites em lote e
// registro de auditoria. Nada aqui mostra resposta, mapa, caderno ou valor em
// reais; o servidor confere cada permissão (school-admin, ações it_*).

/// Cartão do painel da escola com o uso das licenças e as ferramentas da TI.
class CartaoAdministracaoTi extends StatefulWidget {
  const CartaoAdministracaoTi({
    super.key,
    required this.escolaId,
    required this.escolaNome,
    required this.repositorio,
    this.onMudou,
  });

  final String escolaId;
  final String escolaNome;
  final RepositorioEscola repositorio;

  /// Chamado ao voltar de uma tela que pode ter mudado convites ou pessoas.
  final Future<void> Function()? onMudou;

  @override
  State<CartaoAdministracaoTi> createState() => _CartaoAdministracaoTiState();
}

class _CartaoAdministracaoTiState extends State<CartaoAdministracaoTi> {
  LicencasTi? _licencas;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final dados = await widget.repositorio.executar('it_licenses', {
        'school_id': widget.escolaId,
      });
      if (mounted) setState(() => _licencas = LicencasTi.deJson(dados));
    } on FalhaEscola catch (f) {
      if (mounted) setState(() => _erro = f.mensagem);
    }
  }

  Future<void> _abrir(Widget tela) async {
    await Navigator.of(context)
        .push(MistakeMapPageRoute(context: context, builder: (_) => tela));
    await _carregar();
    await widget.onMudou?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l = _licencas;
    return CartaoEscola(
      titulo: 'Licenças e acessos',
      subtitulo:
          'Uso do plano neste mês e as ferramentas da TI. Sem respostas, '
          'mapa de aluno nem valores.',
      children: [
        if (_erro != null) AvisoEscola(_erro!),
        if (l == null && _erro == null)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: ProgressRing()),
          ),
        if (l != null) ...[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Indicador(
                rotulo: 'Usuários ativos',
                valor: l.maxUsuarios == null
                    ? '${l.usuariosAtivos}'
                    : '${l.usuariosAtivos} de ${l.maxUsuarios}',
                nota: 'plano ${l.planoNome}',
              ),
              _Indicador(
                rotulo: 'Alunos ativos no mês',
                valor: '${l.alunosAtivos}',
                nota: 'usaram o app este mês',
              ),
              _Indicador(
                rotulo: 'Turmas',
                valor: l.maxTurmas == null
                    ? '${l.turmas}'
                    : '${l.turmas} de ${l.maxTurmas}',
                nota: 'ligadas à escola',
              ),
              _Indicador(
                rotulo: 'Convites em aberto',
                valor: '${l.convitesAbertos}',
                nota: l.usuariosSuspensos == 0
                    ? 'nenhuma conta suspensa'
                    : '${l.usuariosSuspensos} '
                          '${l.usuariosSuspensos == 1 ? 'conta suspensa' : 'contas suspensas'}',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Análises de IA do mês: ${l.analisesUsadas} de ${l.analisesPote}'
            '${l.analisesExtras > 0 ? ' (+${l.analisesExtras} além do pote)' : ''}'
            ' · treinos: ${l.treinosUsados} de ${l.treinosPote}',
            style: const TextStyle(color: MistakeMapDesign.content),
          ),
          const SizedBox(height: 8),
          ProgressBar(value: l.usoAnalises * 100),
          if (l.convitesPassamDoLimite) ...[
            const SizedBox(height: 12),
            AvisoEscola(
              'Os convites em aberto deixam entrar até '
              '${l.usosConvitesAbertos} pessoas e só há ${l.vagas} '
              '${l.vagas == 1 ? 'vaga' : 'vagas'} no plano ${l.planoNome}. '
              'Quem passar do limite não consegue entrar: peça ao dono para '
              'mudar de plano ou revogue convites.',
            ),
          ],
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            BotaoEscola(
              'Pessoas e acessos',
              principal: true,
              onPressed: () => _abrir(
                TelaPessoasTi(
                  escolaId: widget.escolaId,
                  escolaNome: widget.escolaNome,
                  repositorio: widget.repositorio,
                ),
              ),
            ),
            BotaoEscola(
              'Convidar em lote',
              onPressed: () => _abrir(
                TelaConvitesLoteTi(
                  escolaId: widget.escolaId,
                  escolaNome: widget.escolaNome,
                  repositorio: widget.repositorio,
                ),
              ),
            ),
            BotaoEscola(
              'Registro de auditoria',
              onPressed: () => _abrir(
                TelaAuditoriaTi(
                  escolaId: widget.escolaId,
                  escolaNome: widget.escolaNome,
                  repositorio: widget.repositorio,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Indicador extends StatelessWidget {
  const _Indicador({
    required this.rotulo,
    required this.valor,
    required this.nota,
  });

  final String rotulo;
  final String valor;
  final String nota;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 150),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: MistakeMapDesign.well,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: MistakeMapDesign.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(rotulo, style: const TextStyle(color: MistakeMapDesign.steel)),
        Text(
          valor,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: MistakeMapDesign.primary,
          ),
        ),
        Text(
          nota,
          style: const TextStyle(fontSize: 12, color: MistakeMapDesign.steel),
        ),
      ],
    ),
  );
}

// ─── Moldura comum das telas da TI ───────────────────────────────────────────

class _TelaTi extends StatelessWidget {
  const _TelaTi({
    required this.titulo,
    required this.escolaNome,
    required this.children,
    this.acoes = const [],
  });

  final String titulo;
  final String escolaNome;
  final List<Widget> acoes;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => NavigationView(
    content: AuroraBackground(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      Tooltip(
                        message: 'Voltar',
                        child: IconButton(
                          icon: const Icon(FluentIcons.back, size: 18),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              titulo,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: MistakeMapDesign.primary,
                              ),
                            ),
                            Text(
                              escolaNome,
                              style: const TextStyle(
                                color: MistakeMapDesign.steel,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...acoes,
                    ],
                  ),
                ),
                ...children,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

String _dataCurta(DateTime? d) => d == null
    ? '—'
    : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}'
          '/${d.year} ${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';

Future<bool> _confirmar(
  BuildContext context, {
  required String titulo,
  required String texto,
  required String botao,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogo) => ContentDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          BotaoEscola(
            'Cancelar',
            onPressed: () => Navigator.of(dialogo).pop(false),
          ),
          BotaoEscola(
            botao,
            principal: true,
            onPressed: () => Navigator.of(dialogo).pop(true),
          ),
        ],
      ),
    ) ==
    true;

// ─── Pessoas e acessos ───────────────────────────────────────────────────────

class TelaPessoasTi extends StatefulWidget {
  const TelaPessoasTi({
    super.key,
    required this.escolaId,
    required this.escolaNome,
    required this.repositorio,
  });

  final String escolaId;
  final String escolaNome;
  final RepositorioEscola repositorio;

  @override
  State<TelaPessoasTi> createState() => _TelaPessoasTiState();
}

class _TelaPessoasTiState extends State<TelaPessoasTi> {
  List<PessoaTi> _pessoas = const [];
  bool _carregando = true;
  bool _enviando = false;
  String? _erro;
  String? _aviso;
  final _busca = TextEditingController();
  String? _papel;
  String _situacao = 'all';
  String? _aberta;
  final Map<String, List<SessaoTi>> _sessoes = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final dados = await widget.repositorio.executar('it_directory', {
        'school_id': widget.escolaId,
      });
      if (mounted) setState(() => _pessoas = pessoasDoDiretorio(dados));
    } on FalhaEscola catch (f) {
      if (mounted) setState(() => _erro = f.mensagem);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<DadosEscola?> _rodar(
    String acao,
    DadosEscola dados, {
    String? sucesso,
    bool recarregar = true,
  }) async {
    if (_enviando) return null;
    setState(() {
      _enviando = true;
      _erro = null;
      _aviso = null;
    });
    try {
      final r = await widget.repositorio.executar(acao, {
        'school_id': widget.escolaId,
        ...dados,
      });
      if (mounted && sucesso != null) setState(() => _aviso = sucesso);
      if (recarregar) await _carregar();
      return r;
    } on FalhaEscola catch (f) {
      if (mounted) setState(() => _erro = f.mensagem);
      return null;
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _verAparelhos(PessoaTi p) async {
    final r = await _rodar('it_member_sessions', {
      'user_id': p.id,
    }, recarregar: false);
    if (r == null || !mounted) return;
    setState(
      () => _sessoes[p.id] = [
        for (final s in linhasEscola(r['sessions'])) SessaoTi.deJson(s),
      ],
    );
  }

  Future<void> _encerrarSessoes(PessoaTi p) async {
    if (!await _confirmar(
      context,
      titulo: 'Encerrar sessões',
      texto:
          '${p.titulo} sai do MistakeMap em todos os aparelhos e precisa '
          'entrar de novo (em até uma hora). Use quando um aparelho foi '
          'perdido ou a senha vazou.',
      botao: 'Encerrar',
    )) {
      return;
    }
    final r = await _rodar('it_revoke_sessions', {'user_id': p.id});
    if (r != null && mounted) {
      setState(() {
        _sessoes.remove(p.id);
        _aviso = '${r['revoked'] ?? 0} sessões encerradas para ${p.titulo}.';
      });
    }
  }

  Future<void> _redefinirSenha(PessoaTi p) async {
    if (!await _confirmar(
      context,
      titulo: 'Redefinir senha',
      texto:
          'Enviamos para ${p.email} o mesmo e-mail do "Esqueci minha '
          'senha". A pessoa escolhe a senha nova; a TI nunca vê nem define '
          'a senha.',
      botao: 'Enviar e-mail',
    )) {
      return;
    }
    await _rodar(
      'it_reset_password',
      {'user_id': p.id},
      sucesso: 'E-mail de redefinição enviado para ${p.email}.',
      recarregar: false,
    );
  }

  Future<void> _mudarSituacao(PessoaTi p, PapelPessoaTi papel) async {
    final suspender = papel.ativo;
    if (suspender &&
        !await _confirmar(
          context,
          titulo: 'Suspender ${papel.nome}',
          texto:
              '${p.titulo} perde o acesso de ${papel.nome} nesta escola até '
              'ser reativado. A conta e o histórico continuam guardados.',
          botao: 'Suspender',
        )) {
      return;
    }
    await _rodar(
      'it_set_status',
      {
        'user_id': p.id,
        'role': papel.papel,
        'status': suspender ? 'suspended' : 'active',
      },
      sucesso: suspender
          ? '${papel.nome} suspenso para ${p.titulo}.'
          : '${papel.nome} reativado para ${p.titulo}.',
    );
  }

  Future<void> _remover(PessoaTi p, PapelPessoaTi papel) async {
    if (!await _confirmar(
      context,
      titulo: 'Remover da escola',
      texto:
          '${p.titulo} deixa de ser ${papel.nome} nesta escola. Para voltar, '
          'precisa de um convite novo. A conta da pessoa não é apagada.',
      botao: 'Remover',
    )) {
      return;
    }
    await _rodar('it_remove_member', {
      'user_id': p.id,
      'role': papel.papel,
    }, sucesso: '${p.titulo} removido como ${papel.nome}.');
  }

  @override
  Widget build(BuildContext context) {
    final lista = _pessoas
        .where((p) => p.combina(_busca.text, _papel, _situacao))
        .toList();
    return _TelaTi(
      titulo: 'Pessoas e acessos',
      escolaNome: widget.escolaNome,
      acoes: [
        Tooltip(
          message: 'Copiar lista (CSV)',
          child: IconButton(
            icon: const Icon(FluentIcons.copy, size: 18),
            onPressed: lista.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(
                      ClipboardData(text: pessoasCsv(lista)),
                    );
                    if (mounted) {
                      setState(
                        () => _aviso =
                            'Lista de ${lista.length} pessoas copiada (CSV).',
                      );
                    }
                  },
          ),
        ),
        Tooltip(
          message: 'Atualizar',
          child: IconButton(
            icon: const Icon(FluentIcons.refresh, size: 18),
            onPressed: _carregando ? null : _carregar,
          ),
        ),
      ],
      children: [
        if (_erro != null) AvisoEscola(_erro!),
        if (_aviso != null) AvisoEscola(_aviso!, sucesso: true),
        CartaoEscola(
          titulo: 'Filtrar',
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextBox(
                controller: _busca,
                placeholder: 'Buscar por nome ou e-mail',
                onChanged: (_) => setState(() {}),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ComboBox<String?>(
                  value: _papel,
                  items: [
                    const ComboBoxItem(value: null, child: Text('Todos')),
                    for (final p in const [
                      'owner',
                      'coordinator',
                      'it_admin',
                      'finance',
                      'teacher',
                      'student',
                      'guardian',
                    ])
                      ComboBoxItem(value: p, child: Text(nomesPapel[p] ?? p)),
                  ],
                  onChanged: (v) => setState(() => _papel = v),
                ),
                ComboBox<String>(
                  value: _situacao,
                  items: const [
                    ComboBoxItem(
                      value: 'all',
                      child: Text('Qualquer situação'),
                    ),
                    ComboBoxItem(value: 'active', child: Text('Ativos')),
                    ComboBoxItem(value: 'suspended', child: Text('Suspensos')),
                    ComboBoxItem(value: 'never', child: Text('Nunca entraram')),
                  ],
                  onChanged: (v) => setState(() => _situacao = v ?? 'all'),
                ),
              ],
            ),
          ],
        ),
        if (_carregando)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: ProgressRing()),
          )
        else
          CartaoEscola(
            titulo: lista.length == 1 ? '1 pessoa' : '${lista.length} pessoas',
            children: [
              if (lista.isEmpty)
                const Text('Ninguém com esses filtros.')
              else
                for (final p in lista) _linha(p),
            ],
          ),
      ],
    );
  }

  Widget _linha(PessoaTi p) {
    final aberta = _aberta == p.id;
    final sessoes = _sessoes[p.id];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: MistakeMapDesign.well,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MistakeMapDesign.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HoverButton(
            onPressed: () => setState(() => _aberta = aberta ? null : p.id),
            builder: (context, _) => Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.titulo + (p.souEu ? ' (você)' : ''),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (p.nome != null && p.nome!.isNotEmpty)
                          Text(
                            p.email,
                            style: const TextStyle(
                              color: MistakeMapDesign.steel,
                            ),
                          ),
                        Text(
                          '${p.papeis.map((r) => r.ativo ? r.nome : '${r.nome} (suspenso)').join(', ')}'
                          ' · último acesso ${quandoRelativo(p.ultimoAcesso)}'
                          '${p.sessoes > 0 ? ' · ${p.sessoes} ${p.sessoes == 1 ? 'aparelho' : 'aparelhos'}' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: p.suspensa
                                ? MistakeMapDesign.coralInk
                                : MistakeMapDesign.steel,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    aberta ? FluentIcons.chevron_up : FluentIcons.chevron_down,
                    size: 12,
                  ),
                ],
              ),
            ),
          ),
          if (aberta)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Na escola desde ${_dataCurta(p.entrou)}',
                    style: const TextStyle(color: MistakeMapDesign.steel),
                  ),
                  const SizedBox(height: 8),
                  for (final papel in p.papeis)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${papel.nome}: ${papel.ativo ? 'ativo' : 'suspenso'}',
                          ),
                          if (papel.administravel && !p.souEu) ...[
                            BotaoEscola(
                              papel.ativo ? 'Suspender' : 'Reativar',
                              onPressed: _enviando
                                  ? null
                                  : () => _mudarSituacao(p, papel),
                            ),
                            BotaoEscola(
                              'Remover',
                              onPressed: _enviando
                                  ? null
                                  : () => _remover(p, papel),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (p.contaAdministravel) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        BotaoEscola(
                          'Ver aparelhos',
                          onPressed: _enviando ? null : () => _verAparelhos(p),
                        ),
                        BotaoEscola(
                          'Encerrar sessões',
                          onPressed: _enviando
                              ? null
                              : () => _encerrarSessoes(p),
                        ),
                        BotaoEscola(
                          'Redefinir senha',
                          onPressed: _enviando
                              ? null
                              : () => _redefinirSenha(p),
                        ),
                      ],
                    ),
                  ] else if (!p.souEu)
                    const Text(
                      'Sessões e senha desta conta só o dono da escola ou a '
                      'própria pessoa administram (ela tem papel de gestão '
                      'ou outra escola).',
                      style: TextStyle(
                        fontSize: 12,
                        color: MistakeMapDesign.steel,
                      ),
                    ),
                  if (sessoes != null) ...[
                    const SizedBox(height: 12),
                    if (sessoes.isEmpty)
                      const Text('Nenhum aparelho conectado agora.')
                    else
                      for (final s in sessoes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '${s.aparelho} · desde ${_dataCurta(s.criada)}'
                            ' · visto ${quandoRelativo(s.vistaEm)}'
                            '${s.rede == null ? '' : ' · rede ${s.rede}'}',
                          ),
                        ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Convites em lote ────────────────────────────────────────────────────────

class TelaConvitesLoteTi extends StatefulWidget {
  const TelaConvitesLoteTi({
    super.key,
    required this.escolaId,
    required this.escolaNome,
    required this.repositorio,
  });

  final String escolaId;
  final String escolaNome;
  final RepositorioEscola repositorio;

  @override
  State<TelaConvitesLoteTi> createState() => _TelaConvitesLoteTiState();
}

class _TelaConvitesLoteTiState extends State<TelaConvitesLoteTi> {
  final _texto = TextEditingController();
  String _papelPadrao = 'student';
  bool _enviando = false;
  String? _erro;
  String? _aviso;
  List<DadosEscola>? _resultado;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  List<LinhaPlanilha> get _linhas =>
      lerPlanilha(_texto.text, papelPadrao: _papelPadrao);

  Future<void> _gerar() async {
    final linhas = _linhas;
    if (linhas.isEmpty) {
      setState(() => _erro = 'Cole pelo menos uma linha com e-mail.');
      return;
    }
    if (linhas.length > 500) {
      setState(() => _erro = 'Até 500 pessoas por vez.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
      _aviso = null;
    });
    try {
      final r = await widget.repositorio.executar('it_import_invites', {
        'school_id': widget.escolaId,
        'rows': [for (final l in linhas) l.paraJson()],
        'valid_days': 30,
      });
      if (!mounted) return;
      setState(() {
        _resultado = linhasEscola(r['rows']);
        _aviso =
            '${r['created'] ?? 0} convites criados. Copie a tabela agora: os '
            'códigos não aparecem de novo.';
      });
    } on FalhaEscola catch (f) {
      if (mounted) setState(() => _erro = f.mensagem);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resultado = _resultado;
    final total = _linhas.length;
    return _TelaTi(
      titulo: 'Convidar em lote',
      escolaNome: widget.escolaNome,
      children: [
        if (_erro != null) AvisoEscola(_erro!),
        if (_aviso != null) AvisoEscola(_aviso!, sucesso: true),
        CartaoEscola(
          titulo: 'Cole a planilha',
          subtitulo:
              'Uma pessoa por linha: e-mail e papel (professor, estudante ou '
              'responsável), separados por ponto e vírgula, vírgula ou '
              'tabulação. Cada linha vira um convite pessoal, de uso único, '
              'preso ao e-mail e válido por 30 dias. Coordenação, TI e '
              'Financeiro o dono convida um a um.',
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextBox(
                controller: _texto,
                minLines: 6,
                maxLines: 14,
                placeholder:
                    'email;papel\n'
                    'ana@escola.edu.br;estudante\n'
                    'carlos@escola.edu.br;professor',
                onChanged: (_) => setState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: InfoLabel(
                label: 'Papel para linhas sem papel',
                child: ComboBox<String>(
                  value: _papelPadrao,
                  items: [
                    for (final p in const ['student', 'teacher', 'guardian'])
                      ComboBoxItem(value: p, child: Text(nomesPapel[p] ?? p)),
                  ],
                  onChanged: (v) =>
                      setState(() => _papelPadrao = v ?? 'student'),
                ),
              ),
            ),
            BotaoEscola(
              total == 0
                  ? 'Gerar convites'
                  : 'Gerar $total ${total == 1 ? 'convite' : 'convites'}',
              principal: true,
              onPressed: _enviando ? null : _gerar,
            ),
          ],
        ),
        if (resultado != null)
          CartaoEscola(
            titulo: 'Resultado',
            subtitulo:
                'Envie a cada pessoa o código dela. No cadastro, ela escolhe '
                'o perfil e digita o código com o mesmo e-mail da planilha.',
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: BotaoEscola(
                  'Copiar tabela (CSV)',
                  principal: true,
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: convitesLoteCsv(resultado)),
                    );
                    if (mounted) setState(() => _aviso = 'Tabela copiada.');
                  },
                ),
              ),
              const SizedBox(height: 12),
              for (final l in resultado)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${l['email']} · '
                          '${nomesPapel['${l['role']}'] ?? l['role']}',
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (l['status'] == 'created')
                        SelectableText(
                          '${l['code']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: MistakeMapDesign.primary,
                          ),
                        )
                      else
                        Flexible(
                          child: Text(
                            motivosLinha['${l['status']}'] ?? '${l['status']}',
                            style: const TextStyle(
                              color: MistakeMapDesign.coralInk,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

// ─── Registro de auditoria ───────────────────────────────────────────────────

class TelaAuditoriaTi extends StatefulWidget {
  const TelaAuditoriaTi({
    super.key,
    required this.escolaId,
    required this.escolaNome,
    required this.repositorio,
  });

  final String escolaId;
  final String escolaNome;
  final RepositorioEscola repositorio;

  @override
  State<TelaAuditoriaTi> createState() => _TelaAuditoriaTiState();
}

class _TelaAuditoriaTiState extends State<TelaAuditoriaTi> {
  static const _pagina = 100;
  final List<RegistroAuditoria> _registros = [];
  bool _carregando = true;
  bool _temMais = false;
  String? _erro;
  String? _aviso;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar({bool mais = false}) async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final dados = await widget.repositorio.executar('it_audit', {
        'school_id': widget.escolaId,
        'limit': _pagina,
        if (mais && _registros.isNotEmpty) 'before': _registros.last.id,
      });
      final novos = registrosAuditoria(dados);
      if (!mounted) return;
      setState(() {
        if (!mais) _registros.clear();
        _registros.addAll(novos);
        _temMais = novos.length == _pagina;
      });
    } on FalhaEscola catch (f) {
      if (mounted) setState(() => _erro = f.mensagem);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) => _TelaTi(
    titulo: 'Registro de auditoria',
    escolaNome: widget.escolaNome,
    acoes: [
      Tooltip(
        message: 'Copiar registro (CSV)',
        child: IconButton(
          icon: const Icon(FluentIcons.copy, size: 18),
          onPressed: _registros.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(
                    ClipboardData(text: auditoriaCsv(_registros)),
                  );
                  if (mounted) setState(() => _aviso = 'Registro copiado.');
                },
        ),
      ),
      Tooltip(
        message: 'Atualizar',
        child: IconButton(
          icon: const Icon(FluentIcons.refresh, size: 18),
          onPressed: _carregando ? null : _carregar,
        ),
      ),
    ],
    children: [
      if (_erro != null) AvisoEscola(_erro!),
      if (_aviso != null) AvisoEscola(_aviso!, sucesso: true),
      CartaoEscola(
        titulo: 'Quem mudou o quê',
        subtitulo:
            'Entradas, suspensões, remoções, convites, sessões encerradas e '
            'redefinições de senha. O registro não pode ser editado.',
        children: [
          if (_registros.isEmpty && !_carregando)
            const Text('Nada registrado ainda.'),
          for (final r in _registros)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.descricao,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    [
                      _dataCurta(r.quando),
                      'por ${r.quem ?? 'sistema'}',
                      if (r.alvo != null) 'pessoa: ${r.alvo}',
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: MistakeMapDesign.steel,
                    ),
                  ),
                ],
              ),
            ),
          if (_carregando)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: ProgressRing()),
            )
          else if (_temMais)
            Align(
              alignment: Alignment.centerLeft,
              child: BotaoEscola(
                'Carregar mais',
                onPressed: () => _carregar(mais: true),
              ),
            ),
        ],
      ),
    ],
  );
}
