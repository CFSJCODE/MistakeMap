import 'dart:typed_data';
import 'dart:ui' show ImageFilter;
import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import 'package:crypto/crypto.dart' show sha256;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'theme/design_tokens.dart';
import 'theme/control_styles.dart';
import 'theme/glass_surface.dart';
import 'theme/motion.dart';
import 'layout/adaptativo.dart';
import 'layout/navigation_shell.dart';
import 'auth/google_sign_in.dart';
import 'ai/ai_material_shell.dart';
import 'ai/analysis_repository.dart';
import 'ai/analysis_models.dart' show AttemptStatusGroup, attemptStatusGroup;
import 'admin/metrics_panel.dart';
import 'assets/profile_photo.dart';
import 'about/external_profile.dart';
import 'about/linkedin_profile_button.dart';
import 'local/conta_offline.dart';
import 'local/preferencias_caderno.dart';
import 'local/registro_erro.dart';
import 'local/registro_erro_dao.dart';
import 'sync/armazem_sync.dart' show OperacaoFila;
import 'sync/conexao.dart' show ehFalhaDeRede;
import 'sync/remoto_supabase.dart';
import 'sync/sincronizador.dart';
import 'sync/sobreposicao.dart';

part 'caderno_erros.dart';

// ─── Cores da identidade visual (Obsidian Glass, modo claro) ─────────────────
// titleBlue e contentBlue mantêm o nome histórico; hoje são as tintas escuras
// da paleta para títulos e texto.
const Color titleBlue = MistakeMapDesign.primary;
const Color contentBlue = MistakeMapDesign.content;
// Preenchimento do botão principal (Aqua); a tinta escura vem do contraste.
const Color kAcento = MistakeMapDesign.accent;

// Cores de estado do app. Os nomes vêm da paleta Material antiga; os valores
// são os acentos Aurora escurecidos, legíveis como texto sobre o branco.
abstract final class Cores {
  static const Color branco = Color(0xFFFFFFFF);
  static const Color transparente = Color(0x00000000);
  static const Color vermelho = MistakeMapDesign.coralInk;
  static const Color vermelho300 = MistakeMapDesign.coral;
  static const Color vermelho400 = Color(0xFFC8364A);
  static const Color vermelho600 = MistakeMapDesign.coralInk;
  static const Color vermelho700 = Color(0xFF9E1F31);
  static const Color verde = MistakeMapDesign.mintInk;
  static const Color verde600 = Color(0xFF0F6640);
  static const Color laranja = MistakeMapDesign.amberInk;
  static const Color laranja400 = Color(0xFF9A5E00);
  static const Color laranja700 = Color(0xFF7A4900);
  static const Color ambar = MistakeMapDesign.amber;
  static const Color azul600 = MistakeMapDesign.azureInk;
  static const Color cinza = MistakeMapDesign.steel;
  static const Color cinza100 = MistakeMapDesign.well;
  static const Color cinza200 = MistakeMapDesign.disabledFill;
  static const Color cinza300 = MistakeMapDesign.mist;
  static const Color cinza600 = MistakeMapDesign.steel;
  static const Color cinza700 = MistakeMapDesign.slate;
}

// ─── Fluent UI + Liquid Glass — tokens ───────────────────────────────────────
const Color kGlassBg = MistakeMapDesign.surface;
const Color kGlassBorder = MistakeMapDesign.border;
const Color kScaffoldBg = MistakeMapDesign.background;
const double kRadius = 16;
const double kRadiusSm = 10;
const double kAlturaBarraSuperior = 64;
double _alturaBarraSuperior(BuildContext context) =>
    (MediaQuery.textScalerOf(context).scale(20) * 2.8 + 8).clamp(
      kAlturaBarraSuperior,
      double.infinity,
    );

final FluentThemeData temaFluent = FluentThemeData(
  brightness: Brightness.light,
  accentColor: MistakeMapDesign.aquaInk.toAccentColor(),
  scaffoldBackgroundColor: kScaffoldBg,
  cardColor: kGlassBg,
  menuColor: MistakeMapDesign.white,
  micaBackgroundColor: MistakeMapDesign.canvas,
  inactiveColor: MistakeMapDesign.steel,
  shadowColor: MistakeMapDesign.deep,
  resources: const ResourceDictionary.light(
    textFillColorPrimary: MistakeMapDesign.deep,
    textFillColorSecondary: MistakeMapDesign.steel,
    cardStrokeColorDefault: MistakeMapDesign.hairline,
    controlStrokeColorDefault: MistakeMapDesign.edge,
    solidBackgroundFillColorBase: MistakeMapDesign.canvas,
  ),
  // Diálogos em acrílico: quase opacos para o texto, cantos de cartão, borda
  // clara e véu escuro suave atrás.
  dialogTheme: const ContentDialogThemeData(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFAFFFFFF), Color(0xF2F8FAFB)],
      ),
      borderRadius: BorderRadius.all(Radius.circular(20)),
      border: Border.fromBorderSide(BorderSide(color: Color(0xE6FFFFFF))),
      boxShadow: MistakeMapDesign.liquidShadow,
    ),
    actionsDecoration: BoxDecoration(
      color: Color(0x0A11212D),
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
    ),
    barrierColor: Color(0x6606141B),
  ),
  fasterAnimationDuration: MistakeMapMotion.hover,
  fastAnimationDuration: MistakeMapMotion.controls,
  mediumAnimationDuration: MistakeMapMotion.page,
  animationCurve: MistakeMapMotion.curve,
  buttonTheme: ButtonThemeData(
    defaultButtonStyle: MistakeMapControls.button(),
    outlinedButtonStyle: MistakeMapControls.button(),
    filledButtonStyle: MistakeMapControls.button(
      background: kAcento,
      foreground: MistakeMapDesign.abyss,
    ),
    iconButtonStyle: MistakeMapControls.button(
      padding: const EdgeInsets.all(14),
    ),
    hyperlinkButtonStyle: MistakeMapControls.button(
      background: Cores.transparente,
      foreground: MistakeMapDesign.aquaInk,
      padding: kDefaultButtonPadding,
      fontSize: 14,
    ),
  ),
);

// As cores semânticas do vidro (toasts, brilhos) seguem os acentos Aurora.
const GlassThemeData temaVidro = GlassThemeData(
  brightness: Brightness.light,
  interaction: GlassInteractionSettings(stretch: 0, interactionScale: 0.98),
  light: GlassThemeVariant(
    quality: GlassQuality.standard,
    glowColors: GlassGlowColors(
      primary: MistakeMapDesign.aquaInk,
      secondary: MistakeMapDesign.violetInk,
      success: MistakeMapDesign.mintInk,
      info: MistakeMapDesign.azureInk,
      warning: MistakeMapDesign.amberInk,
      danger: MistakeMapDesign.coralInk,
    ),
  ),
);

// ─── Modo demonstração ───────────────────────────────────────────────────────
// Defina como true para exibir o banner "Demonstração" nas telas com dados de seed.
// Mude para false antes de usar com dados reais de um estudante.
const bool kModoDemo = true;

// ─── Credenciais Supabase ────────────────────────────────────────────────────
const String _supabaseUrl = 'https://bmdjicshcjpknuaywaph.supabase.co';
const String _supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
    '.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJtZGppY3NoY2pwa251YXl3YXBoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgyMjk0NzYsImV4cCI6MjEwMzgwNTQ3Nn0'
    '.8Edj96evd2zty16bH_XWgMfMVonXhzZZuYB8AXx2V4M';

// Atalho para o cliente Supabase
SupabaseClient get _db => Supabase.instance.client;

// Sincronizador do usuário logado: Supabase primeiro, SQLite sem rede.
Sincronizador _sync(String usuarioId) {
  final sync = Sincronizador.instancia;
  sync.temSessao = () => _db.auth.currentSession != null;
  if (sync.usuarioId != usuarioId) sync.iniciar(usuarioId, RemotoSupabase(_db));
  return sync;
}

// ─── Design system: Aurora Glass (Fluent UI + Liquid Glass) ──────────────────
// L0 Mica: fundo Aurora fixo, com luz viva que dá profundidade às camadas.
// L1 Acrílico (Fluent): conteúdo — tipografia, cartões, campos, botões,
// combos, progresso, diálogos e ícones (WindowsIcons).
// L2 Vidro líquido (Apple): o que flutua — barras, navegação, destaques e
// toasts.

extension _Tipografia on BuildContext {
  Typography get tipo => FluentTheme.of(this).typography;
}

class _FundoMica extends StatelessWidget {
  const _FundoMica();

  @override
  Widget build(BuildContext context) => const AuroraBackground();
}

// A barra superior acompanha a fonte; a navegação ocupa espaço fora do corpo.
EdgeInsets _paddingCorpo(
  BuildContext context, {
  double horizontal = 16,
  double topo = 16,
  double base = 24,
}) {
  final p = MediaQuery.paddingOf(context);
  return EdgeInsets.fromLTRB(
    horizontal,
    p.top + _alturaBarraSuperior(context) + topo,
    horizontal,
    p.bottom + base,
  );
}

class _PaginaVidro extends StatelessWidget {
  const _PaginaVidro({
    required this.titulo,
    required this.corpo,
    this.acoes = const [],
    this.voltar = false,
  });

  final String titulo;
  final Widget corpo;
  final List<Widget> acoes;
  final bool voltar;

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      background: const _FundoMica(),
      enableBackgroundSampling: false,
      backgroundColor: kScaffoldBg,
      statusBarStyle: GlassStatusBarStyle.dark,
      // Conteúdo e títulos permanecem nítidos; vidro apenas nos controles.
      edgeFade: false,
      appBar: _BarraVidro(
        child: GlassAppBar(
          backgroundColor: Cores.transparente,
          centerTitle: false,
          toolbarHeight: _alturaBarraSuperior(context),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          leading: voltar
              ? _BotaoBarra(
                  icone: WindowsIcons.back,
                  dica: 'Voltar',
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : null,
          title: Text(
            titulo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.tipo.subtitle?.copyWith(color: titleBlue),
          ),
          actions: [const _IndicadorConexao(), ...acoes],
        ),
      ),
      body: corpo,
    );
  }
}

/// Barra superior em vidro líquido: fixa no topo, com o conteúdo rolando por
/// baixo e desfocado (o vidro precisa de algo atrás para ter efeito). O
/// preenchimento quase opaco mantém o título legível sobre qualquer texto.
/// Com alto contraste ligado no aparelho, a barra fica sólida.
class _BarraVidro extends StatelessWidget implements PreferredSizeWidget {
  const _BarraVidro({required this.child});

  final GlassAppBar child;

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Widget build(BuildContext context) {
    final solida = MediaQuery.highContrastOf(context);
    final barra = DecoratedBox(
      decoration: BoxDecoration(
        color: solida ? MistakeMapDesign.white : null,
        gradient: solida
            ? null
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xE0FFFFFF), Color(0xC7FFFFFF)],
              ),
        // Borda especular embaixo: a aresta do vidro pega a luz.
        border: const Border(
          bottom: BorderSide(color: MistakeMapDesign.hairline),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1411212D),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
    if (solida) return barra;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: MistakeMapDesign.liquidBlur,
          sigmaY: MistakeMapDesign.liquidBlur,
        ),
        child: barra,
      ),
    );
  }
}

// Pílula da barra superior: só aparece sem rede ou com alterações na fila.
class _IndicadorConexao extends StatelessWidget {
  const _IndicadorConexao();

  @override
  Widget build(BuildContext context) {
    final sync = Sincronizador.instancia;
    return ListenableBuilder(
      listenable: Listenable.merge([sync.online, sync.pendentes]),
      builder: (context, _) {
        final online = sync.online.value;
        final pendentes = sync.pendentes.value;
        if (sync.semSessao) {
          // Entrou sem rede: o envio espera um login com internet.
          return const Tooltip(
            message:
                'Você entrou sem internet. Para enviar o que fez neste '
                'aparelho, saia e entre de novo quando estiver conectado.',
            child: Padding(
              padding: EdgeInsetsDirectional.only(end: 8),
              child: Center(
                child: _Pilula(
                  texto: 'Modo offline',
                  icone: WindowsIcons.cloud_not_synced,
                  cor: Cores.laranja700,
                ),
              ),
            ),
          );
        }
        if (online && pendentes == 0) return const SizedBox.shrink();
        final aguardando = pendentes == 1
            ? '1 alteração aguardando envio.'
            : '$pendentes alterações aguardando envio.';
        return Tooltip(
          message: online
              ? 'Enviando ao servidor. $aguardando'
              : 'Sem conexão: mostrando os dados salvos no aparelho.'
                    '${pendentes > 0 ? ' $aguardando' : ''}',
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Center(
              child: _Pilula(
                texto: online ? 'Sincronizando' : 'Offline',
                icone: online
                    ? WindowsIcons.sync
                    : WindowsIcons.cloud_not_synced,
                cor: online ? Cores.azul600 : Cores.laranja700,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BotaoBarra extends StatelessWidget {
  const _BotaoBarra({
    required this.icone,
    required this.dica,
    required this.onPressed,
    this.cor = titleBlue,
  });

  final IconData icone;
  final String dica;
  final VoidCallback? onPressed;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: dica,
      child: SizedBox.square(
        dimension: 40,
        child: MistakeMapIconButton(
          style: MistakeMapControls.button(
            padding: const EdgeInsets.all(11),
            foreground: cor,
          ),
          icon: _IconeBotao(icone, size: 18),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

// Ícones seguem a mesma interpolação de cor dos rótulos dos botões.
class _IconeBotao extends StatelessWidget {
  const _IconeBotao(this.icone, {this.size = 16});

  final IconData icone;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Icon(icone, size: size, color: DefaultTextStyle.of(context).style.color);
}

// Lista com "puxar para atualizar" no estilo Apple, respeitando as barras de vidro.
class _ListaAtualizavel extends StatelessWidget {
  const _ListaAtualizavel({required this.onRefresh, required this.children});

  final Future<void> Function() onRefresh;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final padding = _paddingCorpo(context);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: padding.top)),
        CupertinoSliverRefreshControl(onRefresh: onRefresh),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            padding.left,
            0,
            padding.right,
            padding.bottom,
          ),
          sliver: SliverList(delegate: SliverChildListDelegate(children)),
        ),
      ],
    );
  }
}

// Superfície estável para resumos e formulários: nenhum filtro sobre o conteúdo.
class _PainelVidro extends StatelessWidget {
  const _PainelVidro({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.raio = MistakeMapDesign.cardRadius,
    this.acento,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double raio;

  /// Acento da seção que tinge o canto do vidro.
  final Color? acento;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: raio,
      accent: acento,
      child: Container(padding: padding, child: child),
    );
  }
}

// Card de conteúdo Fluent em acrílico (listas e blocos de texto).
class _CartaoFluent extends StatelessWidget {
  const _CartaoFluent({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.acento,
    this.cor = kGlassBg,
    this.onPressed,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Acento da seção que tinge o canto do vidro.
  final Color? acento;

  /// Preenchimento opaco do cartão clicável (um tom do estado, por exemplo).
  final Color cor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final acao = onPressed;
    if (acao == null) {
      return GlassSurface(accent: acento, padding: padding, child: child);
    }
    // Cartão clicável: superfície opaca do botão, para o rótulo nunca
    // depender do que está atrás durante o hover.
    return MistakeMapButton(
      onPressed: acao,
      style: MistakeMapControls.button(
        radius: kRadius,
        padding: padding,
        background: cor,
      ),
      child: child,
    );
  }
}

// Etiqueta em pílula (status, papéis, tecnologias).
class _Pilula extends StatelessWidget {
  const _Pilula({
    required this.texto,
    required this.cor,
    this.icone,
    this.solida = false,
  });

  final String texto;
  final Color cor;
  final IconData? icone;
  final bool solida;

  @override
  Widget build(BuildContext context) {
    final frente = solida ? MistakeMapDesign.hoverInk(cor, Cores.branco) : cor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: solida ? cor : cor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(kRadiusSm),
        border: solida ? null : Border.all(color: cor.withValues(alpha: 0.4)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (icone != null) ...[
            Icon(icone, size: 12, color: frente),
            const SizedBox(width: 4),
          ],
          Text(
            texto,
            style: context.tipo.caption?.copyWith(
              color: frente,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerDemo extends StatelessWidget {
  const _BannerDemo();

  @override
  Widget build(BuildContext context) {
    if (!kModoDemo) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: MistakeMapDesign.amber.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(kRadiusSm),
        border: Border.all(
          color: MistakeMapDesign.amber.withValues(alpha: 0.6),
        ),
      ),
      child: Text(
        '⚠ Demonstração',
        textAlign: TextAlign.center,
        style: context.tipo.caption?.copyWith(
          color: MistakeMapDesign.amberInk,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// Padding, cantos e texto padronizados para Button/FilledButton do Fluent.
ButtonStyle _estiloBotao({
  double raio = 12,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
    vertical: 12,
    horizontal: 20,
  ),
  double fonte = 16,
  Color? fundo,
  Color? texto,
}) => MistakeMapControls.button(
  radius: raio,
  padding: padding,
  fontSize: fonte,
  background: fundo,
  foreground: texto,
);

// Aviso flutuante: sucesso em contentBlue e erro em vermelho 700 (cores
// semânticas definidas no temaVidro).
void _avisar(BuildContext context, String mensagem, {bool erro = false}) {
  GlassToast.show(
    context,
    message: mensagem,
    type: erro ? GlassToastType.error : GlassToastType.success,
    position: GlassToastPosition.top,
    icon: Icon(erro ? WindowsIcons.error_badge : WindowsIcons.completed),
  );
}

MenuFlyoutItemBuilder _itemMenu({
  required IconData icone,
  required String texto,
  required VoidCallback? onPressed,
  Color cor = contentBlue,
}) => MenuFlyoutItemBuilder(
  builder: (context) => MistakeMapButton(
    style:
        MistakeMapControls.button(
          radius: 4,
          background: Cores.transparente,
          foreground: cor,
          fontSize: 14,
          padding: const EdgeInsetsDirectional.only(
            top: 4,
            bottom: 4,
            start: 10,
            end: 8,
          ),
        ).copyWith(
          backgroundColor: const WidgetStatePropertyAll(Cores.transparente),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              letterSpacing: -0.15,
            ),
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
          ),
          elevation: const WidgetStatePropertyAll(0),
        ),
    onPressed: onPressed == null
        ? null
        : () {
            // Fecha o menu antes de agir: com a ação no mesmo quadro, o
            // diálogo de confirmação abria por cima e o menu ficava órfão na
            // tela depois de excluir o item.
            Navigator.of(context).pop();
            WidgetsBinding.instance.addPostFrameCallback((_) => onPressed());
          },
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 10),
          child: _IconeBotao(icone),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: Text(texto, textAlign: TextAlign.start),
          ),
        ),
      ],
    ),
  ),
);

Future<bool> _confirmar(
  BuildContext context, {
  required String titulo,
  required String mensagem,
  String confirmar = 'Confirmar',
  String cancelar = 'Cancelar',
  bool destrutivo = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => ContentDialog(
      title: Text(titulo),
      content: Text(mensagem),
      actions: [
        MistakeMapButton(
          style: _estiloBotao(fonte: 14),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelar),
        ),
        MistakeMapFilledButton(
          style: _estiloBotao(
            fonte: 14,
            fundo: destrutivo ? Cores.vermelho700 : null,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmar),
        ),
      ],
    ),
  );
  return ok ?? false;
}

// ─── fim: Design system ──────────────────────────────────────────────────────

// ─── Contrato de upload (Edge Function upload-url) ───────────────────────────
// Espelha supabase/functions/upload-url/handler.ts e a política RLS de
// attempt_assets (migração 20260929052429).

/// Tamanho máximo aceito pela upload-url e pela análise de IA.
const int kMaxBytesImagem = 8 * 1024 * 1024;

const Map<String, String> _extensaoPorTipo = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

/// Content-Type que a upload-url assina para a foto, ou null se o formato não
/// é aceito. O PUT para a R2 precisa repetir esse valor exato (image/jpeg,
/// nunca image/jpg), senão a assinatura da URL não confere.
/// Com [bytes], vale a assinatura do arquivo (magic numbers): o
/// image_picker_android reencoda a foto em JPEG/PNG mas mantém o nome
/// original (ex.: scaled_x.heic). Nome e mimeType só decidem sem bytes.
String? tipoMimeImagem(
  String nomeArquivo, {
  String? mimeType,
  List<int>? bytes,
}) {
  if (bytes != null && bytes.isNotEmpty) return imageTypeFromBytes(bytes);
  final ponto = nomeArquivo.lastIndexOf('.');
  final extensao = ponto < 0
      ? ''
      : nomeArquivo.substring(ponto + 1).toLowerCase();
  final porExtensao = switch (extensao) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => null,
  };
  if (porExtensao != null) return porExtensao;
  return _extensaoPorTipo.containsKey(mimeType) ? mimeType : null;
}

/// Corpo do POST para a upload-url, ou null se a foto não pode ser enviada.
/// O nome enviado é sintético: o nome original do arquivo não sai do aparelho
/// e a extensão acompanha o tipo detectado, como a upload-url exige.
Map<String, Object>? pedidoDeUpload(
  String nomeArquivo,
  int tamanhoBytes, {
  String? mimeType,
  List<int>? bytes,
}) {
  final tipo = tipoMimeImagem(nomeArquivo, mimeType: mimeType, bytes: bytes);
  if (tipo == null || tamanhoBytes <= 0 || tamanhoBytes > kMaxBytesImagem) {
    return null;
  }
  return {
    'filename': 'exercicio.${_extensaoPorTipo[tipo]}',
    'content_type': tipo,
    'size_bytes': tamanhoBytes,
  };
}

/// SHA-256 em hexadecimal minúsculo: formato exigido pela política RLS de
/// attempt_assets e conferido pela análise antes de enviar a foto à IA.
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Falha de envio com mensagem já pronta para o usuário.
class ErroDeEnvio implements Exception {
  final String mensagem;
  const ErroDeEnvio(this.mensagem);

  @override
  String toString() => mensagem;
}

// guard_analyzed_exercise: o diagnóstico da IA pertence ao enunciado
// enviado, então enunciado e matéria ficam imutáveis após a tentativa.
const _msgExercicioJaEnviado =
    'Este exercício já foi enviado para análise, então o enunciado e a '
    'matéria não podem mais ser alterados. Registre um novo exercício '
    'com a versão corrigida.';

/// Mensagem amigável para erros conhecidos do backend, ou null quando o erro
/// não é reconhecido (o chamador decide como exibi-lo).
String? mensagemDeErro(Object erro) {
  if (erro is ErroDeEnvio) return erro.mensagem;
  if (erro is FunctionException) {
    final detalhes = erro.details;
    if (detalhes is Map && detalhes['message'] is String) {
      return detalhes['message'] as String;
    }
    if (detalhes is Map && detalhes['error'] == 'storage_quota_exceeded') {
      return 'O limite de armazenamento de fotos foi atingido.';
    }
    return erro.status == 0
        ? 'Sem conexão com o servidor. Verifique a internet e tente novamente.'
        : 'O envio de fotos está temporariamente indisponível.';
  }
  if (erro is PostgrestException &&
      erro.code == '42501' &&
      erro.message.contains('create a new exercise')) {
    return _msgExercicioJaEnviado;
  }
  return null;
}

// ─── fim: Contrato de upload ─────────────────────────────────────────────────

// ─── Modelo de usuário com papel (role) ──────────────────────────────────────
class AppUser {
  final String id;
  final String email;
  final String role;

  const AppUser({required this.id, required this.email, required this.role});

  bool get isAdmin => role == 'admin';
}

// Carrega o perfil do Supabase e constrói um AppUser. Em falha (rede, RLS),
// o papel fica `user` — nunca concede privilégio por engano — e o erro volta
// para a tela avisar o estudante em vez de escondê-lo.
Future<({AppUser user, Object? erro})> _carregarPerfil(User supaUser) async {
  final padrao = AppUser(
    id: supaUser.id,
    email: supaUser.email ?? '',
    role: 'user',
  );
  try {
    final data = await _db
        .from('profiles')
        .select('role')
        .eq('id', supaUser.id)
        .maybeSingle()
        .timeout(const Duration(seconds: 12));
    final papel = data?['role'] as String? ?? 'user';
    // Guardar o papel é reserva para o modo offline; não segura a entrada.
    unawaited(
      _contaOffline.lembrarPapel(
        id: supaUser.id,
        email: supaUser.email ?? '',
        papel: papel,
      ),
    );
    return (
      user: AppUser(id: supaUser.id, email: supaUser.email ?? '', role: papel),
      erro: null,
    );
  } catch (erro) {
    return (user: padrao, erro: erro);
  }
}

/// Usuário com o papel salvo no aparelho, para abrir o app sem esperar a rede.
Future<AppUser?> _perfilSalvo(User supaUser) async {
  final papel = await _contaOffline.papel(supaUser.id);
  if (papel == null) return null;
  return AppUser(id: supaUser.id, email: supaUser.email ?? '', role: papel);
}

/// Mensagem exibida quando o perfil não carrega; o app segue no modo
/// estudante e tenta de novo sozinho.
String mensagemFalhaPerfil(Object erro) {
  return ehFalhaDeRede(erro)
      ? 'Sem conexão para carregar seu perfil. Você entrou como estudante; '
            'tentaremos de novo automaticamente.'
      : 'Não foi possível carregar seu perfil. Você entrou como estudante; '
            'tentaremos de novo automaticamente.';
}

// ─── Entry point ─────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: _supabaseUrl,
    // ignore: deprecated_member_use
    anonKey: _supabaseAnonKey,
  );
  await LiquidGlassWidgets.initialize();
  runApp(
    LiquidGlassWidgets.wrap(
      theme: temaVidro,
      brightnessResolver: (context) => FluentTheme.maybeOf(context)?.brightness,
      child: const MistakeMapApp(),
    ),
  );
}

class MistakeMapApp extends StatelessWidget {
  const MistakeMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'MistakeMap',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: temaFluent,
      // O app é só claro; sem isso, os textos Cupertino dos overlays de vidro
      // (toasts) seguem o modo escuro do sistema e somem sobre o vidro claro.
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return FluentTheme(
          data: media.disableAnimations
              ? temaFluent.copyWith(
                  fasterAnimationDuration: Duration.zero,
                  fastAnimationDuration: Duration.zero,
                  mediumAnimationDuration: Duration.zero,
                )
              : temaFluent,
          child: MediaQuery(
            data: media.copyWith(platformBrightness: Brightness.light),
            child: child!,
          ),
        );
      },
      home: const AuthGate(),
    );
  }
}

// Conta que entrou sem rede (senha conferida com o hash salvo no aparelho).
final _sessaoOffline = ValueNotifier<AppUser?>(null);
const _contaOffline = ContaOffline();

/// Sai da conta mesmo sem rede: o logout no servidor é tentado, mas a sessão
/// local é apagada de qualquer jeito.
Future<void> _sairDaConta() async {
  _sessaoOffline.value = null;
  if (_db.auth.currentSession == null) return;
  try {
    await _db.auth.signOut().timeout(const Duration(seconds: 8));
  } catch (_) {
    await _db.auth.signOut(scope: SignOutScope.local);
  }
}

// ─── AuthGate ─────────────────────────────────────────────────────────────────
// Redireciona para login ou app conforme o estado da sessão Supabase. O link
// de recuperação de senha abre uma sessão temporária: enquanto ela durar, a
// tela pede a nova senha antes de liberar o app.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _recuperandoSenha = false;

  @override
  void initState() {
    super.initState();
    _sessaoOffline.addListener(_atualizar);
  }

  @override
  void dispose() {
    _sessaoOffline.removeListener(_atualizar);
    super.dispose();
  }

  void _atualizar() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _db.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScaffold();
        }
        // Entrou sem rede com a conta salva neste aparelho: o app funciona
        // pelo cache e pela fila até a próxima entrada com internet.
        if (_db.auth.currentSession == null) {
          final offline = _sessaoOffline.value;
          if (offline != null) return TelaNavegacao(user: offline);
        }
        final evento = snapshot.data?.event;
        if (evento == AuthChangeEvent.passwordRecovery) {
          _recuperandoSenha = true;
        } else if (evento == AuthChangeEvent.signedOut) {
          _recuperandoSenha = false;
        }
        // A sessão vem do cliente, não do snapshot: falha de refresh por rede
        // chega como erro sem data, mas a sessão continua válida e o usuário
        // não deve cair no login nem perder o estado das abas.
        final session = _db.auth.currentSession;
        if (session == null) return TelaCadastro(erroAuth: snapshot.error);
        if (_recuperandoSenha) {
          return TelaNovaSenha(
            onConcluido: () => setState(() => _recuperandoSenha = false),
          );
        }
        return _CarregadorDePerfil(supaUser: session.user);
      },
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return const AuroraBackground(child: Center(child: ProgressRing()));
  }
}

// Busca o perfil do usuário no banco e exibe a navegação principal
class _CarregadorDePerfil extends StatefulWidget {
  final User supaUser;
  const _CarregadorDePerfil({required this.supaUser});

  @override
  State<_CarregadorDePerfil> createState() => _CarregadorDePerfilState();
}

class _CarregadorDePerfilState extends State<_CarregadorDePerfil> {
  AppUser? _appUser;
  Timer? _novaTentativa;
  int _tentativas = 0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _novaTentativa?.cancel();
    super.dispose();
  }

  Future<void> _carregar() async {
    // O papel salvo abre o app na hora, mesmo sem rede; o servidor confirma
    // logo em seguida.
    if (_appUser == null) {
      final salvo = await _perfilSalvo(widget.supaUser);
      if (!mounted) return;
      if (salvo != null) setState(() => _appUser = salvo);
    }
    final resultado = await _carregarPerfil(widget.supaUser);
    if (!mounted) return;
    final primeiraCarga = _appUser == null;
    // Não rebaixa um papel já confirmado por causa de uma nova falha.
    if (resultado.erro == null || primeiraCarga) {
      setState(() => _appUser = resultado.user);
    }
    final erro = resultado.erro;
    if (erro == null) return;
    if (primeiraCarga) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _avisar(context, mensagemFalhaPerfil(erro), erro: true);
      });
    }
    // 15 s, 30 s, 60 s… até 5 min entre as tentativas.
    if (_tentativas < 8) {
      final espera = Duration(seconds: (15 << _tentativas).clamp(15, 300));
      _tentativas++;
      _novaTentativa = Timer(espera, _carregar);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_appUser == null) return const _LoadingScaffold();
    return TelaNavegacao(user: _appUser!);
  }
}

// ─── Navegação principal ──────────────────────────────────────────────────────
class TelaNavegacao extends StatefulWidget {
  final AppUser user;
  final AnalysisRepository? analysisRepository;
  const TelaNavegacao({super.key, required this.user, this.analysisRepository});

  @override
  State<TelaNavegacao> createState() => _TelaNavegacaoState();
}

class _TelaNavegacaoState extends State<TelaNavegacao> {
  int _indiceAtual = 0;
  bool _paginaAberta = false;
  final _inicioKey = GlobalKey<_TelaInicialState>();
  final _listaKey = GlobalKey<_TelaPrincipalState>();
  final _mapaKey = GlobalKey<_TelaMapaConceitualState>();
  final _cadernoKey = GlobalKey<_TelaCadernoErrosState>();
  late final AnalysisRepository _analysisRepository =
      widget.analysisRepository ?? SupabaseAnalysisRepository(_db);
  late final Sincronizador _sincronizador = _sync(widget.user.id);

  @override
  void initState() {
    super.initState();
    _sincronizador.alteracoes.addListener(_recarregarAbas);
    _sincronizador.aviso.addListener(_mostrarAviso);
  }

  @override
  void dispose() {
    _sincronizador.alteracoes.removeListener(_recarregarAbas);
    _sincronizador.aviso.removeListener(_mostrarAviso);
    _sincronizador.parar();
    super.dispose();
  }

  // Fila enviada ou mudança no Realtime: as abas vivas no IndexedStack
  // recarregam do Supabase (e regravam o cache).
  void _recarregarAbas() {
    _inicioKey.currentState?.carregarEstatisticas();
    _listaKey.currentState?.carregarExercicios();
    _mapaKey.currentState?.carregar();
  }

  void _mostrarAviso() {
    final mensagem = _sincronizador.aviso.value;
    if (mensagem == null || !mounted) return;
    _sincronizador.aviso.value = null;
    _avisar(context, mensagem, erro: true);
  }

  // Mapa e análise por IA são uma página só; [analisar] abre o painel de
  // envio já expandido (atalho do Início).
  Future<void> _abrirIa({bool analisar = false, bool estudar = false}) async {
    if (_paginaAberta) return;
    setState(() => _paginaAberta = true);
    try {
      await Navigator.of(context).push(
        MistakeMapPageRoute(
          context: context,
          builder: (_) => AiMaterialShell(
            userId: widget.user.id,
            repository: _analysisRepository,
            showMap: true,
            startWithAnalysis: analisar,
            startWithStudy: estudar,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _paginaAberta = false);
        // Recarrega o Início se estiver visível: uma tentativa pode ter sido
        // criada dentro do fluxo de IA. O índice 0 pode estar ativo mesmo
        // quando a guarda `i == _indiceAtual` impediu a troca de aba.
        if (_indiceAtual == 0) {
          _inicioKey.currentState?.carregarEstatisticas();
        }
      }
    }
  }

  Future<void> _abrirSobre() async {
    if (_paginaAberta) return;
    setState(() => _paginaAberta = true);
    try {
      await Navigator.of(context).push(
        MistakeMapPageRoute(
          context: context,
          builder: (_) => const TelaSobre(),
        ),
      );
    } finally {
      if (mounted) setState(() => _paginaAberta = false);
    }
  }

  Future<void> _sair() async {
    final ok = await _confirmar(
      context,
      titulo: 'Sair da conta',
      mensagem: 'Deseja sair do MistakeMap neste aparelho?',
      confirmar: 'Sair',
    );
    if (ok) await _sairDaConta();
  }

  void _selecionar(int i) {
    if (i == _indiceAtual) return;
    setState(() => _indiceAtual = i);
    if (i == 0) _inicioKey.currentState?.carregarEstatisticas();
    if (i == 1) _listaKey.currentState?.carregarExercicios();
    if (i == 2) _mapaKey.currentState?.carregar();
    if (i == 3) _cadernoKey.currentState?._carregar();
  }

  // Índice 3 era "Novo exercício", que só repetia a análise por IA (hoje
  // dentro do Mapa). O Caderno, antes escondido num botão do Início, ocupa
  // a vaga como aba própria.
  List<Widget> get _telas => [
    TelaInicial(
      key: _inicioKey,
      user: widget.user,
      onAnalysis: () => _abrirIa(analisar: true),
      onAbout: _abrirSobre,
      onExercicios: () => _selecionar(1),
      onMapa: _abrirIa,
      onEstudar: () => _abrirIa(estudar: true),
      onCaderno: () => _selecionar(3),
    ),
    TelaPrincipal(key: _listaKey, user: widget.user),
    TelaMapaConceitual(key: _mapaKey, user: widget.user),
    TelaCadernoErros(key: _cadernoKey, user: widget.user, aba: true),
    if (widget.user.isAdmin)
      TelaAdmin(user: widget.user, active: _indiceAtual == 4 && !_paginaAberta),
  ];

  @override
  Widget build(BuildContext context) {
    return AppNavigationShell(
      selectedIndex: _indiceAtual,
      onSelected: _selecionar,
      hasAdmin: widget.user.isAdmin,
      onErrorMap: _abrirIa,
      onStudy: () => _abrirIa(estudar: true),
      onAnalysis: () => _abrirIa(analisar: true),
      onSignOut: _sair,
      onAbout: _abrirSobre,
      child: PopScope(
        canPop: _indiceAtual == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _indiceAtual != 0) _selecionar(0);
        },
        child: NavigationPages(
          index: _indiceAtual,
          active: !_paginaAberta,
          children: _telas,
        ),
      ),
    );
  }
}

// ─── fim: Navegação principal ────────────────────────────────────────────────

// ─── Tela de login / cadastro ─────────────────────────────────────────────────
class TelaCadastro extends StatefulWidget {
  // Erro do stream de auth (ex.: deep link do OAuth) exibido como aviso.
  final Object? erroAuth;
  const TelaCadastro({super.key, this.erroAuth});

  @override
  State<TelaCadastro> createState() => _TelaCadastroState();
}

class _TelaCadastroState extends State<TelaCadastro> {
  final _emailCtrl = TextEditingController();
  final _senhaCtrl = TextEditingController();
  bool _senhaVisivel = false;
  bool _carregando = false;
  bool _modoCadastro = false; // false = entrar, true = criar conta

  @override
  void initState() {
    super.initState();
    _avisarErroAuth();
  }

  @override
  void didUpdateWidget(TelaCadastro oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Identidade: cada falha é um objeto novo; rebuilds com o mesmo snapshot
    // não repetem o aviso.
    if (!identical(widget.erroAuth, oldWidget.erroAuth)) _avisarErroAuth();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _senhaCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    _avisar(context, msg, erro: erro);
  }

  void _avisarErroAuth() {
    final erro = widget.erroAuth;
    if (erro == null) return;
    // O aviso usa o Overlay; espera o frame terminar de montar a tela.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _snack(_mensagemErroAuth(erro), erro: true),
    );
  }

  String _mensagemErroAuth(Object erro) {
    if (erro is AuthRetryableFetchException) {
      return 'Sem conexão com o servidor. Verifique a internet e tente novamente.';
    }
    if (erro is AuthException) return _traduzirErroAuth(erro.message);
    return 'Não foi possível concluir o login. Tente novamente.';
  }

  Future<void> _entrarComEmailSenha() async {
    final email = _emailCtrl.text.trim();
    final senha = _senhaCtrl.text.trim();
    if (email.isEmpty || senha.isEmpty) {
      _snack('Preencha e-mail e senha.', erro: true);
      return;
    }
    setState(() => _carregando = true);
    try {
      if (_modoCadastro) {
        final res = await _db.auth.signUp(email: email, password: senha);
        if (res.user != null && res.session == null) {
          _snack('Verifique seu e-mail para confirmar o cadastro.');
        }
      } else {
        final res = await _db.auth.signInWithPassword(
          email: email,
          password: senha,
        );
        final user = res.user;
        if (user != null) {
          await _contaOffline.lembrarLogin(
            id: user.id,
            email: user.email ?? email,
            senha: senha,
          );
        }
      }
    } catch (e) {
      if (!_modoCadastro &&
          ehFalhaDeRede(e) &&
          await _entrarOffline(email, senha)) {
        return;
      }
      _snack(_mensagemErroAuth(e), erro: true);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// Sem rede, confere a senha com a última conta que entrou neste aparelho.
  Future<bool> _entrarOffline(String email, String senha) async {
    final conta = await _contaOffline.entrar(email, senha);
    if (conta == null) {
      _snack(
        'Sem conexão. Para entrar offline, use a conta que já entrou neste '
        'aparelho com e-mail e senha.',
        erro: true,
      );
      return true;
    }
    _sessaoOffline.value = AppUser(
      id: conta.id,
      email: conta.email,
      role: conta.papel,
    );
    _snack(
      'Você entrou sem internet. O que fizer fica salvo no aparelho e é '
      'enviado quando a conexão voltar.',
    );
    return true;
  }

  Future<void> _entrarComGoogle() async {
    if (_carregando) return;
    setState(() => _carregando = true);
    try {
      // O serviço consulta /auth/v1/settings antes de sair do app: com o
      // provedor desligado, o usuário fica no login com a mensagem, em vez de
      // cair na página de erro 400 do Supabase. O timeout externo cobre os 8 s
      // da consulta mais a abertura do navegador.
      await GoogleSignInService(
            supabaseUrl: Uri.parse(_supabaseUrl),
            publicKey: _supabaseAnonKey,
            launchOAuth: (redirectTo) => _db.auth.signInWithOAuth(
              OAuthProvider.google,
              redirectTo: redirectTo,
            ),
          )
          .signIn(isWeb: kIsWeb, currentUri: Uri.base)
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      if (mounted) {
        _snack(
          'O Google demorou para abrir. Verifique a conexão e tente novamente.',
          erro: true,
        );
      }
    } on GoogleSignInException catch (e) {
      if (mounted) _snack(e.message, erro: true);
    } on AuthException catch (e) {
      if (mounted) _snack(e.message, erro: true);
    } catch (_) {
      if (mounted) {
        _snack(
          'Não foi possível iniciar o login com Google. Tente novamente.',
          erro: true,
        );
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  String _traduzirErroAuth(String msg) {
    if (msg.contains('Invalid login credentials')) {
      return 'E-mail ou senha incorretos.';
    }
    if (msg.contains('Email not confirmed')) {
      return 'Confirme seu e-mail antes de entrar.';
    }
    if (msg.contains('User already registered')) {
      return 'Este e-mail já possui uma conta.';
    }
    if (msg.contains('rate limit') || msg.contains('For security purposes')) {
      return 'Muitas solicitações seguidas. Aguarde um minuto e tente de novo.';
    }
    return msg;
  }

  // Envia o link de redefinição. A resposta é a mesma com ou sem conta para
  // o e-mail, para a tela não revelar quem está cadastrado.
  Future<void> _recuperarSenha() async {
    final campo = TextEditingController(text: _emailCtrl.text.trim());
    final email = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ContentDialog(
        title: const Text('Redefinir senha'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Informe o e-mail da conta. Enviaremos um link para você criar '
              'uma nova senha.',
            ),
            const SizedBox(height: 16),
            TextBox(
              key: const Key('recuperar-email'),
              controller: campo,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              placeholder: 'email@dominio.com',
              onSubmitted: (valor) => Navigator.of(ctx).pop(valor.trim()),
            ),
          ],
        ),
        actions: [
          MistakeMapButton(
            style: _estiloBotao(fonte: 14),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          MistakeMapFilledButton(
            key: const Key('recuperar-enviar'),
            style: _estiloBotao(fonte: 14),
            onPressed: () => Navigator.of(ctx).pop(campo.text.trim()),
            child: const Text('Enviar link'),
          ),
        ],
      ),
    );
    campo.dispose();
    if (email == null || !mounted) return;
    if (!email.contains('@')) {
      _snack('Informe um e-mail válido.', erro: true);
      return;
    }
    setState(() => _carregando = true);
    try {
      await _db.auth.resetPasswordForEmail(
        email,
        redirectTo: googleOAuthRedirect(isWeb: kIsWeb, currentUri: Uri.base),
      );
      _snack(
        'Se houver uma conta com esse e-mail, você receberá o link de '
        'redefinição em instantes.',
      );
    } on AuthRetryableFetchException {
      _snack(
        'Sem conexão com o servidor. Verifique a internet e tente novamente.',
        erro: true,
      );
    } on AuthException catch (e) {
      _snack(_traduzirErroAuth(e.message), erro: true);
    } on GoogleSignInException {
      _snack('Não foi possível montar o link de retorno do app.', erro: true);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fora do shell: sem barra superior nem barra de abas.
    return GlassScaffold(
      background: const _FundoMica(),
      enableBackgroundSampling: false,
      backgroundColor: kScaffoldBg,
      statusBarStyle: GlassStatusBarStyle.dark,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _cabecalho(context),
                  const SizedBox(height: 32),
                  _PainelVidro(
                    padding: const EdgeInsets.all(24),
                    child: _formulario(context),
                  ),
                  const SizedBox(height: 32),
                  _termos(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cabecalho(BuildContext context) {
    return Column(
      children: [
        Text(
          'MistakeMap',
          textAlign: TextAlign.center,
          style: context.tipo.title?.copyWith(
            fontWeight: FontWeight.bold,
            color: titleBlue,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Transforme erros em aprendizado',
          textAlign: TextAlign.center,
          style: context.tipo.body?.copyWith(color: contentBlue),
        ),
      ],
    );
  }

  // Borda contentBlue dos campos. Sem foco, a linha inferior do TextBox fica
  // transparente (unfocusedColor) para não somar um traço cinza à borda; com
  // foco, vale o realce de 2 px do Fluent.
  WidgetStateProperty<BoxDecoration> get _decoracaoCampo {
    return WidgetStatePropertyAll(
      BoxDecoration(
        borderRadius: BorderRadius.circular(kRadiusSm),
        border: Border.all(color: contentBlue),
      ),
    );
  }

  // Ação dentro do campo (mostrar/ocultar senha). O iconButtonStyle do tema é
  // de botão avulso (fundo, borda em gradiente e sombra) e, aqui, aparecia como
  // uma caixa solta sobre a borda do TextBox. Em repouso fica só o ícone; o
  // hover/press seguem o _MistakeMapButtonState e o foco, o mesmo traço de 2 px.
  ButtonStyle get _estiloAcaoCampo {
    return ButtonStyle(
      padding: const WidgetStatePropertyAll(EdgeInsets.all(12)),
      backgroundColor: const WidgetStatePropertyAll(Cores.transparente),
      foregroundColor: const WidgetStatePropertyAll(contentBlue),
      elevation: const WidgetStatePropertyAll(0),
      shape: WidgetStateProperty.resolveWith(
        (states) => RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusSm),
          side: states.contains(WidgetState.focused)
              ? const BorderSide(color: titleBlue, width: 2)
              : BorderSide.none,
        ),
      ),
    );
  }

  Widget _iconeCampo(IconData icone) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 12),
      child: Icon(icone, size: 16, color: contentBlue),
    );
  }

  Widget _divisor() {
    return const Divider(
      style: DividerThemeData(
        thickness: 1,
        horizontalMargin: EdgeInsets.zero,
        decoration: BoxDecoration(color: MistakeMapDesign.mist),
      ),
    );
  }

  Widget _formulario(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Campo de e-mail
        TextBox(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          placeholder: 'email@dominio.com',
          placeholderStyle: const TextStyle(color: contentBlue),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: _decoracaoCampo,
          unfocusedColor: Cores.transparente,
          prefix: _iconeCampo(WindowsIcons.mail),
        ),
        const SizedBox(height: 16),
        TextBox(
          controller: _senhaCtrl,
          obscureText: !_senhaVisivel,
          placeholder: 'senha',
          placeholderStyle: const TextStyle(color: contentBlue),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: _decoracaoCampo,
          unfocusedColor: Cores.transparente,
          prefix: _iconeCampo(WindowsIcons.lock),
          suffix: Padding(
            padding: const EdgeInsetsDirectional.only(end: 4),
            child: Tooltip(
              message: _senhaVisivel ? 'Ocultar senha' : 'Mostrar senha',
              // 40 px fixos, como _BotaoBarra: a densidade compacta do
              // desktop/web reduziria o padding para 36 px.
              child: SizedBox.square(
                dimension: 40,
                child: MistakeMapIconButton(
                  style: _estiloAcaoCampo,
                  icon: _IconeBotao(
                    _senhaVisivel ? WindowsIcons.hide : WindowsIcons.red_eye,
                    size: 16,
                  ),
                  onPressed: () =>
                      setState(() => _senhaVisivel = !_senhaVisivel),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Botão principal
        MistakeMapFilledButton(
          style: _estiloBotao(
            fundo: kAcento,
            texto: MistakeMapDesign.abyss,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
          onPressed: _carregando ? null : _entrarComEmailSenha,
          child: _carregando
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: ProgressRing(
                    strokeWidth: 2.5,
                    activeColor: MistakeMapDesign.abyss,
                  ),
                )
              : Text(_modoCadastro ? 'Criar conta' : 'Entrar'),
        ),
        const SizedBox(height: 8),
        MistakeMapHyperlinkButton(
          onPressed: () => setState(() => _modoCadastro = !_modoCadastro),
          child: Text(
            _modoCadastro
                ? 'Já tenho conta — Entrar'
                : 'Não tenho conta — Criar',
          ),
        ),
        if (!_modoCadastro)
          MistakeMapHyperlinkButton(
            key: const Key('login-esqueci-senha'),
            onPressed: _carregando ? null : _recuperarSenha,
            child: const Text('Esqueci minha senha'),
          ),
        // O retorno do OAuth (io.supabase.mistakemap://) só está registrado no
        // Android; na web ele volta para a própria página. No Windows o
        // navegador abriria e a sessão nunca chegaria ao app.
        if (_googleDisponivel) ...[
          const SizedBox(height: 16),
          // Divisor "ou"
          Row(
            children: [
              Expanded(child: _divisor()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'ou',
                  style: context.tipo.body?.copyWith(color: contentBlue),
                ),
              ),
              Expanded(child: _divisor()),
            ],
          ),
          const SizedBox(height: 16),
          // Botão Google
          MistakeMapButton(
            style:
                _estiloBotao(
                  fundo: Cores.cinza100,
                  texto: contentBlue,
                  fonte: 14,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 24,
                  ),
                ).copyWith(
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kRadiusSm),
                      side: const BorderSide(color: contentBlue),
                    ),
                  ),
                ),
            onPressed: _carregando ? null : _entrarComGoogle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Não há ícone do Google em WindowsIcons: usa-se a letra "G".
                Builder(
                  builder: (context) => ExcludeSemantics(
                    child: Text(
                      'G',
                      style: context.tipo.subtitle?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: DefaultTextStyle.of(context).style.color,
                        height: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'Continue com Google',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  bool get _googleDisponivel =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;

  Widget _termos(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: context.tipo.caption?.copyWith(color: contentBlue),
        children: const [
          TextSpan(text: 'Ao continuar, você concorda com nossos '),
          TextSpan(
            text: 'Termos de Serviço\n',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: 'e '),
          TextSpan(
            text: 'Política de Privacidade',
            style: TextStyle(color: titleBlue, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

// ─── Tela de nova senha (link de recuperação) ────────────────────────────────
class TelaNovaSenha extends StatefulWidget {
  final VoidCallback onConcluido;
  const TelaNovaSenha({super.key, required this.onConcluido});

  @override
  State<TelaNovaSenha> createState() => _TelaNovaSenhaState();
}

class _TelaNovaSenhaState extends State<TelaNovaSenha> {
  final _senhaCtrl = TextEditingController();
  final _confirmacaoCtrl = TextEditingController();
  bool _salvando = false;

  static const _tamanhoMinimo = 6;

  @override
  void dispose() {
    _senhaCtrl.dispose();
    _confirmacaoCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final senha = _senhaCtrl.text;
    if (senha.length < _tamanhoMinimo) {
      _avisar(
        context,
        'A senha precisa ter ao menos $_tamanhoMinimo caracteres.',
        erro: true,
      );
      return;
    }
    if (senha != _confirmacaoCtrl.text) {
      _avisar(context, 'As senhas não conferem.', erro: true);
      return;
    }
    setState(() => _salvando = true);
    try {
      await _db.auth.updateUser(UserAttributes(password: senha));
      if (!mounted) return;
      _avisar(context, 'Senha atualizada. Bons estudos!');
      widget.onConcluido();
    } on AuthRetryableFetchException {
      if (mounted) {
        _avisar(
          context,
          'Sem conexão com o servidor. Verifique a internet e tente novamente.',
          erro: true,
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        _avisar(
          context,
          e.message.contains('different from the old')
              ? 'Escolha uma senha diferente da anterior.'
              : e.message,
          erro: true,
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Widget _campo(TextEditingController controller, String placeholder, Key key) {
    return TextBox(
      key: key,
      controller: controller,
      obscureText: true,
      placeholder: placeholder,
      placeholderStyle: const TextStyle(color: contentBlue),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: WidgetStatePropertyAll(
        BoxDecoration(
          borderRadius: BorderRadius.circular(kRadiusSm),
          border: Border.all(color: contentBlue),
        ),
      ),
      unfocusedColor: Cores.transparente,
      prefix: const Padding(
        padding: EdgeInsetsDirectional.only(start: 12),
        child: Icon(WindowsIcons.lock, size: 16, color: contentBlue),
      ),
      onSubmitted: (_) => _salvar(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      background: const _FundoMica(),
      enableBackgroundSampling: false,
      backgroundColor: kScaffoldBg,
      statusBarStyle: GlassStatusBarStyle.dark,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _PainelVidro(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Crie uma nova senha',
                      style: context.tipo.subtitle?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: titleBlue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use ao menos $_tamanhoMinimo caracteres.',
                      style: context.tipo.body?.copyWith(color: contentBlue),
                    ),
                    const SizedBox(height: 24),
                    _campo(_senhaCtrl, 'nova senha', const Key('nova-senha')),
                    const SizedBox(height: 16),
                    _campo(
                      _confirmacaoCtrl,
                      'confirme a nova senha',
                      const Key('nova-senha-confirmacao'),
                    ),
                    const SizedBox(height: 16),
                    MistakeMapFilledButton(
                      key: const Key('nova-senha-salvar'),
                      style: _estiloBotao(
                        fundo: kAcento,
                        texto: MistakeMapDesign.abyss,
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 24,
                        ),
                      ),
                      onPressed: _salvando ? null : _salvar,
                      child: _salvando
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: ProgressRing(
                                strokeWidth: 2.5,
                                activeColor: MistakeMapDesign.abyss,
                              ),
                            )
                          : const Text('Salvar nova senha'),
                    ),
                    const SizedBox(height: 8),
                    MistakeMapHyperlinkButton(
                      onPressed: _salvando ? null : _sairDaConta,
                      child: const Text('Cancelar e voltar ao login'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── fim: Tela de login / cadastro ───────────────────────────────────────────

// ─── Tela inicial (dashboard) ─────────────────────────────────────────────────
class TelaInicial extends StatefulWidget {
  final AppUser user;
  final VoidCallback? onAnalysis;
  final VoidCallback? onAbout;

  /// Atalhos do ciclo de estudo, na ordem em que o estudante os usa.
  final VoidCallback? onExercicios;
  final VoidCallback? onMapa;
  final VoidCallback? onEstudar;
  final VoidCallback? onCaderno;
  const TelaInicial({
    super.key,
    required this.user,
    this.onAnalysis,
    this.onAbout,
    this.onExercicios,
    this.onMapa,
    this.onEstudar,
    this.onCaderno,
  });

  @override
  State<TelaInicial> createState() => _TelaInicialState();
}

class _TelaInicialState extends State<TelaInicial> {
  int _totalExercicios = 0;
  int _paraRevisar = 0;
  String _evolucao = '—';
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    carregarEstatisticas();
  }

  // Pública para a navegação recarregar ao voltar ao Início: as abas ficam
  // vivas no IndexedStack e o initState não roda de novo.
  Future<void> carregarEstatisticas() async {
    try {
      final sync = _sync(widget.user.id);
      final fila = await sync.fila(widget.user.id);
      final res = await _consultarOuSoFila(
        sync,
        widget.user.id,
        'inicio_tentativas',
        fila,
        const [],
        () => _db
            .from('attempts')
            .select('id, status, exercise_id')
            .eq('user_id', widget.user.id),
      );
      final linhas = sobreporTentativas(res as List, fila);

      final grupos = linhas
          .map((a) => attemptStatusGroup(a['status'] as String?))
          .toList();
      final total = grupos.length;
      // "Para revisar" segue o _StatusBadge: só awaiting_review vira
      // "Revisar". Análises em andamento não pedem ação do estudante.
      final paraRevisar = grupos
          .where((g) => g == AttemptStatusGroup.review)
          .length;
      final completos = grupos
          .where((g) => g == AttemptStatusGroup.completed)
          .length;
      final pct = total > 0 ? '${((completos / total) * 100).round()}%' : '0%';

      if (mounted) {
        setState(() {
          _totalExercicios = total;
          _paraRevisar = paraRevisar;
          _evolucao = pct;
          _carregando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _sair() async {
    // O ícone fica ao lado do título: um toque acidental não deve deslogar.
    final ok = await _confirmar(
      context,
      titulo: 'Sair da conta',
      mensagem: 'Deseja sair do MistakeMap neste aparelho?',
      confirmar: 'Sair',
    );
    if (!ok) return;
    await _sairDaConta();
  }

  @override
  Widget build(BuildContext context) {
    return _PaginaVidro(
      titulo: 'Início — Resumo',
      acoes: [
        _BotaoBarra(
          icone: WindowsIcons.sign_out,
          dica: 'Sair',
          onPressed: _sair,
        ),
      ],
      corpo: _carregando
          ? const Center(child: ProgressRing())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: SingleChildScrollView(
                  padding: _paddingCorpo(context, horizontal: 24, topo: 8),
                  // Ordem de leitura = ordem de uso: quem é, o que fazer
                  // agora (o ciclo de estudo em passos) e só depois os números.
                  child: Column(
                    children: [
                      _cabecalho(context),
                      const SizedBox(height: 24),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: _proximosPassos(context),
                      ),
                      const SizedBox(height: 32),
                      _resumo(context),
                      const SizedBox(height: 24),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: _botaoSobre(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  /// O ciclo de estudo em passos: registrar, conferir, entender o padrão,
  /// estudar e anotar. O passo indicado agora fica em destaque, para o
  /// estudante seguir o caminho sem procurar a função no app.
  Widget _proximosPassos(BuildContext context) {
    final indicado = _totalExercicios == 0
        ? 0
        : _paraRevisar > 0
        ? 1
        : 3;
    final passos =
        <
          ({
            IconData icone,
            String titulo,
            String descricao,
            Color acento,
            Color tinta,
            VoidCallback? acao,
          })
        >[
          (
            icone: WindowsIcons.lightbulb,
            titulo: 'Analisar um exercício',
            descricao:
                'Envie a foto ou o texto da sua resposta; a IA corrige '
                'e aponta onde está o erro.',
            acento: MistakeMapDesign.aqua,
            tinta: MistakeMapDesign.aquaInk,
            acao: widget.onAnalysis,
          ),
          (
            icone: WindowsIcons.bulleted_list,
            titulo: _paraRevisar > 0
                ? 'Revisar $_paraRevisar exercício(s)'
                : 'Ver meus exercícios',
            descricao:
                'Confira a correção de cada tentativa e edite o que '
                'precisar.',
            acento: MistakeMapDesign.azure,
            tinta: MistakeMapDesign.azureInk,
            acao: widget.onExercicios,
          ),
          (
            icone: WindowsIcons.relationship,
            titulo: 'Ver o mapa de erros',
            descricao:
                'Descubra quais tipos de erro se repetem e em quais '
                'matérias.',
            acento: MistakeMapDesign.violet,
            tinta: MistakeMapDesign.violetInk,
            acao: widget.onMapa,
          ),
          (
            icone: WindowsIcons.education,
            titulo: 'Estudar com a IA',
            descricao:
                'Resumo, cartões, quiz e exercícios novos feitos a '
                'partir dos seus erros.',
            acento: MistakeMapDesign.violet,
            tinta: MistakeMapDesign.violetInk,
            acao: widget.onEstudar,
          ),
          (
            icone: WindowsIcons.quick_note,
            titulo: 'Anotar no caderno de erros',
            descricao: 'Guarde a regra que você aprendeu para revisar depois.',
            acento: MistakeMapDesign.amber,
            tinta: MistakeMapDesign.amberInk,
            acao: widget.onCaderno,
          ),
        ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'O que fazer agora',
          style: context.tipo.subtitle?.copyWith(color: titleBlue),
        ),
        const SizedBox(height: 12),
        for (final (i, passo) in passos.indexed)
          if (passo.acao != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PassoCard(
                numero: i + 1,
                icone: passo.icone,
                titulo: passo.titulo,
                descricao: passo.descricao,
                acento: passo.acento,
                tinta: passo.tinta,
                indicado: i == indicado,
                onPressed: passo.acao!,
              ),
            ),
      ],
    );
  }

  // Cabeçalho com nome/email e badge de admin
  Widget _cabecalho(BuildContext context) {
    return GlassHero(
      child: Column(
        children: [
          Text(
            'MistakeMap',
            style: context.tipo.title?.copyWith(
              fontWeight: FontWeight.bold,
              color: Cores.branco,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.user.email,
            textAlign: TextAlign.center,
            style: context.tipo.body?.copyWith(color: Cores.branco),
          ),
          if (widget.user.isAdmin) ...[
            const SizedBox(height: 8),
            const _Pilula(
              texto: 'Administrador',
              cor: contentBlue,
              icone: WindowsIcons.admin,
              solida: true,
            ),
          ],
        ],
      ),
    );
  }

  // Cards de estatísticas
  Widget _resumo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Dashboard do Estudante',
          textAlign: TextAlign.center,
          style: context.tipo.subtitle?.copyWith(color: titleBlue),
        ),
        const SizedBox(height: 8),
        Text(
          'Acompanhe seu progresso e transforme erros em aprendizado.',
          textAlign: TextAlign.center,
          style: context.tipo.body?.copyWith(color: contentBlue),
        ),
        const SizedBox(height: 24),
        GradeAdaptativa(
          larguraMinimaItem: MediaQuery.sizeOf(context).width < 600 ? 320 : 160,
          maxColunas: 3,
          children: [
            _ResumoCard(
              icone: WindowsIcons.bulleted_list,
              // Conta tentativas (attempts), não os exercícios da lista.
              label: 'Tentativas',
              value: '$_totalExercicios',
              acento: MistakeMapDesign.azure,
              tinta: MistakeMapDesign.azureInk,
            ),
            _ResumoCard(
              icone: WindowsIcons.history,
              label: 'Para revisar',
              value: '$_paraRevisar',
              acento: MistakeMapDesign.amber,
              tinta: MistakeMapDesign.amberInk,
            ),
            _ResumoCard(
              icone: WindowsIcons.education,
              label: 'Evolução',
              value: _evolucao,
              acento: MistakeMapDesign.mint,
              tinta: MistakeMapDesign.mintInk,
            ),
          ],
        ),
      ],
    );
  }

  // Botão "Sobre o App"
  Widget _botaoSobre(BuildContext context) {
    return _botaoAtalho(
      icone: WindowsIcons.info,
      texto: 'Sobre o App',
      onPressed:
          widget.onAbout ??
          () {
            if (ModalRoute.of(context)?.isCurrent != true) return;
            Navigator.of(context).push(
              MistakeMapPageRoute(
                context: context,
                builder: (_) => const TelaSobre(),
              ),
            );
          },
    );
  }

  Widget _botaoAtalho({
    required IconData icone,
    required String texto,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: MistakeMapButton(
        // Mesma superfície e mesmos cantos dos cards de resumo acima.
        style: _estiloBotao(
          raio: kRadiusSm,
          texto: contentBlue,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icone, size: 18),
            const SizedBox(width: 8),
            Flexible(child: Text(texto, textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }
}

class _ResumoCard extends StatelessWidget {
  const _ResumoCard({
    required this.icone,
    required this.label,
    required this.value,
    required this.acento,
    required this.tinta,
  });

  final IconData icone;
  final String label;
  final String value;

  /// Cor com função: cada número leva o acento do que ele mede.
  final Color acento;
  final Color tinta;

  @override
  Widget build(BuildContext context) {
    return _PainelVidro(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      raio: kRadius,
      acento: acento,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassIconTile(icon: icone, ink: tinta, accent: acento, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: context.tipo.subtitle?.copyWith(
              fontWeight: FontWeight.bold,
              color: MistakeMapDesign.abyss,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: context.tipo.caption?.copyWith(color: contentBlue),
          ),
        ],
      ),
    );
  }
}

/// Um passo do ciclo de estudo no Início: o cartão inteiro é o botão.
class _PassoCard extends StatelessWidget {
  const _PassoCard({
    required this.numero,
    required this.icone,
    required this.titulo,
    required this.descricao,
    required this.acento,
    required this.tinta,
    required this.indicado,
    required this.onPressed,
  });

  final int numero;
  final IconData icone;
  final String titulo;
  final String descricao;
  final Color acento;
  final Color tinta;

  /// O passo sugerido agora: fundo tingido e etiqueta "Próximo passo".
  final bool indicado;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final fundo = indicado
        ? Color.alphaBlend(acento.withValues(alpha: .16), Cores.branco)
        : kGlassBg;
    // O afundar ao toque vem do MistakeMapButton, igual em todo o app.
    return Semantics(
      label: 'Passo $numero: $titulo',
      child: SizedBox(
        width: double.infinity,
        child: MistakeMapButton(
          onPressed: onPressed,
          style: MistakeMapControls.button(
            radius: kRadius,
            padding: const EdgeInsets.all(16),
            background: fundo,
            foreground: MistakeMapDesign.abyss,
          ),
          child: Row(
            children: [
              GlassIconTile(icon: icone, ink: tinta, accent: acento),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'PASSO $numero',
                          style: context.tipo.caption?.copyWith(
                            color: tinta,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                        if (indicado)
                          _Pilula(texto: 'Próximo passo', cor: tinta),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      titulo,
                      textAlign: TextAlign.start,
                      style: context.tipo.bodyStrong?.copyWith(
                        color: MistakeMapDesign.abyss,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      descricao,
                      textAlign: TextAlign.start,
                      style: context.tipo.caption?.copyWith(
                        color: MistakeMapDesign.steel,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(WindowsIcons.chevron_right, size: 14, color: tinta),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── fim: Tela inicial (dashboard) ───────────────────────────────────────────

// ─── Tela de adicionar exercício ──────────────────────────────────────────────
class TelaAdicionarExercicio extends StatefulWidget {
  final AppUser user;
  final VoidCallback? onIrParaMapa;
  const TelaAdicionarExercicio({
    super.key,
    required this.user,
    this.onIrParaMapa,
  });

  @override
  State<TelaAdicionarExercicio> createState() => _TelaAdicionarExercicioState();
}

class _TelaAdicionarExercicioState extends State<TelaAdicionarExercicio> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();
  final _assuntoCtrl = TextEditingController();
  final _erroCtrl = TextEditingController();
  XFile? _imagemSelecionada;
  Uint8List? _imagemBytes;
  bool _enviando = false;
  bool _sucesso = false;
  String _ultimoAssunto = '';

  @override
  void dispose() {
    _assuntoCtrl.dispose();
    _erroCtrl.dispose();
    super.dispose();
  }

  Future<void> _selecionarImagem(ImageSource source) async {
    // Como ExerciseSubmissionView._pickImage: sem câmera (emulador) ou sem
    // permissão o image_picker lança PlatformException, e sem o aviso o toque
    // ficaria sem resposta. O formato é validado já na escolha.
    try {
      final img = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2048,
      );
      if (img == null) return;
      final bytes = await img.readAsBytes();
      final pedido = pedidoDeUpload(
        img.name,
        bytes.length,
        mimeType: img.mimeType,
        bytes: bytes,
      );
      if (pedido == null) {
        throw const ErroDeEnvio('Envie uma foto JPG, PNG ou WebP de até 8 MB.');
      }
      if (!mounted) return;
      setState(() {
        _imagemSelecionada = img;
        _imagemBytes = bytes;
      });
    } catch (e) {
      _snack(
        mensagemDeErro(e) ??
            (source == ImageSource.camera
                ? 'Não foi possível abrir a câmera. Escolha uma foto da galeria.'
                : 'Não foi possível abrir a galeria. Tente novamente.'),
        erro: true,
      );
    }
  }

  Future<void> _mostrarOpcoesDeImagem() async {
    // ContentDialog em vez de showGlassActionSheet: a folha de vidro pinta o
    // texto com CupertinoColors.label, que segue o brilho do sistema (fica
    // branco sobre o cartão claro quando o SO está em modo escuro), enquanto o
    // diálogo Fluent segue o tema claro do app.
    final source = await showDialog<ImageSource>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ContentDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(WindowsIcons.camera, size: 20),
              title: const Text('Tirar uma foto'),
              onPressed: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(WindowsIcons.photo_collection, size: 20),
              title: const Text('Escolher da galeria'),
              onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _selecionarImagem(source);
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    _avisar(context, msg, erro: erro);
  }

  Future<void> _continuar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _enviando = true);

    String? exerciseId;
    try {
      final assunto = _assuntoCtrl.text.trim();
      final descricao = _erroCtrl.text.trim();

      // 1. Com imagem, o envio para a R2 vem primeiro: se falhar, nenhuma
      //    tentativa fica presa em 'uploading' no banco.
      final imagem = _imagemBytes != null && _imagemSelecionada != null
          ? await _enviarImagem(_imagemSelecionada!, _imagemBytes!)
          : null;

      // 2. Busca ou cria o assunto (subject) do usuário
      final subjectId = await _obterOuCriarSubject(assunto);

      // 3. Cria o exercício
      final exRes = await _db
          .from('exercises')
          .insert({'subject_id': subjectId, 'prompt_text': descricao})
          .select('id')
          .single();
      exerciseId = exRes['id'] as String;

      // 4. Cria a tentativa (attempt). Com imagem ela nasce em 'uploading',
      //    único estado em que a política de attempt_assets aceita anexos.
      final attRes = await _db
          .from('attempts')
          .insert({
            'exercise_id': exerciseId,
            'user_id': widget.user.id,
            'solution_text': descricao,
            'status': imagem != null ? 'uploading' : 'pending',
          })
          .select('id')
          .single();
      final attemptId = attRes['id'] as String;

      // 5. Registra o anexo e libera a tentativa para a análise de IA, que o
      //    pg_cron dispara via process-batch.
      if (imagem != null) {
        await _db.from('attempt_assets').insert({
          'attempt_id': attemptId,
          'object_path': imagem.objectPath,
          'sha256': imagem.sha256,
        });
        await _db
            .from('attempts')
            .update({'status': 'pending'})
            .eq('id', attemptId);
      }

      if (!mounted) return;
      _assuntoCtrl.clear();
      _erroCtrl.clear();
      setState(() {
        _imagemSelecionada = null;
        _imagemBytes = null;
        _ultimoAssunto = assunto;
        _sucesso = true;
      });
    } catch (e) {
      // Desfaz o registro parcial; a exclusão em cascata leva tentativa e
      // anexo junto com o exercício.
      if (exerciseId != null) {
        try {
          await _db.from('exercises').delete().eq('id', exerciseId);
        } catch (_) {
          // Melhor esforço: o erro original é o que interessa ao usuário.
        }
      }
      _snack(mensagemDeErro(e) ?? 'Erro ao registrar: $e', erro: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<String> _obterOuCriarSubject(String nome) async {
    // Tenta encontrar subject existente com esse nome
    final existing = await _db
        .from('subjects')
        .select('id')
        .eq('user_id', widget.user.id)
        .eq('name', nome)
        .maybeSingle();

    if (existing != null) return existing['id'] as String;

    // Cria novo subject
    final res = await _db
        .from('subjects')
        .insert({'user_id': widget.user.id, 'name': nome})
        .select('id')
        .single();
    return res['id'] as String;
  }

  // Envia a foto para a R2 por URL pré-assinada (válida por 15 min) obtida da
  // Edge Function upload-url. Retorna o caminho do objeto e o SHA-256 que a
  // tentativa precisa registrar em attempt_assets.
  Future<({String objectPath, String sha256})> _enviarImagem(
    XFile arquivo,
    Uint8List bytes,
  ) async {
    final pedido = pedidoDeUpload(
      arquivo.name,
      bytes.length,
      mimeType: arquivo.mimeType,
      bytes: bytes,
    );
    if (pedido == null) {
      throw const ErroDeEnvio('Envie uma foto JPG, PNG ou WebP de até 8 MB.');
    }

    // Mesmos limites do SupabaseAnalysisRepository: sem eles, uma rede que
    // trava deixa o botão girando para sempre.
    try {
      final fnRes = await _db.functions
          .invoke('upload-url', body: pedido)
          .timeout(const Duration(seconds: 120));
      final data = fnRes.data;
      if (data is! Map ||
          data['upload_url'] is! String ||
          data['object_path'] is! String) {
        throw const ErroDeEnvio(
          'O envio de fotos está temporariamente indisponível.',
        );
      }

      // Content-Type e Content-Length fazem parte da assinatura: o http envia
      // o tamanho exato dos bytes, igual ao size_bytes informado.
      final putRes = await http
          .put(
            Uri.parse(data['upload_url'] as String),
            headers: {'Content-Type': pedido['content_type'] as String},
            body: bytes,
          )
          .timeout(const Duration(seconds: 90));
      if (putRes.statusCode >= 400) {
        throw ErroDeEnvio(
          'Não foi possível enviar a foto (HTTP ${putRes.statusCode}). '
          'Tente novamente.',
        );
      }

      return (
        objectPath: data['object_path'] as String,
        sha256: sha256Hex(bytes),
      );
    } on TimeoutException {
      throw const ErroDeEnvio(
        'O envio demorou demais. Verifique a conexão e tente novamente.',
      );
    }
  }

  void _resetarParaForm() {
    setState(() => _sucesso = false);
  }

  // O contorno mantém a identidade; o preenchimento usa o hover compartilhado.
  ButtonStyle get _estiloContorno {
    return _estiloBotao(
      fundo: Cores.transparente,
      texto: contentBlue,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
    ).copyWith(
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusSm),
          side: const BorderSide(color: contentBlue),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _PaginaVidro(
      titulo: _sucesso ? 'Registrado!' : 'Adicionar exercício',
      corpo: _sucesso ? _buildSucesso() : _buildForm(),
    );
  }

  Widget _buildSucesso() {
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: _paddingCorpo(context),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: _PainelVidro(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Cores.verde.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            WindowsIcons.completed,
                            size: 72,
                            color: Cores.verde,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Exercício registrado!',
                        textAlign: TextAlign.center,
                        style: context.tipo.subtitle?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: titleBlue,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_ultimoAssunto.isNotEmpty)
                        Text(
                          'Assunto: $_ultimoAssunto',
                          textAlign: TextAlign.center,
                          style: context.tipo.body?.copyWith(
                            color: contentBlue,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Continue registrando para mapear seus padrões de erro.',
                        textAlign: TextAlign.center,
                        style: context.tipo.body?.copyWith(color: contentBlue),
                      ),
                      const SizedBox(height: 32),
                      MistakeMapFilledButton(
                        style: _estiloBotao(
                          fundo: kAcento,
                          texto: MistakeMapDesign.abyss,
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 20,
                          ),
                        ),
                        onPressed: _resetarParaForm,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(WindowsIcons.add, size: 18),
                            SizedBox(width: 8),
                            Text('Registrar outro'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      MistakeMapButton(
                        style: _estiloContorno,
                        onPressed: () {
                          _resetarParaForm();
                          widget.onIrParaMapa?.call();
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(WindowsIcons.relationship, size: 18),
                            SizedBox(width: 8),
                            Text('Ver no Mapa'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: _paddingCorpo(context),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Registre um erro para acompanhar sua evolução.',
                  textAlign: TextAlign.center,
                  style: context.tipo.bodyLarge?.copyWith(color: contentBlue),
                ),
                const SizedBox(height: 24),
                _CartaoFluent(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _AdicionarCampoTexto(
                        rotulo: 'Assunto',
                        dica: 'Ex.: Equações de segundo grau',
                        controller: _assuntoCtrl,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Informe o assunto'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      _AdicionarCampoTexto(
                        rotulo: 'O que você errou?',
                        dica: 'Descreva brevemente sua dificuldade',
                        controller: _erroCtrl,
                        minLines: 4,
                        maxLines: 6,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Descreva o erro'
                            : null,
                      ),
                      const SizedBox(height: 24),
                      if (_imagemBytes == null)
                        MistakeMapButton(
                          style: _estiloContorno,
                          onPressed: _mostrarOpcoesDeImagem,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(WindowsIcons.attach_camera, size: 18),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Adicionar foto do exercício',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(kRadiusSm),
                              child: Image.memory(
                                _imagemBytes!,
                                height: 220,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: MistakeMapHyperlinkButton(
                                onPressed: () => setState(() {
                                  _imagemSelecionada = null;
                                  _imagemBytes = null;
                                }),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(WindowsIcons.delete, size: 16),
                                    SizedBox(width: 8),
                                    Text('Remover imagem'),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                MistakeMapFilledButton(
                  style: _estiloBotao(
                    fundo: kAcento,
                    texto: MistakeMapDesign.abyss,
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 20,
                    ),
                  ),
                  onPressed: _enviando ? null : _continuar,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_enviando)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: ProgressRing(
                            strokeWidth: 2.5,
                            activeColor: MistakeMapDesign.abyss,
                          ),
                        )
                      else
                        const Icon(WindowsIcons.check_mark, size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _enviando ? 'Enviando…' : 'Registrar exercício',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Campo rotulado com fundo branco, compartilhado pelas telas de adicionar e
// editar exercício.
class _AdicionarCampoTexto extends StatelessWidget {
  const _AdicionarCampoTexto({
    required this.rotulo,
    required this.dica,
    required this.controller,
    required this.validator,
    this.minLines,
    this.maxLines = 1,
  });

  final String rotulo;
  final String dica;
  final TextEditingController controller;
  final FormFieldValidator<String> validator;
  final int? minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return InfoLabel(
      label: rotulo,
      labelStyle: context.tipo.bodyStrong?.copyWith(color: contentBlue),
      child: TextFormBox(
        controller: controller,
        placeholder: dica,
        minLines: minLines,
        maxLines: maxLines,
        validator: validator,
        // Revalida a cada digitação: o aviso some assim que o campo é
        // preenchido, sem esperar outro toque em Salvar.
        autovalidateMode: AutovalidateMode.onUserInteraction,
        decoration: const WidgetStatePropertyAll(
          BoxDecoration(color: MistakeMapDesign.white),
        ),
      ),
    );
  }
}

// ─── fim: Tela de adicionar exercício ────────────────────────────────────────

// ─── Mapa conceitual ──────────────────────────────────────────────────────────
class _SubjectData {
  final String nome;
  int total = 0;
  int concluidos = 0;
  int pendentes = 0;
  int semTentativa = 0;
  int erros = 0;

  _SubjectData(this.nome);

  void add(String status) {
    total++;
    switch (attemptStatusGroup(status)) {
      case AttemptStatusGroup.completed:
        concluidos++;
      // O mapa não tem faixa própria para revisão: como no _StatusBadge, que
      // pinta Pendente e Revisar de laranja, ela entra como pendente.
      case AttemptStatusGroup.pending || AttemptStatusGroup.review:
        pendentes++;
      case AttemptStatusGroup.failed:
        erros++;
      case AttemptStatusGroup.none:
        semTentativa++;
    }
  }

  double get taxaConclusao => total == 0 ? 0.0 : concluidos / total;
  int get atencao => pendentes + semTentativa + erros;
}

class TelaMapaConceitual extends StatefulWidget {
  final AppUser user;
  const TelaMapaConceitual({super.key, required this.user});

  @override
  State<TelaMapaConceitual> createState() => _TelaMapaConceitualState();
}

class _TelaMapaConceitualState extends State<TelaMapaConceitual> {
  List<_SubjectData> _stats = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    carregar();
  }

  Future<void> carregar() async {
    if (mounted) setState(() => _carregando = true);
    try {
      final dados = await _carregarMateriasEExercicios(
        widget.user.id,
        'mapa_exercicios',
        'id, subject_id, attempts(id, status, user_id, attempted_at)',
      );
      final subjectMap = <String, String>{
        for (final s in dados.materias) s['id'] as String: s['name'] as String,
      };

      final dataMap = <String, _SubjectData>{};
      for (final e in dados.exercicios) {
        final sid = e['subject_id'] as String;
        final nome = subjectMap[sid] ?? '?';
        if (!dataMap.containsKey(sid)) dataMap[sid] = _SubjectData(nome);
        final latest = tentativaMaisRecente(e['attempts'], widget.user.id);
        final status = latest?['status'] as String? ?? 'sem_tentativa';
        dataMap[sid]!.add(status);
      }

      final lista = dataMap.values.toList()
        ..sort((a, b) => b.total.compareTo(a.total));

      if (mounted) {
        setState(() {
          _stats = lista;
          _carregando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  int get _totalExercicios => _stats.fold(0, (s, d) => s + d.total);
  int get _totalConcluidos => _stats.fold(0, (s, d) => s + d.concluidos);
  int get _totalAtencao => _stats.fold(0, (s, d) => s + d.atencao);
  int get _maxTotal => _stats.isEmpty
      ? 1
      : _stats.map((s) => s.total).reduce((a, b) => a > b ? a : b);

  @override
  Widget build(BuildContext context) {
    return _PaginaVidro(
      titulo: 'Mapa Conceitual',
      acoes: [
        _BotaoBarra(
          icone: WindowsIcons.refresh,
          dica: 'Atualizar',
          onPressed: carregar,
        ),
      ],
      corpo: _carregando && _stats.isEmpty
          ? _estadoFixo(const ProgressRing())
          : _stats.isEmpty
          ? _estadoFixo(_buildVazio())
          : _ListaAtualizavel(
              onRefresh: carregar,
              children: [
                if (kModoDemo) ...[
                  const _BannerDemo(),
                  const SizedBox(height: 16),
                ],
                _buildResumo(),
                const SizedBox(height: 16),
                _buildGrafo(),
                const SizedBox(height: 16),
                _buildPorAssunto(),
                const SizedBox(height: 16),
                _buildFragilidades(),
              ],
            ),
    );
  }

  // Carregando e estado vazio não rolam: ficam entre as barras de vidro e
  // mantêm o aviso de demonstração sempre visível.
  Widget _estadoFixo(Widget conteudo) {
    return Padding(
      padding: _paddingCorpo(context),
      child: Column(
        children: [
          if (kModoDemo) const _BannerDemo(),
          Expanded(child: Center(child: conteudo)),
        ],
      ),
    );
  }

  Widget _buildVazio() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            WindowsIcons.relationship,
            size: 72,
            color: contentBlue.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 24),
          Text(
            'Nenhum dado ainda',
            textAlign: TextAlign.center,
            style: context.tipo.subtitle?.copyWith(
              fontWeight: FontWeight.bold,
              color: titleBlue,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Adicione exercícios para visualizar seu mapa conceitual.',
            textAlign: TextAlign.center,
            style: context.tipo.body?.copyWith(color: contentBlue),
          ),
        ],
      ),
    );
  }

  Widget _buildResumo() {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            valor: _totalExercicios.toString(),
            label: 'Exercícios',
            cor: contentBlue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            valor: _totalConcluidos.toString(),
            label: 'Concluídos',
            cor: Cores.verde600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            valor: _totalAtencao.toString(),
            label: 'Atenção',
            cor: Cores.laranja700,
          ),
        ),
      ],
    );
  }

  Widget _tituloSecao(String texto) {
    return Text(
      texto,
      style: context.tipo.bodyStrong?.copyWith(
        color: titleBlue,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildGrafo() {
    final maxT = _maxTotal.toDouble();
    return _CartaoFluent(
      acento: MistakeMapDesign.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSecao('Grafo por assunto'),
          const SizedBox(height: 4),
          Text(
            'Tamanho = quantidade · Cor = % concluído',
            style: context.tipo.caption?.copyWith(color: contentBlue),
          ),
          const SizedBox(height: 16),
          Center(
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: _stats.map((s) {
                final size =
                    (56.0 + (s.total / maxT) * 28.0) *
                    InfoTela.escalaDeTexto(context);
                final color = Color.lerp(
                  Cores.vermelho400,
                  Cores.verde,
                  s.taxaConclusao,
                )!;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.35),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(s.taxaConclusao * 100).round()}%',
                            style: context.tipo.body?.copyWith(
                              color: Cores.branco,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (size > 66)
                            Text(
                              '${s.total} ex.',
                              // Branco a 70%: o círculo é sempre um tom escuro.
                              style: context.tipo.caption?.copyWith(
                                color: const Color(0xB3FFFFFF),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: size + 10,
                      child: Text(
                        s.nome,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.tipo.caption?.copyWith(
                          color: contentBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const _MapaLegenda(cor: Cores.vermelho400, texto: '0%'),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Cores.vermelho400, Cores.laranja, Cores.verde],
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const _MapaLegenda(cor: Cores.verde, texto: '100%'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPorAssunto() {
    return _CartaoFluent(
      acento: MistakeMapDesign.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSecao('Evolução por assunto'),
          const SizedBox(height: 12),
          ..._stats.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SubjectBar(data: s),
            ),
          ),
          const SizedBox(height: 4),
          // Wrap evita estouro horizontal das quatro legendas em telas estreitas.
          const Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _MapaLegenda(cor: Cores.verde, texto: 'Concluído'),
              _MapaLegenda(cor: Cores.laranja400, texto: 'Pendente'),
              _MapaLegenda(cor: Cores.vermelho400, texto: 'Erro'),
              _MapaLegenda(cor: Cores.cinza300, texto: 'Sem tentativa'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFragilidades() {
    final fragilidades = [..._stats]
      ..sort((a, b) => a.taxaConclusao.compareTo(b.taxaConclusao));
    final top = fragilidades
        .where((s) => s.taxaConclusao < 1.0)
        .take(3)
        .toList();

    return _CartaoFluent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(WindowsIcons.warning, size: 16, color: Cores.laranja),
              const SizedBox(width: 8),
              Expanded(child: _tituloSecao('Principais fragilidades')),
            ],
          ),
          const SizedBox(height: 12),
          if (top.isEmpty)
            Row(
              children: [
                const Icon(
                  WindowsIcons.favorite_star_fill,
                  size: 20,
                  color: Cores.ambar,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    // "completed" só indica análise terminada, mesmo com a
                    // resposta errada; não é motivo de parabéns.
                    'Todos os exercícios foram analisados.',
                    style: context.tipo.body?.copyWith(color: contentBlue),
                  ),
                ),
              ],
            )
          else
            ...top.asMap().entries.map((entry) {
              final i = entry.key;
              final s = entry.value;
              const emojis = ['🔴', '🟠', '🟡'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Text(emojis[i], style: context.tipo.bodyLarge),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.nome,
                            style: context.tipo.bodyStrong?.copyWith(
                              color: titleBlue,
                            ),
                          ),
                          Text(
                            '${s.atencao} de ${s.total} precisam de atenção',
                            style: context.tipo.caption?.copyWith(
                              color: Cores.cinza600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(s.taxaConclusao * 100).round()}%',
                      style: context.tipo.body?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: s.taxaConclusao < 0.5
                            ? Cores.vermelho600
                            : Cores.laranja700,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// Resumo numérico em painel de vidro (camada de destaque do topo do mapa).
class _StatCard extends StatelessWidget {
  final String valor;
  final String label;
  final Color cor;
  const _StatCard({
    required this.valor,
    required this.label,
    required this.cor,
  });

  @override
  Widget build(BuildContext context) {
    return _PainelVidro(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      raio: kRadius,
      acento: cor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            valor,
            style: context.tipo.title?.copyWith(
              fontWeight: FontWeight.bold,
              color: cor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: context.tipo.caption?.copyWith(
              color: cor.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// Barra empilhada por status: as proporções vêm dos contadores (flex), por
// isso continua como Container proporcional e não como ProgressBar.
class _SubjectBar extends StatelessWidget {
  final _SubjectData data;
  const _SubjectBar({required this.data});

  @override
  Widget build(BuildContext context) {
    final total = data.total == 0 ? 1 : data.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                data.nome,
                style: context.tipo.body?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: contentBlue,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${data.concluidos}/${data.total}',
              style: context.tipo.caption?.copyWith(color: Cores.cinza600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 10,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (data.concluidos > 0)
                  Expanded(
                    flex: data.concluidos,
                    child: const ColoredBox(color: Cores.verde),
                  ),
                if (data.pendentes > 0)
                  Expanded(
                    flex: data.pendentes,
                    child: const ColoredBox(color: Cores.laranja400),
                  ),
                if (data.erros > 0)
                  Expanded(
                    flex: data.erros,
                    child: const ColoredBox(color: Cores.vermelho400),
                  ),
                if (data.semTentativa > 0)
                  Expanded(
                    flex: data.semTentativa,
                    child: const ColoredBox(color: Cores.cinza300),
                  ),
                if (total == 1 && data.total == 0)
                  const Expanded(child: ColoredBox(color: Cores.cinza200)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MapaLegenda extends StatelessWidget {
  final Color cor;
  final String texto;
  const _MapaLegenda({required this.cor, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(texto, style: context.tipo.caption?.copyWith(color: contentBlue)),
      ],
    );
  }
}

// ─── Modelo ───────────────────────────────────────────────────────────────────
/// Matérias e exercícios do usuário: Supabase primeiro, cache sem rede, com
/// a fila offline aplicada por cima. Lista e Mapa usam o mesmo formato.
Future<
  ({List<Map<String, dynamic>> materias, List<Map<String, dynamic>> exercicios})
>
_carregarMateriasEExercicios(
  String usuarioId,
  String chave,
  String colunas, {
  bool ordenarPorCriacao = false,
}) async {
  final sync = _sync(usuarioId);
  final fila = await sync.fila(usuarioId);
  final dados = await _consultarOuSoFila(
    sync,
    usuarioId,
    chave,
    fila,
    {'subjects': [], 'exercises': []},
    () async {
      final subjects = await _db
          .from('subjects')
          .select('id, name')
          .eq('user_id', usuarioId);
      if (subjects.isEmpty) return {'subjects': subjects, 'exercises': []};
      final consulta = _db.from('exercises').select(colunas).inFilter(
        'subject_id',
        [for (final s in subjects) s['id']],
      );
      final exercises = ordenarPorCriacao
          ? await consulta.order('created_at', ascending: false)
          : await consulta;
      return {'subjects': subjects, 'exercises': exercises};
    },
  );
  final mapa = dados as Map;
  return sobreporExercicios(
    mapa['subjects'] as List,
    mapa['exercises'] as List,
    fila,
    usuarioId,
  );
}

/// [Sincronizador.consultar], mas sem rede e sem cache (app atualizado já
/// offline) mostra só a fila sobre [vazio], para o aluno ver e poder excluir
/// o que salvou. Sem nada na fila o erro segue para a tela, como antes.
Future<Object?> _consultarOuSoFila(
  Sincronizador sync,
  String usuarioId,
  String chave,
  List<OperacaoFila> fila,
  Object vazio,
  Future<Object?> Function() remoto,
) async {
  try {
    return await sync.consultar(usuarioId, chave, remoto);
  } catch (erro) {
    if (fila.isEmpty || !ehFalhaDeRede(erro)) rethrow;
    return vazio;
  }
}

class Exercicio {
  final String id;
  final String subjectId;
  final String subjectName;
  final String promptText;
  final String status;
  final String? attemptId;
  final DateTime? createdAt;

  const Exercicio({
    required this.id,
    required this.subjectId,
    required this.subjectName,
    required this.promptText,
    required this.status,
    this.attemptId,
    this.createdAt,
  });

  // guard_analyzed_exercise recusa mudar enunciado e matéria depois da
  // primeira tentativa, então a edição só vale antes de qualquer envio.
  bool get podeEditar => attemptId == null;
}

/// Tentativa mais recente do usuário entre as embutidas em `exercises`.
/// Exercícios de prática acumulam várias tentativas e o PostgREST não garante
/// a ordem do recurso embutido, então a escolha é feita aqui por attempted_at.
Map<String, dynamic>? tentativaMaisRecente(Object? attempts, String userId) {
  Map<String, dynamic>? maisRecente;
  DateTime? dataMaisRecente;
  for (final tentativa in (attempts as List?) ?? const []) {
    if (tentativa is! Map<String, dynamic> || tentativa['user_id'] != userId) {
      continue;
    }
    final data = DateTime.tryParse('${tentativa['attempted_at'] ?? ''}');
    // Sem data só vence enquanto nenhuma tentativa datada apareceu.
    if (maisRecente == null ||
        (data != null &&
            (dataMaisRecente == null || data.isAfter(dataMaisRecente)))) {
      maisRecente = tentativa;
      dataMaisRecente = data;
    }
  }
  return maisRecente;
}

/// Exclui no Supabase ou, sem rede, guarda a exclusão na fila do aparelho.
Future<ResultadoEscrita> _excluirExercicio(Exercicio ex, AppUser user) =>
    _sync(user.id).excluirExercicio(
      usuarioId: user.id,
      exercicioId: ex.id,
      materiaId: ex.subjectId,
      tentativaId: ex.attemptId,
    );

String _msgExclusao(ResultadoEscrita resultado) =>
    resultado == ResultadoEscrita.naFila
    ? 'Exercício excluído no aparelho. O servidor será atualizado quando a '
          'conexão voltar.'
    : 'Exercício excluído.';

// ─── fim: Mapa conceitual ────────────────────────────────────────────────────

// ─── Lista de exercícios ──────────────────────────────────────────────────────
class TelaPrincipal extends StatefulWidget {
  final AppUser user;
  const TelaPrincipal({super.key, required this.user});

  @override
  State<TelaPrincipal> createState() => _TelaPrincipalState();
}

class _TelaPrincipalState extends State<TelaPrincipal> {
  List<Exercicio> _exercicios = [];
  Exercicio? _selecionado;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    carregarExercicios();
  }

  Future<void> carregarExercicios() async {
    if (mounted) setState(() => _carregando = true);
    try {
      final dados = await _carregarMateriasEExercicios(
        widget.user.id,
        'lista_exercicios',
        'id, prompt_text, created_at, subject_id, '
            'attempts(id, status, user_id, attempted_at)',
        ordenarPorCriacao: true,
      );
      final subjectMap = <String, String>{
        for (final s in dados.materias) s['id'] as String: s['name'] as String,
      };

      final lista = <Exercicio>[];
      for (final e in dados.exercicios) {
        final latest = tentativaMaisRecente(e['attempts'], widget.user.id);
        lista.add(
          Exercicio(
            id: e['id'] as String,
            subjectId: e['subject_id'] as String,
            subjectName: subjectMap[e['subject_id']] ?? '—',
            promptText: e['prompt_text'] as String? ?? '',
            status: latest?['status'] as String? ?? 'sem_tentativa',
            attemptId: latest?['id'] as String?,
            createdAt: e['created_at'] != null
                ? DateTime.tryParse(e['created_at'] as String)
                : null,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _exercicios = lista;
          if (_selecionado != null) {
            _selecionado = lista
                .where((e) => e.id == _selecionado!.id)
                .firstOrNull;
          }
          _carregando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _confirmarExclusao(Exercicio ex) async {
    final ok = await _confirmar(
      context,
      titulo: 'Excluir exercício',
      mensagem:
          'Excluir o exercício de "${ex.subjectName}"?\n'
          'Esta ação não pode ser desfeita.',
      confirmar: 'Excluir',
      cancelar: 'Cancelar',
      destrutivo: true,
    );
    if (!ok || !mounted) return;
    await _excluir(ex);
  }

  Future<void> _excluir(Exercicio ex) async {
    try {
      final resultado = await _excluirExercicio(ex, widget.user);
      if (!mounted) return;
      _avisar(context, _msgExclusao(resultado));
      carregarExercicios();
    } catch (e) {
      if (!mounted) return;
      _avisar(context, 'Erro ao excluir: $e', erro: true);
    }
  }

  Future<void> _abrirDetalhe(Exercicio ex) async {
    if (DoisPaineis.cabe(context)) {
      setState(() => _selecionado = ex);
      return;
    }
    await Navigator.push(
      context,
      MistakeMapPageRoute(
        context: context,
        builder: (_) => TelaDetalheExercicio(
          exercicio: ex,
          user: widget.user,
          onAtualizar: carregarExercicios,
        ),
      ),
    );
    carregarExercicios();
  }

  Future<void> _abrirEdicao(Exercicio ex) async {
    await Navigator.push(
      context,
      MistakeMapPageRoute(
        context: context,
        builder: (_) => TelaEditarExercicio(exercicio: ex, user: widget.user),
      ),
    );
    carregarExercicios();
  }

  @override
  Widget build(BuildContext context) {
    final lista = _PaginaVidro(
      titulo: 'Meus Exercícios',
      acoes: [
        _BotaoBarra(
          icone: WindowsIcons.refresh,
          dica: 'Atualizar',
          onPressed: carregarExercicios,
        ),
      ],
      corpo: _corpo(context),
    );
    return DoisPaineis(
      inicio: lista,
      fim: _selecionado == null
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Selecione um exercício para ver os detalhes.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : TelaDetalheExercicio(
              exercicio: _selecionado!,
              user: widget.user,
              onAtualizar: carregarExercicios,
              onFechar: () => setState(() => _selecionado = null),
            ),
    );
  }

  Widget _corpo(BuildContext context) {
    if (_carregando && _exercicios.isEmpty) {
      return Padding(
        padding: _paddingCorpo(context),
        child: const Center(child: ProgressRing()),
      );
    }
    if (_exercicios.isEmpty) return const _MapaVazio();
    return _ListaAtualizavel(
      onRefresh: carregarExercicios,
      children: [
        for (final ex in _exercicios)
          _ExercicioCard(
            exercicio: ex,
            onTap: () => _abrirDetalhe(ex),
            onEditar: () => _abrirEdicao(ex),
            onExcluir: () => _confirmarExclusao(ex),
          ),
      ],
    );
  }
}

class _MapaVazio extends StatelessWidget {
  const _MapaVazio();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _paddingCorpo(context, horizontal: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GlassIconTile(
              icon: WindowsIcons.bulleted_list,
              ink: MistakeMapDesign.azureInk,
              accent: MistakeMapDesign.azure,
              size: 72,
            ),
            const SizedBox(height: 24),
            Text(
              'Seu mapa ainda está vazio',
              textAlign: TextAlign.center,
              style: context.tipo.subtitle?.copyWith(
                fontWeight: FontWeight.bold,
                color: titleBlue,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Adicione exercícios para identificar suas fragilidades conceituais.',
              textAlign: TextAlign.center,
              style: context.tipo.body?.copyWith(color: contentBlue),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExercicioCard extends StatelessWidget {
  final Exercicio exercicio;
  final VoidCallback onTap;
  final VoidCallback onEditar;
  final VoidCallback onExcluir;

  const _ExercicioCard({
    required this.exercicio,
    required this.onTap,
    required this.onEditar,
    required this.onExcluir,
  });

  String _fmtData(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';

  @override
  Widget build(BuildContext context) {
    final estado = _EstadoTentativa.de(exercicio.status);
    final inicial = exercicio.subjectName.trim().isEmpty
        ? '?'
        : exercicio.subjectName.trim()[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      // Mesma anatomia dos passos do Início: bloco da matéria, rótulo pequeno
      // com matéria e data, enunciado como título e o estado em cor com
      // função. O fundo leva um tom do estado, para a lista se ler em um
      // relance; o cartão inteiro é o botão e afunda ao toque.
      child: _CartaoFluent(
        onPressed: onTap,
        cor: Color.alphaBlend(
          estado.acento.withValues(alpha: estado.pedeAcao ? .12 : .05),
          kGlassBg,
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Builder(
          builder: (context) => DefaultTextStyle.merge(
            textAlign: TextAlign.start,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InicialMateria(inicial: inicial),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercicio.createdAt == null
                            ? exercicio.subjectName.toUpperCase()
                            : '${exercicio.subjectName.toUpperCase()} · '
                                  '${_fmtData(exercicio.createdAt!)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.tipo.caption?.copyWith(
                          color: MistakeMapDesign.azureInk,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        exercicio.promptText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.tipo.bodyStrong?.copyWith(
                          color: MistakeMapDesign.abyss,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _StatusBadge(status: exercicio.status),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _menu(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menu() {
    return DropDownButton(
      placement: FlyoutPlacementMode.bottomRight,
      menuShape: MistakeMapControls.menuShape,
      menuColor: MistakeMapDesign.surface,
      // Mesmo controle quadrado de 40 px das barras superiores.
      buttonBuilder: (context, abrir) => _BotaoBarra(
        icone: WindowsIcons.more,
        dica: 'Opções',
        cor: contentBlue,
        onPressed: abrir,
      ),
      items: [
        _itemMenu(
          icone: WindowsIcons.view,
          texto: 'Ver detalhes',
          onPressed: onTap,
        ),
        // Depois do envio o banco recusa a edição (guard_analyzed_exercise).
        if (exercicio.podeEditar)
          _itemMenu(
            icone: WindowsIcons.edit,
            texto: 'Editar',
            onPressed: onEditar,
          ),
        _itemMenu(
          icone: WindowsIcons.delete,
          texto: 'Excluir',
          cor: Cores.vermelho700,
          onPressed: onExcluir,
        ),
      ],
    );
  }
}

/// Bloco com a inicial da matéria, no acento azure da Lista.
class _InicialMateria extends StatelessWidget {
  const _InicialMateria({required this.inicial});

  final String inicial;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: MistakeMapDesign.iconTile(
          MistakeMapDesign.azureInk,
          MistakeMapDesign.azure,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x40FFFFFF)),
        boxShadow: [
          BoxShadow(
            color: MistakeMapDesign.azureInk.withValues(alpha: .35),
            blurRadius: 14,
            spreadRadius: -6,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Text(
        inicial,
        style: const TextStyle(
          color: MistakeMapDesign.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

/// Cor com função para cada status: menta é resolvido, âmbar pede ação do
/// estudante, violeta é a IA trabalhando, azure é transporte e coral é erro.
class _EstadoTentativa {
  const _EstadoTentativa(
    this.label,
    this.acento,
    this.tinta,
    this.icone, {
    this.pedeAcao = false,
  });

  final String label;
  final Color acento;
  final Color tinta;
  final IconData icone;

  /// O estudante precisa fazer algo: o cartão ganha um tom mais forte.
  final bool pedeAcao;

  static _EstadoTentativa de(String status) => switch (status) {
    'completed' => const _EstadoTentativa(
      'Concluído',
      MistakeMapDesign.mint,
      MistakeMapDesign.mintInk,
      WindowsIcons.completed,
    ),
    'pending' => const _EstadoTentativa(
      'Pendente',
      MistakeMapDesign.amber,
      MistakeMapDesign.amberInk,
      WindowsIcons.history,
      pedeAcao: true,
    ),
    'uploading' => const _EstadoTentativa(
      'Enviando',
      MistakeMapDesign.azure,
      MistakeMapDesign.azureInk,
      WindowsIcons.upload,
    ),
    // Estados do pipeline de IA (attempts_status_check).
    'queued' || 'processing' => const _EstadoTentativa(
      'Analisando',
      MistakeMapDesign.violet,
      MistakeMapDesign.violetInk,
      WindowsIcons.lightbulb,
    ),
    'awaiting_review' => const _EstadoTentativa(
      'Revisar',
      MistakeMapDesign.amber,
      MistakeMapDesign.amberInk,
      WindowsIcons.view,
      pedeAcao: true,
    ),
    'retryable_failed' => const _EstadoTentativa(
      'Nova tentativa',
      MistakeMapDesign.amber,
      MistakeMapDesign.amberInk,
      WindowsIcons.refresh,
      pedeAcao: true,
    ),
    'dead_letter' || 'error' => const _EstadoTentativa(
      'Erro',
      MistakeMapDesign.coral,
      MistakeMapDesign.coralInk,
      WindowsIcons.error_badge,
      pedeAcao: true,
    ),
    'cancelled' => const _EstadoTentativa(
      'Cancelado',
      MistakeMapDesign.mist,
      MistakeMapDesign.steel,
      WindowsIcons.cancel,
    ),
    // Só no aparelho (fila offline), ainda sem resposta do servidor.
    statusOffline => const _EstadoTentativa(
      'Aguardando conexão',
      MistakeMapDesign.azure,
      MistakeMapDesign.azureInk,
      WindowsIcons.cloud_not_synced,
    ),
    statusRecusado => const _EstadoTentativa(
      'Não enviado',
      MistakeMapDesign.coral,
      MistakeMapDesign.coralInk,
      WindowsIcons.error_badge,
      pedeAcao: true,
    ),
    _ => const _EstadoTentativa(
      'Sem tentativa',
      MistakeMapDesign.mist,
      MistakeMapDesign.steel,
      WindowsIcons.unknown,
    ),
  };
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final estado = _EstadoTentativa.de(status);
    return _Pilula(texto: estado.label, cor: estado.tinta, icone: estado.icone);
  }
}

// ─── fim: Lista de exercícios ────────────────────────────────────────────────

// ─── Detalhe do exercício ─────────────────────────────────────────────────────
class TelaDetalheExercicio extends StatelessWidget {
  final Exercicio exercicio;
  final AppUser user;
  final VoidCallback onAtualizar;
  final VoidCallback? onFechar;

  const TelaDetalheExercicio({
    super.key,
    required this.exercicio,
    required this.user,
    required this.onAtualizar,
    this.onFechar,
  });

  String _fmtData(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';

  Future<void> _excluir(BuildContext context) async {
    final ok = await _confirmar(
      context,
      titulo: 'Excluir exercício',
      mensagem:
          'Excluir o exercício de "${exercicio.subjectName}"?\n'
          'Esta ação não pode ser desfeita.',
      confirmar: 'Excluir',
      cancelar: 'Cancelar',
      destrutivo: true,
    );
    if (!ok || !context.mounted) return;
    try {
      final resultado = await _excluirExercicio(exercicio, user);
      if (!context.mounted) return;
      onAtualizar();
      if (onFechar != null) {
        onFechar!();
      } else {
        Navigator.pop(context);
      }
      // O toast vai para o Overlay do Navigator, então continua visível na
      // tela anterior depois do pop.
      _avisar(context, _msgExclusao(resultado));
    } catch (e) {
      if (!context.mounted) return;
      _avisar(context, 'Erro ao excluir: $e', erro: true);
    }
  }

  Future<void> _editar(BuildContext context) async {
    await Navigator.push(
      context,
      MistakeMapPageRoute(
        context: context,
        builder: (_) => TelaEditarExercicio(exercicio: exercicio, user: user),
      ),
    );
    onAtualizar();
    if (context.mounted && onFechar == null) Navigator.pop(context);
  }

  // A correção da IA mora no fluxo Material; sem este atalho o status
  // "Revisar" da lista não levava a lugar nenhum.
  Future<void> _verCorrecao(BuildContext context) async {
    await Navigator.of(context).push(
      MistakeMapPageRoute(
        context: context,
        builder: (rotaContext) => AiMaterialShell(
          userId: user.id,
          repository: SupabaseAnalysisRepository(_db),
          showMap: false,
          attemptId: exercicio.attemptId,
          onClose: () => Navigator.of(rotaContext).pop(),
        ),
      ),
    );
    onAtualizar();
  }

  @override
  Widget build(BuildContext context) {
    return _PaginaVidro(
      titulo: exercicio.subjectName,
      voltar: onFechar == null,
      acoes: [
        if (onFechar != null)
          _BotaoBarra(
            icone: WindowsIcons.cancel,
            dica: 'Fechar detalhes',
            onPressed: onFechar!,
          ),
        // Depois do envio o banco recusa a edição (guard_analyzed_exercise).
        if (exercicio.podeEditar)
          _BotaoBarra(
            icone: WindowsIcons.edit,
            dica: 'Editar',
            onPressed: () => _editar(context),
          ),
        _BotaoBarra(
          icone: WindowsIcons.delete,
          dica: 'Excluir',
          cor: Cores.vermelho400,
          onPressed: () => _excluir(context),
        ),
      ],
      corpo: SingleChildScrollView(
        padding: _paddingCorpo(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Status:',
                  style: context.tipo.bodyStrong?.copyWith(color: contentBlue),
                ),
                const SizedBox(width: 8),
                _StatusBadge(status: exercicio.status),
              ],
            ),
            if (exercicio.createdAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Adicionado em ${_fmtData(exercicio.createdAt!)}',
                style: context.tipo.caption?.copyWith(color: Cores.cinza),
              ),
            ],
            const SizedBox(height: 24),
            _rotulo(context, 'ASSUNTO'),
            const SizedBox(height: 8),
            _DetalheBox(
              child: Text(
                exercicio.subjectName,
                style: context.tipo.bodyStrong?.copyWith(color: titleBlue),
              ),
            ),
            const SizedBox(height: 16),
            _rotulo(context, 'DESCRIÇÃO DO ERRO'),
            const SizedBox(height: 8),
            _DetalheBox(
              child: Text(
                exercicio.promptText,
                style: context.tipo.body?.copyWith(
                  color: contentBlue,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 32),
            if (exercicio.attemptId != null &&
                exercicio.status != statusOffline &&
                exercicio.status != statusRecusado) ...[
              SizedBox(
                width: double.infinity,
                child: MistakeMapFilledButton(
                  style: _estiloBotao(
                    fundo: kAcento,
                    texto: MistakeMapDesign.abyss,
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 24,
                    ),
                  ),
                  onPressed: () => _verCorrecao(context),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(WindowsIcons.lightbulb, size: 18),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Ver correção da IA',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (exercicio.podeEditar) ...[
              SizedBox(
                width: double.infinity,
                child: MistakeMapFilledButton(
                  style: _estiloBotao(
                    fundo: kAcento,
                    texto: MistakeMapDesign.abyss,
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 24,
                    ),
                  ),
                  onPressed: () => _editar(context),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(WindowsIcons.edit, size: 18),
                      SizedBox(width: 8),
                      Text('Editar exercício'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: MistakeMapButton(
                style:
                    _estiloBotao(
                      fundo: Cores.transparente,
                      texto: Cores.vermelho400,
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 24,
                      ),
                    ).copyWith(
                      shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kRadiusSm),
                          side: const BorderSide(color: Cores.vermelho300),
                        ),
                      ),
                    ),
                onPressed: () => _excluir(context),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(WindowsIcons.delete, size: 18),
                    SizedBox(width: 8),
                    Text('Excluir exercício'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Rótulo de seção em caixa alta (ASSUNTO, DESCRIÇÃO DO ERRO).
  Widget _rotulo(BuildContext context, String texto) {
    return Text(
      texto,
      style: context.tipo.caption?.copyWith(
        color: contentBlue,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    );
  }
}

// Card Fluent sem sombra: a borda contentBlue a 25 % não é configurável no
// _CartaoFluent.
class _DetalheBox extends StatelessWidget {
  final Widget child;
  const _DetalheBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Card(
        padding: const EdgeInsets.all(16),
        backgroundColor: MistakeMapDesign.well,
        borderColor: MistakeMapDesign.hairline,
        borderRadius: BorderRadius.circular(kRadiusSm),
        child: child,
      ),
    );
  }
}

// ─── fim: Detalhe do exercício ───────────────────────────────────────────────

// ─── Editar exercício ──────────────────────────────────────────────────────────
class TelaEditarExercicio extends StatefulWidget {
  final Exercicio exercicio;
  final AppUser user;

  const TelaEditarExercicio({
    super.key,
    required this.exercicio,
    required this.user,
  });

  @override
  State<TelaEditarExercicio> createState() => _TelaEditarExercicioState();
}

class _TelaEditarExercicioState extends State<TelaEditarExercicio> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _assuntoCtrl;
  late final TextEditingController _erroCtrl;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _assuntoCtrl = TextEditingController(text: widget.exercicio.subjectName);
    _erroCtrl = TextEditingController(text: widget.exercicio.promptText);
  }

  @override
  void dispose() {
    _assuntoCtrl.dispose();
    _erroCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    _avisar(context, msg, erro: erro);
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    // O banco recusaria (guard_analyzed_exercise); nem tenta, para não criar
    // matéria à toa.
    if (!widget.exercicio.podeEditar) {
      _snack(_msgExercicioJaEnviado, erro: true);
      return;
    }
    setState(() => _salvando = true);
    try {
      // RemotoSupabase.editarExercicio faz o envio (enunciado antes da
      // matéria, desfazendo matéria órfã); sem rede a edição vai para a fila.
      final resultado = await _sync(widget.user.id).editarExercicio(
        usuarioId: widget.user.id,
        exercicioId: widget.exercicio.id,
        materiaIdAtual: widget.exercicio.subjectId,
        materiaAtual: widget.exercicio.subjectName,
        novaMateria: _assuntoCtrl.text.trim(),
        novoEnunciado: _erroCtrl.text.trim(),
      );

      if (!mounted) return;
      _snack(
        resultado == ResultadoEscrita.naFila
            ? 'Alteração salva no aparelho. Ela sobe quando a conexão voltar.'
            : 'Exercício atualizado!',
      );
      Navigator.pop(context);
    } catch (e) {
      _snack(mensagemDeErro(e) ?? 'Erro ao salvar: $e', erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PaginaVidro(
      titulo: 'Editar exercício',
      voltar: true,
      corpo: SingleChildScrollView(
        padding: _paddingCorpo(context),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Atualize as informações do exercício.',
                    textAlign: TextAlign.center,
                    style: context.tipo.body?.copyWith(color: contentBlue),
                  ),
                  const SizedBox(height: 24),
                  _CartaoFluent(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AdicionarCampoTexto(
                          rotulo: 'Assunto',
                          dica: 'Ex.: Equações de segundo grau',
                          controller: _assuntoCtrl,
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Informe o assunto'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        _AdicionarCampoTexto(
                          rotulo: 'O que você errou?',
                          dica: 'Descreva brevemente sua dificuldade',
                          controller: _erroCtrl,
                          minLines: 4,
                          maxLines: 8,
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Descreva o erro'
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  MistakeMapFilledButton(
                    style: _estiloBotao(
                      fundo: kAcento,
                      texto: MistakeMapDesign.abyss,
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 20,
                      ),
                    ),
                    onPressed: _salvando ? null : _salvar,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_salvando)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: ProgressRing(
                              strokeWidth: 2.5,
                              activeColor: MistakeMapDesign.abyss,
                            ),
                          )
                        else
                          const Icon(WindowsIcons.check_mark, size: 18),
                        const SizedBox(width: 8),
                        Text(_salvando ? 'Salvando…' : 'Salvar alterações'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── fim: Editar exercício ───────────────────────────────────────────────────

// ─── Painel administrativo ────────────────────────────────────────────────────
class TelaAdmin extends StatefulWidget {
  final AppUser user;
  final bool active;
  const TelaAdmin({super.key, required this.user, this.active = true});

  @override
  State<TelaAdmin> createState() => _TelaAdminState();
}

class _TelaAdminState extends State<TelaAdmin> {
  int _secao = 0;
  List<Map<String, dynamic>> _perfis = [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final res = await _db
          .from('profiles')
          .select('id, role, created_at, institution_name, course')
          .order('created_at');
      if (mounted) {
        setState(() {
          _perfis = (res as List)
              .map((p) => Map<String, dynamic>.from(p))
              .toList();
          _carregando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = ehFalhaDeRede(e)
              ? 'A lista de usuários precisa de internet. Conecte-se e toque '
                    'em atualizar.'
              : 'Não foi possível carregar os usuários. Tente novamente.';
          _carregando = false;
        });
      }
    }
  }

  Future<void> _alterarRole(String userId, String novaRole) async {
    try {
      await _db.from('profiles').update({'role': novaRole}).eq('id', userId);
      await _carregar();
    } catch (e) {
      if (mounted) {
        _avisar(context, 'Erro ao alterar papel: $e', erro: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PaginaVidro(
      titulo: 'Painel Administrativo',
      acoes: [
        _BotaoBarra(
          icone: WindowsIcons.refresh,
          dica: 'Atualizar',
          onPressed: _carregar,
        ),
      ],
      corpo: Padding(
        padding: _paddingCorpo(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < 2; i++)
                  Semantics(
                    selected: _secao == i,
                    child: MistakeMapButton(
                      key: ValueKey('admin-section-$i'),
                      style: _estiloBotao(
                        fundo: _secao == i ? kAcento : null,
                        texto: _secao == i
                            ? MistakeMapDesign.abyss
                            : contentBlue,
                      ),
                      onPressed: () => setState(() => _secao = i),
                      child: Text(i == 0 ? 'Funcionamento' : 'Usuários'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: IndexedStack(
                index: _secao,
                children: [
                  ListView(
                    children: [
                      AdminMetricsPanel(
                        client: _db,
                        active: widget.active && _secao == 0,
                      ),
                    ],
                  ),
                  ListView.builder(
                    itemCount: (_carregando || _erro != null)
                        ? 1
                        : _perfis.length + 1,
                    itemBuilder: (ctx, i) {
                      if (_carregando) {
                        return const Center(child: ProgressRing());
                      }
                      if (_erro != null) {
                        return Text(
                          _erro!,
                          style: context.tipo.body?.copyWith(
                            color: Cores.vermelho,
                          ),
                        );
                      }
                      return i == 0
                          ? _cabecalho(ctx)
                          : _itemPerfil(ctx, _perfis[i - 1]);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Resumo com o total de perfis cadastrados
  Widget _cabecalho(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _PainelVidro(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        raio: kRadiusSm,
        child: Row(
          children: [
            const Icon(WindowsIcons.people, size: 20, color: contentBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_perfis.length} usuário(s) cadastrado(s)',
                style: context.tipo.bodyStrong?.copyWith(color: contentBlue),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemPerfil(BuildContext context, Map<String, dynamic> p) {
    final uid = p['id'] as String;
    final role = p['role'] as String;
    final institution = p['institution_name'] as String?;
    final course = p['course'] as String?;
    final isCurrentUser = uid == widget.user.id;
    final isAdmin = role == 'admin';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _CartaoFluent(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isAdmin ? MistakeMapDesign.violet : Cores.cinza300,
              ),
              child: Icon(
                isAdmin ? WindowsIcons.admin : WindowsIcons.contact,
                color: isAdmin
                    ? MistakeMapDesign.abyss
                    : MistakeMapDesign.strong,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // Mostra ID encurtado (email fica em auth.users, inacessível pelo client)
                    'ID: ${uid.substring(0, 8)}…${uid.substring(uid.length - 4)}',
                    style: context.tipo.body?.copyWith(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _RoleBadge(role: role),
                      if (isCurrentUser) ...[
                        const SizedBox(width: 8),
                        Text(
                          '(você)',
                          style: context.tipo.caption?.copyWith(
                            color: Cores.cinza,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (institution != null || course != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      [institution, course].whereType<String>().join(' · '),
                      style: context.tipo.caption?.copyWith(color: Cores.cinza),
                    ),
                  ],
                ],
              ),
            ),
            if (!isCurrentUser) ...[
              const SizedBox(width: 8),
              _menuPapel(uid, isAdmin),
            ],
          ],
        ),
      ),
    );
  }

  // Menu de troca de papel: cada opção só fica habilitada quando muda o papel.
  Widget _menuPapel(String uid, bool isAdmin) {
    return DropDownButton(
      placement: FlyoutPlacementMode.bottomRight,
      menuShape: MistakeMapControls.menuShape,
      menuColor: MistakeMapDesign.surface,
      buttonBuilder: (context, onOpen) => _BotaoBarra(
        icone: WindowsIcons.more,
        dica: 'Gerenciar papel',
        cor: contentBlue,
        onPressed: onOpen,
      ),
      items: [
        _itemMenu(
          icone: WindowsIcons.admin,
          texto: 'Tornar administrador',
          onPressed: isAdmin ? null : () => _alterarRole(uid, 'admin'),
        ),
        _itemMenu(
          icone: WindowsIcons.contact,
          texto: 'Revogar administrador',
          onPressed: isAdmin ? () => _alterarRole(uid, 'user') : null,
        ),
      ],
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == 'admin';
    return _Pilula(
      texto: isAdmin ? 'Administrador' : 'Usuário',
      cor: isAdmin ? contentBlue : Cores.cinza700,
    );
  }
}

// ─── fim: Painel administrativo ──────────────────────────────────────────────

// ─── Sobre o App ──────────────────────────────────────────────────────────────
class TelaSobre extends StatelessWidget {
  const TelaSobre({super.key});

  @override
  Widget build(BuildContext context) {
    return _PaginaVidro(
      titulo: 'Sobre o MistakeMap',
      voltar: true,
      corpo: SingleChildScrollView(
        padding: _paddingCorpo(context),
        child: Center(
          child: ConstrainedBox(
            // Limita a largura de leitura em telas largas (Windows/Web).
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _heroi(context),
                const SizedBox(height: 32),
                // Missão, Visão, Valores
                const _SobreSecaoTitulo(titulo: 'Nossa Identidade'),
                const SizedBox(height: 12),
                const _MvvCard(
                  icone: WindowsIcons.flag,
                  cor: MistakeMapDesign.aquaInk,
                  acento: MistakeMapDesign.aqua,
                  titulo: 'Missão',
                  descricao:
                      'Ajudar estudantes a identificar e superar suas lacunas conceituais, '
                      'transformando exercícios corrigidos em um mapa visual de fragilidades '
                      'para orientar revisões inteligentes.',
                ),
                const SizedBox(height: 12),
                const _MvvCard(
                  icone: WindowsIcons.view,
                  cor: MistakeMapDesign.violetInk,
                  acento: MistakeMapDesign.violet,
                  titulo: 'Visão',
                  descricao:
                      'Ser a principal ferramenta de aprendizado ativo no Brasil, '
                      'onde cada erro se torna uma oportunidade de crescimento '
                      'mensurada e guiada por inteligência artificial.',
                ),
                const SizedBox(height: 12),
                const _MvvCard(
                  icone: WindowsIcons.heart,
                  cor: MistakeMapDesign.amberInk,
                  acento: MistakeMapDesign.amber,
                  titulo: 'Valores',
                  descricao:
                      '• Aprendizado contínuo acima de resultados imediatos\n'
                      '• Transparência no progresso do estudante\n'
                      '• Tecnologia acessível e centrada no ser humano\n'
                      '• Privacidade e respeito aos dados pessoais',
                ),
                const SizedBox(height: 32),
                // Equipe
                const _SobreSecaoTitulo(titulo: 'A Equipe'),
                const SizedBox(height: 12),
                _MembroCard(
                  iniciais: 'CJ',
                  nome: 'Cláudio Francisco',
                  foto: claudioProfilePhotoBytes,
                  corAvatar: MistakeMapDesign.azure,
                  tinta: MistakeMapDesign.azureInk,
                  responsabilidades: [
                    'Backend',
                    'Storage (R2)',
                    'OCR',
                    'IA / LLM',
                  ],
                  descricao:
                      'Responsável pela arquitetura backend, integração com '
                      'Supabase, armazenamento de arquivos no Cloudflare R2 '
                      'e pipeline de processamento com OCR e IA.',
                  acao: LinkedInProfileButton(
                    name: 'Cláudio Francisco',
                    onPressed: () => _abrirLinkedIn(context),
                  ),
                ),
                const SizedBox(height: 12),
                const _MembroCard(
                  iniciais: 'LE',
                  nome: 'Lucas Emanuel',
                  corAvatar: MistakeMapDesign.violet,
                  tinta: MistakeMapDesign.violetInk,
                  responsabilidades: ['Frontend', 'Design', 'UI/UX'],
                  descricao:
                      'Responsável pela experiência do usuário, design de '
                      'interfaces, prototipagem no Figma e implementação '
                      'das telas no Flutter.',
                ),
                const SizedBox(height: 32),
                // Stack técnica
                const _SobreSecaoTitulo(titulo: 'Stack Tecnológica'),
                const SizedBox(height: 12),
                const Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Pilula(texto: 'Flutter / Dart', cor: contentBlue),
                    _Pilula(texto: 'Supabase Auth', cor: contentBlue),
                    _Pilula(texto: 'PostgreSQL', cor: contentBlue),
                    _Pilula(texto: 'Cloudflare R2', cor: contentBlue),
                    _Pilula(texto: 'Edge Functions', cor: contentBlue),
                    _Pilula(texto: 'Rust Worker', cor: contentBlue),
                    _Pilula(texto: 'OCR', cor: contentBlue),
                    _Pilula(texto: 'LLM', cor: contentBlue),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _abrirLinkedIn(BuildContext context) async {
    try {
      if (await openClaudioLinkedInProfile()) return;
    } on Exception {
      // A falha do navegador é apresentada no mesmo canal dos avisos do app.
    }
    if (!context.mounted) return;
    _avisar(
      context,
      'Não foi possível abrir o LinkedIn. Tente novamente.',
      erro: true,
    );
  }

  // Destaque com o gradiente da identidade.
  Widget _heroi(BuildContext context) {
    return GlassHero(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Cores.branco.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Cores.branco.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: const Icon(
              WindowsIcons.map_pin,
              size: 40,
              color: Cores.branco,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'MistakeMap',
            textAlign: TextAlign.center,
            style: context.tipo.title?.copyWith(
              fontWeight: FontWeight.bold,
              color: Cores.branco,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Transforme erros em aprendizado',
            textAlign: TextAlign.center,
            style: context.tipo.body?.copyWith(
              color: Cores.branco.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _SobreSecaoTitulo extends StatelessWidget {
  final String titulo;
  const _SobreSecaoTitulo({required this.titulo});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 24,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [MistakeMapDesign.aqua, MistakeMapDesign.violet],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            titulo,
            style: context.tipo.subtitle?.copyWith(
              fontWeight: FontWeight.bold,
              color: titleBlue,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _MvvCard extends StatelessWidget {
  final IconData icone;
  final Color cor;
  final String titulo;
  final String descricao;

  /// Acento vivo que preenche o bloco do ícone e tinge o vidro.
  final Color acento;

  const _MvvCard({
    required this.icone,
    required this.cor,
    required this.acento,
    required this.titulo,
    required this.descricao,
  });

  @override
  Widget build(BuildContext context) {
    // O tom do acento no canto e o ícone preenchido substituem a barra
    // lateral: a cor marca o cartão sem dividir o vidro em duas peças.
    return _CartaoFluent(
      acento: acento,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassIconTile(icon: icone, ink: cor, accent: acento),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: context.tipo.bodyStrong?.copyWith(color: cor),
                ),
                const SizedBox(height: 8),
                Text(
                  descricao,
                  style: context.tipo.body?.copyWith(
                    color: MistakeMapDesign.steel,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MembroCard extends StatelessWidget {
  final String iniciais;
  final String nome;
  final Uint8List? foto;
  final Color corAvatar;

  /// O acento escurecido, para nome e etiquetas legíveis sobre o vidro.
  final Color tinta;
  final List<String> responsabilidades;
  final String descricao;
  final Widget? acao;

  const _MembroCard({
    required this.iniciais,
    required this.nome,
    this.foto,
    required this.corAvatar,
    required this.tinta,
    required this.responsabilidades,
    required this.descricao,
    this.acao,
  });

  @override
  Widget build(BuildContext context) {
    return _CartaoFluent(
      acento: corAvatar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Semantics(
                image: true,
                label: 'Avatar de $nome',
                child: ExcludeSemantics(
                  child: ClipOval(
                    child: Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      color: corAvatar,
                      child: foto == null
                          ? _iniciais(context)
                          : Image.memory(
                              foto!,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => _iniciais(context),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: context.tipo.bodyStrong?.copyWith(color: tinta),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final r in responsabilidades)
                          _Pilula(texto: r, cor: tinta),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(
            style: DividerThemeData(
              thickness: 0.5,
              horizontalMargin: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            descricao,
            style: context.tipo.body?.copyWith(
              color: MistakeMapDesign.steel,
              height: 1.5,
            ),
          ),
          if (acao != null) ...[const SizedBox(height: 16), acao!],
        ],
      ),
    );
  }

  Widget _iniciais(BuildContext context) => Text(
    iniciais,
    style: context.tipo.bodyLarge?.copyWith(
      color: MistakeMapDesign.abyss,
      fontWeight: FontWeight.bold,
      letterSpacing: 1,
    ),
  );
}

// ─── fim: Sobre o App ───────────────────────────────────────────────────────
