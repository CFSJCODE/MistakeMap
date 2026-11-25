import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import '../theme/botao_redondo.dart';
import '../theme/motion.dart';
import '../layout/conta.dart';
import '../billing/billing_panel.dart';
import '../billing/billing_repository.dart';
import '../billing/checkout_models.dart' show formatBrl;
import '../platform/platform_forms.dart' show PlatformCheck;
import '../reports/school_reports.dart';
import '../reports/school_reports_page.dart';
import '../theme/aparencia_dialogo.dart';
import '../theme/design_tokens.dart';
import '../theme/glass_surface.dart';
import 'escola_repositorio.dart';
import 'escola_ui.dart';
import 'painel_ti.dart';
import 'perfil_modelos.dart';
import 'secoes_escola.dart';
import 'ti_modelos.dart' show LicencasTi;

// ─── Tela inicial dos perfis de escola ───────────────────────────────────────
// Dono, Financeiro/Compras, coordenação, TI e professor: escola, convites,
// equipes e a cobrança (plano, quem paga, faturas). Os relatórios completos
// (uso pedagógico e financeiro, auditoria) chegam no item F.
// Responsável: filhos acompanhados e o código de consentimento.
// Nada aqui mostra resposta, caderno ou mapa individual de aluno.

/// Papéis que cada perfil de gestão pode convidar (o servidor confere de novo).
const papeisConvidaveis = {
  'owner': [
    'coordinator',
    'it_admin',
    'finance',
    'teacher',
    'student',
    'guardian',
  ],
  'coordinator': ['teacher', 'student', 'guardian'],
  'it_admin': ['teacher', 'student', 'guardian'],
};

class TelaPainelEscola extends StatefulWidget {
  const TelaPainelEscola({
    super.key,
    required this.perfil,
    required this.repositorio,
    this.cobranca,
    this.relatorios,
    this.hoje,
  });

  final PerfilAtivo perfil;
  final RepositorioEscola repositorio;

  /// Cobrança (Edge Function school-billing). Sem ela, o cartão não aparece.
  final BillingRepository? cobranca;

  /// Relatórios (RPC school_reports). Sem ele, o cartão não aparece.
  final SchoolReportsRepository? relatorios;

  /// Data de hoje para achar o mês atual nos números (testes fixam).
  final DateTime? hoje;

  @override
  State<TelaPainelEscola> createState() => _TelaPainelEscolaState();
}

class _TelaPainelEscolaState extends State<TelaPainelEscola> {
  DadosEscola _dados = {};
  bool _carregando = true;
  bool _enviando = false;
  String? _erro;
  String? _aviso;

  String _papelConvite = 'teacher';
  final _email = TextEditingController();
  final _usos = TextEditingController(text: '30');
  final _equipe = TextEditingController();
  String _competicao = 'obr';

  /// Seção aberta no painel (chave de [SecaoEscola]); a primeira por padrão.
  String? _secao;

  /// Números do mês para a Visão geral (mesma RPC dos relatórios, que o
  /// servidor recorta por papel). Sem ele, os cartões mostram só o que vem
  /// do school_overview.
  SchoolReport? _resumo;

  /// Licenças da TI: pessoas distintas e convites abertos de verdade (o
  /// school_overview só traz os 50 convites mais recentes).
  LicencasTi? _licencas;

  @override
  void initState() {
    super.initState();
    final papeis = papeisConvidaveis[widget.perfil.papel];
    if (papeis != null) _papelConvite = papeis.first;
    _carregar();
  }

  @override
  void didUpdateWidget(TelaPainelEscola antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.perfil.chave != widget.perfil.chave) {
      _secao = null;
      _resumo = null;
      _licencas = null;
      final papeis = papeisConvidaveis[widget.perfil.papel];
      if (papeis != null) _papelConvite = papeis.first;
      _carregar();
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _usos.dispose();
    _equipe.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final escola = widget.perfil.escolaId;
    if (escola == null) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    unawaited(_carregarResumo(escola));
    try {
      final dados = await widget.repositorio.executar('school_overview', {
        'school_id': escola,
      });
      if (mounted) setState(() => _dados = dados);
    } on FalhaEscola catch (f) {
      if (mounted) setState(() => _erro = f.mensagem);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _carregarResumo(String escola) async {
    if (widget.perfil.papel == 'it_admin') {
      try {
        final dados = await widget.repositorio.executar('it_licenses', {
          'school_id': escola,
        });
        if (mounted && widget.perfil.escolaId == escola) {
          setState(() => _licencas = LicencasTi.deJson(dados));
        }
      } catch (_) {
        // Sem as licenças, os cartões da TI mostram "—".
      }
      return;
    }
    final relatorios = widget.relatorios;
    if (relatorios == null ||
        !_papeisComRelatorio.contains(widget.perfil.papel)) {
      return;
    }
    try {
      // 12 meses: as faturas em aberto e vencidas contam o ano todo, e o uso
      // do mês atual sai comparado com o anterior.
      final r = await relatorios.load(escola, months: 12);
      if (mounted && widget.perfil.escolaId == escola) {
        setState(() => _resumo = r);
      }
    } catch (_) {
      // Sem os relatórios, a Visão geral fica com os totais da escola.
    }
  }

  static const _papeisComRelatorio = {'owner', 'finance', 'coordinator'};

  Future<DadosEscola?> _rodar(String acao, DadosEscola dados) async {
    if (_enviando) return null;
    setState(() {
      _enviando = true;
      _erro = null;
      _aviso = null;
    });
    try {
      return await widget.repositorio.executar(acao, dados);
    } on FalhaEscola catch (f) {
      if (mounted) setState(() => _erro = f.mensagem);
      return null;
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _convidar() async {
    final gestao = const {
      'coordinator',
      'it_admin',
      'finance',
      'owner',
    }.contains(_papelConvite);
    final usos = gestao ? 1 : int.tryParse(_usos.text.trim()) ?? 1;
    final r = await _rodar('create_invite', {
      'school_id': widget.perfil.escolaId,
      'role': _papelConvite,
      if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
      'max_uses': usos.clamp(1, 1000),
      'valid_days': gestao ? 7 : 30,
    });
    if (r == null || !mounted) return;
    _email.clear();
    await mostrarCodigo(
      context,
      titulo: 'Convite de ${nomesPapel[_papelConvite]}',
      codigo: '${r['code']}',
      explicacao: gestao
          ? 'Convite pessoal, de uso único, válido por 7 dias. A pessoa '
                'escolhe "${nomesPapel[_papelConvite]}" no cadastro e digita '
                'este código.'
          : 'Vale para até $usos pessoas por 30 dias. No cadastro, a pessoa '
                'escolhe o perfil e digita este código.',
    );
    await _carregar();
  }

  Future<void> _renovar(DadosEscola convite) async {
    final r = await _rodar('it_renew_invite', {
      'school_id': widget.perfil.escolaId,
      'invite_id': convite['id'],
    });
    if (r == null || !mounted) return;
    final email = convite['email'];
    await mostrarCodigo(
      context,
      titulo: 'Convite renovado',
      codigo: '${r['code']}',
      explicacao:
          'O código antigo deixou de valer. Envie este '
          '${email == null ? 'código' : 'código para $email'}.',
    );
    await _carregar();
  }

  Future<void> _criarEquipe() async {
    final nome = _equipe.text.trim();
    if (nome.length < 2) {
      setState(() => _erro = 'Dê um nome à equipe.');
      return;
    }
    final r = await _rodar('create_team', {
      'school_id': widget.perfil.escolaId,
      'name': nome,
      'competition': _competicao,
    });
    if (r == null || !mounted) return;
    _equipe.clear();
    await mostrarCodigo(
      context,
      titulo: 'Código da equipe $nome',
      codigo: '${r['code']}',
      explicacao:
          'Os estudantes escolhem "Estudante + equipe de robótica" no '
          'cadastro, digitam este código e escolhem a função.',
    );
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final papel = widget.perfil.papel;
    final escola = mapaEscola(_dados['school']);
    final membros = linhasEscola(_dados['members']);
    final convites = linhasEscola(_dados['invites']);
    final equipes = linhasEscola(_dados['teams']);
    final equipeEscola = linhasEscola(_dados['staff']);
    final podeConvidar = papeisConvidaveis.containsKey(papel);
    final podeEquipe = const {
      'owner',
      'coordinator',
      'teacher',
    }.contains(papel);
    final nomeEscola =
        '${escola['name'] ?? widget.perfil.escolaNome ?? 'Escola'}';
    final escolaId = widget.perfil.escolaId;
    final gestaoFinanceira = const {
      'owner',
      'finance',
      'coordinator',
    }.contains(papel);
    final cartaoTi =
        escolaId != null && const {'owner', 'it_admin'}.contains(papel)
        ? CartaoAdministracaoTi(
            key: ValueKey('ti-$escolaId'),
            escolaId: escolaId,
            escolaNome: nomeEscola,
            repositorio: widget.repositorio,
            onMudou: _carregar,
          )
        : null;
    final pessoasNaEscola = membros.isNotEmpty && papel != 'teacher'
        ? CartaoEscola(
            titulo: 'Pessoas na escola',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in membros)
                    _Etiqueta(
                      '${nomesPapel[m['role']] ?? m['role']}: ${m['total']}',
                    ),
                ],
              ),
            ],
          )
        : null;
    // Cada perfil vê só as seções com conteúdo para o papel dele. A TI começa
    // pelas licenças, que é o trabalho do dia a dia dela.
    final secoes = <SecaoEscola>[
      SecaoEscola(
        chave: 'inicio',
        rotulo: 'Visão geral',
        rotuloCurto: 'Início',
        icone: WindowsIcons.home,
        cartoes: [
          if (_indicadores(papel, membros) case final itens
              when itens.length >= 2)
            GradeIndicadoresEscola(
              key: const Key('painel-indicadores'),
              itens: itens,
            ),
          _proximaEtapa(papel),
          ?pessoasNaEscola,
        ],
      ),
      if (cartaoTi != null && papel == 'it_admin')
        SecaoEscola(
          chave: 'ti',
          rotulo: 'Licenças',
          icone: WindowsIcons.permissions,
          cartoes: [cartaoTi],
        ),
      if (equipeEscola.isNotEmpty || podeConvidar)
        SecaoEscola(
          chave: 'pessoas',
          rotulo: 'Pessoas',
          icone: WindowsIcons.people,
          cartoes: [
            if (equipeEscola.isNotEmpty) _cartaoOrganograma(equipeEscola),
            if (podeConvidar) _cartaoConvites(papel, convites),
          ],
        ),
      if (podeEquipe || equipes.isNotEmpty)
        SecaoEscola(
          chave: 'equipes',
          rotulo: 'Equipes',
          icone: WindowsIcons.robot,
          cartoes: [_cartaoEquipes(podeEquipe, equipes)],
        ),
      if (widget.cobranca != null && escolaId != null && gestaoFinanceira)
        SecaoEscola(
          chave: 'cobranca',
          rotulo: 'Cobrança',
          icone: WindowsIcons.payment_card,
          cartoes: [
            CartaoCobranca(
              escolaId: escolaId,
              escolaNome: nomeEscola,
              papel: papel,
              repositorio: widget.cobranca!,
            ),
          ],
        ),
      if (widget.relatorios != null && escolaId != null && gestaoFinanceira)
        SecaoEscola(
          chave: 'relatorios',
          rotulo: 'Relatórios',
          icone: WindowsIcons.report_document,
          cartoes: [_cartaoRelatorios(papel, nomeEscola)],
        ),
      if (cartaoTi != null && papel != 'it_admin')
        SecaoEscola(
          chave: 'ti',
          rotulo: 'TI',
          icone: WindowsIcons.permissions,
          cartoes: [cartaoTi],
        ),
    ];
    var indice = secoes.indexWhere((s) => s.chave == _secao);
    if (indice < 0) indice = 0;
    return _MolduraPerfil(
      perfil: widget.perfil,
      titulo: nomeEscola,
      // Antes do servidor responder, usa o plano que veio com o perfil; sem
      // nenhum dos dois, não mostra plano (nada de "Grátis" piscando).
      subtitulo: [
        nomesPapel[papel] ?? papel,
        ?widget.perfil.cargo,
        if (nomesPlano[escola['plan'] ?? widget.perfil.plano] case final plano?)
          'plano $plano',
      ].join(' · '),
      onAtualizar: _carregar,
      secoes: _carregando ? const [] : secoes,
      indice: indice,
      onSecao: (i) => setState(() => _secao = secoes[i].chave),
      avisos: [
        if (_erro != null) AvisoEscola(_erro!),
        if (_aviso != null) AvisoEscola(_aviso!, sucesso: true),
        if (_carregando)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: ProgressRing()),
          ),
      ],
    );
  }

  /// Os números que cada papel acompanha no dia a dia. Os do mês vêm do
  /// relatório (o servidor só devolve o que o papel pode ver); os totais de
  /// pessoas, do school_overview; os da TI, das licenças.
  List<IndicadorEscola> _indicadores(String papel, List<DadosEscola> membros) {
    int total(String role) => membros
        .where((m) => m['role'] == role)
        .fold(0, (s, m) => s + ((m['total'] as num?)?.toInt() ?? 0));
    final ped = _resumo?.pedagogical;
    final fin = _resumo?.financial;
    // O mês atual é o do calendário: sem linha dele (nenhuma atividade ainda),
    // o uso do mês é zero, e não o do último mês com dados.
    final hoje = widget.hoje ?? DateTime.now();
    final esteMes = DateTime(hoje.year, hoje.month);
    final mesPassado = DateTime(hoje.year, hoje.month - 1);
    bool mesmoMes(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month;
    UsageMonth? uso(DateTime m) =>
        ped?.usage.where((u) => mesmoMes(u.month, m)).firstOrNull;
    final mes = uso(esteMes);
    final anterior = uso(mesPassado);
    final custo = fin?.cost
        .where((c) => mesmoMes(c.month, esteMes))
        .firstOrNull;
    const exemplo = 'Dados de exemplo';
    String? comparar(int atual, int? antes) {
      if (ped?.sample ?? false) return exemplo;
      final quando = monthLabel(mesPassado);
      final dif = atual - (antes ?? 0);
      if (dif == 0) return 'Igual a $quando';
      return '${dif > 0 ? '+' : '−'}${formatInt(dif.abs())} desde $quando';
    }

    final notaFinanceira = (fin?.sample ?? false)
        ? exemplo
        : 'Últimos 12 meses';
    const semValor = '—';
    final ativos = (
      rotulo: 'Alunos ativos no mês',
      valor: ped == null ? semValor : formatInt(mes?.activeStudents ?? 0),
      icone: WindowsIcons.education,
      acento: Acento.aqua,
      nota: ped == null
          ? null
          : comparar(mes?.activeStudents ?? 0, anterior?.activeStudents),
    );
    final analises = (
      rotulo: 'Análises no mês',
      valor: ped == null ? semValor : formatInt(mes?.analyses ?? 0),
      icone: WindowsIcons.search,
      acento: Acento.violet,
      nota: ped == null
          ? null
          : comparar(mes?.analyses ?? 0, anterior?.analyses),
    );
    final emAberto = (
      rotulo: 'Faturas em aberto',
      valor: fin == null ? semValor : formatBrl(fin.openTotal),
      icone: WindowsIcons.payment_card,
      acento: Acento.amber,
      nota: fin == null ? null : notaFinanceira,
    );
    IndicadorEscola contagem(
      String rotulo,
      int? valor,
      IconData icone,
      Acento acento, {
      String? nota,
    }) => (
      rotulo: rotulo,
      valor: valor == null ? semValor : formatInt(valor),
      icone: icone,
      acento: acento,
      nota: nota,
    );
    final estudantes = contagem(
      'Estudantes',
      total('student'),
      WindowsIcons.people,
      Acento.azure,
    );
    final professores = contagem(
      'Professores',
      total('teacher'),
      WindowsIcons.contact,
      Acento.mint,
    );
    final licencas = _licencas;
    return switch (papel) {
      'owner' => [ativos, analises, emAberto, professores],
      'coordinator' => [ativos, analises, estudantes, professores],
      'finance' => [
        emAberto,
        (
          rotulo: 'Custo do mês',
          valor: fin == null ? semValor : formatBrl(custo?.total ?? 0),
          icone: WindowsIcons.calculator,
          acento: Acento.violet,
          nota: (fin?.sample ?? false) ? exemplo : null,
        ),
        contagem(
          'Alunos ativos no mês',
          fin == null ? null : custo?.activeStudents ?? 0,
          WindowsIcons.education,
          Acento.aqua,
          nota: (fin?.sample ?? false) ? exemplo : null,
        ),
        contagem(
          'Faturas vencidas',
          fin?.byStatus
              .where((s) => s.status == 'overdue')
              .fold<int>(0, (t, s) => t + s.count),
          WindowsIcons.warning,
          Acento.coral,
          nota: fin == null ? null : notaFinanceira,
        ),
      ],
      'it_admin' => [
        // Pessoas distintas (uma pessoa com dois papéis conta uma vez).
        contagem(
          'Pessoas ativas',
          licencas?.usuariosAtivos,
          WindowsIcons.people,
          Acento.azure,
        ),
        estudantes,
        professores,
        contagem(
          'Convites abertos',
          licencas?.convitesAbertos,
          WindowsIcons.mail,
          Acento.amber,
        ),
      ],
      _ => const [],
    };
  }

  Widget _cartaoRelatorios(String papel, String nome) {
    void abrir(ReportSection secao) => Navigator.of(context).push(
      MistakeMapPageRoute(
        context: context,
        builder: (_) => SchoolReportsPage(
          schoolId: widget.perfil.escolaId!,
          schoolName: nome,
          repository: widget.relatorios!,
          initial: secao,
        ),
      ),
    );
    final pedagogico = papel != 'finance';
    final financeiro = papel != 'coordinator';
    return CartaoEscola(
      titulo: 'Relatórios',
      subtitulo: switch (papel) {
        'owner' =>
          'Uso pedagógico (alunos ativos, análises, práticas, turmas e mapa '
              'de erros) e financeiro (custo, faturas, pagamentos e formas de '
              'pagamento).',
        'finance' =>
          'Custo pelo uso, faturas, pagamentos e formas de pagamento. '
              'Exporta as faturas em CSV.',
        _ =>
          'Alunos ativos, análises, práticas, turmas e o mapa de erros da '
              'escola, só com totais.',
      },
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (pedagogico)
              FilledButton(
                onPressed: () => abrir(ReportSection.pedagogical),
                child: const Text('Relatório pedagógico'),
              ),
            if (financeiro && pedagogico)
              Button(
                onPressed: () => abrir(ReportSection.financial),
                child: const Text('Relatório financeiro'),
              )
            else if (financeiro)
              FilledButton(
                onPressed: () => abrir(ReportSection.financial),
                child: const Text('Relatório financeiro'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _proximaEtapa(String papel) => CartaoEscola(
    titulo: switch (papel) {
      'owner' => 'Painel do dono',
      'it_admin' => 'Painel de TI',
      'finance' => 'Painel do Financeiro/Compras',
      'teacher' => 'Suas turmas',
      _ => 'Painel da escola',
    },
    children: [
      Text(switch (papel) {
        'owner' =>
          'Escolha o plano e quem paga na seção Cobrança. Numa rede, '
              'convide o Financeiro/Compras: ele paga (Pix, boleto ou cartão) '
              'e você acompanha as faturas. Convide também a coordenação, a '
              'TI e os professores.',
        'finance' =>
          'Você contrata e paga o MistakeMap pela escola: plano, pedido de '
              'compra, centro de custo, boleto ou Pix e nota fiscal. Não vê '
              'respostas nem o mapa de nenhum aluno.',
        'it_admin' =>
          'Você cuida das contas e dos acessos: convites (um a um ou em '
              'lote), quem entrou, aparelhos conectados, senha, suspensão e o '
              'registro de auditoria. A TI não vê respostas, mapa de aluno nem '
              'valores.',
        'teacher' =>
          'Crie e acompanhe suas turmas no perfil Estudante, em Explorar e '
              'aprender > Turmas: a turma fica ligada a esta escola. Aqui você '
              'cria as equipes de robótica.',
        _ =>
          'Convide professores, estudantes e responsáveis em Pessoas. Em '
              'Relatórios '
              'você acompanha o uso da escola e o mapa de erros, só com totais.',
      }, style: TextStyle(color: MistakeMapDesign.content)),
    ],
  );

  /// Quem trabalha na escola, com cargo e área, agrupado por área como num
  /// organograma. Só a gestão e o financeiro recebem essa lista.
  Widget _cartaoOrganograma(List<DadosEscola> pessoas) {
    final porArea = <String, List<DadosEscola>>{};
    for (final p in pessoas) {
      final area = textoOuNulo(p['department']) ?? 'Sem área definida';
      porArea.putIfAbsent(area, () => []).add(p);
    }
    return CartaoEscola(
      titulo: 'Equipe e cargos',
      subtitulo:
          'Quem trabalha na escola, por área. O cargo é só o nome no '
          'organograma; o acesso vem do papel.',
      children: [
        for (final MapEntry(key: area, value: lista) in porArea.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              area,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          for (final p in lista) _LinhaPessoa(pessoa: p),
        ],
      ],
    );
  }

  Widget _cartaoConvites(String papel, List<DadosEscola> convites) {
    final papeis = papeisConvidaveis[papel]!;
    final gestao = const {
      'coordinator',
      'it_admin',
      'finance',
    }.contains(_papelConvite);
    return CartaoEscola(
      titulo: 'Convites',
      subtitulo:
          'O papel só é liberado com o convite. Coordenação e TI recebem '
          'convite pessoal de uso único.',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: InfoLabel(
            label: 'Convidar como',
            child: ComboBox<String>(
              isExpanded: true,
              value: _papelConvite,
              items: [
                for (final p in papeis)
                  ComboBoxItem(value: p, child: Text(nomesPapel[p] ?? p)),
              ],
              onChanged: (v) => setState(() => _papelConvite = v ?? 'teacher'),
            ),
          ),
        ),
        CampoEscola(
          rotulo: gestao
              ? 'E-mail da pessoa (recomendado)'
              : 'E-mail (opcional, prende o convite a uma pessoa)',
          controle: _email,
          teclado: TextInputType.emailAddress,
        ),
        if (!gestao)
          CampoEscola(
            rotulo: 'Quantas pessoas podem usar',
            controle: _usos,
            teclado: TextInputType.number,
          ),
        BotaoEscola(
          'Gerar convite',
          principal: true,
          onPressed: _enviando ? null : _convidar,
        ),
        if (convites.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Convites em aberto',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final c in convites)
            _LinhaConvite(
              convite: c,
              onRenovar: _enviando ? null : () => _renovar(c),
              onRevogar: _enviando
                  ? null
                  : () async {
                      final ok = await _rodar('revoke_invite', {
                        'invite_id': c['id'],
                      });
                      if (ok != null) {
                        _aviso = 'Convite revogado.';
                        await _carregar();
                      }
                    },
            ),
        ],
      ],
    );
  }

  Widget _cartaoEquipes(
    bool podeCriar,
    List<DadosEscola> equipes,
  ) => CartaoEscola(
    titulo: 'Equipes de robótica',
    children: [
      for (final e in equipes)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('${e['name']} · ${competicoes[e['competition']] ?? ''}'),
        ),
      if (equipes.isEmpty)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('Nenhuma equipe ainda.'),
        ),
      if (podeCriar) ...[
        CampoEscola(rotulo: 'Nome da equipe', controle: _equipe),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: InfoLabel(
            label: 'Competição',
            child: ComboBox<String>(
              isExpanded: true,
              value: _competicao,
              items: [
                for (final c in competicoes.entries)
                  ComboBoxItem(value: c.key, child: Text(c.value)),
              ],
              onChanged: (v) => setState(() => _competicao = v ?? 'obr'),
            ),
          ),
        ),
        BotaoEscola('Criar equipe', onPressed: _enviando ? null : _criarEquipe),
      ],
    ],
  );
}

class _LinhaConvite extends StatelessWidget {
  const _LinhaConvite({
    required this.convite,
    required this.onRevogar,
    required this.onRenovar,
  });
  final DadosEscola convite;
  final VoidCallback? onRevogar;

  /// Revoga e gera um código novo igual (perdeu o código, venceu o prazo).
  final VoidCallback? onRenovar;

  @override
  Widget build(BuildContext context) {
    final vence = DateTime.tryParse('${convite['expires_at']}')?.toLocal();
    final email = convite['email'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${nomesPapel[convite['role']] ?? convite['role']}'
              '${email == null ? '' : ' · $email'}'
              ' · ${convite['uses']}/${convite['max_uses']} usos'
              '${vence == null ? '' : ' · vence ${vence.day.toString().padLeft(2, '0')}/${vence.month.toString().padLeft(2, '0')}'}',
            ),
          ),
          const SizedBox(width: 8),
          BotaoEscola('Novo código', onPressed: onRenovar),
          const SizedBox(width: 8),
          BotaoEscola('Revogar', onPressed: onRevogar),
        ],
      ),
    );
  }
}

/// Responsável: filhos acompanhados e o código de consentimento ou da escola.
class TelaResponsavel extends StatefulWidget {
  const TelaResponsavel({
    super.key,
    required this.perfil,
    required this.repositorio,
    required this.onMudou,
  });

  final PerfilAtivo perfil;
  final RepositorioEscola repositorio;
  final VoidCallback onMudou;

  @override
  State<TelaResponsavel> createState() => _TelaResponsavelState();
}

class _TelaResponsavelState extends State<TelaResponsavel> {
  List<DadosEscola> _filhos = [];
  bool _carregando = true;
  bool _enviando = false;
  bool _aceite = false;
  String? _erro;
  String? _aviso;
  final _codigo = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final ctx = await widget.repositorio.executar('context');
      if (mounted) setState(() => _filhos = linhasEscola(ctx['children']));
    } on FalhaEscola catch (f) {
      if (mounted) setState(() => _erro = f.mensagem);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _rodar(String acao, DadosEscola dados, String sucesso) async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
      _aviso = null;
    });
    try {
      await widget.repositorio.executar(acao, dados);
      _aviso = sucesso;
      _codigo.clear();
      _aceite = false;
      widget.onMudou();
      await _carregar();
    } on FalhaEscola catch (f) {
      if (mounted) setState(() => _erro = f.mensagem);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) => _MolduraPerfil(
    perfil: widget.perfil,
    titulo: 'Acompanhar meus filhos',
    subtitulo:
        'O resumo mensal chega nas próximas etapas. Você vê a evolução, nunca '
        'as respostas, o caderno ou o mapa detalhado.',
    onAtualizar: _carregar,
    children: [
      if (_erro != null) AvisoEscola(_erro!),
      if (_aviso != null) AvisoEscola(_aviso!, sucesso: true),
      CartaoEscola(
        titulo: 'Filhos que você acompanha',
        children: [
          if (_carregando)
            const Center(child: ProgressRing())
          else if (_filhos.isEmpty)
            const Text('Nenhum ainda. Use o código abaixo.')
          else
            for (final f in _filhos)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${f['email']}'
                        '${f['revoked_at'] == null ? ' · consentimento ativo' : ' · consentimento retirado'}',
                      ),
                    ),
                    if (f['revoked_at'] == null)
                      BotaoEscola(
                        'Retirar consentimento',
                        onPressed: _enviando
                            ? null
                            : () => _rodar(
                                'revoke_guardian_consent',
                                {'student_id': f['student_id']},
                                'Consentimento retirado. A IA fica bloqueada '
                                    'para ele até um novo aceite.',
                              ),
                      ),
                  ],
                ),
              ),
        ],
      ),
      CartaoEscola(
        titulo: 'Adicionar um código',
        subtitulo:
            'O código que seu filho gerou no app ou o convite de responsável '
            'enviado pela escola.',
        children: [
          CampoEscola(rotulo: 'Código', controle: _codigo, maiusculas: true),
          PlatformCheck(
            checked: _aceite,
            onChanged: (v) => setState(() => _aceite = v ?? false),
            content: const Text(
              'Sou maior de idade e responsável legal pelo estudante. Autorizo '
              'o uso do MistakeMap e da análise por IA dos exercícios dele, '
              'sem anúncios, e sei que posso retirar esta autorização a '
              'qualquer momento.',
            ),
          ),
          const SizedBox(height: 12),
          BotaoEscola(
            'Confirmar',
            principal: true,
            onPressed: _enviando
                ? null
                : () {
                    if (_codigo.text.trim().isEmpty || !_aceite) {
                      setState(
                        () => _erro =
                            'Digite o código e confirme o termo do '
                            'responsável.',
                      );
                      return;
                    }
                    _rodar('guardian_code', {
                      'code': _codigo.text.trim(),
                      'accepted': true,
                    }, 'Código confirmado.');
                  },
          ),
        ],
      ),
    ],
  );
}

class _MolduraPerfil extends StatelessWidget {
  const _MolduraPerfil({
    required this.perfil,
    required this.titulo,
    required this.subtitulo,
    required this.onAtualizar,
    this.secoes = const [],
    this.indice = 0,
    this.onSecao,
    this.avisos = const [],
    this.children = const [],
  });

  final PerfilAtivo perfil;
  final String titulo;
  final String subtitulo;
  final Future<void> Function() onAtualizar;

  /// Seções do perfil; com duas ou mais, aparece a barra de seções.
  final List<SecaoEscola> secoes;
  final int indice;
  final ValueChanged<int>? onSecao;

  /// Erros, avisos e o carregando: ficam acima da seção aberta.
  final List<Widget> avisos;

  /// Conteúdo sem seções (Responsável).
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cadastro = PerfilCadastro.doCodigo(perfil.papel);
    final comBarra = secoes.length >= 2 && onSecao != null;
    final atual = secoes.isEmpty ? null : secoes[indice];
    final cartoes = [...avisos, ...?atual?.cartoes, ...children];
    final cabecalho = LayoutBuilder(
      builder: (context, caixa) {
        final icone = cadastro == null
            ? null
            : GlassIconTile(
                icon: cadastro.icone,
                ink: cadastro.tinta,
                accent: cadastro.acento,
              );
        final textos = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: Tipo.tituloPagina.copyWith(
                color: MistakeMapDesign.primary,
              ),
            ),
            Text(subtitulo, style: TextStyle(color: MistakeMapDesign.steel)),
          ],
        );
        final botoes = Row(
          mainAxisSize: MainAxisSize.min,
          spacing: Espaco.xs,
          children: [
            BotaoRedondo(
              icone: WindowsIcons.refresh,
              dica: 'Atualizar',
              onPressed: onAtualizar,
            ),
            const BotaoAparencia(),
            const BotaoConta(),
          ],
        );
        // No celular os botões ficam numa linha própria, para o
        // nome da escola não quebrar no meio.
        if (caixa.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [?icone, const Spacer(), botoes]),
              const SizedBox(height: 12),
              textos,
            ],
          );
        }
        return Row(
          children: [
            if (icone != null) ...[icone, const SizedBox(width: 12)],
            Expanded(child: textos),
            botoes,
          ],
        );
      },
    );
    return AuroraBackground(
      child: LayoutBuilder(
        builder: (context, tela) {
          final embaixo = tela.maxWidth < larguraBarraEmbaixo;
          final barra = comBarra
              ? BarraSecoesEscola(
                  secoes: secoes,
                  indice: indice,
                  onSelecionar: onSecao!,
                  acento: cadastro?.acento ?? MistakeMapDesign.mist,
                  embaixo: embaixo,
                )
              : null;
          final lista = Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: ListView(
                // Cada seção abre no topo.
                key: ValueKey('painel-${atual?.chave}'),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  cabecalho,
                  const SizedBox(height: 16),
                  if (barra != null && !embaixo) ...[
                    barra,
                    const SizedBox(height: 16),
                  ],
                  ...cartoes,
                ],
              ),
            ),
          );
          final corpo = barra != null && embaixo
              ? Column(
                  children: [
                    Expanded(child: SafeArea(bottom: false, child: lista)),
                    barra,
                  ],
                )
              : SafeArea(child: lista);
          if (!comBarra) return corpo;
          // Voltar numa seção que não é a primeira leva à primeira; na
          // primeira, fecha o app (regra do voltar, etapa 2).
          return PopScope(
            canPop: indice == 0,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) onSecao!(0);
            },
            child: corpo,
          );
        },
      ),
    );
  }
}

class _LinhaPessoa extends StatelessWidget {
  const _LinhaPessoa({required this.pessoa});
  final DadosEscola pessoa;

  @override
  Widget build(BuildContext context) {
    final nome =
        textoOuNulo(pessoa['full_name']) ??
        textoOuNulo(pessoa['email']) ??
        'Pessoa da escola';
    final cargo = textoOuNulo(pessoa['job_title']);
    final papeis = [
      for (final r in pessoa['roles'] is List ? pessoa['roles'] as List : [])
        nomesPapel['$r'] ?? '$r',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(nome),
          Text(
            [?cargo, papeis.join(', ')].where((t) => t.isNotEmpty).join(' · '),
            style: TextStyle(color: MistakeMapDesign.steel),
          ),
        ],
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: MistakeMapDesign.well,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: MistakeMapDesign.border),
    ),
    child: Text(texto),
  );
}
