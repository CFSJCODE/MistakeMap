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
  });

  /// Abre o Mapa com o painel de análise expandido (atalho do Início).
  final bool startWithAnalysis;

  /// Opens straight on the correction of this attempt (from the exercise list).
  final String? attemptId;

  @override
  State<AiMaterialShell> createState() => _AiMaterialShellState();

  static ThemeData _theme(BuildContext context) {
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: MistakeMapDesign.border),
    );
    final inputTheme = InputDecorationTheme(
      filled: true,
      fillColor: MistakeMapDesign.surface,
      hoverColor: MistakeMapDesign.primary.withValues(alpha: .04),
      contentPadding: const EdgeInsets.all(16),
      border: inputBorder,
      enabledBorder: inputBorder,
      disabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: MistakeMapDesign.primary, width: 2),
      ),
      labelStyle: const TextStyle(color: MistakeMapDesign.content),
    );
    final menuShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: MistakeMapDesign.border),
    );
    final menuStyle = MenuStyle(
      backgroundColor: const WidgetStatePropertyAll(MistakeMapDesign.surface),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      shadowColor: WidgetStatePropertyAll(
        MistakeMapDesign.navy.withValues(alpha: .12),
      ),
      elevation: const WidgetStatePropertyAll(3),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
      shape: WidgetStatePropertyAll(menuShape),
    );

    return ThemeData(
      useMaterial3: true,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      colorScheme: ColorScheme.fromSeed(
        seedColor: MistakeMapDesign.primary,
        primary: MistakeMapDesign.primary,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFE5EFF9),
        onPrimaryContainer: MistakeMapDesign.navy,
        secondary: MistakeMapDesign.primary,
        secondaryContainer: const Color(0xFFE5EFF9),
        onSecondaryContainer: MistakeMapDesign.navy,
        surface: MistakeMapDesign.surface,
        onSurface: MistakeMapDesign.navy,
        outline: MistakeMapDesign.border,
      ),
      scaffoldBackgroundColor: MistakeMapDesign.background,
      canvasColor: MistakeMapDesign.surface,
      hoverColor: MistakeMapDesign.primary.withValues(alpha: .04),
      focusColor: MistakeMapDesign.primary.withValues(alpha: .10),
      appBarTheme: const AppBarTheme(
        backgroundColor: MistakeMapDesign.background,
        foregroundColor: MistakeMapDesign.primary,
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
        textStyle: const TextStyle(color: MistakeMapDesign.navy, fontSize: 14),
        disabledColor: const Color(0xFF61758A),
      ),
      menuTheme: MenuThemeData(style: menuStyle),
      menuButtonTheme: MenuButtonThemeData(
        style: _controlStyle(context, quiet: true),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: MistakeMapDesign.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: MistakeMapDesign.navy.withValues(alpha: .12),
        elevation: 3,
        shape: menuShape,
        menuPadding: const EdgeInsets.all(8),
        position: PopupMenuPosition.under,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.disabled)
                ? const Color(0xFF61758A)
                : MistakeMapDesign.navy,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// Light, readable control surfaces with a visible keyboard focus outline.
  /// Opaque fills keep the labels clear above the surrounding page content.
  static ButtonStyle _controlStyle(
    BuildContext context, {
    bool primary = false,
    bool quiet = false,
  }) => MistakeMapMaterialControls.button(
    context,
    background: primary
        ? MistakeMapDesign.primary
        : quiet
        ? Colors.transparent
        : MistakeMapDesign.surface,
    foreground: primary ? Colors.white : MistakeMapDesign.content,
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
