import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../platform/platform_forms.dart' show PlatformCheck;
import '../theme/design_tokens.dart';
import '../theme/glass_surface.dart';
import 'escola_repositorio.dart';
import 'escola_ui.dart';
import 'perfil_modelos.dart';

// ─── Cadastro por perfil: "Quem é você?" ─────────────────────────────────────
// Primeira tela depois de criar a conta. A escolha define o que o app pede em
// seguida. Professor da escola, coordenação e TI só ganham o papel com
// convite: quem confere é o servidor (school-admin + trigger do banco).

class TelaQuemEVoce extends StatefulWidget {
  const TelaQuemEVoce({
    super.key,
    required this.repositorio,
    required this.onConcluido,
    this.hoje,
  });

  final RepositorioEscola repositorio;
  final ValueChanged<ContextoPerfil> onConcluido;

  /// Data de referência para a idade (testes).
  final DateTime? hoje;

  @override
  State<TelaQuemEVoce> createState() => _TelaQuemEVoceState();
}

class _TelaQuemEVoceState extends State<TelaQuemEVoce> {
  PerfilCadastro? _perfil;
  bool _enviando = false;
  String? _erro;
  bool _semConvite = false;
  bool _aceite = false;
  String _funcao = 'programacao';

  final _nascimento = TextEditingController();
  final _codigo = TextEditingController();
  final _codigoTurma = TextEditingController();
  final _nome = TextEditingController();
  final _cnpj = TextEditingController();

  @override
  void dispose() {
    for (final c in [_nascimento, _codigo, _codigoTurma, _nome, _cnpj]) {
      c.dispose();
    }
    super.dispose();
  }

  void _escolher(PerfilCadastro? perfil) => setState(() {
    _perfil = perfil;
    _erro = null;
    _semConvite = false;
    _aceite = false;
    _codigo.clear();
    _codigoTurma.clear();
  });

  Future<void> _continuar() async {
    final perfil = _perfil;
    if (perfil == null || _enviando) return;
    DateTime? nascimento;
    if (perfil.pedeNascimento) {
      nascimento = lerDataNascimento(_nascimento.text, hoje: widget.hoje);
      if (nascimento == null) {
        setState(() => _erro = 'Informe a data de nascimento (DD/MM/AAAA).');
        return;
      }
    }
    final codigo = _codigo.text.trim();
    final turma = _codigoTurma.text.trim();
    final faltando = switch (perfil) {
      PerfilCadastro.estudanteEquipe when codigo.isEmpty =>
        'Informe o código da equipe.',
      PerfilCadastro.professor when !_semConvite && codigo.isEmpty =>
        'Informe o código do convite ou comece no plano Grátis.',
      PerfilCadastro.professor when _semConvite && _nome.text.trim().isEmpty =>
        'Dê um nome ao seu espaço de turmas.',
      PerfilCadastro.responsavel when codigo.isEmpty =>
        'Informe o código que você recebeu.',
      PerfilCadastro.responsavel when !_aceite =>
        'Confirme o termo do responsável para continuar.',
      PerfilCadastro.dono when _nome.text.trim().length < 2 =>
        'Informe o nome da escola.',
      PerfilCadastro.coordenador || PerfilCadastro.ti when codigo.isEmpty =>
        'Informe o código do convite enviado pelo dono da escola.',
      _ => null,
    };
    if (faltando != null) {
      setState(() => _erro = faltando);
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final repo = widget.repositorio;
    try {
      switch (perfil) {
        case PerfilCadastro.estudante:
          if (codigo.isNotEmpty) {
            await repo.executar('join_class', {'code': codigo});
          }
        case PerfilCadastro.estudanteEquipe:
          await repo.executar('join_team', {
            'code': codigo,
            'team_role': _funcao,
          });
          if (turma.isNotEmpty) {
            await repo.executar('join_class', {'code': turma});
          }
        case PerfilCadastro.professor:
          if (_semConvite) {
            await repo.executar('start_free_teacher', {
              'name': _nome.text.trim(),
            });
          } else {
            await repo.executar('redeem_invite', {
              'code': codigo,
              'persona': perfil.codigo,
            });
          }
        case PerfilCadastro.responsavel:
          await repo.executar('guardian_code', {
            'code': codigo,
            'accepted': _aceite,
          });
        case PerfilCadastro.dono:
          await repo.executar('create_school', {
            'name': _nome.text.trim(),
            if (_cnpj.text.trim().isNotEmpty) 'cnpj': _cnpj.text.trim(),
          });
        case PerfilCadastro.coordenador || PerfilCadastro.ti:
          await repo.executar('redeem_invite', {
            'code': codigo,
            'persona': perfil.codigo,
          });
      }
      final resposta = await repo.executar('save_profile', {
        'persona': perfil.codigo,
        if (nascimento != null) 'birth_date': dataIso(nascimento),
      });
      if (!mounted) return;
      widget.onConcluido(ContextoPerfil.deJson(resposta));
    } on FalhaEscola catch (falha) {
      if (mounted) setState(() => _erro = falha.mensagem);
    } catch (_) {
      if (mounted) {
        setState(() => _erro = 'Não foi possível concluir. Tente de novo.');
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuroraBackground(
    child: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
            children: _perfil == null ? _escolha() : _formulario(_perfil!),
          ),
        ),
      ),
    ),
  );

  List<Widget> _escolha() => [
    const Text(
      'Quem é você?',
      style: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: MistakeMapDesign.primary,
      ),
    ),
    const SizedBox(height: 8),
    const Text(
      'Escolha como você vai usar o MistakeMap. Dá para ter mais de um perfil '
      'depois: o app mostra um seletor no topo.',
      style: TextStyle(fontSize: 16, color: MistakeMapDesign.content),
    ),
    const SizedBox(height: 24),
    LayoutBuilder(
      builder: (context, caixa) {
        final colunas = caixa.maxWidth >= 640 ? 2 : 1;
        final largura = (caixa.maxWidth - 12 * (colunas - 1)) / colunas;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final p in PerfilCadastro.values)
              SizedBox(
                width: largura,
                child: _CartaoPerfil(perfil: p, onTap: () => _escolher(p)),
              ),
          ],
        );
      },
    ),
  ];

  List<Widget> _formulario(PerfilCadastro perfil) => [
    Row(
      children: [
        Tooltip(
          message: 'Voltar',
          child: IconButton(
            icon: const Icon(WindowsIcons.back, size: 18),
            onPressed: _enviando ? null : () => _escolher(null),
          ),
        ),
        const SizedBox(width: 8),
        GlassIconTile(
          icon: perfil.icone,
          ink: perfil.tinta,
          accent: perfil.acento,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            perfil.titulo,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: MistakeMapDesign.primary,
            ),
          ),
        ),
      ],
    ),
    const SizedBox(height: 16),
    CartaoEscola(
      titulo: _tituloFormulario(perfil),
      subtitulo: _explicacao(perfil),
      children: [
        if (_erro != null) AvisoEscola(_erro!),
        ..._campos(perfil),
        const SizedBox(height: 8),
        BotaoEscola(
          _enviando ? 'Enviando…' : 'Continuar',
          principal: true,
          onPressed: _enviando ? null : _continuar,
        ),
      ],
    ),
  ];

  String _tituloFormulario(PerfilCadastro p) => switch (p) {
    PerfilCadastro.estudante => 'Sua turma e sua idade',
    PerfilCadastro.estudanteEquipe => 'Sua equipe e sua função',
    PerfilCadastro.professor => 'Convite da escola ou plano Grátis',
    PerfilCadastro.responsavel => 'Código do seu filho ou da escola',
    PerfilCadastro.dono => 'Sua escola',
    PerfilCadastro.coordenador || PerfilCadastro.ti => 'Convite do dono',
  };

  String _explicacao(PerfilCadastro p) => switch (p) {
    PerfilCadastro.estudante =>
      'Sem código, você estuda por conta própria. Menores de 18 anos sem '
          'escola precisam do consentimento do responsável para usar a IA.',
    PerfilCadastro.estudanteEquipe =>
      'O técnico da equipe passa o código. Você pode trocar de função ou sair '
          'da equipe depois.',
    PerfilCadastro.professor =>
      'Com o convite da escola você entra nas turmas dela. Sem convite, '
          'começa no plano Grátis: 1 turma com até 4 alunos.',
    PerfilCadastro.responsavel =>
      'Use o código que seu filho mostrou no app (consentimento) ou o que a '
          'escola enviou. Você acompanha a evolução, sem ver respostas nem o '
          'caderno.',
    PerfilCadastro.dono =>
      'A escola começa no plano Grátis. O plano, o contrato e a cobrança vêm '
          'nas próximas etapas, no painel do dono.',
    PerfilCadastro.coordenador || PerfilCadastro.ti =>
      'Este perfil só é liberado com o convite pessoal que o dono da escola '
          'criou para o seu e-mail.',
  };

  List<Widget> _campos(PerfilCadastro p) {
    final nascimento = CampoEscola(
      rotulo: 'Data de nascimento',
      controle: _nascimento,
      dica: 'DD/MM/AAAA',
      teclado: TextInputType.number,
      formatos: const [FormatoData()],
    );
    final codigoConvite = CampoEscola(
      rotulo: 'Código do convite',
      controle: _codigo,
      dica: 'Ex.: K7P2M9QRT4WX',
      maiusculas: true,
    );
    switch (p) {
      case PerfilCadastro.estudante:
        return [
          nascimento,
          CampoEscola(
            rotulo: 'Código da turma ou da escola (opcional)',
            controle: _codigo,
            dica: 'Deixe em branco para estudar por conta própria',
          ),
        ];
      case PerfilCadastro.estudanteEquipe:
        return [
          nascimento,
          CampoEscola(
            rotulo: 'Código da equipe',
            controle: _codigo,
            maiusculas: true,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: InfoLabel(
              label: 'Sua função na equipe',
              child: ComboBox<String>(
                isExpanded: true,
                value: _funcao,
                items: [
                  for (final f in funcoesEquipe.entries)
                    ComboBoxItem(value: f.key, child: Text(f.value)),
                ],
                onChanged: (v) => setState(() => _funcao = v ?? _funcao),
              ),
            ),
          ),
          CampoEscola(
            rotulo: 'Código da turma (opcional)',
            controle: _codigoTurma,
          ),
        ];
      case PerfilCadastro.professor:
        return [
          PlatformCheck(
            checked: _semConvite,
            onChanged: (v) => setState(() => _semConvite = v ?? false),
            content: const Text('Não tenho convite: começar no plano Grátis'),
          ),
          const SizedBox(height: 12),
          if (_semConvite)
            CampoEscola(
              rotulo: 'Nome do seu espaço de turmas',
              controle: _nome,
              dica: 'Ex.: Robótica com a Prof.ª Ana',
            )
          else
            codigoConvite,
        ];
      case PerfilCadastro.responsavel:
        return [
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
        ];
      case PerfilCadastro.dono:
        return [
          CampoEscola(
            rotulo: 'Nome da escola, curso ou equipe',
            controle: _nome,
          ),
          CampoEscola(
            rotulo: 'CNPJ (opcional agora, obrigatório para cobrança)',
            controle: _cnpj,
            dica: '00.000.000/0000-00',
            teclado: TextInputType.number,
            formatos: [FilteringTextInputFormatter.allow(RegExp(r'[0-9./-]'))],
          ),
        ];
      case PerfilCadastro.coordenador || PerfilCadastro.ti:
        return [codigoConvite];
    }
  }
}

class _CartaoPerfil extends StatelessWidget {
  const _CartaoPerfil({required this.perfil, required this.onTap});

  final PerfilCadastro perfil;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: perfil.titulo,
    child: HoverButton(
      onPressed: onTap,
      builder: (context, estados) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: const BoxConstraints(minHeight: 112),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: estados.isHovered
              ? MistakeMapDesign.hover
              : MistakeMapDesign.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: estados.isHovered
                ? MistakeMapDesign.highlight
                : MistakeMapDesign.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassIconTile(
              icon: perfil.icone,
              ink: perfil.tinta,
              accent: perfil.acento,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    perfil.titulo,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: MistakeMapDesign.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    perfil.descricao,
                    style: const TextStyle(color: MistakeMapDesign.content),
                  ),
                  if (perfil.soComConvite) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Só com convite',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: MistakeMapDesign.warn,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
