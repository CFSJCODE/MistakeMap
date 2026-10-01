import 'package:appmistakemap/about/external_profile.dart';
import 'package:flutter_test/flutter_test.dart';
// The app's already-registered Supabase dependency supplies this interface.
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _ProfileLauncher extends UrlLauncherPlatform {
  _ProfileLauncher({this.result = true});

  final bool result;
  final requests = <(String, LaunchOptions)>[];

  @override
  Null get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    requests.add((url, options));
    return result;
  }
}

void main() {
  late UrlLauncherPlatform previous;
  setUp(() => previous = UrlLauncherPlatform.instance);
  tearDown(() => UrlLauncherPlatform.instance = previous);

  test(
    'LinkedIn abre o perfil fornecido em destino externo sem sair do app',
    () async {
      final launcher = _ProfileLauncher();
      UrlLauncherPlatform.instance = launcher;

      expect(await openClaudioLinkedInProfile(), isTrue);
      expect(launcher.requests, hasLength(1));
      final (url, options) = launcher.requests.single;
      expect(
        url,
        'https://www.linkedin.com/in/claudio-francisco-dos-santos-junior/',
      );
      expect(options.mode, PreferredLaunchMode.externalApplication);
      expect(options.webOnlyWindowName, '_blank');
    },
  );

  test(
    'Falha ao abrir o perfil permanece disponível para aviso ao usuário',
    () async {
      UrlLauncherPlatform.instance = _ProfileLauncher(result: false);
      expect(await openClaudioLinkedInProfile(), isFalse);
    },
  );
}
