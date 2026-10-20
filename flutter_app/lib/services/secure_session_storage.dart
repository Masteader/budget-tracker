import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Minimal string key-value store, so the session storage can be unit tested
/// with in-memory fakes instead of the platform Keystore / Keychain.
abstract class SessionKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Android Keystore / iOS Keychain backed store.
///
/// * Android: `AndroidOptions()` is the plugin's default since v10: an AES-GCM
///   data key wrapped with a Keystore RSA-OAEP key (plugin minSdk 24; the app's is 26).
///   The older `encryptedSharedPreferences` flag relied on the deprecated
///   Jetpack Security library and no longer exists in flutter_secure_storage 11;
///   data written by it is migrated by the plugin (`migrateOnAlgorithmChange`).
///   `resetOnError` drops an undecryptable value (e.g. after a device restore)
///   instead of crashing; the user simply signs in again.
/// * iOS: `first_unlock_this_device` keeps the token out of iCloud Keychain and
///   device-to-device backups while allowing background token refreshes.
class FlutterSecureKeyValueStore implements SessionKeyValueStore {
  FlutterSecureKeyValueStore([FlutterSecureStorage? storage]) : _storage = storage ?? defaultStorage;

  static const FlutterSecureStorage defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true, migrateOnAlgorithmChange: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// The plaintext SharedPreferences store used by supabase_flutter's default
/// `SharedPreferencesLocalStorage`. Only read to migrate and then delete.
class SharedPreferencesKeyValueStore implements SessionKeyValueStore {
  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _prefs()).getString(key);

  @override
  Future<void> write(String key, String value) async => (await _prefs()).setString(key, value);

  @override
  Future<void> delete(String key) async => (await _prefs()).remove(key);
}

/// Supabase session persistence in the platform secure store (MOB-19).
///
/// supabase_flutter's default keeps the session JSON, including the long-lived
/// refresh token, in plaintext SharedPreferences. This storage keeps it in the
/// Keystore/Keychain instead and, on first start after the update, moves an
/// existing plaintext session across and deletes the plaintext copy, so users
/// stay signed in.
///
/// Failure policy: if the secure store cannot be written during migration the
/// plaintext copy is left in place (the user stays signed in and the move is
/// retried on the next start). Once a session is written or removed through
/// this storage the plaintext copy is always deleted, so it is never written
/// to SharedPreferences again.
class SecureSessionLocalStorage extends LocalStorage {
  SecureSessionLocalStorage({
    required this.persistSessionKey,
    SessionKeyValueStore? secureStore,
    SessionKeyValueStore? legacyStore,
  })  : _secure = secureStore ?? FlutterSecureKeyValueStore(),
        _legacy = legacyStore ?? SharedPreferencesKeyValueStore();

  /// Same key supabase_flutter uses for its SharedPreferences storage, so the
  /// existing session can be found and migrated.
  static String sessionKeyFor(String supabaseUrl) =>
      'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';

  final String persistSessionKey;
  final SessionKeyValueStore _secure;
  final SessionKeyValueStore _legacy;

  /// Latest session JSON for this run. supabase_flutter only reads the stored
  /// session at start-up; later reads are served from here.
  String? _session;

  @override
  Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    _session = await _readSecure();

    final String? legacy;
    try {
      legacy = await _legacy.read(persistSessionKey);
    } catch (e) {
      debugPrint('[SecureSessionLocalStorage] Could not read legacy session: $e');
      return;
    }
    if (legacy == null) return;

    if (_session != null) {
      // Already migrated; the plaintext copy is stale.
      await _deleteLegacy();
      return;
    }

    try {
      await _secure.write(persistSessionKey, legacy);
      if (await _secure.read(persistSessionKey) == legacy) {
        await _deleteLegacy();
      } else {
        debugPrint('[SecureSessionLocalStorage] Secure write did not verify; keeping legacy copy for retry.');
      }
    } catch (e) {
      debugPrint('[SecureSessionLocalStorage] Secure write failed; keeping legacy copy for retry: $e');
    }
    _session = legacy;
  }

  Future<String?> _readSecure() async {
    try {
      return await _secure.read(persistSessionKey);
    } catch (e) {
      debugPrint('[SecureSessionLocalStorage] Could not read secure session: $e');
      return null;
    }
  }

  Future<void> _deleteLegacy() async {
    try {
      await _legacy.delete(persistSessionKey);
    } catch (e) {
      debugPrint('[SecureSessionLocalStorage] Could not delete legacy session: $e');
    }
  }

  @override
  Future<bool> hasAccessToken() async => _session != null;

  @override
  Future<String?> accessToken() async => _session;

  @override
  Future<void> persistSession(String persistSessionString) async {
    _session = persistSessionString;
    try {
      await _secure.write(persistSessionKey, persistSessionString);
    } catch (e) {
      // The session stays usable for this run; it is never written in plaintext.
      debugPrint('[SecureSessionLocalStorage] Could not persist session securely: $e');
    }
    await _deleteLegacy();
  }

  @override
  Future<void> removePersistedSession() async {
    _session = null;
    try {
      await _secure.delete(persistSessionKey);
    } catch (e) {
      debugPrint('[SecureSessionLocalStorage] Could not delete secure session: $e');
    }
    await _deleteLegacy();
  }
}
