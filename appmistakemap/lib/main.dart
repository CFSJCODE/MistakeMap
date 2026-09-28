import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

const Color titleBlue = Color.fromARGB(255, 30, 92, 167);
const Color contentBlue = Color.fromARGB(255, 33, 69, 114);

final ValueNotifier<bool> cadastroConcluido = ValueNotifier<bool>(false);

void main() {
  runApp(const MistakeMapApp());
}

class MistakeMapApp extends StatelessWidget {
  const MistakeMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MistakeMap',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: contentBlue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6F4),
      ),
      initialRoute: '/inicial',
      routes: {
        '/cadastro': (context) => const TelaCadastro(),
        '/inicial': (context) => const TelaNavegacao(),
        '/adicionar': (context) => const TelaAdicionarExercicio(),
        '/principal': (context) => const TelaPrincipal(),
        '/sobre': (context) => const TelaSobre(),
      },
    );
  }
}

class TelaNavegacao extends StatefulWidget {
  const TelaNavegacao({super.key});

  @override
  State<TelaNavegacao> createState() => _TelaNavegacaoState();
}

class _TelaNavegacaoState extends State<TelaNavegacao> {
  int _indiceAtual = 0;

  final List<Widget> _telas = const [
    TelaInicial(),
    TelaPrincipal(),
    TelaAdicionarExercicio(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _indiceAtual, children: _telas),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indiceAtual,
        onDestinationSelected: (indice) {
          if (indice != 0 && !cadastroConcluido.value) {
            Navigator.pushNamed(context, '/cadastro');
            return;
          }

          setState(() {
            _indiceAtual = indice;
          });
        },
        backgroundColor: const Color(0xFFE7EBE8),
        indicatorColor: const Color.fromARGB(255, 33, 69, 114).withValues(alpha: 0.4),
        elevation: 2,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_tree_outlined),
            selectedIcon: Icon(Icons.account_tree),
            label: 'Mapa',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Adicionar',
          ),
        ],
      ),
    );
  }
}

// 1 TELA DE CADASTRO
class TelaCadastro extends StatefulWidget {
  const TelaCadastro({super.key});

  @override
  State<TelaCadastro> createState() => _TelaCadastroState();
}

class _TelaCadastroState extends State<TelaCadastro> {
  bool _senhaVisivel = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Fundo totalmente branco
      // SafeArea garante que o layout não invada o "notch" da câmera do celular
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 24.0,
          ), // Margens laterais
          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center, // Centraliza tudo no meio da tela
            crossAxisAlignment: CrossAxisAlignment
                .stretch, // Estica os botões para preencher a tela
            children: [
              // 1. Título e Subtítulo
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
                style: TextStyle(
                  fontSize: 16,
                  color: Color.fromARGB(255, 33, 69, 114),
                ),
              ),
              const SizedBox(height: 40), // Espação antes do input
              // 2. Campo de Email e Senha(TextField)
              TextField(
                decoration: InputDecoration(
                  hintText: 'email@domain.com', // O texto cinza de fundo
                  hintStyle: const TextStyle(
                    color: Color.fromARGB(255, 33, 69, 114),
                  ),
                  border: OutlineInputBorder(
                    // Cria a borda ao redor
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color.fromARGB(255, 33, 69, 114),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color.fromARGB(255, 33, 69, 114),
                    ), // Borda mais suave
                  ),
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                obscureText: !_senhaVisivel,
                decoration: InputDecoration(
                  hintText: 'senha', // O texto cinza de fundo
                  hintStyle: const TextStyle(
                    color: Color.fromARGB(255, 33, 69, 114),
                  ),
                  border: OutlineInputBorder(
                    // Cria a borda ao redor
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color.fromARGB(255, 33, 69, 114),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color.fromARGB(255, 33, 69, 114),
                    ), // Borda mais suave
                  ),
                  suffixIcon: IconButton(
                    tooltip: _senhaVisivel ? 'Ocultar senha' : 'Mostrar senha',
                    icon: Icon(
                      _senhaVisivel ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _senhaVisivel = !_senhaVisivel;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 3. Botão Preto de Continuar
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: contentBlue, // Cor do botão
                  foregroundColor: Colors.white, // Cor do texto
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                  ), // Altura do botão
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: contentBlue),
                  ),
                ),
                onPressed: () {
                  cadastroConcluido.value = true;
                  Navigator.pushReplacementNamed(context, '/inicial');
                },
                child: const Text('Continue', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 24),

              // 4. Divisor com o "ou"
              const Row(
                children: [
                  Expanded(
                    child: Divider(
                      thickness: 1,
                      color: Color.fromARGB(255, 33, 69, 114),
                    ),
                  ), // Linha esquerda
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      'ou',
                      style: TextStyle(color: Color.fromARGB(255, 33, 69, 114)),
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      thickness: 1,
                      color: Color.fromARGB(255, 33, 69, 114),
                    ),
                  ), // Linha direita
                ],
              ),
              const SizedBox(height: 24),

              // 5. Botões Sociais (Google e Apple)
              // Botão Google (Usando um ícone genérico do Material por enquanto)
              ElevatedButton.icon(
                icon: const Icon(
                  Icons.g_mobiledata,
                  size: 30,
                ), // Ícone improvisado do Google
                label: const Text('Continue com Google'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade100, // Cinza bem claro
                  foregroundColor: Color.fromARGB(255, 33, 69, 114),
                  elevation:
                      0, // Tira a sombra para ficar "chapado" igual seu desenho
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: contentBlue),
                  ),
                ),
                onPressed: () {},
              ),
              const SizedBox(height: 12),

              // Botão Apple
              ElevatedButton.icon(
                icon: const Icon(
                  Icons.apple,
                  size: 26,
                ), // O Flutter já tem a maçãzinha nativa!
                label: const Text('Continue com Apple'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                  foregroundColor: Color.fromARGB(255, 33, 69, 114),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: contentBlue),
                  ),
                ),
                onPressed: () {},
              ),

              const SizedBox(height: 40),

              // 6. Texto de Termos de Uso no rodapé
              RichText(
                textAlign: TextAlign.center,
                text: const TextSpan(
                  style: TextStyle(
                    color: Color.fromARGB(255, 33, 69, 114),
                    fontSize: 12,
                  ),
                  children: [
                    TextSpan(
                      text: 'Ao clicar em continuar, você concorda com nossos ',
                    ),
                    TextSpan(
                      text: 'Termos de Serviço\n',
                      style: TextStyle(
                        color: Color.fromARGB(255, 33, 69, 114),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(text: 'e '),
                    TextSpan(
                      text: 'Política de Privacidade',
                      style: TextStyle(
                        color: titleBlue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 2 TELA INICIAL (Dashboard)
class TelaInicial extends StatelessWidget {
  const TelaInicial({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Início - Resumo Semanal'),
        backgroundColor: const Color(0xFFF4F6F4),
        foregroundColor: titleBlue,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF4F6F4),
      body: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: const Column(
                children: [
                  Text(
                    'MistakeMap',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: titleBlue,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Erros mapeados. Aprendizado direcionado.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Color.fromARGB(255, 33, 69, 114),
                    ),
                  ),
                ],
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        fontSize: 16,
                        color: Color.fromARGB(255, 33, 69, 114),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        _ResumoCard(label: 'Exercícios', value: '12'),
                        const SizedBox(width: 10),
                        _ResumoCard(label: 'Para revisar', value: '3'),
                        const SizedBox(width: 10),
                        _ResumoCard(label: 'Evolução', value: '78%'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.info_outline),
                  style: OutlinedButton.styleFrom(
                    textStyle: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                    ),
                    backgroundColor: const Color(0xFFE7EBE8),
                    foregroundColor: Color.fromARGB(255, 33, 69, 114),
                    padding: const EdgeInsets.symmetric(
                      vertical: 18,
                      horizontal: 24,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: contentBlue),
                    ),
                  ),
                  onPressed: () {
                    if (cadastroConcluido.value) {
                      Navigator.pushNamed(context, '/sobre');
                    } else {
                      Navigator.pushNamed(context, '/cadastro');
                    }
                  },
                  label: const Text(
                    'Sobre o App',
                    style: TextStyle(fontSize: 17),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: contentBlue),
        ),
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
              style: const TextStyle(
                fontSize: 12,
                color: Color.fromARGB(255, 33, 69, 114),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TelaAdicionarExercicio extends StatefulWidget {
  const TelaAdicionarExercicio({super.key});

  @override
  State<TelaAdicionarExercicio> createState() => _TelaAdicionarExercicioState();
}

class _TelaAdicionarExercicioState extends State<TelaAdicionarExercicio> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();
  final _assuntoController = TextEditingController();
  final _erroController = TextEditingController();
  XFile? _imagemSelecionada;
  Uint8List? _imagemBytes;

  @override
  void dispose() {
    _assuntoController.dispose();
    _erroController.dispose();
    super.dispose();
  }

  Future<void> _selecionarImagem(ImageSource source) async {
    final imagem = await _imagePicker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 2048,
    );

    if (imagem == null) {
      return;
    }

    final bytes = await imagem.readAsBytes();
    if (!mounted) {
      return;
    }

    setState(() {
      _imagemSelecionada = imagem;
      _imagemBytes = bytes;
    });
  }

  Future<void> _mostrarOpcoesDeImagem() async {
    //popup para escolher entre câmera ou galeria
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar uma foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source != null) {
      await _selecionarImagem(source);
    }
  }

  Future<Map<String, dynamic>> _criarPayloadParaApi() async {
    return {
      'assunto': _assuntoController.text.trim(),
      'erro': _erroController.text.trim(),
      if (_imagemSelecionada != null)
        'imagem': {
          'nome': _imagemSelecionada!.name,
          'bytes': _imagemBytes ?? await _imagemSelecionada!.readAsBytes(),
        },
    };
  }

  Future<void> _continuar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final payload = await _criarPayloadParaApi();
    if (!mounted) {
      return;
    }

    final temImagem = payload['imagem'] != null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          temImagem ? 'Exercício e imagem preparados para envio à API.' : 'Exercício preenchido. O salvamento será conectado ao banco de dados.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adicionar exercício'),
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
                  'Registre um erro para acompanhar sua evolução.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 19,
                    color: Color.fromARGB(255, 33, 69, 114),
                  ),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _assuntoController,
                  decoration: const InputDecoration(
                    labelText: 'Assunto',
                    hintText: 'Ex.: Equações de segundo grau',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Informe o assunto'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _erroController,
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
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Descreva o erro'
                      : null,
                ),
                const SizedBox(height: 24),
                if (_imagemBytes == null)
                  OutlinedButton.icon(
                    onPressed: _mostrarOpcoesDeImagem,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Adicionar foto do exercício'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Color.fromARGB(
                        255,
                        33,
                        69,
                        114,
                      ), //cor do botao
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: contentBlue),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          _imagemBytes!,
                          height: 220,
                          fit: BoxFit.cover,
                        ),
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
                  onPressed: _continuar,
                  icon: const Icon(Icons.check),
                  label: const Text('Registrar exercício'),
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
        ),
      ),
    );
  }
}

// 3 TELA DA PRINCIPAL FUNCIONALIDADE
class TelaPrincipal extends StatelessWidget {
  const TelaPrincipal({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de Fragilidades Conceituais'),
        backgroundColor: const Color(0xFFE7EBE8),
        foregroundColor: titleBlue,
      ),
      backgroundColor: const Color(0xFFF4F6F4),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.account_tree_outlined,
                  size: 64,
                  color: contentBlue,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Seu mapa ainda está vazio',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                    color: titleBlue,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Adicione seu primeiro exercício para começar a identificar suas fragilidades conceituais.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Color.fromARGB(255, 33, 69, 114),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    if (cadastroConcluido.value) {
                      Navigator.pushNamed(context, '/adicionar');
                    } else {
                      Navigator.pushNamed(context, '/cadastro');
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar primeiro exercício'),
                  style: ElevatedButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 17),
                    backgroundColor: Color.fromARGB(255, 33, 69, 114),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 18.5,
                      horizontal: 50,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: contentBlue),
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
}

// 4 TELA SOBRE O APP
class TelaSobre extends StatelessWidget {
  const TelaSobre({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sobre o MistakeMap'),
        backgroundColor: const Color(0xFFE7EBE8),
        foregroundColor: titleBlue,
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Objetivo:',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: titleBlue,
                ),
              ),
              const Text(
                'Transformar exercícios corrigidos em um grafo de fragilidades conceituais para orientar a revisão e ajuda nos estudos.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  color: Color.fromARGB(255, 33, 69, 114),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Equipe:',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: titleBlue,
                ),
              ),
              const Text(
                '- Cláudio Francisco (Backend)',
                style: TextStyle(
                  fontSize: 18,
                  color: Color.fromARGB(255, 33, 69, 114),
                ),
              ),
              const Text(
                '- Lucas Emanuel (Frontend, OCR, LLM)',
                style: TextStyle(
                  fontSize: 18,
                  color: Color.fromARGB(255, 33, 69, 114),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
