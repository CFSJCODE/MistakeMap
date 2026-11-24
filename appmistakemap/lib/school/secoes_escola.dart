import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../theme/design_tokens.dart';
import '../theme/glass_surface.dart';
import '../theme/motion.dart';

// ─── Seções dos painéis de escola ────────────────────────────────────────────
// Cada perfil de escola tem a própria barra: no celular, embaixo, como a do
// aluno; em telas largas, abas logo abaixo do cabeçalho. O conteúdo de cada
// seção são os mesmos cartões de antes, só separados por assunto.

/// Uma seção do painel (Visão geral, Pessoas, Cobrança...).
class SecaoEscola {
  const SecaoEscola({
    required this.chave,
    required this.rotulo,
    required this.icone,
    required this.cartoes,
    this.rotuloCurto,
  });

  final String chave;
  final String rotulo;

  /// Rótulo da barra do celular, quando [rotulo] não cabe na fatia.
  final String? rotuloCurto;
  final IconData icone;
  final List<Widget> cartoes;
}

/// Largura abaixo da qual a barra vai para baixo da tela.
const larguraBarraEmbaixo = 720.0;

/// Barra das seções. [embaixo] escolhe o formato: fatias iguais na base da
/// tela (celular) ou abas em linha (telas largas).
class BarraSecoesEscola extends StatelessWidget {
  const BarraSecoesEscola({
    super.key,
    required this.secoes,
    required this.indice,
    required this.onSelecionar,
    required this.acento,
    required this.embaixo,
  });

  final List<SecaoEscola> secoes;
  final int indice;
  final ValueChanged<int> onSelecionar;

  /// Acento do perfil: marca a seção atual.
  final Color acento;
  final bool embaixo;

  void _tocar(int i) {
    if (i != indice) HapticFeedback.selectionClick();
    onSelecionar(i);
  }

  BoxDecoration get _pilula => BoxDecoration(
    color: Color.alphaBlend(
      acento.withValues(alpha: .22),
      MistakeMapDesign.pelicula(0xC7),
    ),
    borderRadius: BorderRadius.circular(Raio.md),
    border: Border.all(color: acento.withValues(alpha: .55)),
    boxShadow: [
      BoxShadow(
        color: acento.withValues(alpha: .30),
        blurRadius: 14,
        spreadRadius: -6,
        offset: const Offset(0, 5),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final semAnimacao = MediaQuery.disableAnimationsOf(context);
    final duracao = semAnimacao ? Duration.zero : MistakeMapMotion.page;
    if (!embaixo) {
      return Semantics(
        container: true,
        label: 'Seções do painel',
        // Quebra em duas linhas numa janela estreita, sem esconder seção.
        child: Wrap(
          spacing: Espaco.xxs,
          runSpacing: Espaco.xxs,
          children: [
            for (var i = 0; i < secoes.length; i++)
              _AbaLarga(
                key: Key('secao-${secoes[i].chave}'),
                secao: secoes[i],
                atual: i == indice,
                decoracao: _pilula,
                duracao: duracao,
                onPressed: () => _tocar(i),
              ),
          ],
        ),
      );
    }
    final recuo = MediaQuery.paddingOf(context).bottom;
    return Semantics(
      container: true,
      label: 'Seções do painel',
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: GlassSurface(
          tier: GlassTier.liquid,
          radius: 0,
          padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + recuo),
          child: LayoutBuilder(
            builder: (context, caixa) {
              const vao = 2.0;
              final n = secoes.length;
              final largura = (caixa.maxWidth - vao * (n - 1)) / n;
              return Stack(
                children: [
                  // A pílula da seção atual desliza por trás das fatias.
                  AnimatedPositioned(
                    duration: duracao,
                    curve: MistakeMapMotion.curve,
                    left: indice.clamp(0, n - 1) * (largura + vao),
                    top: 0,
                    bottom: 0,
                    width: largura,
                    child: DecoratedBox(decoration: _pilula),
                  ),
                  Row(
                    spacing: vao,
                    children: [
                      for (var i = 0; i < n; i++)
                        Expanded(
                          child: _Fatia(
                            key: Key('secao-${secoes[i].chave}'),
                            secao: secoes[i],
                            atual: i == indice,
                            onPressed: () => _tocar(i),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Fatia extends StatelessWidget {
  const _Fatia({
    super.key,
    required this.secao,
    required this.atual,
    required this.onPressed,
  });

  final SecaoEscola secao;
  final bool atual;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: atual,
    label: secao.rotulo,
    excludeSemantics: true,
    child: HoverButton(
      onPressed: onPressed,
      builder: (context, estados) => PressScale(
        pressed: estados.isPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Raio.md),
            color: !atual && estados.isHovered
                ? MistakeMapDesign.hoverFill(const Color(0x00000000))
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                secao.icone,
                size: 18,
                color: atual
                    ? MistakeMapDesign.abyss
                    : MistakeMapDesign.content,
              ),
              const SizedBox(height: 4),
              Text(
                secao.rotuloCurto ?? secao.rotulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Tipo.legenda.copyWith(
                  fontWeight: atual ? FontWeight.w700 : FontWeight.w600,
                  color: atual
                      ? MistakeMapDesign.abyss
                      : MistakeMapDesign.content,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AbaLarga extends StatelessWidget {
  const _AbaLarga({
    super.key,
    required this.secao,
    required this.atual,
    required this.decoracao,
    required this.duracao,
    required this.onPressed,
  });

  final SecaoEscola secao;
  final bool atual;
  final BoxDecoration decoracao;
  final Duration duracao;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: atual,
    label: secao.rotulo,
    excludeSemantics: true,
    child: HoverButton(
      onPressed: onPressed,
      builder: (context, estados) => PressScale(
        pressed: estados.isPressed,
        child: AnimatedContainer(
          duration: duracao,
          curve: MistakeMapMotion.curve,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: atual
              ? decoracao
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(Raio.md),
                  border: Border.all(color: const Color(0x00000000)),
                  color: estados.isHovered
                      ? MistakeMapDesign.hoverFill(const Color(0x00000000))
                      : null,
                ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Espaco.xs,
            children: [
              Icon(
                secao.icone,
                size: 16,
                color: atual
                    ? MistakeMapDesign.abyss
                    : MistakeMapDesign.content,
              ),
              Text(
                secao.rotulo,
                style: Tipo.corpo.copyWith(
                  fontWeight: atual ? FontWeight.w700 : FontWeight.w600,
                  color: atual
                      ? MistakeMapDesign.abyss
                      : MistakeMapDesign.content,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
