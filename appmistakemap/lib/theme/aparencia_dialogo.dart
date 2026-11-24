import 'package:fluent_ui/fluent_ui.dart';

import 'aparencia.dart';
import 'design_tokens.dart';

/// Escolha da aparência: Igual ao aparelho, Claro ou Escuro. A troca vale na
/// hora (o app inteiro muda atrás do diálogo) e fica salva no aparelho.
Future<void> mostrarAparencia(BuildContext context, {Aparencia? aparencia}) {
  final alvo = aparencia ?? Aparencia.instancia;
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => ContentDialog(
      title: const Text('Aparência'),
      content: ValueListenableBuilder<ModoAparencia>(
        valueListenable: alvo,
        builder: (context, atual, _) => RadioGroup<ModoAparencia>(
          groupValue: atual,
          onChanged: (modo) {
            if (modo != null) alvo.escolher(modo);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'O tema escuro cansa menos a vista à noite. "Igual ao '
                'aparelho" segue o que estiver no sistema.',
                style: Tipo.secundario,
              ),
              const SizedBox(height: Espaco.md),
              for (final modo in ModoAparencia.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: Espaco.xs),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: RadioButton<ModoAparencia>(
                        key: Key('aparencia-${modo.name}'),
                        value: modo,
                        content: Text(modo.rotulo, style: Tipo.corpo),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          child: const Text('Pronto'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

/// Lua/sol que alterna claro e escuro na hora e salva a escolha. Para telas
/// sem a barra do topo (como a escolha de perfil, antes do login).
class BotaoAparencia extends StatelessWidget {
  const BotaoAparencia({super.key, this.aparencia});

  /// Outra instância (testes); por padrão, [Aparencia.instancia].
  final Aparencia? aparencia;

  @override
  Widget build(BuildContext context) {
    final alvo = aparencia ?? Aparencia.instancia;
    if (!Aparencia.disponivel) return const SizedBox.shrink();
    return ValueListenableBuilder<ModoAparencia>(
      valueListenable: alvo,
      builder: (context, _, _) {
        final escuro = MistakeMapDesign.escuro;
        // O MediaQuery do app segue a paleta; aqui vale o brilho do aparelho.
        void alternar() => alvo.alternar(
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
        );
        final dica = escuro
            ? 'Mudar para o modo claro'
            : 'Mudar para o modo escuro';
        return Semantics(
          button: true,
          toggled: escuro,
          label: 'Modo escuro',
          onTap: alternar,
          excludeSemantics: true,
          child: Tooltip(
            message: dica,
            child: SizedBox.square(
              dimension: 44,
              child: IconButton(
                key: const Key('botao-aparencia'),
                icon: Icon(
                  escuro ? WindowsIcons.brightness : WindowsIcons.quiet_hours,
                  size: 18,
                  color: MistakeMapDesign.abyss,
                ),
                style: ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(
                    MistakeMapDesign.pelicula(0xC7),
                  ),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Raio.md),
                      side: BorderSide(color: MistakeMapDesign.hairline),
                    ),
                  ),
                ),
                onPressed: alternar,
              ),
            ),
          ),
        );
      },
    );
  }
}
