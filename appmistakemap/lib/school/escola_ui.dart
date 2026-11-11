import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../theme/control_styles.dart';
import '../theme/design_tokens.dart';

// Peças de tela do cadastro por perfil e dos painéis da escola. Seguem o
// mesmo desenho do Espaço de estudos (platform_hub.dart): cartão branco com
// borda fina, botão de 48 px e InfoBar para erro.

class CartaoEscola extends StatelessWidget {
  const CartaoEscola({
    super.key,
    required this.titulo,
    required this.children,
    this.subtitulo,
  });

  final String titulo;
  final String? subtitulo;
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
          titulo,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: MistakeMapDesign.primary,
          ),
        ),
        if (subtitulo != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitulo!,
            style: const TextStyle(color: MistakeMapDesign.steel),
          ),
        ],
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
}

class BotaoEscola extends StatelessWidget {
  const BotaoEscola(
    this.texto, {
    super.key,
    required this.onPressed,
    this.principal = false,
  });

  final String texto;
  final VoidCallback? onPressed;
  final bool principal;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: MistakeMapButton(
      style: MistakeMapControls.button(
        background: principal ? MistakeMapDesign.aqua : null,
        foreground: principal ? MistakeMapDesign.abyss : null,
      ),
      onPressed: onPressed,
      child: Text(texto),
    ),
  );
}

class CampoEscola extends StatelessWidget {
  const CampoEscola({
    super.key,
    required this.rotulo,
    required this.controle,
    this.dica,
    this.teclado,
    this.formatos,
    this.maiusculas = false,
  });

  final String rotulo;
  final TextEditingController controle;
  final String? dica;
  final TextInputType? teclado;
  final List<TextInputFormatter>? formatos;
  final bool maiusculas;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: InfoLabel(
      label: rotulo,
      child: TextBox(
        controller: controle,
        placeholder: dica,
        keyboardType: teclado,
        inputFormatters: formatos,
        textCapitalization: maiusculas
            ? TextCapitalization.characters
            : TextCapitalization.none,
      ),
    ),
  );
}

class AvisoEscola extends StatelessWidget {
  const AvisoEscola(this.mensagem, {super.key, this.sucesso = false});
  final String mensagem;
  final bool sucesso;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: InfoBar(
      title: Text(sucesso ? 'Pronto' : 'Vamos tentar de novo'),
      content: Text(mensagem),
      severity: sucesso ? InfoBarSeverity.success : InfoBarSeverity.warning,
    ),
  );
}

/// Formata DD/MM/AAAA enquanto a pessoa digita.
class FormatoData extends TextInputFormatter {
  const FormatoData();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitos = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limitado = digitos.length > 8 ? digitos.substring(0, 8) : digitos;
    final saida = StringBuffer();
    for (var i = 0; i < limitado.length; i++) {
      if (i == 2 || i == 4) saida.write('/');
      saida.write(limitado[i]);
    }
    final texto = saida.toString();
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

/// Mostra um código uma única vez (o servidor guarda só o hash).
Future<void> mostrarCodigo(
  BuildContext context, {
  required String titulo,
  required String codigo,
  required String explicacao,
}) => showDialog<void>(
  context: context,
  builder: (dialogo) => ContentDialog(
    title: Text(titulo),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(explicacao),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            color: MistakeMapDesign.well,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MistakeMapDesign.border),
          ),
          child: SelectableText(
            codigo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
              color: MistakeMapDesign.primary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Anote ou copie agora: por segurança ele não aparece de novo.',
          style: TextStyle(color: MistakeMapDesign.steel),
        ),
      ],
    ),
    actions: [
      BotaoEscola(
        'Copiar',
        onPressed: () => Clipboard.setData(ClipboardData(text: codigo)),
      ),
      BotaoEscola(
        'Fechar',
        principal: true,
        onPressed: () => Navigator.of(dialogo).pop(),
      ),
    ],
  ),
);
