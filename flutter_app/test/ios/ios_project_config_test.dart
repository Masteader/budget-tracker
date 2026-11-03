/// Static checks of the iOS project files. Nothing can be compiled for iOS on
/// the Windows and Linux machines that run this suite, so this pins what a
/// wrong edit would silently break: the identifiers auth redirects depend on,
/// the permission strings that crash the app when missing, and the localized
/// app name. See docs/IOS_READINESS.md.
library;

import 'dart:io';

import 'package:budget_tracker/supabase_config.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// The `<string>` values of the first `<array>` following [key].
List<String> _plistStrings(String plist, String key) {
  final array = RegExp('<key>$key</key>\\s*<array>(.*?)</array>', dotAll: true).firstMatch(plist);
  if (array == null) return const [];
  return RegExp('<string>(.*?)</string>').allMatches(array.group(1)!).map((m) => m.group(1)!).toList();
}

String? _plistString(String plist, String key) =>
    RegExp('<key>$key</key>\\s*<string>(.*?)</string>').firstMatch(plist)?.group(1);

/// Parses `"KEY" = "value";` lines of an InfoPlist.strings file.
Map<String, String> _strings(String path) => {
      for (final m in RegExp(r'^"(\w+)"\s*=\s*"(.*)";\s*$', multiLine: true).allMatches(_read(path)))
        m.group(1)!: m.group(2)!,
    };

void main() {
  const infoPlistPath = 'ios/Runner/Info.plist';
  const pbxprojPath = 'ios/Runner.xcodeproj/project.pbxproj';
  const usageKeys = [
    'NSCameraUsageDescription',
    'NSPhotoLibraryUsageDescription',
    'NSMicrophoneUsageDescription',
    'NSSpeechRecognitionUsageDescription',
  ];

  group('identifiers', () {
    test('the bundle ID is exactly the Android applicationId', () {
      final gradle = _read('android/app/build.gradle.kts');
      final applicationId = RegExp(r'applicationId = "([^"]+)"').firstMatch(gradle)!.group(1);
      expect(applicationId, 'com.budgettracker');

      final ids = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);')
          .allMatches(_read(pbxprojPath))
          .map((m) => m.group(1)!)
          .toSet();
      expect(ids, {applicationId, '$applicationId.RunnerTests'});
    });

    test('.metadata keeps android alongside ios', () {
      final platforms = RegExp(r'- platform: (\w+)').allMatches(_read('.metadata')).map((m) => m.group(1)).toList();
      expect(platforms, ['root', 'android', 'ios']);
    });
  });

  group('auth redirect URL schemes', () {
    final plist = _read(infoPlistPath);

    test('registers exactly the two auth schemes', () {
      final schemes = RegExp(r'<key>CFBundleURLSchemes</key>\s*<array>(.*?)</array>', dotAll: true)
          .allMatches(plist)
          .expand((a) => RegExp('<string>(.*?)</string>').allMatches(a.group(1)!))
          .map((m) => m.group(1)!)
          .toSet();
      expect(schemes, {'budgettracker', 'io.supabase.budgettracker'});
    });

    test('every scheme in the Android manifest is registered on iOS', () {
      final manifest = _read('android/app/src/main/AndroidManifest.xml');
      final androidSchemes = RegExp(r'android:scheme="([^"]+)"').allMatches(manifest).map((m) => m.group(1)!).toSet();
      expect(androidSchemes, isNotEmpty);
      for (final scheme in androidSchemes) {
        expect(plist, contains('<string>$scheme</string>'));
      }
    });

    test('the password reset redirect the app sends uses a registered scheme', () {
      expect(authResetRedirectUrl, 'budgettracker://reset-password');
      final scheme = Uri.parse(authResetRedirectUrl).scheme;
      expect(plist, contains('<string>$scheme</string>'));
    });

    test('Flutter deep linking is off so the auth link reaches app_links only', () {
      // Left on, the link is also pushed as a named route. MaterialApp has only
      // `home` here, so a route carrying the auth code is an unknown route.
      expect(plist, matches(RegExp(r'<key>FlutterDeepLinkingEnabled</key>\s*<false/>')));
    });
  });

  group('Info.plist', () {
    final plist = _read(infoPlistPath);

    test('the default display name is the English app name', () {
      expect(_plistString(plist, 'CFBundleDisplayName'), 'Qawam Money');
      expect(_plistString(plist, 'CFBundleName'), 'Qawam Money');
    });

    test('declares a usage description for every permission the plugins use', () {
      for (final key in usageKeys) {
        expect(_plistString(plist, key), isNotEmpty, reason: key);
      }
    });

    test('declares the three app languages', () {
      expect(_plistStrings(plist, 'CFBundleLocalizations'), unorderedEquals(['ar', 'en', 'ur']));
    });
  });

  group('InfoPlist.strings', () {
    const names = {'en': 'Qawam Money', 'ar': 'قوام المال', 'ur': 'Qawam Money'};

    for (final entry in names.entries) {
      final path = 'ios/Runner/${entry.key}.lproj/InfoPlist.strings';

      test('${entry.key} localizes the name and every permission', () {
        final strings = _strings(path);
        expect(strings['CFBundleDisplayName'], entry.value);
        expect(strings['CFBundleName'], entry.value);
        for (final key in usageKeys) {
          expect(strings[key], isNotEmpty, reason: key);
        }
      });

      test('${entry.key} has no withdrawn names', () {
        expect(_read(path), isNot(matches(RegExp('wafeer|budget tracker', caseSensitive: false))));
      });
    }

    test('Arabic and Urdu permission text is translated, not the English copy', () {
      final en = _strings('ios/Runner/en.lproj/InfoPlist.strings');
      final arabicScript = RegExp(r'[؀-ۿ]');
      for (final lang in ['ar', 'ur']) {
        final strings = _strings('ios/Runner/$lang.lproj/InfoPlist.strings');
        for (final key in usageKeys) {
          expect(strings[key], isNot(en[key]), reason: '$lang $key');
          expect(strings[key], matches(arabicScript), reason: '$lang $key');
        }
      }
    });

    test('Urdu uses the Latin app name, with no Urdu-script form', () {
      final strings = _strings('ios/Runner/ur.lproj/InfoPlist.strings');
      for (final key in usageKeys) {
        expect(strings[key], contains('Qawam Money'), reason: key);
        expect(strings[key], isNot(contains('قوام')), reason: key);
      }
    });

    test('the Xcode project ships all three files', () {
      final pbxproj = _read(pbxprojPath);
      expect(pbxproj, contains('/* InfoPlist.strings in Resources */,'));
      for (final lang in names.keys) {
        expect(pbxproj, contains('path = $lang.lproj/InfoPlist.strings;'));
      }
      final regions = RegExp(r'knownRegions = \((.*?)\);', dotAll: true).firstMatch(pbxproj)!.group(1)!;
      for (final lang in ['en', 'ar', 'ur', 'Base']) {
        expect(regions, contains('$lang,'));
      }
    });
  });

  group('plugin setup', () {
    test('the deployment target is the same in the project and the Podfile', () {
      final targets = RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);')
          .allMatches(_read(pbxprojPath))
          .map((m) => m.group(1))
          .toSet();
      expect(targets, {'15.0'});
      expect(_read('ios/Podfile'), matches(RegExp(r"^platform :ios, '15\.0'", multiLine: true)));
    });

    test('the Podfile enables only the permission_handler groups the app uses', () {
      final enabled = RegExp(r"'PERMISSION_(\w+)=1'").allMatches(_read('ios/Podfile')).map((m) => m.group(1)).toSet();
      expect(enabled, {'CAMERA', 'MICROPHONE', 'NOTIFICATIONS'});
    });

    test('the app requests no permission_handler group beyond the enabled ones', () {
      final used = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .expand((f) => RegExp(r'\bPermission\.(\w+)').allMatches(f.readAsStringSync()))
          .map((m) => m.group(1))
          .toSet();
      expect(used, {'camera', 'microphone', 'notification'});
    });

    test('AppDelegate sets the notification delegate before launch finishes', () {
      final delegate = _read('ios/Runner/AppDelegate.swift');
      final set = delegate.indexOf('UNUserNotificationCenter.current().delegate');
      expect(set, greaterThanOrEqualTo(0));
      expect(set, lessThan(delegate.indexOf('super.application(')));
    });
  });
}
