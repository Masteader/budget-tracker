import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/household_permissions.dart';

typedef MembershipsLoader = Future<List<HouseholdMembership>> Function();
typedef CurrentUserIdReader = String? Function();

/// The signed-in user's role in the active household (admin / member, and
/// whether they are the primary admin), used to show only the actions the
/// server will accept: editing or deleting other members' transactions and
/// moving money out of shared pools are admin-only (DB-16 / DB-18).
class HouseholdRoleProvider extends ChangeNotifier {
  HouseholdRoleProvider({MembershipsLoader? loadMemberships, CurrentUserIdReader? currentUserId})
      : _loadMemberships = loadMemberships ?? (() => ApiService.instance.budget.getUserHouseholds()),
        _currentUserId = currentUserId ?? _supabaseUserId;

  final MembershipsLoader _loadMemberships;
  final CurrentUserIdReader _currentUserId;

  String? _householdId;
  String _role = 'member';
  bool _isPrimary = false;
  bool _isLoaded = false;
  int _generation = 0;

  String? get householdId => _householdId;
  String get role => _role;
  bool get isAdmin => _role == 'admin';
  bool get isPrimary => _isPrimary;
  bool get isLoaded => _isLoaded;
  String? get currentUserId => _currentUserId();

  static String? _supabaseUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// Loads the role for [householdId] (the active household).
  Future<void> load(String householdId) async {
    if (_householdId != householdId) {
      _householdId = householdId;
      _role = 'member';
      _isPrimary = false;
      _isLoaded = false;
      notifyListeners();
    }
    await refresh();
  }

  /// Re-reads the role from the server; keeps the last known role when offline.
  Future<void> refresh() async {
    final generation = ++_generation;
    List<HouseholdMembership> memberships;
    try {
      memberships = await _loadMemberships();
    } catch (_) {
      return;
    }
    if (generation != _generation || memberships.isEmpty) return;

    HouseholdMembership? match;
    for (final m in memberships) {
      if (_householdId != null ? m.householdId == _householdId : m.isActive) {
        match = m;
        break;
      }
    }
    if (match == null) return;
    _householdId = match.householdId;
    _role = match.isAdmin ? 'admin' : 'member';
    _isPrimary = match.isPrimary;
    _isLoaded = true;
    notifyListeners();
  }

  void reset() {
    _generation++;
    _householdId = null;
    _role = 'member';
    _isPrimary = false;
    _isLoaded = false;
    notifyListeners();
  }

  /// Whether the signed-in user may edit or delete [tx].
  bool canModify(Transaction tx) => HouseholdPermissions.canModifyTransaction(
        currentUserId: currentUserId,
        creatorUserId: tx.userId,
        isAdmin: isAdmin && (_householdId == null || tx.householdId == _householdId),
      );
}
