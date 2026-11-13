import 'package:fluent_ui/fluent_ui.dart';

import '../theme/design_tokens.dart';

// ─── Cadastro por perfil: modelos ────────────────────────────────────────────
// O perfil escolhido em "Quem é você?" é só um pedido. Papel de escola vem do
// servidor (convite validado na Edge Function school-admin e no banco). Aqui
// ficam os modelos e as regras de exibição; nenhuma regra de acesso.

/// Os 8 perfis da primeira tela do cadastro.
enum PerfilCadastro {
  estudante(
    'student',
    'Estudante',
    'Envio meus erros, vejo meu mapa e treino. Entro com o código da turma ou '
        'estudo por conta própria.',
    WindowsIcons.education,
    MistakeMapDesign.aquaInk,
    MistakeMapDesign.aqua,
  ),
  estudanteEquipe(
    'student_team',
    'Estudante + equipe de robótica',
    'Tudo do estudante e mais a equipe de competição ou projeto, com a minha '
        'função nela.',
    WindowsIcons.relationship,
    MistakeMapDesign.violetInk,
    MistakeMapDesign.violet,
  ),
  professor(
    'teacher',
    'Professor',
    'Dou aula ou treino equipe. Entro com o convite da escola ou começo '
        'sozinho no plano Grátis.',
    WindowsIcons.people,
    MistakeMapDesign.azureInk,
    MistakeMapDesign.azure,
  ),
  responsavel(
    'guardian',
    'Pai ou responsável',
    'Acompanho a evolução do meu filho e dou o consentimento para ele usar o '
        'app.',
    WindowsIcons.contact,
    MistakeMapDesign.mintInk,
    MistakeMapDesign.mint,
  ),
  dono(
    'owner',
    'Dono da escola',
    'Contrato o MistakeMap para a minha escola, curso ou equipe.',
    WindowsIcons.home,
    MistakeMapDesign.amberInk,
    MistakeMapDesign.amber,
  ),
  coordenador(
    'coordinator',
    'Coordenador',
    'Cuido da gestão pedagógica da escola. Preciso do convite do dono.',
    WindowsIcons.bulleted_list,
    MistakeMapDesign.coralInk,
    MistakeMapDesign.coral,
  ),
  ti(
    'it_admin',
    'TI da escola',
    'Cuido das contas, dos acessos e dos aparelhos. Preciso do convite do '
        'dono.',
    WindowsIcons.admin,
    MistakeMapDesign.deep,
    MistakeMapDesign.steel,
  ),
  financeiro(
    'finance',
    'Financeiro / Compras',
    'Contrato e pago o MistakeMap pela escola ou rede: pedido de compra, '
        'boleto e nota fiscal. Preciso do convite do dono.',
    WindowsIcons.payment_card,
    MistakeMapDesign.azureInk,
    MistakeMapDesign.azure,
  );

  const PerfilCadastro(
    this.codigo,
    this.titulo,
    this.descricao,
    this.icone,
    this.tinta,
    this.acento,
  );

  final String codigo;
  final String titulo;
  final String descricao;
  final IconData icone;
  final Color tinta;
  final Color acento;

  /// Coordenação, TI e Financeiro só ganham o papel com convite. O professor
  /// da escola também, mas ele tem a saída do plano Grátis.
  bool get soComConvite =>
      this == coordenador || this == ti || this == financeiro;

  bool get pedeNascimento => this == estudante || this == estudanteEquipe;

  static PerfilCadastro? doCodigo(String? codigo) {
    for (final p in values) {
      if (p.codigo == codigo) return p;
    }
    return null;
  }
}

/// Funções numa equipe de robótica.
const funcoesEquipe = {
  'programacao': 'Programação',
  'mecanica': 'Mecânica',
  'eletronica': 'Eletrônica',
  'estrategia': 'Estratégia',
};

/// Competições aceitas pelo servidor.
const competicoes = {
  'obr': 'OBR',
  'fll': 'FIRST LEGO League',
  'ftc': 'FIRST Tech Challenge',
  'frc': 'FIRST Robotics Competition',
  'projeto': 'Projeto da escola',
  'outra': 'Outra',
};

/// Nome de cada papel de escola na tela.
const nomesPapel = {
  'owner': 'Dono da escola',
  'coordinator': 'Coordenação',
  'it_admin': 'TI da escola',
  'finance': 'Financeiro/Compras',
  'teacher': 'Professor',
  'student': 'Estudante',
  'guardian': 'Responsável',
};

const nomesPlano = {
  'free': 'Grátis',
  'escola': 'Escola',
  'plus': 'Escola Plus',
};

/// Papel do usuário numa escola, como o servidor devolveu.
class PapelEscola {
  const PapelEscola({
    required this.escolaId,
    required this.escolaNome,
    required this.papel,
    this.plano,
    this.ativo = true,
  });

  final String escolaId;
  final String escolaNome;
  final String papel;
  final String? plano;
  final bool ativo;

  factory PapelEscola.deJson(Map<String, dynamic> j) {
    final escola = j['schools'] is Map
        ? Map<String, dynamic>.from(j['schools'] as Map)
        : <String, dynamic>{};
    return PapelEscola(
      escolaId: '${j['school_id'] ?? ''}',
      escolaNome: '${escola['name'] ?? j['school_name'] ?? 'Escola'}',
      papel: '${j['role'] ?? ''}',
      plano: (escola['plan'] ?? j['plan']) as String?,
      ativo: (j['status'] ?? 'active') == 'active',
    );
  }

  Map<String, dynamic> paraJson() => {
    'school_id': escolaId,
    'school_name': escolaNome,
    'role': papel,
    'plan': plano,
    'status': ativo ? 'active' : 'suspended',
  };
}

class EquipeDoUsuario {
  const EquipeDoUsuario({
    required this.id,
    required this.nome,
    required this.funcao,
  });
  final String id;
  final String nome;
  final String funcao;

  factory EquipeDoUsuario.deJson(Map<String, dynamic> j) {
    final equipe = j['school_teams'] is Map
        ? Map<String, dynamic>.from(j['school_teams'] as Map)
        : j;
    return EquipeDoUsuario(
      id: '${equipe['id'] ?? j['team_id'] ?? ''}',
      nome: '${equipe['name'] ?? j['team_name'] ?? 'Equipe'}',
      funcao: '${j['team_role'] ?? ''}',
    );
  }

  Map<String, dynamic> paraJson() => {
    'id': id,
    'name': nome,
    'team_role': funcao,
  };
}

/// Perfil que a pessoa pode usar agora (o seletor no topo troca entre eles).
class PerfilAtivo {
  const PerfilAtivo(this.papel, {this.escolaId, this.escolaNome, this.plano});

  /// `student` (o app de sempre) ou um papel de escola.
  final String papel;
  final String? escolaId;
  final String? escolaNome;

  /// Plano da escola conhecido no login; o painel o mostra até carregar.
  final String? plano;

  String get chave => escolaId == null ? papel : '$papel:$escolaId';
  bool get ehEstudante => papel == 'student';

  String get rotulo {
    final nome = nomesPapel[papel] ?? papel;
    return escolaNome == null ? nome : '$nome · $escolaNome';
  }
}

/// O que o app sabe da pessoa para montar o cadastro e o seletor.
class ContextoPerfil {
  const ContextoPerfil({
    this.perfil,
    this.nascimento,
    this.papeis = const [],
    this.equipes = const [],
    this.consentimentoPendente = false,
    this.temFilhos = false,
  });

  final PerfilCadastro? perfil;
  final DateTime? nascimento;
  final List<PapelEscola> papeis;
  final List<EquipeDoUsuario> equipes;
  final bool consentimentoPendente;
  final bool temFilhos;

  /// Conta sem perfil escolhido e sem papel de escola vê "Quem é você?".
  /// Quem chega por convite ou planilha já tem o papel e pula a tela.
  bool get precisaCadastro => perfil == null && papeis.isEmpty;

  /// Perfis do seletor: o modo estudante e cada papel ativo de escola.
  List<PerfilAtivo> get perfis {
    final lista = <PerfilAtivo>[const PerfilAtivo('student')];
    final vistos = <String>{'student'};
    for (final p in papeis) {
      if (!p.ativo || p.papel == 'student') continue;
      final perfil = PerfilAtivo(
        p.papel,
        escolaId: p.escolaId,
        escolaNome: p.escolaNome,
        plano: p.plano,
      );
      if (vistos.add(perfil.chave)) lista.add(perfil);
    }
    // Responsável por consentimento individual (sem escola).
    if (temFilhos && !papeis.any((p) => p.ativo && p.papel == 'guardian')) {
      lista.add(const PerfilAtivo('guardian'));
    }
    if (perfil == PerfilCadastro.responsavel &&
        !lista.any((p) => p.papel == 'guardian')) {
      lista.add(const PerfilAtivo('guardian'));
    }
    return lista;
  }

  /// Perfil que abre: o último escolhido neste aparelho ou o do cadastro.
  PerfilAtivo perfilInicial(String? chaveSalva) {
    final lista = perfis;
    for (final p in lista) {
      if (p.chave == chaveSalva) return p;
    }
    final pedido = perfil?.codigo;
    if (pedido != null && pedido != 'student' && pedido != 'student_team') {
      for (final p in lista) {
        if (p.papel == pedido) return p;
      }
    }
    return lista.first;
  }

  factory ContextoPerfil.deJson(Map<String, dynamic> j) {
    final signup = j['signup'] is Map
        ? Map<String, dynamic>.from(j['signup'] as Map)
        : null;
    List<Map<String, dynamic>> linhas(Object? v) => v is List
        ? [
            for (final item in v)
              if (item is Map) Map<String, dynamic>.from(item),
          ]
        : const [];
    return ContextoPerfil(
      perfil: PerfilCadastro.doCodigo(signup?['persona'] as String?),
      nascimento: DateTime.tryParse('${signup?['birth_date'] ?? ''}'),
      papeis: [for (final r in linhas(j['roles'])) PapelEscola.deJson(r)],
      equipes: [for (final r in linhas(j['teams'])) EquipeDoUsuario.deJson(r)],
      consentimentoPendente: j['guardian_consent_pending'] == true,
      temFilhos: j['has_children'] == true || linhas(j['children']).isNotEmpty,
    );
  }

  Map<String, dynamic> paraJson() => {
    'signup': perfil == null
        ? null
        : {
            'persona': perfil!.codigo,
            'birth_date': nascimento?.toIso8601String().substring(0, 10),
          },
    'roles': [for (final p in papeis) p.paraJson()],
    'teams': [for (final e in equipes) e.paraJson()],
    'guardian_consent_pending': consentimentoPendente,
    'has_children': temFilhos,
  };
}

/// Idade completa em anos na data [hoje].
int idadeEm(DateTime nascimento, DateTime hoje) {
  var anos = hoje.year - nascimento.year;
  if (hoje.month < nascimento.month ||
      (hoje.month == nascimento.month && hoje.day < nascimento.day)) {
    anos--;
  }
  return anos;
}

/// Lê DD/MM/AAAA. Devolve null se a data não existir, for futura ou tiver
/// mais de 120 anos.
DateTime? lerDataNascimento(String texto, {DateTime? hoje}) {
  final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(texto.trim());
  if (m == null) return null;
  final dia = int.parse(m[1]!), mes = int.parse(m[2]!), ano = int.parse(m[3]!);
  final data = DateTime(ano, mes, dia);
  if (data.year != ano || data.month != mes || data.day != dia) return null;
  final agora = hoje ?? DateTime.now();
  final idade = idadeEm(data, agora);
  if (data.isAfter(agora) || idade > 120) return null;
  return data;
}

String dataIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Confere o perfil escolhido na tela inicial (antes do login) com o que o
/// servidor devolveu para a conta. Devolve null quando a conta pode entrar
/// nele, ou a mensagem para mostrar no login.
///
/// O modo estudante é de toda conta. Conta nova (sem perfil e sem papel)
/// entra e segue para o "Quem é você?". Coordenação, TI e Financeiro dependem do papel
/// na escola (convite); professor, responsável e dono aceitam também o
/// perfil do cadastro.
String? motivoPerfilRecusado(PerfilCadastro pedido, ContextoPerfil ctx) {
  if (ctx.precisaCadastro) return null;
  bool temPapel(String papel) =>
      ctx.papeis.any((p) => p.ativo && p.papel == papel);
  final confere = switch (pedido) {
    PerfilCadastro.estudante || PerfilCadastro.estudanteEquipe => true,
    PerfilCadastro.professor =>
      ctx.perfil == PerfilCadastro.professor || temPapel('teacher'),
    PerfilCadastro.responsavel =>
      ctx.perfil == PerfilCadastro.responsavel ||
          ctx.temFilhos ||
          temPapel('guardian'),
    PerfilCadastro.dono =>
      ctx.perfil == PerfilCadastro.dono || temPapel('owner'),
    PerfilCadastro.coordenador => temPapel('coordinator'),
    PerfilCadastro.ti => temPapel('it_admin'),
    PerfilCadastro.financeiro => temPapel('finance'),
  };
  if (confere) return null;
  return 'Esta conta não tem o perfil "${pedido.titulo}". Entre com a conta '
      'desse perfil ou volte e escolha outro.';
}
