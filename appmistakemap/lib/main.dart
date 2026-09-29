import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Cores da identidade visual ──────────────────────────────────────────────
const Color titleBlue = Color.fromARGB(255, 30, 92, 167);
const Color contentBlue = Color.fromARGB(255, 33, 69, 114);

// ─── Fluent UI + Liquid Glass — tokens ───────────────────────────────────────
const Color kGlassBg        = Color(0xCCFFFFFF);   // branco 80 %
const Color kGlassBorder    = Color(0xB3FFFFFF);   // borda 70 %
const Color kScaffoldBg     = Color(0xFFE8EFF2);   // fundo ligeiramente azulado
const double kRadius        = 16;
const double kRadiusSm      = 10;

// gradiente de fundo para realçar o efeito glass
const BoxDecoration kBgGradient = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFDDE8EE), Color(0xFFEBF3EF), Color(0xFFE4EBF0)],
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

// ─── Modelo de usuário com papel (role) ──────────────────────────────────────
class AppUser {
  final String id;
  final String email;
  final String role;

  const AppUser({
    required this.id,
    required this.email,
    required this.role,
  });

  bool get isAdmin => role == 'admin';
}

// Carrega o perfil do Supabase e constrói um AppUser
Future<AppUser> _carregarPerfil(User supaUser) async {
  try {
    final data = await _db
        .from('profiles')
        .select('role')
        .eq('id', supaUser.id)
        .maybeSingle();
    return AppUser(
      id: supaUser.id,
      email: supaUser.email ?? '',
      role: data?['role'] as String? ?? 'user',
    );
  } catch (_) {
    return AppUser(id: supaUser.id, email: supaUser.email ?? '', role: 'user');
  }
}

// ─── Entry point ─────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey); // ignore: deprecated_member_use
  runApp(const MistakeMapApp());
}

class MistakeMapApp extends StatelessWidget {
  const MistakeMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MistakeMap',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: contentBlue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6F4),
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
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
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
  final _listaKey = GlobalKey<_TelaPrincipalState>();
  final _mapaKey = GlobalKey<_TelaMapaConceitualState>();

  void _irParaExercicios() {
    setState(() => _indiceAtual = 1);
    _listaKey.currentState?.carregarExercicios();
  }

  List<Widget> get _telas => [
        TelaInicial(user: widget.user),
        TelaPrincipal(key: _listaKey, user: widget.user),
        TelaMapaConceitual(key: _mapaKey, user: widget.user),
        TelaAdicionarExercicio(user: widget.user, onIrParaMapa: _irParaExercicios),
        if (widget.user.isAdmin) TelaAdmin(user: widget.user),
      ];

  List<NavigationDestination> get _destinos => [
        const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Início',
        ),
        const NavigationDestination(
          icon: Icon(Icons.list_alt_outlined),
          selectedIcon: Icon(Icons.list_alt),
          label: 'Exercícios',
        ),
        const NavigationDestination(
          icon: Icon(Icons.account_tree_outlined),
          selectedIcon: Icon(Icons.account_tree),
          label: 'Mapa',
        ),
        const NavigationDestination(
          icon: Icon(Icons.add_circle_outline),
          selectedIcon: Icon(Icons.add_circle),
          label: 'Adicionar',
        ),
        if (widget.user.isAdmin)
          const NavigationDestination(
            icon: Icon(Icons.admin_panel_settings_outlined),
            selectedIcon: Icon(Icons.admin_panel_settings),
            label: 'Admin',
          ),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kScaffoldBg,
      extendBody: true,
      body: IndexedStack(index: _indiceAtual, children: _telas),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xB3E7EBE8),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.55),
                  width: 0.6,
                ),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _indiceAtual,
              onDestinationSelected: (i) {
                setState(() => _indiceAtual = i);
                if (i == 1) _listaKey.currentState?.carregarExercicios();
                if (i == 2) _mapaKey.currentState?.carregar();
              },
              backgroundColor: Colors.transparent,
              indicatorColor:
                  contentBlue.withValues(alpha: 0.18),
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              destinations: _destinos,
            ),
          ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: erro ? Colors.red.shade700 : contentBlue,
      ),
    );
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
        final res =
            await _db.auth.signUp(email: email, password: senha);
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
    if (msg.contains('Invalid login credentials')) return 'E-mail ou senha incorretos.';
    if (msg.contains('Email not confirmed')) return 'Confirme seu e-mail antes de entrar.';
    if (msg.contains('User already registered')) return 'Este e-mail já possui uma conta.';
    return msg;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),
              const Text(
                'MistakeMap',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: titleBlue,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Transforme erros em aprendizado',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: contentBlue),
              ),
              const SizedBox(height: 40),
              // Campo de e-mail
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'email@dominio.com',
                  hintStyle: const TextStyle(color: contentBlue),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: contentBlue),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Campo de senha
              TextField(
                controller: _senhaCtrl,
                obscureText: !_senhaVisivel,
                decoration: InputDecoration(
                  hintText: 'senha',
                  hintStyle: const TextStyle(color: contentBlue),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: contentBlue),
                  ),
                  suffixIcon: IconButton(
                    tooltip: _senhaVisivel ? 'Ocultar senha' : 'Mostrar senha',
                    icon: Icon(_senhaVisivel
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _senhaVisivel = !_senhaVisivel),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Botão principal
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: contentBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _carregando ? null : _entrarComEmailSenha,
                child: _carregando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        _modoCadastro ? 'Criar conta' : 'Entrar',
                        style: const TextStyle(fontSize: 16),
                      ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    setState(() => _modoCadastro = !_modoCadastro),
                child: Text(
                  _modoCadastro
                      ? 'Já tenho conta — Entrar'
                      : 'Não tenho conta — Criar',
                  style: const TextStyle(color: contentBlue),
                ),
              ),
              const SizedBox(height: 16),
              // Divisor "ou"
              const Row(
                children: [
                  Expanded(
                      child: Divider(thickness: 1, color: contentBlue)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('ou',
                        style: TextStyle(color: contentBlue)),
                  ),
                  Expanded(
                      child: Divider(thickness: 1, color: contentBlue)),
                ],
              ),
              const SizedBox(height: 16),
              // Botão Google
              ElevatedButton.icon(
                icon: const Icon(Icons.g_mobiledata, size: 30),
                label: const Text('Continue com Google'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                  foregroundColor: contentBlue,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: contentBlue),
                  ),
                ),
                onPressed: _carregando ? null : _entrarComGoogle,
              ),
              const SizedBox(height: 40),
              RichText(
                textAlign: TextAlign.center,
                text: const TextSpan(
                  style: TextStyle(color: contentBlue, fontSize: 12),
                  children: [
                    TextSpan(
                        text:
                            'Ao continuar, você concorda com nossos '),
                    TextSpan(
                      text: 'Termos de Serviço\n',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: 'e '),
                    TextSpan(
                      text: 'Política de Privacidade',
                      style: TextStyle(
                          color: titleBlue,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
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
  const TelaInicial({super.key, required this.user});

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

  Future<void> _carregarEstatisticas() async {
    try {
      final res = await _db
          .from('attempts')
          .select('status')
          .eq('user_id', widget.user.id);

      final lista = res as List;
      final total = lista.length;
      final pendentes = lista
          .where((a) =>
              a['status'] == 'pending' || a['status'] == 'uploading')
          .length;
      final completos =
          lista.where((a) => a['status'] == 'completed').length;
      final pct = total > 0
          ? '${((completos / total) * 100).round()}%'
          : '0%';

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
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Início — Resumo'),
        backgroundColor: Colors.transparent,
        foregroundColor: titleBlue,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: const BoxDecoration(color: Color(0xAAE8EFF2)),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: _sair,
          ),
        ],
      ),
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: kBgGradient,
        child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
          children: [
            // Cabeçalho com nome/email e badge de admin
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'MistakeMap',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: titleBlue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.user.email,
                      style: const TextStyle(
                          fontSize: 13, color: contentBlue),
                    ),
                    if (widget.user.isAdmin) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 3),
                        decoration: BoxDecoration(
                          color: contentBlue,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Administrador',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Cards de estatísticas
            Center(
              child: _carregando
                  ? const CircularProgressIndicator()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment:
                            CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Dashboard do Estudante',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                              color: titleBlue,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Acompanhe seu progresso e transforme erros em aprendizado.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 16, color: contentBlue),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              _ResumoCard(
                                  label: 'Exercícios',
                                  value: '$_totalExercicios'),
                              const SizedBox(width: 10),
                              _ResumoCard(
                                  label: 'Para revisar',
                                  value: '$_paraRevisar'),
                              const SizedBox(width: 10),
                              _ResumoCard(
                                  label: 'Evolução',
                                  value: _evolucao),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
            // Botão "Sobre o App"
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.info_outline),
                  style: OutlinedButton.styleFrom(
                    textStyle: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w500),
                    backgroundColor: const Color(0xFFE7EBE8),
                    foregroundColor: contentBlue,
                    padding: const EdgeInsets.symmetric(
                        vertical: 18, horizontal: 24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: contentBlue),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const TelaSobre()),
                  ),
                  label: const Text('Sobre o App',
                      style: TextStyle(fontSize: 17)),
                ),
              ),
            ),
          ],
        ),
            ),
          ],
        ),
        ), // SafeArea
      ), // Container gradient
    );
  }
}

class _ResumoCard extends StatelessWidget {
  const _ResumoCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: _GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        radius: kRadiusSm,
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: contentBlue,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: contentBlue),
            ),
          ],
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
  const TelaAdicionarExercicio({super.key, required this.user, this.onIrParaMapa});

  @override
  State<TelaAdicionarExercicio> createState() =>
      _TelaAdicionarExercicioState();
}

class _TelaAdicionarExercicioState
    extends State<TelaAdicionarExercicio> {
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
        source: source, imageQuality: 85, maxWidth: 2048);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    if (!mounted) return;
    setState(() {
      _imagemSelecionada = img;
      _imagemBytes = bytes;
    });
  }

  Future<void> _mostrarOpcoesDeImagem() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar uma foto'),
              onTap: () =>
                  Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher da galeria'),
              onTap: () =>
                  Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _selecionarImagem(source);
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: erro ? Colors.red.shade700 : contentBlue,
      ),
    );
  }

  Future<void> _continuar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _enviando = true);

    try {
      final assunto = _assuntoCtrl.text.trim();
      final descricao = _erroCtrl.text.trim();

      // 1. Busca ou cria o assunto (subject) do usuário
      final subjectId = await _obterOuCriarSubject(assunto);

      // 2. Cria o exercício
      final exRes = await _db
          .from('exercises')
          .insert({
            'subject_id': subjectId,
            'prompt_text': descricao,
          })
          .select('id')
          .single();
      final exerciseId = exRes['id'] as String;

      // 3. Cria a tentativa (attempt)
      final attRes = await _db
          .from('attempts')
          .insert({
            'exercise_id': exerciseId,
            'user_id': widget.user.id,
            'solution_text': descricao,
            'status': _imagemBytes != null ? 'uploading' : 'pending',
          })
          .select('id')
          .single();
      final attemptId = attRes['id'] as String;

      // 4. Se há imagem, faz upload para R2 via Edge Function
      if (_imagemBytes != null && _imagemSelecionada != null) {
        await _uploadImagem(attemptId);
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
      _snack('Erro ao registrar: $e', erro: true);
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

  Future<void> _uploadImagem(String attemptId) async {
    final ext = _imagemSelecionada!.name
        .split('.')
        .last
        .toLowerCase();

    // Chama a Edge Function para obter URL presigned da R2
    final fnRes = await _db.functions
        .invoke('upload-url', body: {'file_ext': ext});

    if (fnRes.status >= 400) {
      throw Exception(
          'upload-url retornou status ${fnRes.status}');
    }

    final data = fnRes.data as Map<String, dynamic>;
    final uploadUrl = data['upload_url'] as String;
    final objectPath = data['object_path'] as String;

    // PUT dos bytes da imagem para o URL presigned
    final putRes = await http.put(
      Uri.parse(uploadUrl),
      headers: {'Content-Type': 'image/$ext'},
      body: _imagemBytes,
    );

    if (putRes.statusCode >= 400) {
      throw Exception(
          'Upload para R2 falhou: HTTP ${putRes.statusCode}');
    }

    // Registra o asset e atualiza o status da attempt
    await _db.from('attempt_assets').insert({
      'attempt_id': attemptId,
      'object_path': objectPath,
      'sha256': 'pending',
    });

    await _db
        .from('attempts')
        .update({'status': 'pending'})
        .eq('id', attemptId);
  }

  void _resetarParaForm() {
    setState(() => _sucesso = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_sucesso ? 'Registrado!' : 'Adicionar exercício'),
        backgroundColor: const Color(0xFFE7EBE8),
        foregroundColor: titleBlue,
      ),
      backgroundColor: const Color(0xFFF4F6F4),
      body: SafeArea(
        child: _sucesso ? _buildSucesso() : _buildForm(),
      ),
    );
  }

  Widget _buildSucesso() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline,
                  size: 72, color: Colors.green),
            ),
            const SizedBox(height: 24),
            const Text(
              'Exercício registrado!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: titleBlue),
            ),
            const SizedBox(height: 10),
            if (_ultimoAssunto.isNotEmpty)
              Text(
                'Assunto: $_ultimoAssunto',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: contentBlue),
              ),
            const SizedBox(height: 8),
            const Text(
              'Continue registrando para mapear seus padrões de erro.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: contentBlue),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Registrar outro'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: contentBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _resetarParaForm,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Ver no Mapa'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: contentBlue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: contentBlue),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  _resetarParaForm();
                  widget.onIrParaMapa?.call();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Registre um erro para acompanhar sua evolução.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, color: contentBlue),
            ),
            const SizedBox(height: 28),
            TextFormField(
              controller: _assuntoCtrl,
              decoration: const InputDecoration(
                labelText: 'Assunto',
                hintText: 'Ex.: Equações de segundo grau',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Informe o assunto' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _erroCtrl,
              minLines: 4,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'O que você errou?',
                hintText: 'Descreva brevemente sua dificuldade',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
                alignLabelWithHint: true,
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Descreva o erro' : null,
            ),
            const SizedBox(height: 24),
            if (_imagemBytes == null)
              OutlinedButton.icon(
                onPressed: _mostrarOpcoesDeImagem,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Adicionar foto do exercício'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: contentBlue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: contentBlue),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(_imagemBytes!,
                        height: 220, fit: BoxFit.cover),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _imagemSelecionada = null;
                      _imagemBytes = null;
                    }),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remover imagem'),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _enviando ? null : _continuar,
              icon: _enviando
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check),
              label: Text(_enviando ? 'Enviando…' : 'Registrar exercício'),
              style: ElevatedButton.styleFrom(
                backgroundColor: contentBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 17),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: contentBlue),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Mapa conceitual ─────────────────────────────────────────────────────────
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

// ─── fim: Tela de adicionar exercício ────────────────────────────────────────

// ─── Mapa conceitual ──────────────────────────────────────────────────────────
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
        if (mounted) setState(() { _stats = []; _carregando = false; });
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

      if (mounted) setState(() { _stats = lista; _carregando = false; });
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  int get _totalExercicios => _stats.fold(0, (s, d) => s + d.total);
  int get _totalConcluidos => _stats.fold(0, (s, d) => s + d.concluidos);
  int get _totalAtencao => _stats.fold(0, (s, d) => s + d.atencao);
  int get _maxTotal => _stats.isEmpty ? 1 : _stats.map((s) => s.total).reduce((a, b) => a > b ? a : b);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Mapa Conceitual'),
        backgroundColor: Colors.transparent,
        foregroundColor: titleBlue,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(color: const Color(0xAAE8EFF2)),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: carregar,
          ),
        ],
      ),
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: kBgGradient,
        child: Column(
          children: [
            Expanded(
              child: _carregando
                  ? const Center(child: CircularProgressIndicator())
                  : _stats.isEmpty
                      ? _buildVazio()
                      : RefreshIndicator(
                          onRefresh: carregar,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 16, 16, 16),
                            children: [
                              _buildResumo(),
                              const SizedBox(height: 16),
                              _buildGrafo(),
                              const SizedBox(height: 16),
                              _buildPorAssunto(),
                              const SizedBox(height: 16),
                              _buildFragilidades(),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
            ),
            if (kModoDemo) const _BannerDemo(),
          ],
        ),
      ),
    );
  }

  Widget _buildVazio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined,
                size: 72, color: contentBlue.withValues(alpha: 0.35)),
            const SizedBox(height: 20),
            const Text('Nenhum dado ainda',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: titleBlue)),
            const SizedBox(height: 8),
            const Text(
              'Adicione exercícios para visualizar seu mapa conceitual.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: contentBlue),
            ),
          ],
        ),
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
                cor: contentBlue)),
        const SizedBox(width: 8),
        Expanded(
            child: _StatCard(
                valor: _totalConcluidos.toString(),
                label: 'Concluídos',
                cor: Colors.green.shade600)),
        const SizedBox(width: 8),
        Expanded(
            child: _StatCard(
                valor: _totalAtencao.toString(),
                label: 'Atenção',
                cor: Colors.orange.shade700)),
      ],
    );
  }

  Widget _buildGrafo() {
    final maxT = _maxTotal.toDouble();
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Grafo por assunto',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: titleBlue,
                    letterSpacing: 0.5)),
            const SizedBox(height: 2),
            const Text('Tamanho = quantidade · Cor = % concluído',
                style: TextStyle(fontSize: 11, color: contentBlue)),
            const SizedBox(height: 16),
            Center(
              child: Wrap(
                spacing: 14,
                runSpacing: 18,
                alignment: WrapAlignment.center,
                children: _stats.map((s) {
                  final size = 56.0 + (s.total / maxT) * 28.0;
                  final color = Color.lerp(
                      Colors.red.shade400, Colors.green.shade500, s.taxaConclusao)!;
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
                                spreadRadius: 1),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${(s.taxaConclusao * 100).round()}%',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold),
                            ),
                            if (size > 66)
                              Text(
                                '${s.total} ex.',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 10),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 5),
                      SizedBox(
                        width: size + 10,
                        child: Text(
                          s.nome,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11,
                              color: contentBlue,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _MapaLegenda(cor: Colors.red.shade400, texto: '0%'),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.red.shade400,
                        Colors.orange,
                        Colors.green.shade500,
                      ]),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _MapaLegenda(cor: Colors.green.shade500, texto: '100%'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPorAssunto() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Evolução por assunto',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: titleBlue,
                    letterSpacing: 0.5)),
            const SizedBox(height: 12),
            ..._stats.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SubjectBar(data: s),
                )),
            const SizedBox(height: 4),
            Row(
              children: [
                _MapaLegenda(cor: Colors.green.shade500, texto: 'Concluído'),
                const SizedBox(width: 10),
                _MapaLegenda(cor: Colors.orange.shade400, texto: 'Pendente'),
                const SizedBox(width: 10),
                _MapaLegenda(cor: Colors.red.shade400, texto: 'Erro'),
                const SizedBox(width: 10),
                _MapaLegenda(cor: Colors.grey.shade300, texto: 'Sem tentativa'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFragilidades() {
    final fragilidades = [..._stats]
      ..sort((a, b) => a.taxaConclusao.compareTo(b.taxaConclusao));
    final top = fragilidades.where((s) => s.taxaConclusao < 1.0).take(3).toList();

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.warning_amber_outlined, size: 18, color: Colors.orange),
                SizedBox(width: 6),
                Text('Principais fragilidades',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: titleBlue,
                        letterSpacing: 0.5)),
              ],
            ),
            const SizedBox(height: 12),
            if (top.isEmpty)
              const Row(
                children: [
                  Icon(Icons.emoji_events, color: Colors.amber),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Parabéns! Todos os exercícios foram concluídos.',
                      style: TextStyle(color: contentBlue, fontSize: 14),
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
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Text(emojis[i], style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.nome,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: titleBlue,
                                    fontSize: 14)),
                            Text(
                              '${s.atencao} de ${s.total} precisam de atenção',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${(s.taxaConclusao * 100).round()}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: s.taxaConclusao < 0.5
                              ? Colors.red.shade600
                              : Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String valor;
  final String label;
  final Color cor;
  const _StatCard({required this.valor, required this.label, required this.cor});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      radius: kRadiusSm,
      child: Column(
        children: [
          Text(valor,
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.bold, color: cor)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: cor.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

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
              child: Text(data.nome,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: contentBlue)),
            ),
            Text('${data.concluidos}/${data.total}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                if (data.concluidos > 0)
                  Expanded(
                      flex: data.concluidos,
                      child: Container(color: Colors.green.shade500)),
                if (data.pendentes > 0)
                  Expanded(
                      flex: data.pendentes,
                      child: Container(color: Colors.orange.shade400)),
                if (data.erros > 0)
                  Expanded(
                      flex: data.erros,
                      child: Container(color: Colors.red.shade400)),
                if (data.semTentativa > 0)
                  Expanded(
                      flex: data.semTentativa,
                      child: Container(color: Colors.grey.shade300)),
                if (total == 1 && data.total == 0)
                  Expanded(child: Container(color: Colors.grey.shade200)),
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
            decoration: BoxDecoration(color: cor, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(texto, style: const TextStyle(fontSize: 11, color: contentBlue)),
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
        if (mounted) setState(() { _exercicios = []; _carregando = false; });
        return;
      }

      final exRes = await _db
          .from('exercises')
          .select('id, prompt_text, created_at, subject_id, attempts(id, status, user_id)')
          .inFilter('subject_id', subjectMap.keys.toList())
          .order('created_at', ascending: false);

      final lista = <Exercicio>[];
      for (final e in (exRes as List)) {
        final userAttempts = ((e['attempts'] as List?) ?? [])
            .where((a) => a['user_id'] == widget.user.id)
            .toList();
        final latest = userAttempts.isNotEmpty ? userAttempts.first : null;
        lista.add(Exercicio(
          id: e['id'] as String,
          subjectId: e['subject_id'] as String,
          subjectName: subjectMap[e['subject_id']] ?? '—',
          promptText: e['prompt_text'] as String? ?? '',
          status: latest?['status'] as String? ?? 'sem_tentativa',
          attemptId: latest?['id'] as String?,
          createdAt: e['created_at'] != null
              ? DateTime.tryParse(e['created_at'] as String)
              : null,
        ));
      }

      if (mounted) setState(() { _exercicios = lista; _carregando = false; });
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _confirmarExclusao(Exercicio ex) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir exercício'),
        content: Text(
          'Excluir o exercício de "${ex.subjectName}"?\n'
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _excluir(ex);
  }

  Future<void> _excluir(Exercicio ex) async {
    try {
      if (ex.attemptId != null) {
        await _db.from('attempt_assets').delete().eq('attempt_id', ex.attemptId!);
      }
      await _db.from('attempts').delete()
          .eq('exercise_id', ex.id)
          .eq('user_id', widget.user.id);
      await _db.from('exercises').delete().eq('id', ex.id);
      final rem = await _db.from('exercises').select('id').eq('subject_id', ex.subjectId);
      if ((rem as List).isEmpty) {
        await _db.from('subjects').delete().eq('id', ex.subjectId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exercício excluído.'), backgroundColor: contentBlue),
      );
      carregarExercicios();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao excluir: $e'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Meus Exercícios'),
        backgroundColor: Colors.transparent,
        foregroundColor: titleBlue,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(color: const Color(0xAAE8EFF2)),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: carregarExercicios,
          ),
        ],
      ),
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: kBgGradient,
        child: Column(
        children: [
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _exercicios.isEmpty
                    ? const _MapaVazio()
                    : RefreshIndicator(
                        onRefresh: carregarExercicios,
                        child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _exercicios.length,
                    itemBuilder: (_, i) {
                      final ex = _exercicios[i];
                      return _ExercicioCard(
                        exercicio: ex,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TelaDetalheExercicio(
                                exercicio: ex,
                                user: widget.user,
                                onAtualizar: carregarExercicios,
                              ),
                            ),
                          );
                          carregarExercicios();
                        },
                        onEditar: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TelaEditarExercicio(
                                exercicio: ex,
                                user: widget.user,
                              ),
                            ),
                          );
                          carregarExercicios();
                        },
                        onExcluir: () => _confirmarExclusao(ex),
                      );
                    },
                  ),
                ),
          ),
        ],
        ), // Column
      ), // Container gradient
    );
  }
}

// ─── Glass card (Fluent UI + Liquid Glass) ────────────────────────────────────
class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;

  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = kRadius,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: kGlassBg,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: kGlassBorder, width: 0.8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 20,
                spreadRadius: 0,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: child,
        ),
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
      color: Colors.red.shade600,
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: const Text(
        '⚠ Demonstração',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _MapaVazio extends StatelessWidget {
  const _MapaVazio();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined,
                size: 72, color: contentBlue.withValues(alpha: 0.4)),
            const SizedBox(height: 20),
            const Text(
              'Seu mapa ainda está vazio',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: titleBlue),
            ),
            const SizedBox(height: 12),
            const Text(
              'Adicione exercícios para identificar suas fragilidades conceituais.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: contentBlue),
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
      child: _GlassCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(kRadius),
          onTap: onTap,
          child: Padding(
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
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: titleBlue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusBadge(status: exercicio.status),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      exercicio.promptText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: contentBlue),
                    ),
                    if (exercicio.createdAt != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _fmtData(exercicio.createdAt!),
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: contentBlue, size: 20),
                tooltip: 'Opções',
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'ver',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.visibility_outlined),
                      title: Text('Ver detalhes'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'editar',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Editar'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'excluir',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline, color: Colors.red),
                      title: Text('Excluir',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ),
                ],
                onSelected: (v) {
                  if (v == 'ver') onTap();
                  if (v == 'editar') onEditar();
                  if (v == 'excluir') onExcluir();
                },
              ),
            ],
          ),
        ),
        ), // _GlassCard
      ), // Padding
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
        cor = Colors.green.shade600;
      case 'pending':
        label = 'Pendente';
        cor = Colors.orange.shade700;
      case 'uploading':
        label = 'Enviando';
        cor = Colors.blue.shade600;
      case 'error':
        label = 'Erro';
        cor = Colors.red.shade600;
      default:
        label = 'Sem tentativa';
        cor = Colors.grey.shade500;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cor.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, color: cor, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ─── fim: Lista de exercícios ────────────────────────────────────────────────

// ─── Detalhe do exercício ─────────────────────────────────────────────────────
class TelaDetalheExercicio extends StatelessWidget {
  final Exercicio exercicio;
  final AppUser user;
  final VoidCallback onAtualizar;

  const TelaDetalheExercicio({
    super.key,
    required this.exercicio,
    required this.user,
    required this.onAtualizar,
  });

  String _fmtData(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';

  Future<void> _excluir(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir exercício'),
        content: Text(
          'Excluir o exercício de "${exercicio.subjectName}"?\n'
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      if (exercicio.attemptId != null) {
        await _db.from('attempt_assets').delete().eq('attempt_id', exercicio.attemptId!);
      }
      await _db.from('attempts').delete()
          .eq('exercise_id', exercicio.id)
          .eq('user_id', user.id);
      await _db.from('exercises').delete().eq('id', exercicio.id);
      final rem = await _db.from('exercises').select('id').eq('subject_id', exercicio.subjectId);
      if ((rem as List).isEmpty) {
        await _db.from('subjects').delete().eq('id', exercicio.subjectId);
      }
      if (!context.mounted) return;
      onAtualizar();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exercício excluído.'), backgroundColor: contentBlue),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao excluir: $e'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(exercicio.subjectName),
        backgroundColor: const Color(0xFFE7EBE8),
        foregroundColor: titleBlue,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TelaEditarExercicio(
                      exercicio: exercicio, user: user),
                ),
              );
              onAtualizar();
              if (context.mounted) Navigator.pop(context);
            },
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
            tooltip: 'Excluir',
            onPressed: () => _excluir(context),
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF4F6F4),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Status:',
                      style: TextStyle(
                          color: contentBlue, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  _StatusBadge(status: exercicio.status),
                ],
              ),
              if (exercicio.createdAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Adicionado em ${_fmtData(exercicio.createdAt!)}',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
              const SizedBox(height: 20),
              const Text('ASSUNTO',
                  style: TextStyle(
                      fontSize: 11,
                      color: contentBlue,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              _DetalheBox(child: Text(exercicio.subjectName,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: titleBlue))),
              const SizedBox(height: 16),
              const Text('DESCRIÇÃO DO ERRO',
                  style: TextStyle(
                      fontSize: 11,
                      color: contentBlue,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              _DetalheBox(child: Text(exercicio.promptText,
                  style: const TextStyle(
                      fontSize: 15, color: contentBlue, height: 1.5))),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar exercício'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: contentBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TelaEditarExercicio(
                            exercicio: exercicio, user: user),
                      ),
                    );
                    onAtualizar();
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                  label: Text('Excluir exercício',
                      style: TextStyle(color: Colors.red.shade400)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: Colors.red.shade300),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _excluir(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetalheBox extends StatelessWidget {
  final Widget child;
  const _DetalheBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: contentBlue.withValues(alpha: 0.25)),
      ),
      child: child,
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
    _assuntoCtrl =
        TextEditingController(text: widget.exercicio.subjectName);
    _erroCtrl =
        TextEditingController(text: widget.exercicio.promptText);
  }

  @override
  void dispose() {
    _assuntoCtrl.dispose();
    _erroCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: erro ? Colors.red.shade700 : contentBlue,
      ),
    );
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
                    .single())['id'] as String;

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
      _snack('Erro ao salvar: $e', erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar exercício'),
        backgroundColor: const Color(0xFFE7EBE8),
        foregroundColor: titleBlue,
      ),
      backgroundColor: const Color(0xFFF4F6F4),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Atualize as informações do exercício.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: contentBlue),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _assuntoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Assunto',
                    hintText: 'Ex.: Equações de segundo grau',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Informe o assunto'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _erroCtrl,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'O que você errou?',
                    hintText: 'Descreva brevemente sua dificuldade',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    alignLabelWithHint: true,
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Descreva o erro'
                      : null,
                ),
                const SizedBox(height: 28),
                ElevatedButton.icon(
                  onPressed: _salvando ? null : _salvar,
                  icon: _salvando
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check),
                  label: Text(_salvando ? 'Salvando…' : 'Salvar alterações'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: contentBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
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

// ─── fim: Editar exercício ───────────────────────────────────────────────────

// ─── Painel administrativo ────────────────────────────────────────────────────
class TelaAdmin extends StatefulWidget {
  final AppUser user;
  const TelaAdmin({super.key, required this.user});

  @override
  State<TelaAdmin> createState() => _TelaAdminState();
}

class _TelaAdminState extends State<TelaAdmin> {
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
          _erro = 'Falha ao carregar usuários: $e';
          _carregando = false;
        });
      }
    }
  }

  Future<void> _alterarRole(String userId, String novaRole) async {
    try {
      await _db
          .from('profiles')
          .update({'role': novaRole})
          .eq('id', userId);
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao alterar papel: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel Administrativo'),
        backgroundColor: const Color(0xFFE7EBE8),
        foregroundColor: titleBlue,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _carregar,
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF4F6F4),
      body: SafeArea(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_erro!,
                          style: const TextStyle(
                              color: Colors.red)),
                    ),
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            16, 16, 16, 8),
                        child: Row(
                          children: [
                            const Icon(Icons.group,
                                color: contentBlue),
                            const SizedBox(width: 8),
                            Text(
                              '${_perfis.length} usuário(s) cadastrado(s)',
                              style: const TextStyle(
                                fontSize: 15,
                                color: contentBlue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16),
                          itemCount: _perfis.length,
                          itemBuilder: (ctx, i) {
                            final p = _perfis[i];
                            final uid = p['id'] as String;
                            final role = p['role'] as String;
                            final institution =
                                p['institution_name'] as String?;
                            final course = p['course'] as String?;
                            final isCurrentUser =
                                uid == widget.user.id;
                            final isAdmin = role == 'admin';

                            return Card(
                              margin: const EdgeInsets.only(
                                  bottom: 10),
                              elevation: 1,
                              child: ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8),
                                leading: CircleAvatar(
                                  backgroundColor: isAdmin
                                      ? contentBlue
                                      : Colors.grey.shade300,
                                  child: Icon(
                                    isAdmin
                                        ? Icons
                                            .admin_panel_settings
                                        : Icons.person,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  // Mostra ID encurtado (email fica em auth.users, inacessível pelo client)
                                  'ID: ${uid.substring(0, 8)}…${uid.substring(uid.length - 4)}',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        _RoleBadge(role: role),
                                        if (isCurrentUser) ...[
                                          const SizedBox(width: 6),
                                          const Text(
                                            '(você)',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (institution != null ||
                                        course != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        [institution, course]
                                            .whereType<String>()
                                            .join(' · '),
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: isCurrentUser
                                    ? null
                                    : PopupMenuButton<String>(
                                        icon: const Icon(
                                            Icons.more_vert),
                                        tooltip: 'Gerenciar papel',
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                            value: 'admin',
                                            enabled: !isAdmin,
                                            child: const ListTile(
                                              dense: true,
                                              contentPadding:
                                                  EdgeInsets.zero,
                                              leading: Icon(Icons
                                                  .admin_panel_settings),
                                              title: Text(
                                                  'Tornar administrador'),
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'user',
                                            enabled: isAdmin,
                                            child: const ListTile(
                                              dense: true,
                                              contentPadding:
                                                  EdgeInsets.zero,
                                              leading:
                                                  Icon(Icons.person),
                                              title: Text(
                                                  'Revogar administrador'),
                                            ),
                                          ),
                                        ],
                                        onSelected: (novaRole) =>
                                            _alterarRole(
                                                uid, novaRole),
                                      ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == 'admin';
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isAdmin
            ? contentBlue.withValues(alpha: 0.15)
            : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        isAdmin ? 'Administrador' : 'Usuário',
        style: TextStyle(
          fontSize: 11,
          color: isAdmin ? contentBlue : Colors.grey.shade700,
          fontWeight: FontWeight.bold,
        ),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F4),
      body: CustomScrollView(
        slivers: [
          // ── Hero expandido ────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: const Color(0xFF142A4A),
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF142A4A),
                      Color(0xFF1E5CA7),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 32),
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 1.5),
                        ),
                        child: const Icon(Icons.map_outlined,
                            size: 40, color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'MistakeMap',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Transforme erros em aprendizado',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              title: const Text(
                'Sobre o MistakeMap',
                style: TextStyle(fontSize: 18, color: Colors.white),
              ),
              titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
            ),
          ),
          // ── Conteúdo rolável ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Missão, Visão, Valores
                  _SobreSecaoTitulo(titulo: 'Nossa Identidade'),
                  const SizedBox(height: 12),
                  _MvvCard(
                    icone: Icons.flag_outlined,
                    cor: const Color(0xFF1E5CA7),
                    titulo: 'Missão',
                    descricao:
                        'Ajudar estudantes a identificar e superar suas lacunas conceituais, '
                        'transformando exercícios corrigidos em um mapa visual de fragilidades '
                        'para orientar revisões inteligentes.',
                  ),
                  const SizedBox(height: 12),
                  _MvvCard(
                    icone: Icons.visibility_outlined,
                    cor: const Color(0xFF21457A),
                    titulo: 'Visão',
                    descricao:
                        'Ser a principal ferramenta de aprendizado ativo no Brasil, '
                        'onde cada erro se torna uma oportunidade de crescimento '
                        'mensurada e guiada por inteligência artificial.',
                  ),
                  const SizedBox(height: 12),
                  _MvvCard(
                    icone: Icons.diamond_outlined,
                    cor: const Color(0xFF142A4A),
                    titulo: 'Valores',
                    descricao:
                        '• Aprendizado contínuo acima de resultados imediatos\n'
                        '• Transparência no progresso do estudante\n'
                        '• Tecnologia acessível e centrada no ser humano\n'
                        '• Privacidade e respeito aos dados pessoais',
                  ),
                  const SizedBox(height: 32),
                  // Equipe
                  _SobreSecaoTitulo(titulo: 'A Equipe'),
                  const SizedBox(height: 12),
                  _MembroCard(
                    iniciais: 'CJ',
                    nome: 'Cláudio Francisco',
                    corAvatar: const Color(0xFF1E5CA7),
                    responsabilidades: const [
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
                  _MembroCard(
                    iniciais: 'LE',
                    nome: 'Lucas Emanuel',
                    corAvatar: const Color(0xFF21457A),
                    responsabilidades: const [
                      'Frontend',
                      'Design',
                      'UI/UX',
                    ],
                    descricao:
                        'Responsável pela experiência do usuário, design de '
                        'interfaces, prototipagem no Figma e implementação '
                        'das telas no Flutter.',
                  ),
                  const SizedBox(height: 32),
                  // Stack técnica
                  _SobreSecaoTitulo(titulo: 'Stack Tecnológica'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _TechChip(label: 'Flutter / Dart'),
                      _TechChip(label: 'Supabase Auth'),
                      _TechChip(label: 'PostgreSQL'),
                      _TechChip(label: 'Cloudflare R2'),
                      _TechChip(label: 'Edge Functions'),
                      _TechChip(label: 'Rust Worker'),
                      _TechChip(label: 'OCR'),
                      _TechChip(label: 'LLM'),
                    ],
                  ),
                  const SizedBox(height: 32),
                  // Rodapé
                  Center(
                    child: Text(
                      'PUC Minas · Projeto Integrado I · 2026',
                      style: TextStyle(
                          fontSize: 12,
                          color: contentBlue.withValues(alpha: 0.6)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'v1.0.0 — Sprint 2',
                      style: TextStyle(
                          fontSize: 11,
                          color: contentBlue.withValues(alpha: 0.4)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
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
          height: 22,
          decoration: BoxDecoration(
            color: titleBlue,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: titleBlue,
            letterSpacing: 0.3,
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: cor.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Barra lateral colorida
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: cor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
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
                        const SizedBox(width: 10),
                        Text(
                          titulo,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: cor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      descricao,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF4A5568),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: corAvatar.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: corAvatar,
                child: Text(
                  iniciais,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: corAvatar,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: responsabilidades
                          .map((r) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: corAvatar.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: corAvatar.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  r,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: corAvatar,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 10),
          Text(
            descricao,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF4A5568),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _TechChip extends StatelessWidget {
  final String label;
  const _TechChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: contentBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: contentBlue.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: contentBlue,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── fim: Sobre o App ───────────────────────────────────────────────────────
