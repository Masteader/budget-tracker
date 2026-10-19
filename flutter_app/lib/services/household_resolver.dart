import 'package:shared_preferences/shared_preferences.dart';

/// Fetches the signed-in user's `users.household_id` from the server.
/// Returns null when the user has no household yet; throws on network errors.
typedef RemoteHouseholdFetcher = Future<String?> Function(String userId);

/// Resolves the active household for a user, offline-first.
///
/// The last household confirmed by the server is cached per user so that an
/// app start without connectivity opens the user's dashboard (with its offline
/// queue) instead of the "create or join a household" onboarding screen.
class HouseholdResolver {
  final RemoteHouseholdFetcher fetchRemote;

  const HouseholdResolver({required this.fetchRemote});

  static String cacheKeyFor(String userId) => 'last_household_id_$userId';

  /// Returns the household id, or null when the server says the user has none.
  /// Rethrows the network error only when there is no cached household.
  Future<String?> resolve(String userId) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      prefs = null;
    }
    final key = cacheKeyFor(userId);

    try {
      final householdId = await fetchRemote(userId);
      if (householdId == null || householdId.isEmpty) {
        await prefs?.remove(key);
        return null;
      }
      await prefs?.setString(key, householdId);
      return householdId;
    } catch (_) {
      final cached = prefs?.getString(key);
      if (cached != null && cached.isNotEmpty) return cached;
      rethrow;
    }
  }
}
