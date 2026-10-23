import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/supabase_config.dart';

String _jwt(Map<String, dynamic> claims) {
  String seg(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${seg({'alg': 'HS256', 'typ': 'JWT'})}.${seg(claims)}.signature';
}

void main() {
  group('MOB-02 client configuration', () {
    test('safe public defaults are compiled in as fallbacks and non-privileged', () {
      expect(defaultSupabaseUrl, startsWith('https://'));
      expect(defaultFastapiBaseUrl, startsWith('https://'));
      expect(defaultSupabasePublishableKey, isNotEmpty);
      expect(isPrivilegedSupabaseKey(defaultSupabasePublishableKey), isFalse);

      final problems = validateClientConfig(
        supabaseUrl: defaultSupabaseUrl,
        supabaseKey: defaultSupabasePublishableKey,
        fastapiBaseUrl: defaultFastapiBaseUrl,
        isRelease: true,
      );
      expect(problems, isEmpty);
    });

    test('no static app token or other shared secret is read by the client', () {
      final libDir = Directory('lib');
      final offenders = <String>[];
      for (final f in libDir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final text = f.readAsStringSync();
        if (text.contains("'APP_AUTH_TOKEN'") || text.contains('X-App-Token') || text.contains('SERVICE_ROLE')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty);
    });

    test('a build without defines fails with every missing flag named', () {
      final problems = validateClientConfig(
        supabaseUrl: '',
        supabaseKey: '',
        fastapiBaseUrl: '',
        isRelease: true,
      );
      expect(problems.join('\n'), contains('SUPABASE_URL'));
      expect(problems.join('\n'), contains('SUPABASE_PUBLISHABLE_KEY'));
      expect(problems.join('\n'), contains('FASTAPI_BASE_URL'));
      // WEBHOOK_SECRET is optional: requests are authenticated by the user's JWT.
      expect(problems.join('\n'), isNot(contains('WEBHOOK_SECRET')));
    });

    test('a release build without WEBHOOK_SECRET is valid (signing is optional)', () {
      final problems = validateClientConfig(
        supabaseUrl: 'https://x.supabase.co',
        supabaseKey: 'sb_publishable_example',
        fastapiBaseUrl: 'https://api.example.com',
        isRelease: true,
      );
      expect(problems, isEmpty);
    });

    test('the client config no longer requires WEBHOOK_SECRET at startup', () {
      final source = File('lib/supabase_config.dart').readAsStringSync();
      expect(source, isNot(contains('Missing --dart-define=WEBHOOK_SECRET')));
    });

    test('ensureValidClientConfig succeeds with default config, throws on invalid config', () {
      // Default compiled-in config is valid out of the box
      expect(() => ensureValidClientConfig(isRelease: true), returnsNormally);

      // Throws on missing URL or key
      expect(
        () => ensureValidClientConfig(isRelease: true, customUrl: ''),
        throwsStateError,
      );
      expect(
        () => ensureValidClientConfig(isRelease: true, customKey: ''),
        throwsStateError,
      );

      // Throws on privileged service role key
      expect(
        () => ensureValidClientConfig(isRelease: true, customKey: 'sb_secret_admin'),
        throwsStateError,
      );
    });

    test('debug builds accept cleartext local endpoints', () {
      final problems = validateClientConfig(
        supabaseUrl: 'http://10.0.2.2:54321',
        supabaseKey: 'sb_publishable_example',
        fastapiBaseUrl: 'http://10.0.2.2:8000',
        isRelease: false,
      );
      expect(problems, isEmpty);
    });

    test('release builds reject cleartext endpoints', () {
      final problems = validateClientConfig(
        supabaseUrl: 'http://example.supabase.co',
        supabaseKey: 'sb_publishable_example',
        fastapiBaseUrl: 'http://api.example.com',
        isRelease: true,
      );
      expect(problems, hasLength(2));
    });

    test('service-role keys are rejected, publishable/anon keys accepted', () {
      expect(isPrivilegedSupabaseKey('sb_secret_abc'), isTrue);
      expect(isPrivilegedSupabaseKey(_jwt({'role': 'service_role', 'iss': 'supabase'})), isTrue);
      expect(isPrivilegedSupabaseKey(_jwt({'role': 'anon', 'iss': 'supabase'})), isFalse);
      expect(isPrivilegedSupabaseKey('sb_publishable_abc'), isFalse);

      final problems = validateClientConfig(
        supabaseUrl: 'https://x.supabase.co',
        supabaseKey: _jwt({'role': 'service_role'}),
        fastapiBaseUrl: 'https://api.example.com',
        isRelease: true,
      );
      expect(problems.single, contains('service-role'));
    });
  });

  test('MOB-25 / DB-17: the invite code is never selected directly from a table', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('.select(') && lines[i].contains('invite_code')) {
          offenders.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  group('MOB-18 Android hardening', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    test('zero SMS policy: no SMS permissions or receivers', () {
      expect(manifest, isNot(contains('READ_SMS')));
      expect(manifest, isNot(contains('RECEIVE_SMS')));
      expect(manifest, isNot(contains('SMS_RECEIVED')));
      final pubspec = File('pubspec.yaml').readAsStringSync().toLowerCase();
      expect(pubspec, isNot(contains('telephony')));
      expect(pubspec, isNot(contains('sms')));
    });

    test('zero SMS policy: no SMS reading, parsing or SMS channel in app code', () {
      // `raw_sms` is the historical name of the transactions audit-note column, not SMS data.
      final smsCode = RegExp(
        r"webhook/sms|telephony|SmsMessage|SmsQuery|readSms|sms_advanced|flutter_sms|'sms'|" r'"sms"',
        caseSensitive: false,
      );
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (smsCode.hasMatch(lines[i])) offenders.add('${f.path}:${i + 1}');
        }
      }
      expect(offenders, isEmpty);
    });

    test('app data (session tokens, offline queue, receipts) is excluded from backups', () {
      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:fullBackupContent="false"'));
      expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
      expect(File('android/app/src/main/res/xml/data_extraction_rules.xml').existsSync(), isTrue);
    });

    test('cleartext traffic is disabled explicitly', () {
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
    });

    test('release builds are not signed with the debug key when a release keystore is configured', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('key.properties'));
      expect(gradle, contains('create("release")'));
      expect(gradle, contains('signingConfigs.getByName("release")'));
      expect(gradle, isNot(contains('TODO')));
    });
  });
}
