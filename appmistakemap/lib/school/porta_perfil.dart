import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/design_tokens.dart';
import '../theme/glass_surface.dart';
import 'escola_repositorio.dart';
import 'escola_ui.dart';
import 'painel_escola.dart';
import 'perfil_modelos.dart';
import 'quem_e_voce.dart';

// ─── Porta de perfil ─────────────────────────────────────────────────────────
// Fica entre o login e o app. Conta sem perfil vê "Quem é você?"; quem tem
// mais de um papel ganha o seletor no topo; menor sem escola e sem
// consentimento vê o pedido ao responsável antes de entrar. Sem rede e sem
// contexto salvo, abre direto o app de estudante (a regra de acesso fica no
// servidor, então abrir a tela errada não libera nada).

class PortaDePerfil extends StatefulWidget {
  const PortaDePerfil({
    super.key,
    required this.usuarioId,
    required this.estudante,
    this.repositorio,
    this.preferencias = const PreferenciasPerfil(),
  });

  final String usuarioId;

  /// O app de sempre (navegação do estudante).
  final Widget estudante;
  final RepositorioEscola? repositorio;
  final PreferenciasPerfil preferencias;

  @override
  State<PortaDePerfil> createState() => _PortaDePerfilState();
}

class _PortaDePerfilState extends State<PortaDePerfil> {
  late final RepositorioEscola _repo =
      widget.repositorio ?? RepositorioEscolaSupabase(Supabase.instance.client);

  ContextoPerfil? _ctx;
  bool _carregado = false;
  String? _chaveAtiva;
  bool _consentimentoDispensado = false;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    final salvo = await widget.preferencias.contexto(widget.usuarioId);
    final chave = await widget.preferencias.perfilAtivo(widget.usuarioId);
    if (!mounted) return;
    setState(() {
      _chaveAtiva = chave;
      if (salvo != null) {
        _ctx = salvo;
        _carregado = true;
      }
    });
    await _atualizar();
  }

  Future<void> _atualizar() async {
    try {
      final ctx = await _repo.contexto();
      if (!mounted) return;
      setState(() {
        _ctx = ctx;
        _carregado = true;
      });
      unawaited(widget.preferencias.guardarContexto(widget.usuarioId, ctx));
    } catch (_) {
      // Sem rede ou sem a migration ainda: segue com o que tem (ou o app de
      // estudante) e tenta de novo na próxima abertura.
      if (mounted) setState(() => _carregado = true);
    }
  }

  void _concluiuCadastro(ContextoPerfil ctx) {
    setState(() {
      _ctx = ctx;
      _chaveAtiva = null;
    });
    unawaited(widget.preferencias.guardarContexto(widget.usuarioId, ctx));
    // Confere com o servidor (papéis recém-criados, consentimento).
    unawaited(_atualizar());
  }

  void _trocar(PerfilAtivo perfil) {
    setState(() => _chaveAtiva = perfil.chave);
    unawaited(
      widget.preferencias.guardarPerfilAtivo(widget.usuarioId, perfil.chave),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_carregado) {
      return const AuroraBackground(child: Center(child: ProgressRing()));
    }
    final ctx = _ctx;
    if (ctx == null) return widget.estudante;
    if (ctx.precisaCadastro) {
      return TelaQuemEVoce(repositorio: _repo, onConcluido: _concluiuCadastro);
    }
    final perfis = ctx.perfis;
    final ativo = ctx.perfilInicial(_chaveAtiva);
    Widget conteudo;
    if (ativo.ehEstudante &&
        ctx.consentimentoPendente &&
        !_consentimentoDispensado) {
      conteudo = TelaConsentimentoPendente(
        repositorio: _repo,
        onConferir: _atualizar,
        onContinuar: () => setState(() => _consentimentoDispensado = true),
      );
    } else if (ativo.ehEstudante) {
      conteudo = widget.estudante;
    } else if (ativo.papel == 'guardian' && ativo.escolaId == null) {
      conteudo = TelaResponsavel(
        perfil: ativo,
        repositorio: _repo,
        onMudou: _atualizar,
      );
    } else {
      conteudo = TelaPainelEscola(
        key: ValueKey(ativo.chave),
        perfil: ativo,
        repositorio: _repo,
      );
    }
    // O app de estudante fica vivo (IndexedStack) ao trocar de perfil, para
    // não perder abas, rascunhos e a fila de sincronização.
    final pilha = IndexedStack(
      index: identical(conteudo, widget.estudante) ? 0 : 1,
      children: [
        widget.estudante,
        identical(conteudo, widget.estudante) ? const SizedBox() : conteudo,
      ],
    );
    if (perfis.length < 2) return pilha;
    return Column(
      children: [
        SeletorPerfil(perfis: perfis, ativo: ativo, onTrocar: _trocar),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: pilha,
          ),
        ),
      ],
    );
  }
}

/// Seletor de perfil no topo, para quem tem mais de um papel.
class SeletorPerfil extends StatelessWidget {
  const SeletorPerfil({
    super.key,
    required this.perfis,
    required this.ativo,
    required this.onTrocar,
  });

  final List<PerfilAtivo> perfis;
  final PerfilAtivo ativo;
  final ValueChanged<PerfilAtivo> onTrocar;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      16,
      MediaQuery.paddingOf(context).top + 6,
      16,
      6,
    ),
    decoration: const BoxDecoration(
      color: MistakeMapDesign.surface,
      border: Border(bottom: BorderSide(color: MistakeMapDesign.border)),
    ),
    child: Row(
      children: [
        const Text(
          'Perfil',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: MistakeMapDesign.steel,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, minHeight: 40),
            child: ComboBox<String>(
              isExpanded: true,
              value: ativo.chave,
              items: [
                for (final p in perfis)
                  ComboBoxItem(
                    value: p.chave,
                    child: Text(p.rotulo, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (chave) {
                for (final p in perfis) {
                  if (p.chave == chave) onTrocar(p);
                }
              },
            ),
          ),
        ),
      ],
    ),
  );
}

/// Menor de 18 anos sem escola: gera o código para o responsável aceitar na
/// conta dele. A IA fica bloqueada no servidor até o aceite.
class TelaConsentimentoPendente extends StatefulWidget {
  const TelaConsentimentoPendente({
    super.key,
    required this.repositorio,
    required this.onConferir,
    required this.onContinuar,
  });

  final RepositorioEscola repositorio;
  final Future<void> Function() onConferir;
  final VoidCallback onContinuar;

  @override
  State<TelaConsentimentoPendente> createState() =>
      _TelaConsentimentoPendenteState();
}

class _TelaConsentimentoPendenteState extends State<TelaConsentimentoPendente> {
  bool _enviando = false;
  String? _erro;

  Future<void> _gerar() async {
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final r = await widget.repositorio.executar('request_guardian_consent');
      if (!mounted) return;
      await mostrarCodigo(
        context,
        titulo: 'Código para o seu responsável',
        codigo: '${r['code']}',
        explicacao:
            'Peça para ele criar a conta dele no MistakeMap, escolher "Pai ou '
            'responsável" e digitar este código. Vale por 7 dias.',
      );
    } on FalhaEscola catch (f) {
      if (mounted) setState(() => _erro = f.mensagem);
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
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
            children: [
              CartaoEscola(
                titulo: 'Falta o consentimento do seu responsável',
                subtitulo:
                    'Pela LGPD, quem tem menos de 18 anos e usa o app sem a '
                    'escola precisa da autorização do responsável para usar '
                    'a análise por IA. Sem anúncios, sempre.',
                children: [
                  if (_erro != null) AvisoEscola(_erro!),
                  BotaoEscola(
                    _enviando ? 'Gerando…' : 'Gerar código para o responsável',
                    principal: true,
                    onPressed: _enviando ? null : _gerar,
                  ),
                  const SizedBox(height: 12),
                  BotaoEscola(
                    'Ele já aceitou: conferir',
                    onPressed: _enviando ? null : widget.onConferir,
                  ),
                  const SizedBox(height: 12),
                  BotaoEscola(
                    'Continuar sem a IA por enquanto',
                    onPressed: widget.onContinuar,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Se você entrar numa turma da escola, a escola cuida do '
                    'consentimento e este passo some.',
                    style: TextStyle(color: MistakeMapDesign.steel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
