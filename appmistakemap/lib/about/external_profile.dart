// Supabase already supplies and registers this plugin on the app's targets.
// ignore: depend_on_referenced_packages
import 'package:url_launcher/url_launcher.dart';

const claudioLinkedInProfileUrl =
    'https://www.linkedin.com/in/claudio-francisco-dos-santos-junior/';

Future<bool> openClaudioLinkedInProfile() => launchUrl(
  Uri.parse(claudioLinkedInProfileUrl),
  mode: LaunchMode.externalApplication,
  webOnlyWindowName: '_blank',
);
