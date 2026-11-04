/// Decides which incoming deep links `supabase_flutter` may treat as auth
/// callbacks. Passed to Supabase as `detectSessionInUriPredicate`.
///
/// Any app or web page can open a custom-scheme link, so a link is untrusted
/// input. A link carrying tokens is never accepted: under PKCE, gotrue still
/// saves tokens found in a URL, so one link could sign a victim in to an
/// attacker's account and collect their financial data there. A PKCE `code` is
/// safe because exchanging it needs the verifier stored on this device when
/// this device asked for the email.
///
/// `error*` parameters are accepted on the expected targets because Supabase
/// reports an expired link that way. gotrue only throws for them, before any
/// session is read or written, and `AuthGate` shows its own localized message.
library;

const _appScheme = 'budgettracker';

/// The hosts `AndroidManifest.xml` declares under [_appScheme]. iOS delivers
/// every host under a scheme, so this list is what limits it there.
const _appHosts = {'reset-password', 'auth-callback', 'login'};

/// Declared without a host in `AndroidManifest.xml`, so any host is expected.
const _supabaseScheme = 'io.supabase.budgettracker';

const _tokenParameters = {
  'access_token',
  'refresh_token',
  'provider_token',
  'provider_refresh_token',
};

const _errorParameters = {'error', 'error_code', 'error_description'};

/// True only for a link from an expected target that carries a PKCE `code` or
/// a Supabase error, and no tokens. Fails closed on malformed parameters.
bool isTrustedAuthDeepLink(Uri uri) {
  final expectedTarget = uri.scheme == _supabaseScheme ||
      (uri.scheme == _appScheme && _appHosts.contains(uri.host));
  if (!expectedTarget) return false;

  try {
    final query = uri.queryParameters;
    final fragment = Uri.splitQueryString(uri.fragment);
    bool hasAny(Set<String> names) => names.any((name) => query.containsKey(name) || fragment.containsKey(name));

    if (hasAny(_tokenParameters)) return false;
    if (hasAny(_errorParameters)) return true;
    return query['code']?.isNotEmpty ?? false;
  } on FormatException {
    return false;
  }
}
