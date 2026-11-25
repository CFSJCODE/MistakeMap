import 'package:fluent_ui/fluent_ui.dart';

import 'design_tokens.dart';
import 'motion.dart';

/// Botão redondo de vidro das barras do topo (Voltar, Atualizar, Aparência).
///
/// Tem o mesmo desenho do botão de conta (`BotaoConta`): um círculo com 88%
/// da área de toque, reflexo no topo, sombra curta que sobe no hover, anel de
/// foco e o toque de 0,97. A diferença é o preenchimento: aqui é a película
/// de vidro da superfície, e não o acento do perfil, para o avatar continuar
/// sendo o único botão colorido da barra.
class BotaoRedondo extends StatelessWidget {
  const BotaoRedondo({
    super.key,
    required this.icone,
    required this.dica,
    required this.onPressed,
    this.tamanho = 44,
    this.cor,
    this.botaoKey,
  });

  final IconData icone;

  /// Texto da dica e rótulo lido pelo leitor de tela.
  final String dica;

  /// Nulo desliga o botão (fica apagado e não reage ao hover).
  final VoidCallback? onPressed;

  /// Área de toque; o círculo ocupa 88% dela.
  final double tamanho;

  /// Cor do ícone; por padrão, a dos títulos.
  final Color? cor;

  /// Chave do botão tocável, para os testes acharem pelo [Key].
  final Key? botaoKey;

  @override
  Widget build(BuildContext context) {
    final ativo = onPressed != null;
    final botao = SizedBox.square(
      dimension: tamanho,
      child: HoverButton(
        key: botaoKey,
        onPressed: onPressed,
        builder: (context, estados) => Center(
          child: _Circulo(
            icone: icone,
            cor: ativo
                ? (cor ?? MistakeMapDesign.abyss)
                : MistakeMapDesign.disabledInk,
            diametro: tamanho * .88,
            ativo: ativo,
            hover: ativo && estados.isHovered,
            pressionado: ativo && estados.isPressed,
            foco: estados.isFocused,
          ),
        ),
      ),
    );
    final semantica = Semantics(
      button: true,
      enabled: ativo,
      label: dica,
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(message: dica, child: botao),
    );
    // Fora de um app Fluent (telas e testes só em Material), o botão leva o
    // próprio tema, que a dica e o hover pedem.
    if (FluentTheme.maybeOf(context) != null) return semantica;
    return FluentTheme(
      data: FluentThemeData(
        brightness: MistakeMapDesign.escuro
            ? Brightness.dark
            : Brightness.light,
      ),
      child: semantica,
    );
  }
}

class _Circulo extends StatelessWidget {
  const _Circulo({
    required this.icone,
    required this.cor,
    required this.diametro,
    required this.ativo,
    required this.hover,
    required this.pressionado,
    required this.foco,
  });

  final IconData icone;
  final Color cor;
  final double diametro;
  final bool ativo, hover, pressionado, foco;

  @override
  Widget build(BuildContext context) {
    final reduzir = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duracao = reduzir ? Duration.zero : Movimento.rapido;
    final escuro = MistakeMapDesign.escuro;
    // Mesma elevação do avatar: repousa em 0,6, sobe a 1 no hover e assenta
    // ao tocar. Sem o brilho colorido; só a sombra neutra.
    final elevacao = !ativo || pressionado ? 0.0 : (hover ? 1.0 : .6);
    final sombras = [
      if (foco) BoxShadow(color: MistakeMapDesign.abyss, spreadRadius: 3.5),
      BoxShadow(
        color: MistakeMapDesign.sombra(escuro ? 0x52 : 0x24),
        blurRadius: 4 + 8 * elevacao,
        spreadRadius: -1,
        offset: Offset(0, 1 + 3 * elevacao),
      ),
      BoxShadow(
        color: MistakeMapDesign.sombra(0x29),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
    ];
    return PressScale(
      pressed: pressionado,
      child: AnimatedContainer(
        duration: duracao,
        curve: Movimento.curva,
        width: diametro,
        height: diametro,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hover
              ? MistakeMapDesign.hoverFill(MistakeMapDesign.raised)
              : MistakeMapDesign.pelicula(ativo ? 0xE0 : 0x99),
          border: Border.all(
            color: hover ? MistakeMapDesign.highlight : MistakeMapDesign.edge,
          ),
          boxShadow: sombras,
        ),
        // Reflexo no topo, como no avatar e nos outros vidros do app.
        foregroundDecoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.center,
            colors: [
              const Color(0xFFFFFFFF).withValues(alpha: escuro ? .10 : .45),
              const Color(0x00FFFFFF),
            ],
          ),
        ),
        child: Icon(icone, size: 18, color: cor),
      ),
    );
  }
}
