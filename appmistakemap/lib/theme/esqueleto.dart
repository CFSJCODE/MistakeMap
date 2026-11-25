import 'package:flutter/widgets.dart';

import 'design_tokens.dart';

/// Carregamento com esqueleto: blocos cinza no formato do que vai chegar
/// (cartões, linhas de lista, números), com um brilho que passa devagar.
///
/// Substitui o anel girando quando a tela inteira (ou um cartão inteiro)
/// espera dados. Ações curtas, como "validando…", continuam com o anel.
/// Só usa a biblioteca `widgets`, então serve nas telas Fluent e Material.
class Esqueleto extends StatefulWidget {
  const Esqueleto({super.key, required this.child, this.rotulo = 'Carregando'});

  /// Blocos ([BlocoEsqueleto]) e qualquer moldura ao redor deles.
  final Widget child;

  /// O que o leitor de tela anuncia no lugar dos blocos.
  final String rotulo;

  @override
  State<Esqueleto> createState() => _EsqueletoState();
}

class _EsqueletoState extends State<Esqueleto>
    with SingleTickerProviderStateMixin {
  late final AnimationController _brilho = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Com "reduzir movimento", os blocos ficam parados.
    final parado = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (parado) {
      _brilho
        ..stop()
        ..value = .5;
    } else if (!_brilho.isAnimating) {
      _brilho.repeat();
    }
  }

  @override
  void dispose() {
    _brilho.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Dentro de outro esqueleto, segue o brilho e o rótulo dele.
    if (context.getInheritedWidgetOfExactType<_Brilho>() != null) {
      return widget.child;
    }
    return Semantics(
      label: widget.rotulo,
      liveRegion: true,
      child: ExcludeSemantics(
        child: _Brilho(animacao: _brilho, child: widget.child),
      ),
    );
  }
}

class _Brilho extends InheritedWidget {
  const _Brilho({required this.animacao, required super.child});

  final Animation<double> animacao;

  @override
  bool updateShouldNotify(_Brilho old) => old.animacao != animacao;
}

/// Um bloco do esqueleto: uma linha de texto, um número, um ícone.
class BlocoEsqueleto extends StatelessWidget {
  const BlocoEsqueleto({
    super.key,
    this.largura,
    this.fracao,
    this.altura = 12,
    this.raio = Raio.sm,
  });

  /// Largura fixa. Sem ela (e sem [fracao]), ocupa a largura toda.
  final double? largura;

  /// Fração da largura disponível (0 a 1), alinhada ao início.
  final double? fracao;

  final double altura;
  final double raio;

  @override
  Widget build(BuildContext context) {
    final animacao = context.getInheritedWidgetOfExactType<_Brilho>()?.animacao;
    final escuro = MistakeMapDesign.escuro;
    final base = MistakeMapDesign.tom(escuro ? 0x17 : 0x12);
    final alto = MistakeMapDesign.tom(escuro ? 0x2A : 0x05);
    Widget pintado(double t) => DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(raio),
        color: animacao == null ? base : null,
        gradient: animacao == null
            ? null
            : LinearGradient(
                colors: [base, alto, base],
                stops: const [.3, .5, .7],
                transform: _Deslize(t * 2 - 1),
              ),
      ),
      child: SizedBox(width: largura, height: altura),
    );
    final bloco = animacao == null
        ? pintado(0)
        : AnimatedBuilder(
            animation: animacao,
            builder: (context, _) => pintado(animacao.value),
          );
    if (fracao == null) return bloco;
    return FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: fracao,
      child: bloco,
    );
  }
}

/// Leva o brilho de fora a fora do bloco.
class _Deslize extends GradientTransform {
  const _Deslize(this.deslocamento);

  final double deslocamento;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * deslocamento, 0, 0);
}

/// Moldura de cartão (superfície, borda e cantos dos cartões do app).
class CartaoEsqueleto extends StatelessWidget {
  const CartaoEsqueleto({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Espaco.md),
    decoration: BoxDecoration(
      color: MistakeMapDesign.surface,
      border: Border.all(color: MistakeMapDesign.border),
      borderRadius: BorderRadius.circular(Raio.lg),
    ),
    child: child,
  );
}

/// Lista de cartões: ícone à esquerda, título e uma linha de detalhe.
class EsqueletoLista extends StatelessWidget {
  const EsqueletoLista({super.key, this.itens = 4, this.cartoes = true});

  final int itens;

  /// Falso quando a lista já está dentro de um cartão: só as linhas.
  final bool cartoes;

  @override
  Widget build(BuildContext context) => Esqueleto(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: cartoes ? Espaco.sm : Espaco.md,
      children: [
        for (var i = 0; i < itens; i++)
          cartoes ? CartaoEsqueleto(child: _linha(i)) : _linha(i),
      ],
    ),
  );

  // Larguras alternadas para não parecer um carimbo repetido.
  Widget _linha(int i) => Row(
    spacing: Espaco.sm,
    children: [
      const BlocoEsqueleto(largura: 32, altura: 32),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Espaco.xs,
          children: [
            BlocoEsqueleto(fracao: i.isEven ? .72 : .58, altura: 14),
            BlocoEsqueleto(fracao: i.isEven ? .44 : .52, altura: 10),
          ],
        ),
      ),
    ],
  );
}

/// Grade de cartões de número, no formato da grade de indicadores.
class EsqueletoCartoes extends StatelessWidget {
  const EsqueletoCartoes({super.key, this.quantidade = 4});

  final int quantidade;

  @override
  Widget build(BuildContext context) => Esqueleto(
    child: LayoutBuilder(
      builder: (context, caixa) {
        final escala = MediaQuery.textScalerOf(context).scale(1);
        final largura = caixa.maxWidth / escala;
        final colunas = largura >= 720 ? 4 : (largura >= 280 ? 2 : 1);
        return Wrap(
          spacing: Espaco.sm,
          runSpacing: Espaco.sm,
          children: [
            for (var i = 0; i < quantidade; i++)
              SizedBox(
                width: (caixa.maxWidth - Espaco.sm * (colunas - 1)) / colunas,
                child: const CartaoEsqueleto(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Espaco.xs,
                    children: [
                      BlocoEsqueleto(largura: 32, altura: 32),
                      SizedBox(height: Espaco.xxs),
                      BlocoEsqueleto(largura: 56, altura: 24),
                      BlocoEsqueleto(fracao: .7, altura: 12),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// Página inteira chegando: título, números e uma lista.
class EsqueletoPagina extends StatelessWidget {
  const EsqueletoPagina({super.key, this.numeros = true, this.titulo = true});

  /// Falso nas telas sem grade de números.
  final bool numeros;

  /// Falso quando a tela já mostra o título no cabeçalho.
  final bool titulo;

  @override
  Widget build(BuildContext context) => Esqueleto(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Espaco.md,
      children: [
        if (titulo)
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Espaco.xs,
            children: [
              BlocoEsqueleto(fracao: .5, altura: 22),
              BlocoEsqueleto(fracao: .32, altura: 12),
            ],
          ),
        if (numeros) const EsqueletoCartoes(),
        const EsqueletoLista(itens: 3),
      ],
    ),
  );
}
