import 'package:fluent_ui/fluent_ui.dart';

import '../billing/billing_panel.dart';
import '../billing/billing_repository.dart';
import '../platform/platform_forms.dart' show PlatformCheck;
import '../reports/school_reports.dart';
import '../reports/school_reports_page.dart';
import '../theme/design_tokens.dart';
import '../theme/glass_surface.dart';
import 'escola_repositorio.dart';
import 'escola_ui.dart';
import 'perfil_modelos.dart';

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
  });

  final PerfilAtivo perfil;
  final RepositorioEscola repositorio;

  /// Cobrança (Edge Function school-billing). Sem ela, o cartão não aparece.
  final BillingRepository? cobranca;

  /// Relatórios (RPC school_reports). Sem ele, o cartão não aparece.
  final SchoolReportsRepository? relatorios;

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
    final podeConvidar = papeisConvidaveis.containsKey(papel);
    final podeEquipe = const {
      'owner',
      'coordinator',
      'teacher',
    }.contains(papel);
    return _MolduraPerfil(
      perfil: widget.perfil,
      titulo: '${escola['name'] ?? widget.perfil.escolaNome ?? 'Escola'}',
      subtitulo:
          '${nomesPapel[papel] ?? papel} · plano '
          '${nomesPlano[escola['plan']] ?? 'Grátis'}',
      onAtualizar: _carregar,
      children: [
        if (_erro != null) AvisoEscola(_erro!),
        if (_aviso != null) AvisoEscola(_aviso!, sucesso: true),
        if (_carregando)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: ProgressRing()),
          )
        else ...[
          _proximaEtapa(papel),
          if (widget.cobranca != null &&
              widget.perfil.escolaId != null &&
              const {'owner', 'finance', 'coordinator'}.contains(papel))
            CartaoCobranca(
              escolaId: widget.perfil.escolaId!,
              escolaNome:
                  '${escola['name'] ?? widget.perfil.escolaNome ?? 'Escola'}',
              papel: papel,
              repositorio: widget.cobranca!,
            ),
          if (widget.relatorios != null &&
              widget.perfil.escolaId != null &&
              const {'owner', 'finance', 'coordinator'}.contains(papel))
            _cartaoRelatorios(
              papel,
              '${escola['name'] ?? widget.perfil.escolaNome ?? 'Escola'}',
            ),
          if (membros.isNotEmpty && papel != 'teacher')
            CartaoEscola(
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
            ),
          if (podeConvidar) _cartaoConvites(papel, convites),
          if (podeEquipe || equipes.isNotEmpty)
            _cartaoEquipes(podeEquipe, equipes),
        ],
      ],
    );
  }

  Widget _cartaoRelatorios(String papel, String nome) {
    void abrir(ReportSection secao) => Navigator.of(context).push(
      FluentPageRoute(
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
          'Escolha o plano e quem paga em "Plano e cobrança". Numa rede, '
              'convide o Financeiro/Compras: ele paga (Pix, boleto ou cartão) '
              'e você acompanha as faturas. Convide também a coordenação, a '
              'TI e os professores.',
        'finance' =>
          'Você contrata e paga o MistakeMap pela escola: plano, pedido de '
              'compra, centro de custo, boleto ou Pix e nota fiscal. Não vê '
              'respostas nem o mapa de nenhum aluno.',
        'it_admin' =>
          'Convide professores, estudantes e responsáveis. Busca de usuários, '
              'importação por planilha e uso dos aparelhos chegam nas próximas '
              'etapas. A TI não vê respostas nem o mapa de nenhum aluno.',
        'teacher' =>
          'Crie e acompanhe suas turmas no perfil Estudante, em Explorar e '
              'aprender > Turmas: a turma fica ligada a esta escola. Aqui você '
              'cria as equipes de robótica.',
        _ =>
          'Convide professores, estudantes e responsáveis. Em "Relatórios" '
              'você acompanha o uso da escola e o mapa de erros, só com totais.',
      }, style: const TextStyle(color: MistakeMapDesign.content)),
    ],
  );

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
  const _LinhaConvite({required this.convite, required this.onRevogar});
  final DadosEscola convite;
  final VoidCallback? onRevogar;

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
    required this.children,
  });

  final PerfilAtivo perfil;
  final String titulo;
  final String subtitulo;
  final Future<void> Function() onAtualizar;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cadastro = PerfilCadastro.doCodigo(perfil.papel);
    return AuroraBackground(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Row(
                  children: [
                    if (cadastro != null) ...[
                      GlassIconTile(
                        icon: cadastro.icone,
                        ink: cadastro.tinta,
                        accent: cadastro.acento,
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titulo,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: MistakeMapDesign.primary,
                            ),
                          ),
                          Text(
                            subtitulo,
                            style: const TextStyle(
                              color: MistakeMapDesign.steel,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Tooltip(
                      message: 'Atualizar',
                      child: IconButton(
                        icon: const Icon(WindowsIcons.refresh, size: 18),
                        onPressed: onAtualizar,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...children,
              ],
            ),
          ),
        ),
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
