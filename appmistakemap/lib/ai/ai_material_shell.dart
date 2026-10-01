import 'package:flutter/material.dart';

import 'analysis_repository.dart';
import 'exercise_submission_view.dart';
import 'insights_view.dart';
import '../theme/design_tokens.dart';
import 'material_control_styles.dart';

/// Hosts the new analysis flow within the existing Fluent navigation.
class AiMaterialShell extends StatelessWidget {
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
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _theme(context),
    home: showMap
        ? ErrorMapView(userId: userId, repository: repository, onClose: onClose)
        : ExerciseSubmissionView(
            userId: userId,
            repository: repository,
            onClose: onClose,
          ),
  );

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
