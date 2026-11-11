import 'package:flutter/foundation.dart' show kReleaseMode;

/// Atalhos de login da equipe e o app "MistakeMap Equipe".
///
/// O app da equipe é o mesmo código compilado com
/// `--dart-define=MISTAKEMAP_TEAM_BUILD=true` (scripts/build-equipe.ps1). Ele
/// instala ao lado do app dos alunos e só aceita a conta de desenvolvimento e
/// contas com papel admin ou developer no banco.
///
/// As credenciais nunca ficam no repositório: chegam na compilação por
/// `--dart-define-from-file=.env.team.local` (arquivo ignorado pelo Git, só no
/// computador de quem desenvolve). No app publicado dos alunos (loja, web,
/// Shorebird), build de release sem a flag da equipe, os atalhos não existem,
/// mesmo que alguém passe o arquivo.
///
/// O papel continua vindo do banco (`profiles.role`). O atalho só preenche o
/// login; quem decide se a conta é admin é o Supabase.
enum TeamAccount { developer, admin }

/// Verdadeiro só no app "MistakeMap Equipe".
const bool kTeamBuild = bool.fromEnvironment('MISTAKEMAP_TEAM_BUILD');

class TeamLoginConfig {
  const TeamLoginConfig({
    this.devEmail = '',
    this.devPassword = '',
    this.adminEmail = '',
    this.adminPassword = '',
  });

  /// Lê os valores passados na compilação. No release dos alunos devolve
  /// vazio, e o compilador descarta as constantes.
  factory TeamLoginConfig.fromEnvironment() {
    if (kReleaseMode && !kTeamBuild) return const TeamLoginConfig();
    return const TeamLoginConfig(
      devEmail: String.fromEnvironment('MISTAKEMAP_TEST_EMAIL'),
      devPassword: String.fromEnvironment('MISTAKEMAP_TEST_PASSWORD'),
      adminEmail: String.fromEnvironment('MISTAKEMAP_ADMIN_EMAIL'),
      adminPassword: String.fromEnvironment('MISTAKEMAP_ADMIN_PASSWORD'),
    );
  }

  final String devEmail;
  final String devPassword;
  final String adminEmail;
  final String adminPassword;

  String emailOf(TeamAccount conta) =>
      (conta == TeamAccount.developer ? devEmail : adminEmail).trim();

  String passwordOf(TeamAccount conta) =>
      conta == TeamAccount.developer ? devPassword : adminPassword;

  /// A conta aparece quando há pelo menos o e-mail. Sem senha (o recomendado
  /// para a conta de admin), o atalho só preenche o e-mail e pede a senha.
  bool has(TeamAccount conta) => emailOf(conta).contains('@');

  bool get isEmpty => !has(TeamAccount.developer) && !has(TeamAccount.admin);

  /// Com e-mail e senha, o atalho entra direto.
  bool canSignInDirectly(TeamAccount conta) =>
      has(conta) && passwordOf(conta).isNotEmpty;

  String label(TeamAccount conta) => conta == TeamAccount.developer
      ? 'Conta de desenvolvimento'
      : 'Conta de admin';
}

/// Confere o papel da conta que entrou pelo atalho. Só o atalho de admin exige
/// `role = 'admin'`; a conta de desenvolvimento é um usuário comum.
String? teamRoleMismatch(TeamAccount conta, String? papel) {
  if (conta != TeamAccount.admin || papel == 'admin') return null;
  return 'Essa conta não é administradora do MistakeMap. Peça a um admin '
      'para promovê-la no painel Admin.';
}

/// No app da equipe, só entram contas com `profiles.role` 'admin' ou
/// 'developer' (o admin promove no painel Admin) e, como reserva, a conta de
/// desenvolvimento do arquivo local. Devolve a mensagem de recusa, ou null.
String? teamAccessDenied(
  TeamLoginConfig config, {
  required String email,
  required String role,
}) {
  if (role == 'admin' || role == 'developer') return null;
  final dev = config.emailOf(TeamAccount.developer).toLowerCase();
  if (dev.isNotEmpty && email.trim().toLowerCase() == dev) return null;
  return 'O MistakeMap Equipe é só para a conta de desenvolvimento e para '
      'administradores. Use o app MistakeMap normal com esta conta.';
}
