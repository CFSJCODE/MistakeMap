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
