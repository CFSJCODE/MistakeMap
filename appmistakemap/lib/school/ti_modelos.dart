import 'escola_repositorio.dart';
import 'perfil_modelos.dart';

// Modelos do Painel de TI da escola. Só dados de conta e acesso: nada de
// resposta, mapa, caderno ou valor em reais. A conferência de permissão é
// toda do servidor (migration 20261113180000_school_it_admin.sql).

DateTime? _data(Object? v) => DateTime.tryParse('${v ?? ''}')?.toLocal();
int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

class PapelPessoaTi {
  const PapelPessoaTi({
    required this.papel,
    required this.ativo,
    required this.administravel,
  });

  factory PapelPessoaTi.deJson(DadosEscola j) => PapelPessoaTi(
    papel: '${j['role']}',
    ativo: j['status'] == 'active',
    administravel: j['manageable'] == true,
  );

  final String papel;
  final bool ativo;

  /// Quem está vendo pode suspender, reativar e remover este papel.
  final bool administravel;

  String get nome => nomesPapel[papel] ?? papel;
}

class PessoaTi {
  const PessoaTi({
    required this.id,
    required this.email,
    required this.nome,
    required this.papeis,
    required this.entrou,
    required this.ultimoAcesso,
    required this.sessoes,
    required this.contaAdministravel,
    required this.souEu,
  });

  factory PessoaTi.deJson(DadosEscola j) => PessoaTi(
    id: '${j['user_id']}',
    email: '${j['email'] ?? ''}',
    nome: (j['name'] as String?)?.trim(),
    papeis: [for (final p in linhasEscola(j['roles'])) PapelPessoaTi.deJson(p)],
    entrou: _data(j['joined_at']),
    ultimoAcesso: _data(j['last_sign_in_at']),
    sessoes: _int(j['sessions']),
    contaAdministravel: j['account_manageable'] == true,
    souEu: j['is_me'] == true,
  );

  final String id;
  final String email;
  final String? nome;
  final List<PapelPessoaTi> papeis;
  final DateTime? entrou;
  final DateTime? ultimoAcesso;
  final int sessoes;

  /// Encerrar sessões e enviar redefinição de senha.
  final bool contaAdministravel;
  final bool souEu;

  String get titulo => (nome == null || nome!.isEmpty) ? email : nome!;
  bool get suspensa => papeis.isNotEmpty && papeis.every((p) => !p.ativo);

  bool combina(String busca, String? papel, String situacao) {
    final b = busca.trim().toLowerCase();
    if (b.isNotEmpty &&
        !email.toLowerCase().contains(b) &&
        !(nome ?? '').toLowerCase().contains(b)) {
      return false;
    }
    if (papel != null && !papeis.any((p) => p.papel == papel)) return false;
    return switch (situacao) {
      'active' => papeis.any((p) => p.ativo),
      'suspended' => papeis.any((p) => !p.ativo),
      'never' => ultimoAcesso == null,
      _ => true,
    };
  }
}

List<PessoaTi> pessoasDoDiretorio(DadosEscola dados) => [
  for (final p in linhasEscola(dados['people'])) PessoaTi.deJson(p),
];

class SessaoTi {
  const SessaoTi({
    required this.criada,
    required this.vistaEm,
    required this.aparelho,
    required this.rede,
  });

  factory SessaoTi.deJson(DadosEscola j) => SessaoTi(
    criada: _data(j['created_at']),
    vistaEm: _data(j['last_seen_at']),
    aparelho: resumoAparelho('${j['user_agent'] ?? ''}'),
    rede: j['network'] as String?,
  );

  final DateTime? criada;
  final DateTime? vistaEm;
  final String aparelho;
  final String? rede;
}

/// Nome curto do aparelho a partir do user agent (sem biblioteca externa).
String resumoAparelho(String ua) {
  final u = ua.toLowerCase();
  if (u.isEmpty) return 'Aparelho não identificado';
  final sistema = switch (u) {
    _ when u.contains('android') => 'Android',
    _ when u.contains('iphone') || u.contains('ipad') => 'iPhone/iPad',
    _ when u.contains('windows') => 'Windows',
    _ when u.contains('mac os') || u.contains('macintosh') => 'Mac',
    _ when u.contains('cros') => 'Chromebook',
    _ when u.contains('linux') => 'Linux',
    _ => null,
  };
  final onde = switch (u) {
    _ when u.contains('dart') => 'app MistakeMap',
    _ when u.contains('edg/') => 'Edge',
    _ when u.contains('chrome/') => 'Chrome',
    _ when u.contains('firefox/') => 'Firefox',
    _ when u.contains('safari/') => 'Safari',
    _ => null,
  };
  if (sistema == null && onde == null) return 'Outro aparelho';
  return [?sistema, ?onde].join(' · ');
}

class LicencasTi {
  const LicencasTi({
    required this.planoNome,
    required this.maxUsuarios,
    required this.usuariosAtivos,
    required this.usuariosSuspensos,
    required this.porPapel,
    required this.maxTurmas,
    required this.turmas,
    required this.convitesAbertos,
    required this.alunosAtivos,
    required this.analisesPote,
    required this.analisesUsadas,
    required this.analisesExtras,
    required this.treinosPote,
    required this.treinosUsados,
  });

  factory LicencasTi.deJson(DadosEscola j) => LicencasTi(
    planoNome: '${j['plan_label'] ?? nomesPlano[j['plan']] ?? j['plan']}',
    maxUsuarios: j['max_users'] == null ? null : _int(j['max_users']),
    usuariosAtivos: _int(j['users_active']),
    usuariosSuspensos: _int(j['users_suspended']),
    porPapel: {
      for (final e in mapaEscola(j['by_role']).entries) e.key: _int(e.value),
    },
    maxTurmas: j['max_classes'] == null ? null : _int(j['max_classes']),
    turmas: _int(j['classes']),
    convitesAbertos: _int(j['open_invites']),
    alunosAtivos: _int(j['active_students']),
    analisesPote: _int(j['analyses_pot']),
    analisesUsadas: _int(j['analyses_used']),
    analisesExtras: _int(j['extra_analyses']),
    treinosPote: _int(j['practices_pot']),
    treinosUsados: _int(j['practices_used']),
  );

  final String planoNome;
  final int? maxUsuarios;
  final int usuariosAtivos;
  final int usuariosSuspensos;
  final Map<String, int> porPapel;
  final int? maxTurmas;
  final int turmas;
  final int convitesAbertos;
  final int alunosAtivos;
  final int analisesPote;
  final int analisesUsadas;
  final int analisesExtras;
  final int treinosPote;
  final int treinosUsados;

  /// Vagas que ainda cabem no plano (null = sem limite).
  int? get vagas => maxUsuarios == null
      ? null
      : (maxUsuarios! - usuariosAtivos).clamp(0, maxUsuarios!);

  /// Convites em aberto que não cabem no plano se todos forem usados.
  bool get convitesPassamDoLimite => vagas != null && convitesAbertos > vagas!;

  double get usoAnalises => analisesPote == 0
      ? (analisesUsadas > 0 ? 1 : 0)
      : (analisesUsadas / analisesPote).clamp(0, 1).toDouble();
}

class RegistroAuditoria {
  const RegistroAuditoria({
    required this.id,
    required this.acao,
    required this.quando,
    required this.quem,
    required this.alvo,
    required this.papel,
    required this.detalhes,
  });

  factory RegistroAuditoria.deJson(DadosEscola j) => RegistroAuditoria(
    id: _int(j['id']),
    acao: '${j['action']}',
    quando: _data(j['created_at']),
    quem: j['actor_email'] as String?,
    alvo: j['target_email'] as String?,
    papel: j['target_role'] as String?,
    detalhes: mapaEscola(j['details']),
  );

  final int id;
  final String acao;
  final DateTime? quando;
  final String? quem;
  final String? alvo;
  final String? papel;
  final DadosEscola detalhes;

  /// Frase curta do que aconteceu.
  String get descricao {
    final p = papel == null ? '' : nomesPapel[papel] ?? papel!;
    final email = detalhes['email'] as String?;
    final convite = [if (p.isNotEmpty) p, ?email].join(' · ');
    return switch (acao) {
      'member_joined' => 'Entrou como $p',
      'member_suspended' => 'Suspenso: $p',
      'member_reactivated' => 'Reativado: $p',
      'member_removed' => 'Removido: $p',
      'invite_created' => 'Convite criado ($convite)',
      'invite_revoked' => 'Convite revogado ($convite)',
      'invite_renewed' => 'Convite renovado ($convite)',
      'invites_imported' =>
        'Convites em lote: ${_int(detalhes['created'])} de '
            '${_int(detalhes['rows'])} linhas',
      'sessions_revoked' =>
        'Sessões encerradas em todos os aparelhos '
            '(${_int(detalhes['sessions'])})',
      'password_reset_sent' => 'E-mail de redefinição de senha enviado',
      _ => acao,
    };
  }
}

List<RegistroAuditoria> registrosAuditoria(DadosEscola dados) => [
  for (final e in linhasEscola(dados['entries'])) RegistroAuditoria.deJson(e),
];

// ─── Planilha de convites ────────────────────────────────────────────────────

/// Papel escrito na planilha → papel do sistema (aceita português).
String papelDaPlanilha(String texto) {
  final t = texto
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[áàâã]'), 'a')
      .replaceAll(RegExp('[éê]'), 'e')
      .replaceAll(RegExp('[íî]'), 'i')
      .replaceAll(RegExp('[óôõ]'), 'o')
      .replaceAll(RegExp('[úû]'), 'u')
      .replaceAll('ç', 'c');
  return switch (t) {
    'professor' ||
    'professora' ||
    'prof' ||
    'docente' ||
    'teacher' => 'teacher',
    'aluno' || 'aluna' || 'estudante' || 'student' => 'student',
    'responsavel' || 'pai' || 'mae' || 'guardian' => 'guardian',
    _ => t,
  };
}

class LinhaPlanilha {
  const LinhaPlanilha(this.email, this.papel);
  final String email;
  final String papel;
  Map<String, String> paraJson() => {'email': email, 'role': papel};
}

/// Lê o texto colado de uma planilha: uma pessoa por linha, com e-mail e
/// papel separados por ponto e vírgula, vírgula ou tabulação. Aceita
/// cabeçalho e linhas só com e-mail (usa [papelPadrao]).
List<LinhaPlanilha> lerPlanilha(
  String texto, {
  String papelPadrao = 'student',
}) {
  final linhas = <LinhaPlanilha>[];
  for (final bruta in texto.split(RegExp(r'\r?\n'))) {
    final linha = bruta.trim();
    if (linha.isEmpty) continue;
    final partes = linha
        .split(RegExp(r'[;,\t]'))
        .map((p) => p.trim().replaceAll('"', ''))
        .where((p) => p.isNotEmpty)
        .toList();
    final email = partes.firstWhere((p) => p.contains('@'), orElse: () => '');
    if (email.isEmpty) {
      // Cabeçalho ("e-mail;papel") ou linha sem e-mail: ignora o cabeçalho,
      // mantém o resto para o servidor explicar o motivo.
      final cabecalho = partes.any(
        (p) => RegExp(
          '^(e-?mail|papel|perfil|nome)\$',
          caseSensitive: false,
        ).hasMatch(p),
      );
      if (!cabecalho) linhas.add(LinhaPlanilha(linha, papelPadrao));
      continue;
    }
    final outros = partes.where((p) => p != email).map(papelDaPlanilha);
    final papel = outros.firstWhere(
      (p) => const {'teacher', 'student', 'guardian'}.contains(p),
      orElse: () => outros.isEmpty ? papelPadrao : outros.last,
    );
    linhas.add(LinhaPlanilha(email.toLowerCase(), papel));
  }
  return linhas;
}

const motivosLinha = {
  'created': 'Convite criado',
  'duplicate': 'Repetida na planilha',
  'already_member': 'Já está na escola com esse papel',
  'invalid_email': 'E-mail inválido',
  'invalid_role': 'Papel inválido (professor, estudante ou responsável)',
};

// ─── CSV (ponto e vírgula: abre direto no Excel em português) ────────────────

String _celula(String v) =>
    v.contains(';') || v.contains('"') || v.contains('\n')
    ? '"${v.replaceAll('"', '""')}"'
    : v;

String _iso(DateTime? d) => d == null
    ? ''
    : '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')} '
          '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';

String _csv(List<List<String>> linhas) =>
    linhas.map((l) => l.map(_celula).join(';')).join('\n');

String pessoasCsv(List<PessoaTi> pessoas) => _csv([
  ['email', 'nome', 'papeis', 'situacao', 'entrou_em', 'ultimo_acesso'],
  for (final p in pessoas)
    [
      p.email,
      p.nome ?? '',
      p.papeis.map((r) => r.nome).join(', '),
      p.papeis
          .map((r) => '${r.nome}: ${r.ativo ? 'ativo' : 'suspenso'}')
          .join(', '),
      _iso(p.entrou),
      _iso(p.ultimoAcesso),
    ],
]);

String auditoriaCsv(List<RegistroAuditoria> registros) => _csv([
  ['quando', 'quem', 'acao', 'pessoa', 'descricao'],
  for (final r in registros)
    [_iso(r.quando), r.quem ?? 'sistema', r.acao, r.alvo ?? '', r.descricao],
]);

String convitesLoteCsv(List<DadosEscola> linhas) => _csv([
  ['email', 'papel', 'codigo', 'vence_em', 'resultado'],
  for (final l in linhas)
    [
      '${l['email'] ?? ''}',
      nomesPapel['${l['role']}'] ?? '${l['role'] ?? ''}',
      '${l['code'] ?? ''}',
      _iso(_data(l['expires_at'])),
      motivosLinha['${l['status']}'] ?? '${l['status'] ?? ''}',
    ],
]);

/// "há 3 dias", "hoje", "nunca".
String quandoRelativo(DateTime? d, {DateTime? agora}) {
  if (d == null) return 'nunca';
  final dias = (agora ?? DateTime.now()).difference(d).inDays;
  if (dias <= 0) return 'hoje';
  if (dias == 1) return 'ontem';
  if (dias < 60) return 'há $dias dias';
  return 'há ${dias ~/ 30} meses';
}
