import 'package:fluent_ui/fluent_ui.dart';

import 'aparencia.dart';
import 'botao_redondo.dart';
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
/// sem a barra do topo (como a escolha de perfil, antes do login) e na
/// barra do topo, com [tamanho] 40.
class BotaoAparencia extends StatelessWidget {
  const BotaoAparencia({super.key, this.aparencia, this.tamanho = 44});

  /// Outra instância (testes); por padrão, [Aparencia.instancia].
  final Aparencia? aparencia;

  /// Área de toque: 44 nas telas sem barra, 40 na barra do topo.
  final double tamanho;

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
          child: BotaoRedondo(
            botaoKey: const Key('botao-aparencia'),
            icone: escuro ? WindowsIcons.brightness : WindowsIcons.quiet_hours,
            dica: dica,
            tamanho: tamanho,
            onPressed: alternar,
          ),
        );
      },
    );
  }
}
