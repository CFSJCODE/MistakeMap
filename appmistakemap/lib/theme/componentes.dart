import 'package:fluent_ui/fluent_ui.dart';

import 'control_styles.dart';
import 'design_tokens.dart';
import 'glass_surface.dart';

// Componentes do design system (DESIGN_SYSTEM.md). Regras comuns:
// - superfície acrílica só no nível do grupo: nada de cartão dentro de cartão;
// - uma ação principal por tela (CartaoProximoPasso); o resto é linha de lista;
// - cor sempre com rótulo, alvo de toque ≥ 48 dp, valores das escalas
//   Espaco/Raio/Tipo, nunca números soltos.

/// Título de seção, com ação opcional à direita ("Ver tudo").
class SecaoTitulo extends StatelessWidget {
  const SecaoTitulo(this.titulo, {super.key, this.descricao, this.acao});

  final String titulo;
  final String? descricao;
  final Widget? acao;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Espaco.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(titulo, style: Tipo.tituloSecao),
              ),
              if (descricao != null) ...[
                const SizedBox(height: Espaco.xxs),
                Text(descricao!, style: Tipo.secundario),
              ],
            ],
          ),
        ),
        ?acao,
      ],
    ),
  );
}

/// Grupo de linhas numa única superfície, separadas por um fio: substitui a
/// pilha de cartões soltos (padrão das listas do iOS e do Fluent 2).
class GrupoLista extends StatelessWidget {
  const GrupoLista({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return GlassSurface(
      radius: Raio.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, filho) in children.indexed) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.only(left: 64),
                child: SizedBox(
                  height: 1,
                  child: ColoredBox(color: MistakeMapDesign.hairline),
                ),
              ),
            filho,
          ],
        ],
      ),
    );
  }
}

/// Linha de lista: ícone com o acento do destino, título, apoio e, se
/// tocável, a seta. Altura mínima de 56 dp.
class LinhaLista extends StatelessWidget {
  const LinhaLista({
    super.key,
    required this.icone,
    required this.titulo,
    this.subtitulo,
    this.acento = MistakeMapDesign.steel,
    this.tinta = MistakeMapDesign.steel,
    this.valor,
    this.onPressed,
  });

  final IconData icone;
  final String titulo;
  final String? subtitulo;
  final Color acento;
  final Color tinta;

  /// Texto curto à direita (uma contagem, por exemplo).
  final String? valor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final conteudo = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                acento.withValues(alpha: .16),
                MistakeMapDesign.white,
              ),
              borderRadius: BorderRadius.circular(Raio.md),
            ),
            child: Icon(icone, size: 18, color: tinta),
          ),
          const SizedBox(width: Espaco.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  textAlign: TextAlign.start,
                  style: Tipo.tituloComponente.copyWith(fontSize: 15),
                ),
                if (subtitulo != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitulo!,
                    textAlign: TextAlign.start,
                    style: Tipo.secundario,
                  ),
                ],
              ],
            ),
          ),
          if (valor != null) ...[
            const SizedBox(width: Espaco.xs),
            Text(valor!, style: Tipo.tituloComponente.copyWith(color: tinta)),
          ],
          if (onPressed != null) ...[
            const SizedBox(width: Espaco.xs),
            const Icon(
              WindowsIcons.chevron_right,
              size: 12,
              color: MistakeMapDesign.steel,
            ),
          ],
        ],
      ),
    );
    final acao = onPressed;
    if (acao == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Espaco.md,
          vertical: Espaco.xs,
        ),
        child: conteudo,
      );
    }
    return Semantics(
      button: true,
      label: subtitulo == null ? titulo : '$titulo. $subtitulo',
      // O nó substitui o do botão: precisa da ação, senão o leitor de tela
      // anuncia a linha e não consegue ativá-la.
      onTap: acao,
      excludeSemantics: true,
      child: MistakeMapButton(
        onPressed: acao,
        style: MistakeMapControls.button(
          radius: Raio.lg,
          padding: const EdgeInsets.symmetric(
            horizontal: Espaco.md,
            vertical: Espaco.xs,
          ),
          background: const Color(0x00FFFFFF),
          foreground: MistakeMapDesign.abyss,
        ),
        child: conteudo,
      ),
    );
  }
}

/// Um indicador da faixa de progresso.
typedef Indicador = ({
  String rotulo,
  String valor,
  IconData icone,
  Color tinta,
});

/// Indicadores lado a lado numa só superfície; empilham quando não cabem
/// (tela estreita ou fonte ampliada).
class FaixaIndicadores extends StatelessWidget {
  const FaixaIndicadores({super.key, required this.itens});

  final List<Indicador> itens;

  @override
  Widget build(BuildContext context) => GlassSurface(
    radius: Raio.lg,
    child: LayoutBuilder(
      builder: (context, limites) {
        final escala = MediaQuery.textScalerOf(context).scale(1);
        final lado = limites.maxWidth / escala >= 112.0 * itens.length;
        Widget item(Indicador i) => Semantics(
          label: '${i.rotulo}: ${i.valor}',
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.all(Espaco.md),
            child: Column(
              crossAxisAlignment: lado
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(i.icone, size: 14, color: i.tinta),
                    const SizedBox(width: Espaco.xs),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(i.valor, style: Tipo.numero),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Espaco.xxs),
                Text(i.rotulo, style: Tipo.secundario),
              ],
            ),
          ),
        );
        const fio = ColoredBox(color: MistakeMapDesign.hairline);
        if (lado) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (n, i) in itens.indexed) ...[
                  if (n > 0) const SizedBox(width: 1, child: fio),
                  Expanded(child: item(i)),
                ],
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (n, i) in itens.indexed) ...[
              if (n > 0) const SizedBox(height: 1, child: fio),
              item(i),
            ],
          ],
        );
      },
    ),
  );
}

/// A ação principal da tela: o que fazer agora, por quê e um único botão
/// cheio. Uma por tela.
class CartaoProximoPasso extends StatelessWidget {
  const CartaoProximoPasso({
    super.key,
    required this.icone,
    required this.titulo,
    required this.descricao,
    required this.rotuloBotao,
    required this.onPressed,
    this.sobretitulo = 'Próximo passo',
    this.acento = MistakeMapDesign.aqua,
    this.tinta = MistakeMapDesign.aquaInk,
    this.carregando = false,
    this.rodape,
  });

  final IconData icone;
  final String sobretitulo;
  final String titulo;
  final String descricao;
  final String rotuloBotao;
  final VoidCallback? onPressed;
  final Color acento;
  final Color tinta;

  /// Dados ainda chegando: o cartão guarda o lugar, sem botão.
  final bool carregando;

  /// Aviso ou ação secundária em texto, abaixo do botão.
  final Widget? rodape;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: sobretitulo,
    child: GlassSurface(
      radius: Raio.xl,
      accent: acento,
      padding: const EdgeInsets.all(Espaco.lg - 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GlassIconTile(icon: icone, ink: tinta, accent: acento, size: 32),
              const SizedBox(width: Espaco.sm),
              Expanded(
                child: Text(
                  sobretitulo.toUpperCase(),
                  style: Tipo.sobretitulo.copyWith(color: tinta),
                ),
              ),
            ],
          ),
          const SizedBox(height: Espaco.md),
          if (carregando) ...[
            const Center(
              child: SizedBox.square(dimension: 28, child: ProgressRing()),
            ),
            const SizedBox(height: Espaco.xs),
          ] else ...[
            Text(titulo, style: Tipo.tituloPagina.copyWith(fontSize: 22)),
            const SizedBox(height: Espaco.xs),
            Text(descricao, style: Tipo.corpo),
            const SizedBox(height: Espaco.md),
            ConstrainedBox(
              // Altura mínima, não fixa: com fonte ampliada o rótulo quebra
              // em duas linhas e o botão cresce junto.
              constraints: const BoxConstraints(minHeight: Espaco.alvoToque),
              child: MistakeMapFilledButton(
                onPressed: onPressed,
                child: Text(rotuloBotao, textAlign: TextAlign.center),
              ),
            ),
          ],
          if (rodape != null) ...[const SizedBox(height: Espaco.sm), rodape!],
        ],
      ),
    ),
  );
}

/// Aviso curto dentro de uma seção (sem rede, falha, confirmação).
class AvisoLinha extends StatelessWidget {
  const AvisoLinha(this.texto, {super.key, this.erro = false});

  final String texto;
  final bool erro;

  @override
  Widget build(BuildContext context) {
    final tinta = erro ? MistakeMapDesign.coralInk : MistakeMapDesign.steel;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              erro ? WindowsIcons.error_badge : WindowsIcons.info,
              size: 14,
              color: tinta,
            ),
          ),
          const SizedBox(width: Espaco.xs),
          Expanded(
            child: Text(texto, style: Tipo.secundario.copyWith(color: tinta)),
          ),
        ],
      ),
    );
  }
}
