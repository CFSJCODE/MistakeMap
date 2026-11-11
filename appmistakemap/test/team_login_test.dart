import 'package:appmistakemap/auth/team_login.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sem arquivo local não há atalhos da equipe', () {
    // Os testes rodam sem --dart-define-from-file.
    expect(TeamLoginConfig.fromEnvironment().isEmpty, isTrue);
  });

  test('atalho só aparece com e-mail e entra direto só com senha', () {
    const config = TeamLoginConfig(
      devEmail: ' dev@exemplo.dev ',
      devPassword: 'segredo',
      adminEmail: 'admin@exemplo.dev',
    );
    expect(config.has(TeamAccount.developer), isTrue);
    expect(config.emailOf(TeamAccount.developer), 'dev@exemplo.dev');
    expect(config.canSignInDirectly(TeamAccount.developer), isTrue);
    expect(config.has(TeamAccount.admin), isTrue);
    expect(config.canSignInDirectly(TeamAccount.admin), isFalse);
    expect(const TeamLoginConfig(devEmail: 'sem-arroba').isEmpty, isTrue);
  });

  test('atalho de admin exige papel admin no banco', () {
    expect(teamRoleMismatch(TeamAccount.admin, 'admin'), isNull);
    expect(teamRoleMismatch(TeamAccount.admin, 'user'), isNotNull);
    expect(teamRoleMismatch(TeamAccount.admin, null), isNotNull);
    expect(teamRoleMismatch(TeamAccount.developer, 'user'), isNull);
  });

  test('app da equipe aceita admin e a conta de desenvolvimento', () {
    const config = TeamLoginConfig(devEmail: 'Dev@Exemplo.dev');
    expect(
      teamAccessDenied(config, email: 'qualquer@x.com', role: 'admin'),
      isNull,
    );
    expect(
      teamAccessDenied(config, email: 'outro@x.com', role: 'developer'),
      isNull,
    );
    expect(
      teamAccessDenied(config, email: 'dev@exemplo.dev ', role: 'user'),
      isNull,
    );
    expect(
      teamAccessDenied(config, email: 'aluno@x.com', role: 'user'),
      isNotNull,
    );
    expect(
      teamAccessDenied(
        const TeamLoginConfig(),
        email: 'aluno@x.com',
        role: 'user',
      ),
      isNotNull,
    );
  });

  test('o app dos alunos não é o app da equipe', () {
    expect(kTeamBuild, isFalse);
  });
}
