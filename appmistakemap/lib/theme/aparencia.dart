import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design_tokens.dart';

/// Como o aluno quer ver o app.
enum ModoAparencia {
  /// Segue o claro/escuro do aparelho.
  sistema('Igual ao aparelho'),
  claro('Claro'),
  escuro('Escuro');

  const ModoAparencia(this.rotulo);

  final String rotulo;
}

/// Aparência escolhida, salva no aparelho.
///
/// As cores do design system leem [MistakeMapDesign.paleta]; quando a
/// aparência efetiva muda, a paleta é trocada e a árvore inteira é
/// reconstruída, inclusive os widgets `const` (eles leem os tokens no build).
///
/// A escolha fica no botão de conta > Aparência. Sem escolha salva, segue o aparelho.
/// Para gerar uma build só clara: `--dart-define=MISTAKEMAP_MODO_ESCURO=false`.
class Aparencia extends ValueNotifier<ModoAparencia> {
  Aparencia([super.value = ModoAparencia.claro]);

  static final instancia = Aparencia();

  static const disponivel = bool.fromEnvironment(
    'MISTAKEMAP_MODO_ESCURO',
    defaultValue: true,
  );

  static const _chave = 'mistakemap.aparencia';

  /// Lê a escolha salva (sem escolha: igual ao aparelho). Com o modo escuro
  /// desligado na build, o app fica no claro.
  Future<void> carregar() async {
    if (!disponivel) return;
    try {
      final salvo = (await SharedPreferences.getInstance()).getString(_chave);
      value = ModoAparencia.values.asNameMap()[salvo] ?? ModoAparencia.sistema;
    } catch (_) {
      // Sem armazenamento local (teste, navegador bloqueado): fica no padrão.
    }
  }

  Future<void> escolher(ModoAparencia modo) async {
    value = modo;
    try {
      await (await SharedPreferences.getInstance()).setString(
        _chave,
        modo.name,
      );
    } catch (_) {}
  }

  /// Troca rápida (botão da barra do topo): vai para o oposto do que está
  /// na tela e salva a escolha. "Igual ao aparelho" volta no botão de conta > Aparência.
  Future<void> alternar(Brightness doAparelho) => escolher(
    brilho(doAparelho) == Brightness.dark
        ? ModoAparencia.claro
        : ModoAparencia.escuro,
  );

  /// Brilho efetivo, dado o brilho do aparelho.
  Brightness brilho(Brightness doAparelho) => switch (value) {
    ModoAparencia.claro => Brightness.light,
    ModoAparencia.escuro => Brightness.dark,
    ModoAparencia.sistema => doAparelho,
  };
}

/// Aplica a aparência: troca a paleta e reconstrói o app quando ela muda.
///
/// Fica acima do `FluentApp`, para que o tema do app já nasça com a paleta
/// certa.
class AparenciaApp extends StatefulWidget {
  const AparenciaApp({super.key, required this.builder, this.aparencia});

  final WidgetBuilder builder;

  /// Outra instância (testes); por padrão, [Aparencia.instancia].
  final Aparencia? aparencia;

  @override
  State<AparenciaApp> createState() => _AparenciaAppState();
}

class _AparenciaAppState extends State<AparenciaApp>
    with WidgetsBindingObserver {
  Aparencia get _aparencia => widget.aparencia ?? Aparencia.instancia;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _aparencia.addListener(_aplicar);
    MistakeMapDesign.paleta = _paletaEfetiva();
  }

  @override
  void dispose() {
    _aparencia.removeListener(_aplicar);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _aplicar();

  PaletaMistakeMap _paletaEfetiva() {
    final doAparelho =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return _aparencia.brilho(doAparelho) == Brightness.dark
        ? PaletaMistakeMap.escuro
        : PaletaMistakeMap.claro;
  }

  void _aplicar() {
    final nova = _paletaEfetiva();
    if (identical(nova, MistakeMapDesign.paleta)) return;
    MistakeMapDesign.paleta = nova;
    if (!mounted) return;
    // Widgets const não se reconstroem sozinhos: marca a árvore toda.
    void marcar(Element e) {
      e.markNeedsBuild();
      e.visitChildren(marcar);
    }

    (context as Element).visitChildren(marcar);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
