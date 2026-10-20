// MOB-19: the Supabase session must live in the platform secure store, with a
// one-time migration out of plaintext SharedPreferences.
import 'dart:io';

import 'package:budget_tracker/services/secure_session_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements SessionKeyValueStore {
  final Map<String, String> values = {};
  bool failWrites = false;
  bool failReads = false;
  bool failDeletes = false;
  int writes = 0;

  @override
  Future<String?> read(String key) async {
    if (failReads) throw StateError('keystore unavailable');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('keystore unavailable');
    writes++;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDeletes) throw StateError('keystore unavailable');
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = 'sb-abcd-auth-token';
  const sessionJson = '{"access_token":"a","refresh_token":"r"}';

  late _MemoryStore secure;
  late _MemoryStore legacy;
  late SecureSessionLocalStorage storage;

  setUp(() {
    secure = _MemoryStore();
    legacy = _MemoryStore();
    storage = SecureSessionLocalStorage(
      persistSessionKey: key,
      secureStore: secure,
      legacyStore: legacy,
    );
  });

  test('uses the same key as supabase_flutter so the old session is found', () {
    expect(
      SecureSessionLocalStorage.sessionKeyFor('https://abcd.supabase.co'),
      key,
    );
  });

  test('migrates a plaintext session into secure storage and deletes it', () async {
    legacy.values[key] = sessionJson;

    await storage.initialize();

    expect(secure.values[key], sessionJson);
    expect(legacy.values.containsKey(key), isFalse);
    expect(await storage.hasAccessToken(), isTrue);
    expect(await storage.accessToken(), sessionJson);
  });

  test('keeps the plaintext copy when the secure write fails, so the user stays signed in', () async {
    legacy.values[key] = sessionJson;
    secure.failWrites = true;

    await storage.initialize();

    expect(legacy.values[key], sessionJson, reason: 'retry migration next start');
    expect(await storage.accessToken(), sessionJson);
  });

  test('a stale plaintext copy is deleted when a secure session already exists', () async {
    secure.values[key] = 'new';
    legacy.values[key] = 'old';

    await storage.initialize();

    expect(await storage.accessToken(), 'new');
    expect(legacy.values.containsKey(key), isFalse);
    expect(secure.values[key], 'new');
  });

  test('without any stored session there is no access token', () async {
    await storage.initialize();
    expect(await storage.hasAccessToken(), isFalse);
    expect(await storage.accessToken(), isNull);
  });

  test('an unreadable secure store does not crash start-up', () async {
    secure.failReads = true;
    await storage.initialize();
    expect(await storage.hasAccessToken(), isFalse);
  });

  test('persistSession writes only to secure storage and clears plaintext', () async {
    legacy.values[key] = 'old';
    await storage.initialize();

    await storage.persistSession('refreshed');

    expect(secure.values[key], 'refreshed');
    expect(legacy.values.containsKey(key), isFalse);
    expect(await storage.accessToken(), 'refreshed');
  });

  test('persistSession never falls back to plaintext when the secure write fails', () async {
    await storage.initialize();
    secure.failWrites = true;

    await storage.persistSession('fresh');

    expect(legacy.values, isEmpty);
    expect(await storage.accessToken(), 'fresh', reason: 'session usable for this run');
  });

  test('removePersistedSession clears both stores', () async {
    secure.values[key] = sessionJson;
    legacy.values[key] = sessionJson;
    await storage.initialize();

    await storage.removePersistedSession();

    expect(secure.values, isEmpty);
    expect(legacy.values, isEmpty);
    expect(await storage.hasAccessToken(), isFalse);
  });

  test('main.dart wires the secure storage into Supabase.initialize', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('localStorage: SecureSessionLocalStorage('));
  });

  test('Android minSdk satisfies flutter_secure_storage (plugin minSdk 24) and backups stay off', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final minSdk = int.parse(RegExp(r'minSdk\s*=\s*(\d+)').firstMatch(gradle)!.group(1)!);
    expect(minSdk, greaterThanOrEqualTo(24));
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:allowBackup="false"'));
  });
}
