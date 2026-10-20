/// Supabase + FastAPI client configuration, supplied at build time with
/// `--dart-define` (see README "Flutter App (--dart-define flags)").
///
/// No environment, URL or key is hard-coded: a build without the required
/// defines fails fast at startup with a message naming the missing flags
/// (see [validateClientConfig]), instead of silently talking to production.
///
/// Only the Supabase publishable/anon key belongs in the client. Anything
/// compiled into the app can be extracted from the APK/IPA, so service-role
/// keys are rejected outright.
library;

import 'dart:convert';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

const supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
);

/// Deprecated: alias for [supabasePublishableKey].
const supabaseAnonKey = supabasePublishableKey;

const fastapiBaseUrl = String.fromEnvironment('FASTAPI_BASE_URL');

const fastapiWebhookUrl = String.fromEnvironment(
  'FASTAPI_WEBHOOK_URL',
  defaultValue: fastapiBaseUrl,
);

const authRedirectUrl = String.fromEnvironment(
  'AUTH_REDIRECT_URL',
  defaultValue: fastapiBaseUrl,
);

/// Optional HMAC key for the `X-Signature` header. When provided with
/// `--dart-define=WEBHOOK_SECRET=...` POST requests are signed; when it is
/// missing they are sent unsigned and the app still starts normally.
///
/// Requests are authenticated by the user's Supabase JWT. The backend treats a
/// signature as defense in depth: it is not required, but a signature that is
/// present must match the backend's WEBHOOK_SECRET (otherwise 401). The key is
/// extractable from the binary, so it is never an authentication secret; a
/// build signed with an old, rotated key must be rebuilt (or built without it).
const webhookSecret = String.fromEnvironment('WEBHOOK_SECRET');

/// Returns every configuration problem (empty when the configuration is usable).
List<String> validateClientConfig({
  required String supabaseUrl,
  required String supabaseKey,
  required String fastapiBaseUrl,
  required bool isRelease,
}) {
  final problems = <String>[];

  if (supabaseUrl.isEmpty) {
    problems.add('Missing --dart-define=SUPABASE_URL');
  } else if (isRelease && !supabaseUrl.startsWith('https://')) {
    problems.add('SUPABASE_URL must use https:// in release builds');
  }

  if (supabaseKey.isEmpty) {
    problems.add('Missing --dart-define=SUPABASE_PUBLISHABLE_KEY (or SUPABASE_ANON_KEY)');
  } else if (isPrivilegedSupabaseKey(supabaseKey)) {
    problems.add(
      'The Supabase key is a service-role/secret key. Only the publishable (anon) key may be compiled into the app.',
    );
  }

  if (fastapiBaseUrl.isEmpty) {
    problems.add('Missing --dart-define=FASTAPI_BASE_URL');
  } else if (isRelease && !fastapiBaseUrl.startsWith('https://')) {
    problems.add('FASTAPI_BASE_URL must use https:// in release builds');
  }

  return problems;
}

/// True for keys that bypass Row Level Security: new-style `sb_secret_...`
/// keys and legacy JWT keys whose `role` claim is `service_role`.
bool isPrivilegedSupabaseKey(String key) {
  final k = key.trim();
  if (k.startsWith('sb_secret_')) return true;
  final parts = k.split('.');
  if (parts.length != 3) return false;
  try {
    final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final claims = jsonDecode(payload);
    return claims is Map && claims['role'] == 'service_role';
  } catch (_) {
    return false;
  }
}

/// Throws a [StateError] listing every problem with the compiled-in configuration.
void ensureValidClientConfig({required bool isRelease}) {
  final problems = validateClientConfig(
    supabaseUrl: supabaseUrl,
    supabaseKey: supabasePublishableKey,
    fastapiBaseUrl: fastapiBaseUrl,
    isRelease: isRelease,
  );
  if (problems.isNotEmpty) {
    throw StateError('Invalid Budget Tracker build configuration:\n- ${problems.join('\n- ')}');
  }
}
