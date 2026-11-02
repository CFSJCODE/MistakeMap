// Supabase already supplies and registers this plugin on the app's targets.
// ignore: depend_on_referenced_packages
import 'package:url_launcher/url_launcher.dart';

const claudioLinkedInProfileUrl =
    'https://www.linkedin.com/in/claudio-francisco-dos-santos-junior/';

const lucasLinkedInProfileUrl = 'https://www.linkedin.com/in/devlucassilva/';

Future<bool> openClaudioLinkedInProfile() =>
    openLinkedInProfile(claudioLinkedInProfileUrl);

Future<bool> openLucasLinkedInProfile() =>
    openLinkedInProfile(lucasLinkedInProfileUrl);

Future<bool> openLinkedInProfile(String url) => launchUrl(
  Uri.parse(url),
  mode: LaunchMode.externalApplication,
  webOnlyWindowName: '_blank',
);

Future<bool> openLearningLink(Uri uri) => launchUrl(
  uri,
  mode: LaunchMode.externalApplication,
  webOnlyWindowName: '_blank',
);
