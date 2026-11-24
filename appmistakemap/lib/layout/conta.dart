import 'package:fluent_ui/fluent_ui.dart';

import '../school/perfil_modelos.dart';
import '../theme/aparencia.dart';
import '../theme/aparencia_dialogo.dart';
import '../theme/design_tokens.dart';

// ─── Botão de conta ──────────────────────────────────────────────────────────
// Um lugar só, no topo de toda tela, para o que é da conta: trocar de perfil
// (sem pedir a senha de novo; quem confere o papel continua sendo o
// servidor), aparência, sobre e sair. Substitui a barra "Trocar perfil" e o
// menu Mais da barra de baixo.

/// Perfis da conta, vindos da porta de perfil.
class ContaAtual extends InheritedWidget {
  const ContaAtual({
    super.key,
    required this.perfis,
    required this.ativo,
    required this.onTrocar,
    required this.onSair,
    required super.child,
  });

  final List<PerfilAtivo> perfis;
  final PerfilAtivo ativo;
  final ValueChanged<PerfilAtivo> onTrocar;

  /// Sai da conta sem perguntar (o botão pergunta antes).
  final Future<void> Function() onSair;

  static ContaAtual? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContaAtual>();

  @override
  bool updateShouldNotify(ContaAtual old) =>
      old.ativo.chave != ativo.chave ||
      old.perfis.length != perfis.length ||
      old.onTrocar != onTrocar ||
      old.onSair != onSair;
}

/// Um item do menu da conta além de perfis, aparência e sair.
class ItemConta {
  const ItemConta({
    required this.chave,
    required this.icone,
    required this.rotulo,
    required this.onPressed,
  });

  final String chave;
  final IconData icone;
  final String rotulo;
  final VoidCallback onPressed;
}

/// O que a tela de navegação acrescenta ao menu (Sobre, Administração) e o
/// e-mail da conta. Sem a porta de perfil (offline), é daqui que vem o sair.
class AcoesConta extends InheritedWidget {
  const AcoesConta({
    super.key,
    this.email,
    this.itens = const [],
    this.onSair,
    required super.child,
  });

  final String? email;
  final List<ItemConta> itens;
  final Future<void> Function()? onSair;

  static AcoesConta? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AcoesConta>();

  @override
  bool updateShouldNotify(AcoesConta old) =>
      old.email != email || old.itens != itens || old.onSair != onSair;
}

/// Nome do papel sem a escola (a escola vai na segunda linha).
String nomeDoPerfil(PerfilAtivo perfil) {
  final base = nomesPapel[perfil.papel] ?? perfil.papel;
  final cargo = perfil.cargo;
  return cargo != null && papeisGestao.contains(perfil.papel)
      ? '$base ($cargo)'
      : base;
}

/// Botão redondo do topo, com o ícone do perfil atual: um "avatar" no acento
/// do perfil, com aro da superfície e sombra na cor do acento, que sobe no
/// hover e afunda ao tocar.
class BotaoConta extends StatelessWidget {
  const BotaoConta({super.key, this.tamanho = 44});

  /// Área de toque (o avatar ocupa 88% dela).
  final double tamanho;

  /// Acento neutro (TI e conta sem perfil): o "mist" da paleta clara, igual
  /// nos dois temas para o glifo escuro continuar legível.
  static const _neutro = Color(0xFF9BA8AB);

  @override
  Widget build(BuildContext context) {
    final conta = ContaAtual.of(context);
    final acoes = AcoesConta.of(context);
    if (conta == null && acoes == null) return const SizedBox.shrink();
    final perfil = conta == null
        ? null
        : PerfilCadastro.doCodigo(conta.ativo.papel);
    final nome = conta == null ? null : nomeDoPerfil(conta.ativo);
    final acento = perfil?.tom?.cor ?? _neutro;
    return Semantics(
      button: true,
      label: nome == null ? 'Conta' : 'Conta e perfis. Perfil atual: $nome',
      onTap: () => mostrarConta(context),
      excludeSemantics: true,
      child: Tooltip(
        message: 'Conta e perfis',
        child: SizedBox.square(
          dimension: tamanho,
          child: HoverButton(
            key: const Key('botao-conta'),
            onPressed: () => mostrarConta(context),
            builder: (context, estados) => Center(
              child: _Avatar(
                icone: perfil?.icone ?? WindowsIcons.contact,
                acento: acento,
                diametro: tamanho * .88,
                hover: estados.isHovered,
                pressionado: estados.isPressed,
                foco: estados.isFocused,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.icone,
    required this.acento,
    required this.diametro,
    required this.hover,
    required this.pressionado,
    required this.foco,
  });

  final IconData icone;
  final Color acento;
  final double diametro;
  final bool hover, pressionado, foco;

  @override
  Widget build(BuildContext context) {
    final reduzir = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duracao = reduzir ? Duration.zero : Movimento.rapido;
    // Sombra em duas camadas: o brilho colorido do acento, que dá a cor ao
    // redor, e uma sombra curta e escura que assenta o botão na barra.
    final elevacao = pressionado ? 0.0 : (hover ? 1.0 : .6);
    final sombras = [
      if (foco) BoxShadow(color: MistakeMapDesign.abyss, spreadRadius: 3.5),
      BoxShadow(
        color: acento.withValues(
          alpha: (MistakeMapDesign.escuro ? .38 : .50) * elevacao,
        ),
        blurRadius: 6 + 10 * elevacao,
        spreadRadius: -1,
        offset: Offset(0, 1 + 5 * elevacao),
      ),
      BoxShadow(
        color: MistakeMapDesign.sombra(0x29),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
    ];
    return AnimatedScale(
      scale: pressionado ? .93 : (hover ? 1.04 : 1),
      duration: duracao,
      curve: Movimento.curva,
      child: AnimatedContainer(
        duration: duracao,
        curve: Movimento.curva,
        width: diametro,
        height: diametro,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Do acento mais claro (luz de cima) ao mais fundo (embaixo).
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(acento, const Color(0xFFFFFFFF), hover ? .30 : .22)!,
              Color.lerp(acento, MistakeMapDesign.onAccent, .14)!,
            ],
          ),
          // Aro da superfície: separa o avatar do vidro em qualquer fundo.
          border: Border.all(color: MistakeMapDesign.raised, width: 2),
          boxShadow: sombras,
        ),
        // Reflexo no topo, como nos outros vidros do app.
        foregroundDecoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.center,
            colors: [
              const Color(0xFFFFFFFF).withValues(alpha: .35),
              const Color(0x00FFFFFF),
            ],
          ),
        ),
        child: Icon(
          icone,
          size: diametro * .5,
          color: MistakeMapDesign.onAccent,
        ),
      ),
    );
  }
}

/// Menu da conta: perfis desta conta, aparência, os itens da tela e sair.
Future<void> mostrarConta(BuildContext context) {
  final conta = ContaAtual.of(context);
  final acoes = AcoesConta.of(context);
  // A porta de perfil sabe voltar ao início depois de sair; sem ela
  // (offline), vale o sair da tela.
  final sair = conta?.onSair ?? acoes?.onSair;
  final perfis = conta?.perfis ?? const <PerfilAtivo>[];
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogo) {
      void fecharE(VoidCallback acao) {
        Navigator.of(dialogo).pop();
        acao();
      }

      Widget item(
        String chave,
        IconData icone,
        String rotulo,
        VoidCallback acao,
      ) => ListTile(
        key: Key('conta-$chave'),
        leading: Icon(icone, size: 18, color: MistakeMapDesign.deep),
        title: Text(rotulo, style: Tipo.corpo),
        onPressed: () => fecharE(acao),
      );

      return ContentDialog(
        constraints: const BoxConstraints(maxWidth: 420),
        title: const Text('Sua conta'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (acoes?.email case final email?) ...[
                Text(
                  email,
                  key: const Key('conta-email'),
                  style: Tipo.secundario.copyWith(
                    color: MistakeMapDesign.steel,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Espaco.md),
              ],
              if (conta != null && perfis.length >= 2) ...[
                Text(
                  'Perfis desta conta',
                  style: Tipo.tituloComponente.copyWith(
                    color: MistakeMapDesign.primary,
                  ),
                ),
                const SizedBox(height: Espaco.xs),
                for (final p in perfis)
                  _LinhaPerfil(
                    perfil: p,
                    atual: p.chave == conta.ativo.chave,
                    onPressed: () => fecharE(() {
                      if (p.chave != conta.ativo.chave) conta.onTrocar(p);
                    }),
                  ),
                const SizedBox(height: Espaco.sm),
                const Divider(),
                const SizedBox(height: Espaco.sm),
              ],
              if (Aparencia.disponivel)
                item(
                  'aparencia',
                  WindowsIcons.brightness,
                  'Aparência',
                  () => mostrarAparencia(context),
                ),
              for (final extra in acoes?.itens ?? const <ItemConta>[])
                item(extra.chave, extra.icone, extra.rotulo, extra.onPressed),
              if (sair != null)
                item(
                  'sair',
                  WindowsIcons.sign_out,
                  'Sair da conta',
                  () => _confirmarSaida(context, sair),
                ),
            ],
          ),
        ),
        actions: [
          Button(
            child: const Text('Fechar'),
            onPressed: () => Navigator.of(dialogo).pop(),
          ),
        ],
      );
    },
  );
}

Future<void> _confirmarSaida(
  BuildContext context,
  Future<void> Function() sair,
) async {
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogo) => ContentDialog(
      title: const Text('Sair da conta'),
      content: const Text('Deseja sair do MistakeMap neste aparelho?'),
      actions: [
        Button(
          child: const Text('Cancelar'),
          onPressed: () => Navigator.of(dialogo).pop(false),
        ),
        FilledButton(
          key: const Key('conta-sair-confirmar'),
          child: const Text('Sair'),
          onPressed: () => Navigator.of(dialogo).pop(true),
        ),
      ],
    ),
  );
  if (ok == true) await sair();
}

class _LinhaPerfil extends StatelessWidget {
  const _LinhaPerfil({
    required this.perfil,
    required this.atual,
    required this.onPressed,
  });

  final PerfilAtivo perfil;
  final bool atual;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cadastro = PerfilCadastro.doCodigo(perfil.papel);
    final escola = perfil.escolaNome;
    return Semantics(
      selected: atual,
      child: ListTile.selectable(
        key: Key('conta-perfil-${perfil.chave}'),
        selected: atual,
        leading: Icon(
          cadastro?.icone ?? WindowsIcons.contact,
          size: 18,
          color: cadastro?.tinta ?? MistakeMapDesign.deep,
        ),
        title: Text(nomeDoPerfil(perfil), style: Tipo.corpo),
        subtitle: escola == null
            ? null
            : Text(
                escola,
                style: Tipo.secundario.copyWith(color: MistakeMapDesign.steel),
              ),
        trailing: atual
            ? Icon(
                WindowsIcons.check_mark,
                size: 14,
                color: MistakeMapDesign.deep,
              )
            : null,
        onPressed: onPressed,
      ),
    );
  }
}
