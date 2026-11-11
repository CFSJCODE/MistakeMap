import 'package:fluent_ui/fluent_ui.dart';

import '../theme/control_styles.dart';
import '../theme/design_tokens.dart';

/// Moldura das telas do professor, igual à da sessão de estudos: voltar,
/// título, avisos e conteúdo numa coluna centralizada.
class TeacherPage extends StatelessWidget {
  const TeacherPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.error,
    this.notice,
    this.loading = false,
    this.maxWidth = 1040,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final String? error;
  final String? notice;
  final bool loading;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => NavigationView(
    content: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: MistakeMapButton(
                  onPressed: () => Navigator.maybePop(context),
                  child: const Text('Voltar'),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(subtitle),
              const SizedBox(height: 16),
              if (error != null) ...[
                InfoBar(
                  title: const Text('Vamos tentar de novo'),
                  content: Text(error!),
                  severity: InfoBarSeverity.warning,
                ),
                const SizedBox(height: 16),
              ],
              if (notice != null) ...[
                InfoBar(title: const Text('Concluído'), content: Text(notice!)),
                const SizedBox(height: 16),
              ],
              if (loading) const Center(child: ProgressRing()) else ...children,
            ],
          ),
        ),
      ),
    ),
  );
}

/// Cartão com título, como os do espaço de estudos.
class TeacherCard extends StatelessWidget {
  const TeacherCard({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: MistakeMapDesign.surface,
      border: Border.all(color: MistakeMapDesign.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
}

/// Botão das telas do professor (48 px de altura, principal em aqua).
Widget teacherButton(
  String text,
  VoidCallback? action, {
  bool primary = false,
}) => ConstrainedBox(
  constraints: const BoxConstraints(minHeight: 48),
  child: MistakeMapButton(
    style: MistakeMapControls.button(
      background: primary ? MistakeMapDesign.aqua : null,
      foreground: primary ? MistakeMapDesign.abyss : null,
    ),
    onPressed: action,
    child: Text(text),
  ),
);

/// Barra horizontal proporcional (0 a 1), para tendência e acerto.
class TeacherBar extends StatelessWidget {
  const TeacherBar({super.key, required this.fraction, this.color});

  final double fraction;
  final Color? color;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: SizedBox(
      height: 8,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: MistakeMapDesign.well),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fraction.clamp(0, 1).toDouble(),
            child: ColoredBox(color: color ?? MistakeMapDesign.azure),
          ),
        ],
      ),
    ),
  );
}
