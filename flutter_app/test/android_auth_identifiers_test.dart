// Login depends on these Android identifiers: Supabase redirects return through
// the deep link schemes, and the application id decides whether an update
// installs over the existing app. A brand rename must not change them.
//
// The real files are parsed with comments removed, so a commented-out value
// cannot satisfy these tests.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _manifestPath = 'android/app/src/main/AndroidManifest.xml';
const _gradlePath = 'android/app/build.gradle.kts';

Map<String, String> _attributes(String tagBody) => {
      for (final m in RegExp(r'([\w:]+)\s*=\s*"([^"]*)"').allMatches(tagBody)) m.group(1)!: m.group(2)!,
    };

List<String> _androidNames(String block, String tag) => [
      for (final m in RegExp('<$tag\\b([^>]*?)/?>').allMatches(block)) _attributes(m.group(1)!)['android:name'] ?? '',
    ];

/// `scheme` or `scheme://host` for every deep link declared by MainActivity.
List<String> _deepLinks(String manifestSource) {
  final manifest = manifestSource.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  final activity = RegExp(
    r'<activity\b([^>]*)>(.*?)</activity>',
    dotAll: true,
  ).allMatches(manifest).where((m) => _attributes(m.group(1)!)['android:name'] == '.MainActivity');
  if (activity.length != 1) return const [];

  final links = <String>[];
  final filters = RegExp(r'<intent-filter\b[^>]*>(.*?)</intent-filter>', dotAll: true);
  for (final filter in filters.allMatches(activity.single.group(2)!)) {
    final body = filter.group(1)!;
    final opensLinks = _androidNames(body, 'action').contains('android.intent.action.VIEW') &&
        _androidNames(body, 'category').contains('android.intent.category.DEFAULT') &&
        _androidNames(body, 'category').contains('android.intent.category.BROWSABLE');
    if (!opensLinks) continue;
    for (final data in RegExp(r'<data\b([^>]*?)/?>').allMatches(body)) {
      final attributes = _attributes(data.group(1)!);
      final host = attributes['android:host'];
      links.add('${attributes['android:scheme']}${host == null ? '' : '://$host'}');
    }
  }
  return links..sort();
}

const _expectedDeepLinks = [
  'budgettracker://auth-callback',
  'budgettracker://login',
  'budgettracker://reset-password',
  'io.supabase.budgettracker',
];

String _stripKotlinComments(String source) =>
    source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '').replaceAll(RegExp(r'//[^\n]*'), '');

/// The body of the first `name { ... }` block in [source], or an empty string.
String _block(String source, String name) {
  final open = RegExp('(^|\\s)$name\\s*\\{').firstMatch(source);
  if (open == null) return '';
  var depth = 1;
  for (var i = open.end; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}' && --depth == 0) return source.substring(open.end, i);
  }
  return '';
}

/// Every string value assigned to [property] in [block].
List<String> _assignments(String block, String property) => [
      for (final m in RegExp('^\\s*$property\\s*=\\s*"([^"]*)"\\s*\$', multiLine: true).allMatches(block)) m.group(1)!,
    ];

List<String> _namespaces(String gradleSource) =>
    _assignments(_block(_stripKotlinComments(gradleSource.replaceAll('\r\n', '\n')), 'android'), 'namespace');

List<String> _applicationIds(String gradleSource) {
  final android = _block(_stripKotlinComments(gradleSource.replaceAll('\r\n', '\n')), 'android');
  return _assignments(_block(android, 'defaultConfig'), 'applicationId');
}

void main() {
  group('real Android files', () {
    test('MainActivity declares exactly the auth deep links', () {
      expect(_deepLinks(File(_manifestPath).readAsStringSync()), _expectedDeepLinks);
    });

    test('namespace is com.budgettracker', () {
      expect(_namespaces(File(_gradlePath).readAsStringSync()), ['com.budgettracker']);
    });

    test('applicationId is com.budgettracker', () {
      expect(_applicationIds(File(_gradlePath).readAsStringSync()), ['com.budgettracker']);
    });
  });

  group('a comment cannot satisfy the parsers', () {
    test('commented-out deep link is not counted', () {
      const manifest = '''
<activity android:name=".MainActivity">
  <intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <!-- <data android:scheme="budgettracker" android:host="login" /> -->
  </intent-filter>
</activity>''';
      expect(_deepLinks(manifest), isEmpty);
    });

    test('commented-out Gradle values are not counted', () {
      const gradle = '''
android {
    // namespace = "com.budgettracker"
    /* namespace = "com.budgettracker" */
    defaultConfig {
        // applicationId = "com.budgettracker"
    }
}''';
      expect(_namespaces(gradle), isEmpty);
      expect(_applicationIds(gradle), isEmpty);
    });
  });
}
