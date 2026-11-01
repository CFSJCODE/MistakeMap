import 'package:flutter/material.dart';

import 'analysis_repository.dart';
import 'exercise_submission_view.dart';
import 'insights_view.dart';
import '../theme/design_tokens.dart';
import 'material_control_styles.dart';

/// Hosts the new analysis flow within the existing Fluent navigation.
class AiMaterialShell extends StatefulWidget {
  final String userId;
  final AnalysisRepository repository;
  final bool showMap;
  final VoidCallback onClose;

  const AiMaterialShell({
    super.key,
    required this.userId,
    required this.repository,
    required this.showMap,
    required this.onClose,
    this.attemptId,
    this.startWithAnalysis = false,
    this.startWithStudy = false,
  });

  /// Abre o Mapa e, por cima dele, o Estudar.
  final bool startWithStudy;

  /// Abre o Mapa com o painel de análise expandido (atalho do Início).
  final bool startWithAnalysis;

  /// Opens straight on the correction of this attempt (from the exercise list).
  final String? attemptId;

  @override
  State<AiMaterialShell> createState() => _AiMaterialShellState();

  static ThemeData _theme(BuildContext context) {
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: MistakeMapDesign.fieldBorder),
    );
    final inputTheme = InputDecorationTheme(
      filled: true,
      fillColor: MistakeMapDesign.white,
      hoverColor: MistakeMapDesign.deep.withValues(alpha: .02),
      contentPadding: const EdgeInsets.all(16),
      border: inputBorder,
      enabledBorder: inputBorder,
      disabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: MistakeMapDesign.aquaInk, width: 2),
      ),
      errorBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: MistakeMapDesign.bad),
      ),
      labelStyle: const TextStyle(color: MistakeMapDesign.steel),
      floatingLabelStyle: const TextStyle(color: MistakeMapDesign.aquaInk),
      hintStyle: const TextStyle(color: MistakeMapDesign.disabledInk),
      errorStyle: const TextStyle(color: MistakeMapDesign.bad),
    );
    final menuShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: MistakeMapDesign.border),
    );
    final menuStyle = MenuStyle(
      backgroundColor: const WidgetStatePropertyAll(MistakeMapDesign.white),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      shadowColor: WidgetStatePropertyAll(
        MistakeMapDesign.deep.withValues(alpha: .16),
      ),
      elevation: const WidgetStatePropertyAll(3),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
      shape: WidgetStatePropertyAll(menuShape),
    );

    return ThemeData(
      useMaterial3: true,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      colorScheme: const ColorScheme.light(
        primary: MistakeMapDesign.aquaInk,
        onPrimary: MistakeMapDesign.white,
        primaryContainer: Color(0xFFD7F7F3),
        onPrimaryContainer: MistakeMapDesign.abyss,
        secondary: MistakeMapDesign.violetInk,
        onSecondary: MistakeMapDesign.white,
        secondaryContainer: Color(0xFFEAE4FF),
        onSecondaryContainer: MistakeMapDesign.abyss,
        tertiary: MistakeMapDesign.azureInk,
        onTertiary: MistakeMapDesign.white,
        error: MistakeMapDesign.bad,
        onError: MistakeMapDesign.white,
        surface: MistakeMapDesign.white,
        onSurface: MistakeMapDesign.deep,
        onSurfaceVariant: MistakeMapDesign.steel,
        surfaceContainerLowest: MistakeMapDesign.white,
        surfaceContainerLow: MistakeMapDesign.well,
        surfaceContainer: MistakeMapDesign.well,
        surfaceContainerHigh: MistakeMapDesign.disabledFill,
        surfaceContainerHighest: MistakeMapDesign.pressed,
        outline: MistakeMapDesign.mist,
        outlineVariant: MistakeMapDesign.border,
        shadow: MistakeMapDesign.deep,
      ),
      scaffoldBackgroundColor: MistakeMapDesign.background,
      canvasColor: MistakeMapDesign.white,
      cardColor: MistakeMapDesign.white,
      dividerColor: MistakeMapDesign.hairline,
      hoverColor: MistakeMapDesign.deep.withValues(alpha: .03),
      focusColor: MistakeMapDesign.aqua.withValues(alpha: .2),
      textTheme: Typography.blackMountainView.apply(
        bodyColor: MistakeMapDesign.content,
        displayColor: MistakeMapDesign.strong,
      ),
      iconTheme: const IconThemeData(color: MistakeMapDesign.steel),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: MistakeMapDesign.aquaInk,
        linearTrackColor: MistakeMapDesign.disabledFill,
        circularTrackColor: MistakeMapDesign.disabledFill,
      ),
      // Cartões em acrílico: branco quase opaco, borda clara e sombra suave.
      cardTheme: CardThemeData(
        color: const Color(0xEBFFFFFF),
        surfaceTintColor: Colors.transparent,
        shadowColor: MistakeMapDesign.deep.withValues(alpha: .22),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MistakeMapDesign.cardRadius),
          side: const BorderSide(color: Color(0xE6FFFFFF)),
        ),
      ),
      // Abas de seção em cápsula: a selecionada acende no acento da IA.
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xD9FFFFFF),
        selectedColor: Color.alphaBlend(
          MistakeMapDesign.violet.withValues(alpha: .22),
          MistakeMapDesign.white,
        ),
        side: const BorderSide(color: MistakeMapDesign.border),
        shape: const StadiumBorder(),
        labelStyle: const TextStyle(
          color: MistakeMapDesign.deep,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: MistakeMapDesign.violetInk),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: MistakeMapDesign.strong,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // Mesmo recuo de 12 px das barras Fluent: os botões não encostam na
        // borda da tela.
        actionsPadding: EdgeInsets.only(right: 12),
        leadingWidth: 68,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _controlStyle(context, primary: true),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _controlStyle(context, primary: true),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _controlStyle(context),
      ),
      textButtonTheme: TextButtonThemeData(
        style: _controlStyle(context, quiet: true),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: _controlStyle(context).copyWith(
          padding: const WidgetStatePropertyAll(EdgeInsets.all(10)),
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        ),
      ),
      inputDecorationTheme: inputTheme,
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: inputTheme,
        menuStyle: menuStyle,
        textStyle: const TextStyle(color: MistakeMapDesign.deep, fontSize: 14),
        disabledColor: MistakeMapDesign.disabledInk,
      ),
      menuTheme: MenuThemeData(style: menuStyle),
      menuButtonTheme: MenuButtonThemeData(
        style: _controlStyle(context, quiet: true),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: MistakeMapDesign.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: MistakeMapDesign.deep.withValues(alpha: .16),
        elevation: 3,
        shape: menuShape,
        menuPadding: const EdgeInsets.all(8),
        position: PopupMenuPosition.under,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.disabled)
                ? MistakeMapDesign.disabledInk
                : MistakeMapDesign.deep,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// White raised controls with a visible aqua keyboard focus outline.
  /// Opaque fills keep the labels clear above the surrounding page content.
  static ButtonStyle _controlStyle(
    BuildContext context, {
    bool primary = false,
    bool quiet = false,
  }) => MistakeMapMaterialControls.button(
    context,
    background: primary
        ? MistakeMapDesign.accent
        : quiet
        ? Colors.transparent
        : MistakeMapDesign.raised,
    foreground: primary ? MistakeMapDesign.abyss : MistakeMapDesign.content,
    quiet: quiet,
  );
}

class _AiMaterialShellState extends State<AiMaterialShell> {
  // O MaterialApp interno tem Navigator próprio; a chave deixa o Voltar do
  // sistema desempilhar primeiro as telas internas em vez da rota do shell.
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final _closeAtBase = _CloseAtBase(() => widget.onClose());

  // Uma base invisível fica sempre por baixo da primeira tela. Assim o
  // Navigator interno sempre "pode voltar" e o Android entrega o Voltar ao
  // Flutter: sem ela, o MaterialApp interno avisava que não tratava o gesto e
  // o sistema fechava o aplicativo inteiro. Voltar até a base fecha o shell.
  List<Route<dynamic>> _initialRoutes(String _) => [
    _baseRoute(),
    MaterialPageRoute<void>(builder: (_) => _firstPage()),
  ];

  Route<void> _baseRoute() =>
      MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink());

  Widget _firstPage() {
    final attemptId = widget.attemptId;
    if (attemptId != null) {
      return AttemptDetailView(
        userId: widget.userId,
        attemptId: attemptId,
        repository: widget.repository,
      );
    }
    return widget.showMap
        ? ErrorMapView(
            userId: widget.userId,
            repository: widget.repository,
            onClose: widget.onClose,
            startWithAnalysis: widget.startWithAnalysis,
            startWithStudy: widget.startWithStudy,
          )
        : ExerciseSubmissionView(
            userId: widget.userId,
            repository: widget.repository,
            onClose: widget.onClose,
          );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // O WidgetsApp externo recebe o Voltar antes do interno; bloquear aqui
    // evita que o fluxo de IA inteiro seja fechado de uma vez.
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      // Desempilha uma tela interna; ao chegar à base o observer fecha o shell.
      _navigatorKey.currentState?.maybePop();
    },
    child: MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AiMaterialShell._theme(context),
      navigatorObservers: [_closeAtBase],
      onGenerateInitialRoutes: _initialRoutes,
      onGenerateRoute: (_) => _baseRoute(),
    ),
  );
}

/// Closes the shell once only the invisible base route is left.
class _CloseAtBase extends NavigatorObserver {
  _CloseAtBase(this.onBase);

  final VoidCallback onBase;
  int _depth = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _depth++;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _depth--;
    if (_depth == 1) onBase();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _depth--;
}
