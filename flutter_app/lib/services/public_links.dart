import 'package:url_launcher/url_launcher.dart';

import '../supabase_config.dart';
import '../utils/failure_log.dart';

/// The public site is served by the same backend as the API
/// (`ai_service/main.py`: `GET /`, `GET /delete-account`), so its address is
/// [fastapiBaseUrl]. Privacy is a section of the landing page, not a page of its
/// own: `/privacy` does not exist there.
String get _site => fastapiBaseUrl.endsWith('/') ? fastapiBaseUrl.substring(0, fastapiBaseUrl.length - 1) : fastapiBaseUrl;

Uri publicDeleteAccountUri(String languageCode) => Uri.parse('$_site/delete-account?lang=$languageCode');

/// The landing page has no Urdu: for `ur` it shows English, with a notice in Urdu
/// pointing to the deletion page, which has it.
Uri publicPrivacyUri(String languageCode) => Uri.parse('$_site/?lang=$languageCode#privacy');

/// Opens [uri] in the browser; false when that could not be done. It does not ask
/// canLaunchUrl first, which would need https declared in the Android manifest
/// (`<queries>`) and the iOS Info.plist (`LSApplicationQueriesSchemes`).
Future<bool> openPublicLink(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    logFailure('PublicLinks.open', e);
    return false;
  }
}
