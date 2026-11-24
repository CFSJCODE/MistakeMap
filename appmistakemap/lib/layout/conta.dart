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

/// Botão redondo do topo, com o ícone do perfil atual.
class BotaoConta extends StatelessWidget {
  const BotaoConta({super.key, this.tamanho = 44});

  final double tamanho;

  @override
  Widget build(BuildContext context) {
    final conta = ContaAtual.of(context);
    final acoes = AcoesConta.of(context);
    if (conta == null && acoes == null) return const SizedBox.shrink();
    final perfil = conta == null
        ? null
        : PerfilCadastro.doCodigo(conta.ativo.papel);
    final nome = conta == null ? null : nomeDoPerfil(conta.ativo);
    return Semantics(
      button: true,
      label: nome == null ? 'Conta' : 'Conta e perfis. Perfil atual: $nome',
      onTap: () => mostrarConta(context),
      excludeSemantics: true,
      child: Tooltip(
        message: 'Conta e perfis',
        child: SizedBox.square(
          dimension: tamanho,
          child: IconButton(
            key: const Key('botao-conta'),
            icon: Icon(
              perfil?.icone ?? WindowsIcons.contact,
              size: 18,
              color: perfil?.tinta ?? MistakeMapDesign.abyss,
            ),
            style: ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(
                Color.alphaBlend(
                  (perfil?.acento ?? MistakeMapDesign.mist).withValues(
                    alpha: .18,
                  ),
                  MistakeMapDesign.pelicula(0xE6),
                ),
              ),
              shape: WidgetStatePropertyAll(
                CircleBorder(
                  side: BorderSide(
                    color: (perfil?.acento ?? MistakeMapDesign.hairline)
                        .withValues(alpha: .55),
                  ),
                ),
              ),
            ),
            onPressed: () => mostrarConta(context),
          ),
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
