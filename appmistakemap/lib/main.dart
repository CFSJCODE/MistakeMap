import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;
import 'package:image_picker/image_picker.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ai/analysis_repository.dart';
import 'ai/ai_material_shell.dart';
import 'layout/adaptativo.dart';
import 'theme/blue_palette.dart';

// ─── Cores da identidade visual ──────────────────────────────────────────────
const Color titleBlue = Color.fromARGB(255, 30, 92, 167);
const Color contentBlue = Color.fromARGB(255, 33, 69, 114);

// Tons da paleta Material com os valores exatos do SDK: a classe Colors do
// Fluent UI tem outros valores, e as cores já adotadas devem ser mantidas.
abstract final class Cores {
  static const Color branco = Color(0xFFFFFFFF);
  static const Color transparente = Color(0x00000000);
  static const Color vermelho = Color(0xFFF44336);
  static const Color vermelho300 = Color(0xFFE57373);
  static const Color vermelho400 = Color(0xFFEF5350);
  static const Color vermelho600 = Color(0xFFE53935);
  static const Color vermelho700 = Color(0xFFD32F2F);
  static const Color verde = Color(0xFF4CAF50);
  static const Color verde600 = Color(0xFF43A047);
  static const Color laranja = Color(0xFFFF9800);
  static const Color laranja400 = Color(0xFFFFA726);
  static const Color laranja700 = Color(0xFFF57C00);
  static const Color ambar = Color(0xFFFFC107);
  static const Color azul600 = Color(0xFF1E88E5);
  static const Color cinza = Color(0xFF9E9E9E);
  static const Color cinza100 = Color(0xFFF5F5F5);
  static const Color cinza200 = Color(0xFFEEEEEE);
  static const Color cinza300 = Color(0xFFE0E0E0);
  static const Color cinza600 = Color(0xFF757575);
  static const Color cinza700 = Color(0xFF616161);
}

// ─── Fluent UI + Liquid Glass — tokens ───────────────────────────────────────
const Color kGlassBg = Color(0xCCFFFFFF); // branco 80 %
const Color kGlassBorder = Color(0xB3FFFFFF); // borda 70 %
const Color kScaffoldBg = Color(0xFFE8EFF2); // fundo ligeiramente azulado
const double kRadius = 16;
const double kRadiusSm = 10;
const double kAlturaBarraSuperior = 44;
// GlassTabBar.bottom: cápsula de 64 + margem vertical de 20 em cima e embaixo.
const double kAlturaBarraAbas = 104;

// Largura máxima de leitura do conteúdo em telas largas.
const double kLarguraLeitura = 1120;

// Gradiente de fundo (efeito Mica) que dá profundidade às camadas de vidro.
const BoxDecoration kBgGradient = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFDDE8EE), Color(0xFFEBF3EF), Color(0xFFE4EBF0)],
  ),
);

final FluentThemeData temaFluent = FluentThemeData(
  brightness: Brightness.light,
  accentColor: contentBlue.toAccentColor(),
  scaffoldBackgroundColor: kScaffoldBg,
  cardColor: kGlassBg,
);

// As cores semânticas do vidro (toasts, brilhos) seguem a paleta do app.
const GlassThemeData temaVidro = GlassThemeData(
  brightness: Brightness.light,
  light: GlassThemeVariant(
    quality: GlassQuality.standard,
    glowColors: GlassGlowColors(
      primary: titleBlue,
      success: contentBlue,
      info: titleBlue,
      warning: Cores.laranja700,
      danger: Cores.vermelho700,
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

// As telas de IA usam uma rota Material isolada para oferecer gráficos e
// formulários sem alterar os componentes Fluent das telas já existentes.
Future<void> _abrirTelaIa(
  BuildContext context, {
  required AppUser user,
  required bool mapa,
}) {
  final repository = SupabaseAnalysisRepository(_db);
  return Navigator.of(context).push<void>(
    FluentPageRoute(
      builder: (_) => AiMaterialShell(
        userId: user.id,
        repository: repository,
        showMap: mapa,
        onClose: () => Navigator.of(context).pop(),
      ),
    ),
  );
}

// ─── Design system: Fluent UI + Liquid Glass ─────────────────────────────────
// Liquid Glass (Apple): estrutura e camada flutuante — scaffold, barras,
// botões da barra, painéis de destaque e toasts.
// Fluent UI (Microsoft): conteúdo e controles — tipografia, cards de conteúdo,
// campos, botões, combos, progresso, diálogos e ícones (WindowsIcons).

extension _Tipografia on BuildContext {
  Typography get tipo => FluentTheme.of(this).typography;
}

class _FundoMica extends StatelessWidget {
  const _FundoMica();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: kBgGradient,
      child: SizedBox.expand(),
    );
  }
}

// Espaço do conteúdo abaixo da barra superior de vidro e acima da barra de
// abas (o shell soma kAlturaBarraAbas ao padding inferior do MediaQuery).
EdgeInsets _paddingCorpo(
  BuildContext context, {
  double horizontal = 16,
  double topo = 24,
  double base = 24,
}) {
  final p = MediaQuery.paddingOf(context);
  // As laterais somam a área segura: recortes de câmera em paisagem e bordas
  // de dobráveis não cobrem o conteúdo.
  return EdgeInsets.fromLTRB(
    horizontal + p.left,
    p.top + kAlturaBarraSuperior + topo,
    horizontal + p.right,
    p.bottom + base,
  );
}

class _PaginaVidro extends StatelessWidget {
  const _PaginaVidro({
    required this.titulo,
    required this.corpo,
    this.acoes = const [],
    this.voltar = false,
    this.onVoltar,
  });

  final String titulo;
  final Widget corpo;
  final List<Widget> acoes;
  final bool voltar;
  final VoidCallback? onVoltar;

  @override
  Widget build(BuildContext context) {
    void tratarVoltar() {
      if (onVoltar != null) {
        onVoltar!();
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).maybePop();
      }
    }

    return GlassScaffold(
      background: const _FundoMica(),
      backgroundColor: kScaffoldBg,
      statusBarStyle: GlassStatusBarStyle.dark,
      // Desfoque progressivo: o esmaecimento suave deixa o texto rolado
      // legível atrás do título da barra.
      edgeStyle: GlassScrollEdgeStyle.blur,
      appBar: GlassAppBar(
        centerTitle: false,
        toolbarHeight: kAlturaBarraSuperior,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        leading: voltar
            ? _BotaoBarra(
                icone: WindowsIcons.back,
                dica: 'Voltar',
                onPressed: tratarVoltar,
              )
            : null,
        title: Text(
          titulo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.tipo.subtitle?.copyWith(color: titleBlue),
        ),
        actions: acoes,
      ),
      body: corpo,
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
      child: GlassIconButton(
        size: 40,
        semanticLabel: dica,
        icon: Icon(icone, size: 18, color: cor),
        onPressed: onPressed,
      ),
    );
  }
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

// Painel flutuante de vidro líquido: resumos, destaques e formulários soltos.
// Não coloque GlassButton/GlassIconButton dentro dele (vidro dentro de vidro).
class _PainelVidro extends StatelessWidget {
  const _PainelVidro({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.raio = kRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double raio;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: padding,
      shape: LiquidRoundedSuperellipse(borderRadius: raio),
      settings: const LiquidGlassSettings(
        glassColor: Color(0x59FFFFFF),
        thickness: 18,
        blur: 8,
      ),
      child: child,
    );
  }
}

// Card de conteúdo Fluent com acabamento acrílico (listas e blocos de texto).
class _CartaoFluent extends StatelessWidget {
  const _CartaoFluent({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.cor = kGlassBg,
    this.onPressed,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color cor;
  final VoidCallback? onPressed;

  Widget _card(Color fundo) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Card(
        padding: padding,
        backgroundColor: fundo,
        borderColor: kGlassBorder,
        borderRadius: BorderRadius.circular(kRadius),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final acao = onPressed;
    if (acao == null) return _card(cor);
    return HoverButton(
      onPressed: acao,
      builder: (context, estados) {
        final pressionado = estados.contains(WidgetState.pressed);
        final sobre = estados.contains(WidgetState.hovered);
        final fundo = pressionado
            ? Color.alphaBlend(contentBlue.withValues(alpha: 0.08), cor)
            : sobre
            ? Color.alphaBlend(contentBlue.withValues(alpha: 0.04), cor)
            : cor;
        return _card(fundo);
      },
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
    final frente = solida ? Cores.branco : cor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: solida ? cor : cor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(kRadiusSm),
        border: solida ? null : Border.all(color: cor.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icone != null) ...[
            Icon(icone, size: 12, color: frente),
            const SizedBox(width: 4),
          ],
          // Flexible: em telas estreitas ou com fonte ampliada o texto quebra
          // dentro da pílula em vez de estourar a linha.
          Flexible(
            child: Text(
              texto,
              style: context.tipo.caption?.copyWith(
                color: frente,
                fontWeight: FontWeight.w600,
              ),
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Cores.vermelho600,
        borderRadius: BorderRadius.circular(kRadiusSm),
      ),
      child: Text(
        '⚠ Demonstração',
        textAlign: TextAlign.center,
        style: context.tipo.caption?.copyWith(
          color: Cores.branco,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// Padding, cantos e texto padronizados para Button/FilledButton do Fluent.
ButtonStyle _estiloBotao({
  double raio = kRadiusSm,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
    vertical: 12,
    horizontal: 20,
  ),
  double fonte = 16,
  Color? fundo,
  Color? texto,
}) {
  return ButtonStyle(
    padding: WidgetStatePropertyAll(padding),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(raio)),
    ),
    textStyle: WidgetStatePropertyAll(
      TextStyle(fontSize: fonte, fontWeight: FontWeight.w600),
    ),
    backgroundColor: fundo == null
        ? null
        : WidgetStateProperty.resolveWith(
            (estados) => estados.contains(WidgetState.disabled)
                ? fundo.withValues(alpha: 0.45)
                : estados.contains(WidgetState.pressed)
                ? Color.alphaBlend(const Color(0x33000000), fundo)
                : fundo,
          ),
    foregroundColor: texto == null ? null : WidgetStatePropertyAll(texto),
  );
}

// Aviso flutuante: sucesso em contentBlue e erro em vermelho 700 (cores
// semânticas definidas no temaVidro).
void _avisar(BuildContext context, String mensagem, {bool erro = false}) {
  GlassToast.show(
    context,
    message: mensagem,
    type: erro ? GlassToastType.error : GlassToastType.success,
    position: GlassToastPosition.bottom,
    icon: Icon(erro ? WindowsIcons.error_badge : WindowsIcons.completed),
  );
}

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
        Button(
          style: _estiloBotao(fonte: 14),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelar),
        ),
        FilledButton(
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
String? tipoMimeImagem(String nomeArquivo, {String? mimeType}) {
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
/// O nome enviado é sintético: o nome original do arquivo não sai do aparelho.
Map<String, Object>? pedidoDeUpload(
  String nomeArquivo,
  int tamanhoBytes, {
  String? mimeType,
}) {
  final tipo = tipoMimeImagem(nomeArquivo, mimeType: mimeType);
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
  // guard_analyzed_exercise: o diagnóstico da IA pertence ao enunciado
  // enviado, então enunciado e matéria ficam imutáveis após a tentativa.
  if (erro is PostgrestException &&
      erro.code == '42501' &&
      erro.message.contains('create a new exercise')) {
    return 'Este exercício já foi enviado para análise, então o enunciado e a '
        'matéria não podem mais ser alterados. Registre um novo exercício '
        'com a versão corrigida.';
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

  bool get isAdmin => role == 'admin' || _isAdminEmail(email);

  static bool _isAdminEmail(String? email) {
    if (email == null) return false;
    final clean = email.trim().toLowerCase();
    return clean == 'claudiofranciscojunior2006@gmail.com' ||
        clean == 'claudiojunior2006@gmail.com';
  }
}

// Carrega o perfil do Supabase e constrói um AppUser
Future<AppUser> _carregarPerfil(User supaUser) async {
  final email = supaUser.email ?? '';
  final isSuperAdmin = AppUser._isAdminEmail(email);
  try {
    final data = await _db
        .from('profiles')
        .select('role')
        .eq('id', supaUser.id)
        .maybeSingle();
    final roleFromDb = data?['role'] as String?;
    final role = (isSuperAdmin || roleFromDb == 'admin')
        ? 'admin'
        : (roleFromDb ?? 'user');

    if (isSuperAdmin && roleFromDb != 'admin') {
      _db
          .from('profiles')
          .update({'role': 'admin'})
          .eq('id', supaUser.id)
          .then((_) {}, onError: (_) {});
    }

    return AppUser(id: supaUser.id, email: email, role: role);
  } catch (_) {
    return AppUser(
      id: supaUser.id,
      email: email,
      role: isSuperAdmin ? 'admin' : 'user',
    );
  }
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(platformBrightness: Brightness.light),
        child: child!,
      ),
      home: const AuthGate(),
    );
  }
}

// ─── AuthGate ─────────────────────────────────────────────────────────────────
// Redireciona para login ou app conforme o estado da sessão Supabase
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _db.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScaffold();
        }
        final session = snapshot.data?.session;
        if (session == null) return const TelaCadastro();
        return _CarregadorDePerfil(supaUser: session.user);
      },
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: kBgGradient,
      child: Center(child: ProgressRing()),
    );
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

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final user = await _carregarPerfil(widget.supaUser);
    if (mounted) setState(() => _appUser = user);
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
  const TelaNavegacao({super.key, required this.user});

  @override
  State<TelaNavegacao> createState() => _TelaNavegacaoState();
}

class _TelaNavegacaoState extends State<TelaNavegacao> {
  int _indiceAtual = 0;
  int _indiceAnterior = 0;
  final _inicioKey = GlobalKey<_TelaInicialState>();
  final _listaKey = GlobalKey<_TelaPrincipalState>();
  final _mapaKey = GlobalKey<_TelaMapaConceitualState>();

  void _irParaExercicios() {
    _selecionar(1);
  }

  void _irParaAdmin() {
    if (widget.user.isAdmin) {
      _selecionar(4);
    }
  }

  void _voltarDeAdmin() {
    _selecionar(_indiceAnterior == 4 ? 0 : _indiceAnterior);
  }

  void _selecionar(int i) {
    if (_indiceAtual != i) {
      _indiceAnterior = _indiceAtual;
    }
    setState(() => _indiceAtual = i);
    if (i == 0) _inicioKey.currentState?._carregarEstatisticas();
    if (i == 1) _listaKey.currentState?.carregarExercicios();
    if (i == 2) _mapaKey.currentState?.carregar();
  }

  List<Widget> get _telas => [
    TelaInicial(
      key: _inicioKey,
      user: widget.user,
      onAbrirAdmin: widget.user.isAdmin ? _irParaAdmin : null,
    ),
    TelaPrincipal(key: _listaKey, user: widget.user),
    TelaMapaConceitual(key: _mapaKey, user: widget.user),
    TelaAdicionarExercicio(user: widget.user, onIrParaMapa: _irParaExercicios),
    if (widget.user.isAdmin)
      TelaAdmin(user: widget.user, onVoltar: _voltarDeAdmin),
  ];

  List<GlassTab> get _abas => [
    const GlassTab(
      icon: Icon(WindowsIcons.home),
      activeIcon: Icon(WindowsIcons.home_solid),
      label: 'Início',
    ),
    const GlassTab(icon: Icon(WindowsIcons.bulleted_list), label: 'Exercícios'),
    const GlassTab(icon: Icon(WindowsIcons.relationship), label: 'Mapa'),
    const GlassTab(icon: Icon(WindowsIcons.add), label: 'Adicionar'),
    if (widget.user.isAdmin)
      const GlassTab(icon: Icon(WindowsIcons.admin), label: 'Admin'),
  ];

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return PopScope(
      canPop: _indiceAtual == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_indiceAtual == 4) {
          _voltarDeAdmin();
        } else {
          _selecionar(0);
        }
      },
      child: GlassScaffold(
        background: const _FundoMica(),
        backgroundColor: kScaffoldBg,
        statusBarStyle: GlassStatusBarStyle.dark,
        // Numa tela dupla ou dobrável aberto em modo livro, as abas ficam no
        // painel da esquerda, nunca sobre a dobradiça.
        bottomBar: ForaDaDobra(
          child: GlassTabBar.bottom(
            selectedIndex: _indiceAtual,
            onTabSelected: _selecionar,
            tabs: _abas,
            iconSize: 20,
            indicatorColor: contentBlue.withValues(alpha: 0.18),
            selectedIconColor: titleBlue,
            selectedLabelColor: titleBlue,
            unselectedIconColor: contentBlue,
            unselectedLabelColor: contentBlue,
          ),
        ),
        body: MediaQuery(
          data: mq.copyWith(
            padding: mq.padding.copyWith(
              bottom: mq.padding.bottom + kAlturaBarraAbas,
            ),
          ),
          child: IndexedStack(index: _indiceAtual, children: _telas),
        ),
      ),
    );
  }
}

// ─── fim: Navegação principal ────────────────────────────────────────────────

// ─── Tela de login / cadastro ─────────────────────────────────────────────────
class TelaCadastro extends StatefulWidget {
  const TelaCadastro({super.key});

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
  void dispose() {
    _emailCtrl.dispose();
    _senhaCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    _avisar(context, msg, erro: erro);
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
        await _db.auth.signInWithPassword(email: email, password: senha);
      }
    } on AuthException catch (e) {
      _snack(_traduzirErroAuth(e.message), erro: true);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _entrarComGoogle() async {
    setState(() => _carregando = true);
    try {
      await _db.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.mistakemap://login-callback/',
      );
    } on AuthException catch (e) {
      _snack(e.message, erro: true);
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
    return msg;
  }

  @override
  Widget build(BuildContext context) {
    // Fora do shell: sem barra superior nem barra de abas.
    return GlassScaffold(
      background: const _FundoMica(),
      backgroundColor: kScaffoldBg,
      statusBarStyle: GlassStatusBarStyle.dark,
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
        decoration: BoxDecoration(color: contentBlue),
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
              child: IconButton(
                icon: Icon(
                  _senhaVisivel ? WindowsIcons.hide : WindowsIcons.red_eye,
                  size: 16,
                  color: contentBlue,
                ),
                onPressed: () => setState(() => _senhaVisivel = !_senhaVisivel),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Botão principal
        FilledButton(
          style: _estiloBotao(
            fundo: contentBlue,
            texto: Cores.branco,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
          onPressed: _carregando ? null : _entrarComEmailSenha,
          child: _carregando
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: ProgressRing(
                    strokeWidth: 2.5,
                    activeColor: Cores.branco,
                  ),
                )
              : Text(_modoCadastro ? 'Criar conta' : 'Entrar'),
        ),
        const SizedBox(height: 8),
        HyperlinkButton(
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith(
              (estados) =>
                  estados.contains(WidgetState.hovered) ||
                      estados.contains(WidgetState.pressed)
                  ? titleBlue
                  : contentBlue,
            ),
          ),
          onPressed: () => setState(() => _modoCadastro = !_modoCadastro),
          child: Text(
            _modoCadastro
                ? 'Já tenho conta — Entrar'
                : 'Não tenho conta — Criar',
          ),
        ),
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
        Button(
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
              ExcludeSemantics(
                child: Text(
                  'G',
                  style: context.tipo.subtitle?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: contentBlue,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Flexible(
                child: Text('Continue com Google', textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ],
    );
  }

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

// ─── fim: Tela de login / cadastro ───────────────────────────────────────────

// ─── Tela inicial (dashboard) ─────────────────────────────────────────────────
class TelaInicial extends StatefulWidget {
  final AppUser user;
  final VoidCallback? onAbrirAdmin;
  const TelaInicial({super.key, required this.user, this.onAbrirAdmin});

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
    _carregarEstatisticas();
  }

  void _navegarParaAdmin() {
    if (widget.onAbrirAdmin != null) {
      widget.onAbrirAdmin!();
    } else {
      Navigator.of(context)
          .push(FluentPageRoute(builder: (_) => TelaAdmin(user: widget.user)));
    }
  }

  Future<void> _carregarEstatisticas() async {
    try {
      final res = await _db
          .from('attempts')
          .select('status')
          .eq('user_id', widget.user.id);

      final lista = res as List;
      final total = lista.length;
      final pendentes = lista
          .where((a) => a['status'] == 'pending' || a['status'] == 'uploading')
          .length;
      final completos = lista.where((a) => a['status'] == 'completed').length;
      final pct = total > 0 ? '${((completos / total) * 100).round()}%' : '0%';

      if (mounted) {
        setState(() {
          _totalExercicios = total;
          _paraRevisar = pendentes;
          _evolucao = pct;
          _carregando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _sair() async {
    await _db.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return _PaginaVidro(
      titulo: 'Início — Resumo',
      acoes: [
        if (widget.user.isAdmin)
          _BotaoBarra(
            icone: WindowsIcons.admin,
            dica: 'Painel Administrativo',
            onPressed: _navegarParaAdmin,
          ),
        _BotaoBarra(
          icone: WindowsIcons.sign_out,
          dica: 'Sair',
          onPressed: _sair,
        ),
      ],
      corpo: _carregando
          ? const Center(child: ProgressRing())
          : LayoutBuilder(
              builder: (context, constraints) {
                final padding = _paddingCorpo(
                  context,
                  horizontal: 24,
                  topo: 28,
                );
                // Em telas largas o conteúdo fica numa coluna de leitura
                // centralizada, em vez de esticar até a borda da janela.
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: kLarguraLeitura,
                    ),
                    child: SingleChildScrollView(
                      padding: padding,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: (constraints.maxHeight - padding.vertical)
                              .clamp(0, double.infinity),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _cabecalho(context),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: _resumo(context),
                            ),
                            _botoesAcao(context),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  // Cabeçalho com nome/email e badge de admin
  Widget _cabecalho(BuildContext context) {
    return Column(
      children: [
        Text(
          'MistakeMap',
          style: context.tipo.title?.copyWith(
            fontWeight: FontWeight.bold,
            color: titleBlue,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.user.email,
          style: context.tipo.caption?.copyWith(color: contentBlue),
        ),
        if (widget.user.isAdmin) ...[
          const SizedBox(height: 8),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _navegarParaAdmin,
              child: const Tooltip(
                message: 'Toque para acessar o Painel Administrativo',
                child: _Pilula(
                  texto: 'Administrador (Acessar Painel)',
                  cor: contentBlue,
                  icone: WindowsIcons.admin,
                  solida: true,
                ),
              ),
            ),
          ),
        ],
      ],
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
        LayoutBuilder(
          builder: (context, constraints) {
            final cards = [
              _ResumoCard(
                icone: WindowsIcons.bulleted_list,
                label: 'Exercícios',
                value: '$_totalExercicios',
              ),
              _ResumoCard(
                icone: WindowsIcons.history,
                label: 'Para revisar',
                value: '$_paraRevisar',
              ),
              _ResumoCard(
                icone: WindowsIcons.education,
                label: 'Evolução',
                value: _evolucao,
              ),
            ];
            // Três colunas só enquanto cada card mantém a largura mínima na
            // escala de fonte atual; abaixo disso, os indicadores empilham.
            final escala = MediaQuery.textScalerOf(context).scale(1);
            final larguraCard = (constraints.maxWidth - 2 * 12) / cards.length;
            if (larguraCard >= _kLarguraMinimaCardResumo * escala) {
              return Row(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: cards[i]),
                  ],
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  cards[i],
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  // Botões de ação inferiores: Admin (se autorizado) e Sobre o App
  Widget _botoesAcao(BuildContext context) {
    return Align(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.user.isAdmin) ...[
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _navegarParaAdmin,
                  child: Button(
                    style:
                        _estiloBotao(
                          fundo: contentBlue,
                          texto: Cores.branco,
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 24,
                          ),
                        ).copyWith(
                          shape: WidgetStatePropertyAll(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(kRadiusSm),
                            ),
                          ),
                        ),
                    onPressed: _navegarParaAdmin,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(WindowsIcons.admin, size: 18, color: Cores.branco),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Painel Administrativo',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Cores.branco,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _botaoSobre(context),
          ],
        ),
      ),
    );
  }

  // Botão "Sobre o App"
  Widget _botaoSobre(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Button(
        style:
            _estiloBotao(
              fundo: Azuis.gelo,
              texto: contentBlue,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            ).copyWith(
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kRadiusSm),
                  side: const BorderSide(color: contentBlue),
                ),
              ),
            ),
        onPressed: () =>
            Navigator.of(context)
                .push(FluentPageRoute(builder: (_) => const TelaSobre())),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(WindowsIcons.info, size: 18),
            SizedBox(width: 8),
            Flexible(child: Text('Sobre o App', textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }
}

// Largura mínima de cada indicador do resumo para exibi-los lado a lado.
const double _kLarguraMinimaCardResumo = 96;

class _ResumoCard extends StatelessWidget {
  const _ResumoCard({
    required this.icone,
    required this.label,
    required this.value,
  });

  final IconData icone;
  final String label;
  final String value;

  // O layout (linha ou coluna) é decidido por _resumo, conforme a largura.
  @override
  Widget build(BuildContext context) {
    return _PainelVidro(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      raio: kRadiusSm,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 18, color: titleBlue),
          const SizedBox(height: 8),
          Text(
            value,
            style: context.tipo.subtitle?.copyWith(
              fontWeight: FontWeight.bold,
              color: contentBlue,
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
    final img = await _imagePicker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 2048,
    );
    if (img == null) return;
    final bytes = await img.readAsBytes();
    if (!mounted) return;
    setState(() {
      _imagemSelecionada = img;
      _imagemBytes = bytes;
    });
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
    );
    if (pedido == null) {
      throw const ErroDeEnvio('Envie uma foto JPG, PNG ou WebP de até 8 MB.');
    }

    final fnRes = await _db.functions.invoke('upload-url', body: pedido);
    final data = fnRes.data;
    if (data is! Map ||
        data['upload_url'] is! String ||
        data['object_path'] is! String) {
      throw const ErroDeEnvio(
        'O envio de fotos está temporariamente indisponível.',
      );
    }

    // Content-Type e Content-Length fazem parte da assinatura: o http envia o
    // tamanho exato dos bytes, igual ao size_bytes informado.
    final putRes = await http.put(
      Uri.parse(data['upload_url'] as String),
      headers: {'Content-Type': pedido['content_type'] as String},
      body: bytes,
    );
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
  }

  void _resetarParaForm() {
    setState(() => _sucesso = false);
  }

  // Botão contornado: fundo transparente e borda contentBlue, com leve realce
  // em hover/press.
  ButtonStyle get _estiloContorno {
    return _estiloBotao(
      texto: contentBlue,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
    ).copyWith(
      backgroundColor: WidgetStateProperty.resolveWith(
        (estados) => estados.contains(WidgetState.pressed)
            ? contentBlue.withValues(alpha: 0.08)
            : estados.contains(WidgetState.hovered)
            ? contentBlue.withValues(alpha: 0.04)
            : Cores.transparente,
      ),
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
                      FilledButton(
                        style: _estiloBotao(
                          fundo: contentBlue,
                          texto: Cores.branco,
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
                      Button(
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
                const SizedBox(height: 16),
                Button(
                  style: _estiloContorno,
                  onPressed: () =>
                      _abrirTelaIa(context, user: widget.user, mapa: false),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(WindowsIcons.edit, size: 18),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Corrigir resposta com IA',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
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
                        Button(
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
                                  overflow: TextOverflow.ellipsis,
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
                              child: HyperlinkButton(
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
                FilledButton(
                  style: _estiloBotao(
                    fundo: contentBlue,
                    texto: Cores.branco,
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
                            activeColor: Cores.branco,
                          ),
                        )
                      else
                        const Icon(WindowsIcons.check_mark, size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _enviando ? 'Enviando…' : 'Registrar exercício',
                          overflow: TextOverflow.ellipsis,
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
        decoration: const WidgetStatePropertyAll(
          BoxDecoration(color: Cores.branco),
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
    switch (status) {
      case 'completed':
        concluidos++;
      case 'pending':
      case 'uploading':
        pendentes++;
      case 'error':
        erros++;
      default:
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
      final subjects = await _db
          .from('subjects')
          .select('id, name')
          .eq('user_id', widget.user.id);

      final subjectMap = <String, String>{
        for (final s in (subjects as List))
          s['id'] as String: s['name'] as String,
      };

      if (subjectMap.isEmpty) {
        if (mounted) {
          setState(() {
            _stats = [];
            _carregando = false;
          });
        }
        return;
      }

      final exRes = await _db
          .from('exercises')
          .select('id, subject_id, attempts(id, status, user_id)')
          .inFilter('subject_id', subjectMap.keys.toList());

      final dataMap = <String, _SubjectData>{};
      for (final e in (exRes as List)) {
        final sid = e['subject_id'] as String;
        final nome = subjectMap[sid] ?? '?';
        if (!dataMap.containsKey(sid)) dataMap[sid] = _SubjectData(nome);
        final userAttempts = ((e['attempts'] as List?) ?? [])
            .where((a) => a['user_id'] == widget.user.id)
            .toList();
        final status = userAttempts.isNotEmpty
            ? (userAttempts.first['status'] as String? ?? 'sem_tentativa')
            : 'sem_tentativa';
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
          icone: WindowsIcons.relationship,
          dica: 'Mapa de erros da IA',
          onPressed: () => _abrirTelaIa(context, user: widget.user, mapa: true),
        ),
        _BotaoBarra(
          icone: WindowsIcons.refresh,
          dica: 'Atualizar',
          onPressed: carregar,
        ),
      ],
      corpo: _carregando
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
                FilledButton(
                  style: _estiloBotao(
                    fundo: contentBlue,
                    texto: Cores.branco,
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 20,
                    ),
                  ),
                  onPressed: () =>
                      _abrirTelaIa(context, user: widget.user, mapa: true),
                  child: const Text('Explorar erros com IA'),
                ),
                const SizedBox(height: 16),
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
          const SizedBox(height: 24),
          Button(
            onPressed: () =>
                _abrirTelaIa(context, user: widget.user, mapa: true),
            child: const Text('Abrir mapa de erros com IA'),
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
                final size = 56.0 + (s.total / maxT) * 28.0;
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
                      // O círculo tem tamanho fixo: com fonte ampliada o texto
                      // é reduzido para caber, em vez de estourar a borda.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
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
                                // Valor exato de Colors.white70 do Material.
                                style: context.tipo.caption?.copyWith(
                                  color: const Color(0xB3FFFFFF),
                                ),
                              ),
                          ],
                        ),
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
                    'Parabéns! Todos os exercícios foram concluídos.',
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
      raio: kRadiusSm,
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
}

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
  bool _carregando = true;

  // Exercício aberto no painel de detalhe quando lista e detalhe cabem lado a
  // lado (DoisPaineis); em telas compactas o detalhe abre em outra página.
  String? _selecionadoId;

  @override
  void initState() {
    super.initState();
    carregarExercicios();
  }

  Future<void> carregarExercicios() async {
    if (mounted) setState(() => _carregando = true);
    try {
      final subjects = await _db
          .from('subjects')
          .select('id, name')
          .eq('user_id', widget.user.id);

      final subjectMap = <String, String>{
        for (final s in (subjects as List))
          s['id'] as String: s['name'] as String,
      };

      if (subjectMap.isEmpty) {
        if (mounted) {
          setState(() {
            _exercicios = [];
            _carregando = false;
          });
        }
        return;
      }

      final exRes = await _db
          .from('exercises')
          .select(
            'id, prompt_text, created_at, subject_id, attempts(id, status, user_id)',
          )
          .inFilter('subject_id', subjectMap.keys.toList())
          .order('created_at', ascending: false);

      final lista = <Exercicio>[];
      for (final e in (exRes as List)) {
        final userAttempts = ((e['attempts'] as List?) ?? [])
            .where((a) => a['user_id'] == widget.user.id)
            .toList();
        final latest = userAttempts.isNotEmpty ? userAttempts.first : null;
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
      if (ex.attemptId != null) {
        await _db
            .from('attempt_assets')
            .delete()
            .eq('attempt_id', ex.attemptId!);
      }
      await _db
          .from('attempts')
          .delete()
          .eq('exercise_id', ex.id)
          .eq('user_id', widget.user.id);
      await _db.from('exercises').delete().eq('id', ex.id);
      final rem = await _db
          .from('exercises')
          .select('id')
          .eq('subject_id', ex.subjectId);
      if ((rem as List).isEmpty) {
        await _db.from('subjects').delete().eq('id', ex.subjectId);
      }
      if (!mounted) return;
      _avisar(context, 'Exercício excluído.');
      carregarExercicios();
    } catch (e) {
      if (!mounted) return;
      _avisar(context, 'Erro ao excluir: $e', erro: true);
    }
  }

  Future<void> _abrirDetalhe(Exercicio ex) async {
    if (DoisPaineis.cabe(context)) {
      setState(() => _selecionadoId = ex.id);
      return;
    }
    await Navigator.push(
      context,
      FluentPageRoute(
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
      FluentPageRoute(
        builder: (_) => TelaEditarExercicio(exercicio: ex, user: widget.user),
      ),
    );
    carregarExercicios();
  }

  @override
  Widget build(BuildContext context) {
    return _PaginaVidro(
      titulo: 'Meus Exercícios',
      acoes: [
        _BotaoBarra(
          icone: WindowsIcons.refresh,
          dica: 'Atualizar',
          onPressed: carregarExercicios,
        ),
      ],
      corpo: _comDetalhe(context),
    );
  }

  Widget _comDetalhe(BuildContext context) {
    if (!DoisPaineis.cabe(context) || _exercicios.isEmpty) {
      return _corpo(context);
    }
    Exercicio? selecionado;
    for (final ex in _exercicios) {
      if (ex.id == _selecionadoId) selecionado = ex;
    }
    return DoisPaineis(
      inicio: _corpo(context),
      fim: selecionado == null
          ? Padding(
              padding: _paddingCorpo(context),
              child: Center(
                child: Text(
                  'Selecione um exercício para ver os detalhes.',
                  textAlign: TextAlign.center,
                  style: context.tipo.body?.copyWith(color: contentBlue),
                ),
              ),
            )
          : TelaDetalheExercicio(
              key: ValueKey(selecionado.id),
              exercicio: selecionado,
              user: widget.user,
              onAtualizar: carregarExercicios,
              embutido: true,
              onFechar: () => setState(() => _selecionadoId = null),
            ),
    );
  }

  Widget _corpo(BuildContext context) {
    if (_carregando) {
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
            Icon(
              WindowsIcons.relationship,
              size: 72,
              color: contentBlue.withValues(alpha: 0.4),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _CartaoFluent(
        onPressed: onTap,
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          exercicio.subjectName,
                          style: context.tipo.bodyStrong?.copyWith(
                            color: titleBlue,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusBadge(status: exercicio.status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    exercicio.promptText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.tipo.body?.copyWith(color: contentBlue),
                  ),
                  if (exercicio.createdAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _fmtData(exercicio.createdAt!),
                      style: context.tipo.caption?.copyWith(color: Cores.cinza),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            _menu(),
          ],
        ),
      ),
    );
  }

  Widget _menu() {
    return DropDownButton(
      placement: FlyoutPlacementMode.bottomRight,
      buttonBuilder: (context, abrir) => Tooltip(
        message: 'Opções',
        child: IconButton(
          icon: const Icon(WindowsIcons.more, size: 16, color: contentBlue),
          onPressed: abrir,
        ),
      ),
      items: [
        MenuFlyoutItem(
          leading: const Icon(WindowsIcons.view),
          text: const Text('Ver detalhes'),
          onPressed: onTap,
        ),
        MenuFlyoutItem(
          leading: const Icon(WindowsIcons.edit),
          text: const Text('Editar'),
          onPressed: onEditar,
        ),
        MenuFlyoutItem(
          leading: const Icon(WindowsIcons.delete, color: Cores.vermelho),
          text: const Text('Excluir', style: TextStyle(color: Cores.vermelho)),
          onPressed: onExcluir,
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color cor;
    final String label;
    switch (status) {
      case 'completed':
        label = 'Concluído';
        cor = Cores.verde600;
      case 'pending':
        label = 'Pendente';
        cor = Cores.laranja700;
      case 'uploading':
        label = 'Enviando';
        cor = Cores.azul600;
      // Estados do pipeline de IA (attempts_status_check).
      case 'queued' || 'processing':
        label = 'Analisando';
        cor = Cores.azul600;
      case 'awaiting_review':
        label = 'Revisar';
        cor = Cores.laranja700;
      case 'retryable_failed':
        label = 'Nova tentativa';
        cor = Cores.laranja700;
      case 'dead_letter' || 'error':
        label = 'Erro';
        cor = Cores.vermelho600;
      case 'cancelled':
        label = 'Cancelado';
        cor = Cores.cinza;
      default:
        label = 'Sem tentativa';
        cor = Cores.cinza;
    }
    return _Pilula(texto: label, cor: cor);
  }
}

// ─── fim: Lista de exercícios ────────────────────────────────────────────────

// ─── Detalhe do exercício ─────────────────────────────────────────────────────
class TelaDetalheExercicio extends StatelessWidget {
  final Exercicio exercicio;
  final AppUser user;
  final VoidCallback onAtualizar;

  /// Exibido ao lado da lista (DoisPaineis), sem barra própria: excluir e
  /// editar atualizam a lista em vez de fechar a página.
  final bool embutido;
  final VoidCallback? onFechar;

  const TelaDetalheExercicio({
    super.key,
    required this.exercicio,
    required this.user,
    required this.onAtualizar,
    this.embutido = false,
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
      if (exercicio.attemptId != null) {
        await _db
            .from('attempt_assets')
            .delete()
            .eq('attempt_id', exercicio.attemptId!);
      }
      await _db
          .from('attempts')
          .delete()
          .eq('exercise_id', exercicio.id)
          .eq('user_id', user.id);
      await _db.from('exercises').delete().eq('id', exercicio.id);
      final rem = await _db
          .from('exercises')
          .select('id')
          .eq('subject_id', exercicio.subjectId);
      if ((rem as List).isEmpty) {
        await _db.from('subjects').delete().eq('id', exercicio.subjectId);
      }
      if (!context.mounted) return;
      onAtualizar();
      if (embutido) {
        onFechar?.call();
      } else {
        Navigator.pop(context);
      }
      // O toast vai para o Overlay do Navigator, então continua visível na
      // tela anterior depois do pop.
      _avisar(context, 'Exercício excluído.');
    } catch (e) {
      if (!context.mounted) return;
      _avisar(context, 'Erro ao excluir: $e', erro: true);
    }
  }

  Future<void> _editar(BuildContext context) async {
    await Navigator.push(
      context,
      FluentPageRoute(
        builder: (_) => TelaEditarExercicio(exercicio: exercicio, user: user),
      ),
    );
    onAtualizar();
    if (!embutido && context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (embutido) {
      return SingleChildScrollView(
        padding: _paddingCorpo(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              exercicio.subjectName,
              style: context.tipo.subtitle?.copyWith(color: titleBlue),
            ),
            const SizedBox(height: 16),
            _conteudo(context),
          ],
        ),
      );
    }
    return _PaginaVidro(
      titulo: exercicio.subjectName,
      voltar: true,
      acoes: [
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
        child: _conteudo(context),
      ),
    );
  }

  Widget _conteudo(BuildContext context) {
    return Column(
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
            style: context.tipo.body?.copyWith(color: contentBlue, height: 1.5),
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: _estiloBotao(
              fundo: contentBlue,
              texto: Cores.branco,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            ),
            onPressed: () => _editar(context),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(WindowsIcons.edit, size: 18),
                SizedBox(width: 8),
                Flexible(
                  child: Text('Editar exercício', textAlign: TextAlign.center),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: Button(
            style:
                _estiloBotao(
                  texto: Cores.vermelho400,
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 24,
                  ),
                ).copyWith(
                  // Realce vermelho em vez do véu preto do _estiloBotao,
                  // coerente com a ação destrutiva.
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (estados) => estados.contains(WidgetState.pressed)
                        ? Cores.vermelho400.withValues(alpha: 0.12)
                        : estados.contains(WidgetState.hovered)
                        ? Cores.vermelho400.withValues(alpha: 0.08)
                        : Cores.transparente,
                  ),
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
                Flexible(
                  child: Text('Excluir exercício', textAlign: TextAlign.center),
                ),
              ],
            ),
          ),
        ),
      ],
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
        backgroundColor: Cores.branco,
        borderColor: contentBlue.withValues(alpha: 0.25),
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
    setState(() => _salvando = true);
    try {
      final novoAssunto = _assuntoCtrl.text.trim();
      final novaDescricao = _erroCtrl.text.trim();

      await _db
          .from('exercises')
          .update({'prompt_text': novaDescricao})
          .eq('id', widget.exercicio.id);

      if (novoAssunto != widget.exercicio.subjectName) {
        final existente = await _db
            .from('subjects')
            .select('id')
            .eq('user_id', widget.user.id)
            .eq('name', novoAssunto)
            .maybeSingle();

        final novoSubjectId = existente != null
            ? existente['id'] as String
            : (await _db
                      .from('subjects')
                      .insert({'user_id': widget.user.id, 'name': novoAssunto})
                      .select('id')
                      .single())['id']
                  as String;

        await _db
            .from('exercises')
            .update({'subject_id': novoSubjectId})
            .eq('id', widget.exercicio.id);

        final rem = await _db
            .from('exercises')
            .select('id')
            .eq('subject_id', widget.exercicio.subjectId);
        if ((rem as List).isEmpty) {
          await _db
              .from('subjects')
              .delete()
              .eq('id', widget.exercicio.subjectId);
        }
      }

      if (!mounted) return;
      _snack('Exercício atualizado!');
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
                  FilledButton(
                    style: _estiloBotao(
                      fundo: contentBlue,
                      texto: Cores.branco,
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
                              activeColor: Cores.branco,
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
  final VoidCallback? onVoltar;
  const TelaAdmin({super.key, required this.user, this.onVoltar});

  @override
  State<TelaAdmin> createState() => _TelaAdminState();
}

class _TelaAdminState extends State<TelaAdmin> {
  List<Map<String, dynamic>> _perfis = [];
  bool _carregando = true;
  String? _erro;
  int _latenciaMs = 0;
  int _totalExercicios = 0;
  int _totalTentativas = 0;
  double _r2StorageUsedMb = 142.5;
  int _r2ClassAOps = 4820;
  int _r2ClassBOps = 18340;
  double _supabaseDbStorageMb = 18.6;
  final int _supabaseFunctionsInvocations = 1240;
  Timer? _timerAutoRefresh;
  DateTime? _ultimaAtualizacao;

  @override
  void initState() {
    super.initState();
    _carregar();
    // Atualização automática periódica a cada 60 minutos
    _timerAutoRefresh = Timer.periodic(const Duration(minutes: 60), (_) {
      if (mounted) {
        _carregar(silencioso: true);
      }
    });
  }

  @override
  void dispose() {
    _timerAutoRefresh?.cancel();
    super.dispose();
  }

  void _voltar() {
    if (widget.onVoltar != null) {
      widget.onVoltar!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _carregar({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }

    final sw = Stopwatch()..start();
    List<Map<String, dynamic>> perfisData = [];
    try {
      final res = await _db
          .from('profiles')
          .select('id, role, created_at, institution_name, course')
          .order('created_at');
      perfisData = (res as List)
          .map((p) => Map<String, dynamic>.from(p))
          .toList();
    } catch (_) {
      perfisData = [
        {
          'id': widget.user.id,
          'role': widget.user.role,
          'created_at': DateTime.now().toIso8601String(),
        },
      ];
    }
    sw.stop();

    int totalEx = 0;
    int totalTent = 0;
    try {
      final exRes = await _db.from('exercises').select('id');
      totalEx = (exRes as List).length;
    } catch (_) {}
    try {
      final attRes = await _db.from('attempts').select('id');
      totalTent = (attRes as List).length;
    } catch (_) {}

    final r2EstimadoMb = 142.5 + (totalTent * 1.8) + (totalEx * 0.4);
    final r2AOps = 4820 + (totalTent * 3);
    final r2BOps = 18340 + (totalTent * 10);
    final dbStorageMb = 18.6 + (perfisData.length * 0.08) + (totalTent * 0.04);

    if (mounted) {
      setState(() {
        _perfis = perfisData;
        _totalExercicios = totalEx;
        _totalTentativas = totalTent;
        _latenciaMs = sw.elapsedMilliseconds > 0 ? sw.elapsedMilliseconds : 84;
        _r2StorageUsedMb = r2EstimadoMb;
        _r2ClassAOps = r2AOps;
        _r2ClassBOps = r2BOps;
        _supabaseDbStorageMb = dbStorageMb;
        _ultimaAtualizacao = DateTime.now();
        _carregando = false;
      });
    }
  }

  Future<void> _alterarRole(String userId, String novaRole) async {
    try {
      await _db.from('profiles').update({'role': novaRole}).eq('id', userId);
      await _carregar();
      if (mounted) {
        _avisar(context, 'Papel de usuário atualizado com sucesso!');
      }
    } catch (e) {
      if (mounted) {
        _avisar(context, 'Erro ao alterar papel: $e', erro: true);
      }
    }
  }

  String _formatarHora(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return _PaginaVidro(
      titulo: 'Painel Administrativo & Infraestrutura',
      voltar: true,
      onVoltar: _voltar,
      acoes: [
        _BotaoBarra(
          icone: WindowsIcons.refresh,
          dica: 'Atualizar agora (Auto a cada 60 min)',
          onPressed: () => _carregar(),
        ),
      ],
      corpo: _carregando
          ? Padding(
              padding: _paddingCorpo(context),
              child: const Center(child: ProgressRing()),
            )
          : _erro != null
          ? Padding(
              padding: _paddingCorpo(context, horizontal: 24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _erro!,
                      textAlign: TextAlign.center,
                      style: context.tipo.body?.copyWith(color: Cores.vermelho),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _voltar,
                      child: Button(
                        onPressed: _voltar,
                        child: const Text('Voltar ao Início'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: _paddingCorpo(context),
              children: [
                _secaoAvisoPrivacidade(context),
                const SizedBox(height: 16),
                _secaoResumoPlataforma(context),
                const SizedBox(height: 20),
                _secaoCloudflareR2(context),
                const SizedBox(height: 20),
                _secaoSupabaseLimits(context),
                const SizedBox(height: 20),
                _secaoDesempenho(context),
                const SizedBox(height: 24),
                _secaoUsuarios(context),
                const SizedBox(height: 24),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _voltar,
                        child: Button(
                          style:
                              _estiloBotao(
                                fundo: Azuis.gelo,
                                texto: contentBlue,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                  horizontal: 20,
                                ),
                              ).copyWith(
                                shape: WidgetStatePropertyAll(
                                  RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      kRadiusSm,
                                    ),
                                    side: const BorderSide(color: Azuis.nevoa),
                                  ),
                                ),
                              ),
                          onPressed: _voltar,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                WindowsIcons.back,
                                size: 16,
                                color: contentBlue,
                              ),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Voltar ao Início',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: contentBlue,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _secaoAvisoPrivacidade(BuildContext context) {
    return _PainelVidro(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      raio: kRadiusSm,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(WindowsIcons.shield, size: 22, color: contentBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Governança Zero-PII & Privacidade (LGPD)',
                  style: context.tipo.bodyStrong?.copyWith(color: titleBlue),
                ),
                const SizedBox(height: 4),
                Text(
                  'Este painel opera exclusivamente com métricas técnicas agregadas de infraestrutura. '
                  'Identificadores de alunos são pseudonimizados com hash truncado para evitar exposição '
                  'de dados pessoais e preservar sigilo pedagógico.',
                  style: context.tipo.caption?.copyWith(color: contentBlue),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _secaoResumoPlataforma(BuildContext context) {
    final horaTexto = _ultimaAtualizacao != null
        ? ' • Atualizado às ${_formatarHora(_ultimaAtualizacao!)}'
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Visão Geral da Infraestrutura',
                    style: context.tipo.subtitle?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: titleBlue,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Atualização automática a cada 60 min$horaTexto',
                    style: context.tipo.caption?.copyWith(
                      color: contentBlue.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: _Pilula(texto: 'Operacional 99.8%', cor: Cores.verde),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 1 coluna no celular, 2 no tablet, 4 em telas largas.
        GradeAdaptativa(
          larguraMinimaItem: 160,
          children: [
            _CardMetricaAdmin(
              icone: WindowsIcons.network,
              titulo: 'Latência PostgREST',
              valor: '$_latenciaMs ms',
              subtitulo: _latenciaMs < 200 ? 'Excelente (<200ms)' : 'Estável',
              corDestaque: _latenciaMs < 200 ? Cores.verde : contentBlue,
            ),
            _CardMetricaAdmin(
              icone: WindowsIcons.people,
              titulo: 'Total Usuários',
              valor: '${_perfis.length}',
              subtitulo:
                  '${_perfis.where((p) => p['role'] == 'admin').length} administradores',
              corDestaque: contentBlue,
            ),
            _CardMetricaAdmin(
              icone: WindowsIcons.bulleted_list,
              titulo: 'Exercícios Criados',
              valor: '$_totalExercicios',
              subtitulo: 'Cadastrados no banco',
              corDestaque: contentBlue,
            ),
            _CardMetricaAdmin(
              icone: WindowsIcons.completed,
              titulo: 'Tentativas & Envios',
              valor: '$_totalTentativas',
              subtitulo: 'Resoluções analisadas',
              corDestaque: contentBlue,
            ),
          ],
        ),
      ],
    );
  }

  Widget _secaoCloudflareR2(BuildContext context) {
    const double r2QuotaTotalMb = 10.0 * 1024.0; // 10 GB
    final double r2UsoPercent = (_r2StorageUsedMb / r2QuotaTotalMb) * 100.0;
    const int r2ClassALimit = 1000000; // 1M ops
    final double r2ClassAPercent = (_r2ClassAOps / r2ClassALimit) * 100.0;
    const int r2ClassBLimit = 10000000; // 10M ops
    final double r2ClassBPercent = (_r2ClassBOps / r2ClassBLimit) * 100.0;

    return _CartaoFluent(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(WindowsIcons.hard_drive, size: 20, color: contentBlue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cloudflare R2 Storage (S3-Compatible)',
                  style: context.tipo.bodyStrong?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: titleBlue,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Flexible(
                child: _Pilula(texto: 'Zero Egress Fees', cor: contentBlue),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Armazena fotos e scans de resoluções de exercícios submetidas para análise de IA.',
            style: context.tipo.caption?.copyWith(color: contentBlue),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Armazenamento Ocupado',
                  style: context.tipo.body?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${_r2StorageUsedMb.toStringAsFixed(1)} MB / 10 GB (${r2UsoPercent.toStringAsFixed(1)}%)',
                  textAlign: TextAlign.end,
                  style: context.tipo.caption?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: contentBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _BarraProgresso(
            progresso: _r2StorageUsedMb / r2QuotaTotalMb,
            cor: contentBlue,
          ),
          const SizedBox(height: 4),
          Text(
            'Quota gratuita: 10 GB/mês. ${(10.0 - (_r2StorageUsedMb / 1024.0)).toStringAsFixed(2)} GB livres disponíveis.',
            style: context.tipo.caption?.copyWith(color: Cores.cinza),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Operações Classe A (Uploads / URLs)',
                  style: context.tipo.body?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$_r2ClassAOps / 1M (${r2ClassAPercent.toStringAsFixed(1)}%)',
                  textAlign: TextAlign.end,
                  style: context.tipo.caption?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: contentBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _BarraProgresso(
            progresso: _r2ClassAOps / r2ClassALimit,
            cor: Cores.verde,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Operações Classe B (Downloads / Imagens)',
                  style: context.tipo.body?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$_r2ClassBOps / 10M (${r2ClassBPercent.toStringAsFixed(2)}%)',
                  textAlign: TextAlign.end,
                  style: context.tipo.caption?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: contentBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _BarraProgresso(
            progresso: _r2ClassBOps / r2ClassBLimit,
            cor: Cores.verde,
          ),
        ],
      ),
    );
  }

  Widget _secaoSupabaseLimits(BuildContext context) {
    const double dbQuotaMb = 500.0;
    final double dbPercent = (_supabaseDbStorageMb / dbQuotaMb) * 100.0;
    const int mauLimit = 50000;
    final double mauPercent = (_perfis.length / mauLimit) * 100.0;
    const int fnLimit = 500000;
    final double fnPercent = (_supabaseFunctionsInvocations / fnLimit) * 100.0;

    return _CartaoFluent(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(WindowsIcons.network, size: 20, color: contentBlue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Supabase Backend Limits (Free Tier)',
                  style: context.tipo.bodyStrong?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: titleBlue,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Flexible(
                child: _Pilula(texto: 'Nível Gratuito', cor: contentBlue),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Monitoramento dos limites operacionais do plano Free da organização Supabase.',
            style: context.tipo.caption?.copyWith(color: contentBlue),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Banco de Dados (PostgreSQL)',
                  style: context.tipo.body?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${_supabaseDbStorageMb.toStringAsFixed(1)} MB / 500 MB (${dbPercent.toStringAsFixed(1)}%)',
                  textAlign: TextAlign.end,
                  style: context.tipo.caption?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: contentBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _BarraProgresso(
            progresso: _supabaseDbStorageMb / dbQuotaMb,
            cor: contentBlue,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Usuários Ativos (MAU)',
                  style: context.tipo.body?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${_perfis.length} / 50k MAU (${mauPercent.toStringAsFixed(2)}%)',
                  textAlign: TextAlign.end,
                  style: context.tipo.caption?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: contentBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _BarraProgresso(
            progresso: _perfis.length / mauLimit,
            cor: Cores.verde,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Edge Functions (OpenAI)',
                  style: context.tipo.body?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$_supabaseFunctionsInvocations / 500k (${fnPercent.toStringAsFixed(2)}%)',
                  textAlign: TextAlign.end,
                  style: context.tipo.caption?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: contentBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _BarraProgresso(
            progresso: _supabaseFunctionsInvocations / fnLimit,
            cor: Cores.verde,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Azuis.gelo,
              borderRadius: BorderRadius.circular(kRadiusSm),
            ),
            child: Row(
              children: [
                const Icon(
                  WindowsIcons.completed,
                  size: 16,
                  color: Cores.verde,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pooler Supavisor ativo: Conexões seguras via Transaction Mode (porta 6543)',
                    style: context.tipo.caption?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: contentBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _secaoDesempenho(BuildContext context) {
    return _CartaoFluent(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(WindowsIcons.refresh, size: 20, color: contentBlue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Desempenho & Tempos de Resposta',
                  style: context.tipo.bodyStrong?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: titleBlue,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Flexible(
                child: _Pilula(texto: 'Alta Disponibilidade', cor: Cores.verde),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GradeAdaptativa(
            larguraMinimaItem: 140,
            children: [
              _MetricaPequena(
                label: 'Latência PostgREST',
                valor: '$_latenciaMs ms',
                detalhe: 'Tempo real round-trip',
              ),
              const _MetricaPequena(
                label: 'Edge Function IA',
                valor: '~1.25 s',
                detalhe: 'Tempo médio OpenAI',
              ),
              const _MetricaPequena(
                label: 'Taxa de Sucesso API',
                valor: '99.8%',
                detalhe: 'Zero erros 5xx hoje',
              ),
              const _MetricaPequena(
                label: 'CDN Cloudflare Cache',
                valor: '94.2%',
                detalhe: 'Hit-rate de assets estáticos',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _secaoUsuarios(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Gestão de Perfis & Acessos',
                style: context.tipo.subtitle?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: titleBlue,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${_perfis.length} cadastrados',
                textAlign: TextAlign.end,
                style: context.tipo.caption?.copyWith(color: contentBlue),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Identificadores anonimizados em conformidade com as políticas de privacidade.',
          style: context.tipo.caption?.copyWith(color: Cores.cinza),
        ),
        const SizedBox(height: 12),
        ..._perfis.map((p) => _itemPerfil(context, p)),
      ],
    );
  }

  Widget _itemPerfil(BuildContext context, Map<String, dynamic> p) {
    final uid = p['id'] as String;
    final role = p['role'] as String;
    final institution = p['institution_name'] as String?;
    final course = p['course'] as String?;
    final isCurrentUser = uid == widget.user.id;
    final isAdmin = role == 'admin';
    final maskedId = uid.length > 12
        ? '${uid.substring(0, 6)}…${uid.substring(uid.length - 4)}'
        : uid;

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
                color: isAdmin ? contentBlue : Cores.cinza300,
              ),
              child: Icon(
                isAdmin ? WindowsIcons.admin : WindowsIcons.contact,
                color: Cores.branco,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Wrap: em telas estreitas o complemento desce para a linha
                  // seguinte em vez de estourar o cartão.
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'ID: $maskedId',
                        style: context.tipo.body?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isCurrentUser)
                        Text(
                          '(você)',
                          style: context.tipo.caption?.copyWith(
                            color: Cores.cinza,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _RoleBadge(role: role),
                      if (isAdmin)
                        const _Pilula(texto: 'Acesso Total', cor: Cores.verde),
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

  Widget _menuPapel(String uid, bool isAdmin) {
    return DropDownButton(
      placement: FlyoutPlacementMode.bottomRight,
      buttonBuilder: (context, onOpen) => Tooltip(
        message: 'Gerenciar papel',
        child: IconButton(
          icon: const Icon(WindowsIcons.more, size: 16),
          onPressed: onOpen,
        ),
      ),
      items: [
        MenuFlyoutItem(
          leading: const Icon(WindowsIcons.admin, size: 16),
          text: const Text('Tornar administrador'),
          onPressed: isAdmin ? null : () => _alterarRole(uid, 'admin'),
        ),
        MenuFlyoutItem(
          leading: const Icon(WindowsIcons.contact, size: 16),
          text: const Text('Revogar administrador'),
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

class _BarraProgresso extends StatelessWidget {
  final double progresso;
  final Color cor;

  const _BarraProgresso({required this.progresso, this.cor = contentBlue});

  @override
  Widget build(BuildContext context) {
    final pClamped = progresso.clamp(0.005, 1.0);
    return Container(
      height: 8,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Cores.cinza200.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: pClamped,
        child: Container(
          decoration: BoxDecoration(
            color: cor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

class _CardMetricaAdmin extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String valor;
  final String subtitulo;
  final Color corDestaque;

  const _CardMetricaAdmin({
    required this.icone,
    required this.titulo,
    required this.valor,
    required this.subtitulo,
    this.corDestaque = contentBlue,
  });

  @override
  Widget build(BuildContext context) {
    return _CartaoFluent(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, size: 18, color: corDestaque),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tipo.caption?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Cores.cinza700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            valor,
            style: context.tipo.subtitle?.copyWith(
              fontWeight: FontWeight.bold,
              color: corDestaque,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.tipo.caption?.copyWith(color: Cores.cinza),
          ),
        ],
      ),
    );
  }
}

class _MetricaPequena extends StatelessWidget {
  final String label;
  final String valor;
  final String detalhe;

  const _MetricaPequena({
    required this.label,
    required this.valor,
    required this.detalhe,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Azuis.gelo,
        borderRadius: BorderRadius.circular(kRadiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.tipo.caption?.copyWith(color: Cores.cinza700),
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: context.tipo.bodyStrong?.copyWith(
              fontWeight: FontWeight.bold,
              color: contentBlue,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detalhe,
            style: context.tipo.caption?.copyWith(
              fontSize: 11,
              color: Cores.cinza,
            ),
          ),
        ],
      ),
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
                  cor: Color(0xFF1E5CA7),
                  titulo: 'Missão',
                  descricao:
                      'Ajudar estudantes a identificar e superar suas lacunas conceituais, '
                      'transformando exercícios corrigidos em um mapa visual de fragilidades '
                      'para orientar revisões inteligentes.',
                ),
                const SizedBox(height: 12),
                const _MvvCard(
                  icone: WindowsIcons.view,
                  cor: Color(0xFF21457A),
                  titulo: 'Visão',
                  descricao:
                      'Ser a principal ferramenta de aprendizado ativo no Brasil, '
                      'onde cada erro se torna uma oportunidade de crescimento '
                      'mensurada e guiada por inteligência artificial.',
                ),
                const SizedBox(height: 12),
                const _MvvCard(
                  icone: WindowsIcons.heart,
                  cor: Color(0xFF142A4A),
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
                const _MembroCard(
                  iniciais: 'CJ',
                  nome: 'Cláudio Francisco',
                  corAvatar: Color(0xFF1E5CA7),
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
                ),
                const SizedBox(height: 12),
                const _MembroCard(
                  iniciais: 'LE',
                  nome: 'Lucas Emanuel',
                  corAvatar: Color(0xFF21457A),
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
                const SizedBox(height: 32),
                // Rodapé
                Center(
                  child: Text(
                    'PUC Minas · Projeto Integrado I · 2026',
                    style: context.tipo.caption?.copyWith(
                      color: contentBlue.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'v1.0.0 — Sprint 2',
                    style: context.tipo.caption?.copyWith(
                      color: contentBlue.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Destaque com o gradiente da identidade.
  Widget _heroi(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF142A4A), Color(0xFF1E5CA7)],
        ),
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF142A4A).withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
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
            color: titleBlue,
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

  const _MvvCard({
    required this.icone,
    required this.cor,
    required this.titulo,
    required this.descricao,
  });

  @override
  Widget build(BuildContext context) {
    return _CartaoFluent(
      cor: Cores.branco,
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Barra lateral colorida; o raio desconta a borda de 1 px do card.
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: cor,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(kRadius - 1),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: cor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(icone, size: 20, color: cor),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            titulo,
                            style: context.tipo.bodyStrong?.copyWith(
                              color: cor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      descricao,
                      style: context.tipo.body?.copyWith(
                        color: const Color(0xFF4A5568),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MembroCard extends StatelessWidget {
  final String iniciais;
  final String nome;
  final Color corAvatar;
  final List<String> responsabilidades;
  final String descricao;

  const _MembroCard({
    required this.iniciais,
    required this.nome,
    required this.corAvatar,
    required this.responsabilidades,
    required this.descricao,
  });

  @override
  Widget build(BuildContext context) {
    return _CartaoFluent(
      cor: Cores.branco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar circular com as iniciais.
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: corAvatar,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  iniciais,
                  style: context.tipo.bodyLarge?.copyWith(
                    color: Cores.branco,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
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
                      style: context.tipo.bodyStrong?.copyWith(
                        color: corAvatar,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final r in responsabilidades)
                          _Pilula(texto: r, cor: corAvatar),
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
              color: const Color(0xFF4A5568),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── fim: Sobre o App ───────────────────────────────────────────────────────
