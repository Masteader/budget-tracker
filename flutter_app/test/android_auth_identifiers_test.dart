// Login depends on these Android identifiers: Supabase redirects return through
// the deep link schemes, and the application id decides whether an update
// installs over the existing app. A brand rename must not change them.
//
// The real files are parsed with comments removed, so a commented-out value
// cannot satisfy these tests.
//
// Password reset emails redirect to authResetRedirectUrl, so its default must
// stay one of the deep links the manifest declares. The Kotlin package must
// match the namespace or Android cannot resolve `.MainActivity`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _manifestPath = 'android/app/src/main/AndroidManifest.xml';
const _gradlePath = 'android/app/build.gradle.kts';
const _configPath = 'lib/supabase_config.dart';
const _kotlinRoot = 'android/app/src/main/kotlin';

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

/// Full-line and block comments only: the value itself contains `//`.
String _stripDartComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'^\s*//[^\n]*', multiLine: true), '');

/// The compile-time default of `authResetRedirectUrl`, or null if not declared.
String? _resetLinkDefault(String source) => RegExp(
      r"const\s+authResetRedirectUrl\s*=\s*String\.fromEnvironment\(\s*"
      r"'AUTH_RESET_REDIRECT_URL'\s*,\s*defaultValue:\s*'([^']*)'",
    ).firstMatch(_stripDartComments(source.replaceAll('\r\n', '\n')))?.group(1);

/// The package a Kotlin source declares, or null if none.
String? _kotlinPackage(String source) => RegExp(
      r'^\s*package\s+([\w.]+)\s*$',
      multiLine: true,
    ).firstMatch(_stripKotlinComments(source.replaceAll('\r\n', '\n')))?.group(1);

bool _declaresMainActivity(String source) =>
    RegExp(r'\bclass\s+MainActivity\b').hasMatch(_stripKotlinComments(source));

void main() {
  group('real Dart and Kotlin sources', () {
    test('the default reset link is budgettracker://reset-password', () {
      expect(_resetLinkDefault(File(_configPath).readAsStringSync()), 'budgettracker://reset-password');
    });

    test('the default reset link is a deep link the manifest declares', () {
      final link = _resetLinkDefault(File(_configPath).readAsStringSync());
      expect(_deepLinks(File(_manifestPath).readAsStringSync()), contains(link));
    });

    test('MainActivity is the only one and lives in package com.budgettracker', () {
      final activities = Directory(_kotlinRoot)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.kt') && _declaresMainActivity(f.readAsStringSync()))
          .toList();
      expect(activities, hasLength(1));
      expect(_kotlinPackage(activities.single.readAsStringSync()), 'com.budgettracker');
      expect(activities.single.path.replaceAll(r'\', '/'), '$_kotlinRoot/com/budgettracker/MainActivity.kt');
    });
  });

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

    test('commented-out reset link defaults are not counted', () {
      const commented = '''
// defaultValue: 'budgettracker://reset-password',
const authResetRedirectUrl = String.fromEnvironment(
  'AUTH_RESET_REDIRECT_URL',
  defaultValue: 'other://link', // 'budgettracker://reset-password'
);''';
      expect(_resetLinkDefault(commented), 'other://link');
      expect(_resetLinkDefault("// const authResetRedirectUrl = String.fromEnvironment('AUTH_RESET_REDIRECT_URL', defaultValue: 'x');"), isNull);
    });

    test('a commented-out Kotlin package or class is not counted', () {
      const kotlin = '''
// package com.budgettracker
/* class MainActivity : FlutterActivity() */
package com.other
''';
      expect(_kotlinPackage(kotlin), 'com.other');
      expect(_declaresMainActivity(kotlin), isFalse);
    });
  });
}
