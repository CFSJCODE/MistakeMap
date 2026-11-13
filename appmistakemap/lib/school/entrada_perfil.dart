import 'package:fluent_ui/fluent_ui.dart';

import '../layout/adaptativo.dart';
import '../theme/design_tokens.dart';
import '../theme/glass_surface.dart';
import 'perfil_modelos.dart';
import 'quem_e_voce.dart' show CartaoPerfil;

// ─── Entrada por perfil ──────────────────────────────────────────────────────
// Primeira tela do app, logo depois da apresentação, em toda abertura e ao
// voltar ao início: a pessoa escolhe o perfil e só então faz o login com
// e-mail e senha. Quem decide se a conta tem o perfil é o servidor, depois do
// login (ver motivoPerfilRecusado e o AuthGate).

class TelaEntradaPorPerfil extends StatelessWidget {
  const TelaEntradaPorPerfil({
    super.key,
    required this.onEscolher,
    this.subtitulo,
    this.rodape,
  });

  final ValueChanged<PerfilCadastro> onEscolher;

  /// Linha abaixo do título (o app da equipe troca o texto).
  final String? subtitulo;

  /// Fica no fim da lista (o app passa a versão e as atualizações).
  final Widget? rodape;

  @override
  Widget build(BuildContext context) => AuroraBackground(
    child: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
            children: [
              const Text(
                'Como você vai entrar?',
                key: ValueKey('entrada-titulo'),
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: MistakeMapDesign.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitulo ??
                    'Escolha o perfil. Em seguida, entre com o e-mail e a '
                        'senha da conta desse perfil.',
                style: const TextStyle(
                  fontSize: 16,
                  color: MistakeMapDesign.content,
                ),
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, caixa) => GradeAlinhada(
                  colunas: caixa.maxWidth >= 640 ? 2 : 1,
                  children: [
                    for (final p in PerfilCadastro.values)
                      CartaoPerfil(
                        key: ValueKey('entrada-${p.codigo}'),
                        perfil: p,
                        onTap: () => onEscolher(p),
                      ),
                  ],
                ),
              ),
              if (rodape != null) ...[const SizedBox(height: 24), rodape!],
            ],
          ),
        ),
      ),
    ),
  );
}
