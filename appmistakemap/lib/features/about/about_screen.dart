import 'package:flutter/material.dart';
import 'package:appmistakemap/core/constants/about_content.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sobre o MistakeMap'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          // ── Cabeçalho ────────────────────────────────────────────────────
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: colors.primaryContainer,
                  child: Icon(Icons.map_outlined,
                      size: 40, color: colors.onPrimaryContainer),
                ),
                const SizedBox(height: 12),
                Text(
                  AboutContent.appName,
                  style: text.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  AboutContent.tagline,
                  style: text.bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Chip(label: Text(AboutContent.version)),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── O que é ──────────────────────────────────────────────────────
          _Section(
            icon: Icons.info_outline,
            title: 'O que é',
            child: Text(AboutContent.description, style: text.bodyMedium),
          ),

          // ── Missão ───────────────────────────────────────────────────────
          _Section(
            icon: Icons.flag_outlined,
            title: AboutContent.missionTitle,
            child: Text(AboutContent.mission, style: text.bodyMedium),
          ),

          // ── Visão ────────────────────────────────────────────────────────
          _Section(
            icon: Icons.visibility_outlined,
            title: AboutContent.visionTitle,
            child: Text(AboutContent.vision, style: text.bodyMedium),
          ),

          // ── Valores ──────────────────────────────────────────────────────
          _Section(
            icon: Icons.favorite_border,
            title: AboutContent.valuesTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final v in AboutContent.values) ...[
                  _ValueTile(titulo: v.titulo, descricao: v.descricao),
                  if (v != AboutContent.values.last)
                    const Divider(height: 20),
                ],
              ],
            ),
          ),

          // ── Disciplina ───────────────────────────────────────────────────
          _Section(
            icon: Icons.school_outlined,
            title: AboutContent.academicTitle,
            child: Text(AboutContent.academic, style: text.bodyMedium),
          ),

          // ── Orientação ───────────────────────────────────────────────────
          _Section(
            icon: Icons.person_outline,
            title: AboutContent.advisorTitle,
            child: Text(AboutContent.advisorLabel, style: text.bodyMedium),
          ),

          // ── Criadores ────────────────────────────────────────────────────
          _Section(
            icon: Icons.group_outlined,
            title: AboutContent.creatorsTitle,
            child: Column(
              children: [
                for (final c in AboutContent.creators)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: colors.secondaryContainer,
                      child: Text(
                        c.nome[0],
                        style: TextStyle(color: colors.onSecondaryContainer),
                      ),
                    ),
                    title: Text(c.nome, style: text.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: Text(c.papel),
                  ),
              ],
            ),
          ),

          // ── Tecnologia ───────────────────────────────────────────────────
          _Section(
            icon: Icons.code,
            title: AboutContent.techTitle,
            child: Text(AboutContent.tech, style: text.bodyMedium),
          ),

          // ── Rodapé ───────────────────────────────────────────────────────
          const SizedBox(height: 12),
          Center(
            child: Text(
              AboutContent.footerCopyright,
              style: text.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Widgets auxiliares ────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: text.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
          const SizedBox(height: 16),
          const Divider(),
        ],
      ),
    );
  }
}

class _ValueTile extends StatelessWidget {
  const _ValueTile({required this.titulo, required this.descricao});

  final String titulo;
  final String descricao;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle_outline, size: 18, color: colors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo,
                  style: text.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(descricao, style: text.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
