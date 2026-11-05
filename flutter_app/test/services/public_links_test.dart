// The public pages the app opens carry its language, so nobody lands on the wrong one.
import 'package:budget_tracker/services/public_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final lang in const ['ar', 'en', 'ur']) {
    test('$lang: the deletion page and the privacy section carry the language', () {
      final deletion = publicDeleteAccountUri(lang);
      expect(deletion.path, '/delete-account');
      expect(deletion.queryParameters['lang'], lang);

      final privacy = publicPrivacyUri(lang);
      expect(privacy.path, anyOf('', '/'));
      expect(privacy.queryParameters['lang'], lang);
      expect(privacy.fragment, 'privacy');
    });
  }
}
