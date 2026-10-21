/// Household membership model representing a user's role and link to a household.
class HouseholdMembership {
  final String householdId;
  final String householdName;
  final String inviteCode;
  final String role;
  final bool isActive;

  /// The household's primary admin (creator/owner). Co-admins cannot demote
  /// them; only they transfer primary admin.
  final bool isPrimary;

  const HouseholdMembership({
    required this.householdId,
    required this.householdName,
    required this.inviteCode,
    this.role = 'member',
    this.isActive = false,
    this.isPrimary = false,
  });

  bool get isAdmin => role.toLowerCase() == 'admin';

  factory HouseholdMembership.fromMap(Map<String, dynamic> map) {
    return HouseholdMembership(
      householdId: map['household_id'] as String? ?? '',
      householdName: map['household_name'] as String? ?? 'Household',
      inviteCode: map['invite_code'] as String? ?? '',
      role: map['role'] as String? ?? 'member',
      isActive: map['is_active'] as bool? ?? false,
      isPrimary: map['is_primary'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'household_id': householdId,
      'household_name': householdName,
      'invite_code': inviteCode,
      'role': role,
      'is_active': isActive,
      'is_primary': isPrimary,
    };
  }
}

/// A member of a household with their role, as served by
/// `GET /households/{id}/members` (primary admin first).
class HouseholdMember {
  final String userId;
  final String? displayName;
  final String role;
  /// The financial role in THIS household (`household_memberships.financial_role`:
  /// 'provider' | 'spouse' | 'family_member' | 'peer'), never the per-user cache.
  final String? financialRole;
  final bool isPrimary;
  final bool isSelf;

  /// The household's Nafaqah provider (husband), chosen explicitly by an admin.
  final bool isNafaqahProvider;

  const HouseholdMember({
    required this.userId,
    this.displayName,
    this.role = 'member',
    this.financialRole,
    this.isPrimary = false,
    this.isSelf = false,
    this.isNafaqahProvider = false,
  });

  bool get isAdmin => role.toLowerCase() == 'admin';

  /// A wife in this household (she can never be the Nafaqah provider).
  bool get isSpouse => (financialRole ?? '').toLowerCase() == 'spouse';

  bool get isPeer => (financialRole ?? '').toLowerCase() == 'peer';

  factory HouseholdMember.fromMap(Map<String, dynamic> map) => HouseholdMember(
        userId: map['user_id'] as String? ?? '',
        displayName: map['display_name'] as String?,
        role: map['role'] as String? ?? 'member',
        financialRole: map['financial_role'] as String?,
        isPrimary: map['is_primary'] as bool? ?? false,
        isSelf: map['is_self'] as bool? ?? false,
        isNafaqahProvider: map['is_nafaqah_provider'] as bool? ?? false,
      );
}

/// Members of a household and what the signed-in user may change.
class HouseholdRoster {
  final String householdId;
  final String? primaryAdminUserId;
  final String? callerRole;
  final bool callerIsPrimary;
  final bool canManageAdmins;
  final bool canTransferPrimary;

  /// `households.nafaqah_provider_user_id` as stored (the husband).
  final String? nafaqahProviderUserId;

  /// Any admin may choose the Nafaqah provider (`PUT .../nafaqah/provider`).
  final bool canSetNafaqahProvider;
  final List<HouseholdMember> members;

  const HouseholdRoster({
    required this.householdId,
    this.primaryAdminUserId,
    this.callerRole,
    this.callerIsPrimary = false,
    this.canManageAdmins = false,
    this.canTransferPrimary = false,
    this.nafaqahProviderUserId,
    this.canSetNafaqahProvider = false,
    this.members = const [],
  });

  factory HouseholdRoster.fromMap(Map<String, dynamic> map) => HouseholdRoster(
        householdId: map['household_id'] as String? ?? '',
        primaryAdminUserId: map['primary_admin_user_id'] as String?,
        callerRole: map['caller_role'] as String?,
        callerIsPrimary: map['caller_is_primary'] as bool? ?? false,
        canManageAdmins: map['can_manage_admins'] as bool? ?? false,
        canTransferPrimary: map['can_transfer_primary'] as bool? ?? false,
        nafaqahProviderUserId: map['nafaqah_provider_user_id'] as String?,
        canSetNafaqahProvider: map['can_set_nafaqah_provider'] as bool? ?? false,
        members: ((map['members'] as List?) ?? const [])
            .map((e) => HouseholdMember.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  /// Role actions the caller may take on [member].
  bool canPromote(HouseholdMember member) => canManageAdmins && !member.isAdmin;
  bool canRevoke(HouseholdMember member) => canManageAdmins && member.isAdmin && !member.isPrimary;
  bool canMakePrimary(HouseholdMember member) => canTransferPrimary && !member.isSelf && !member.isPrimary;

  /// Family (Nafaqah) household: a member is a wife.
  bool get isFamily => members.any((m) => m.isSpouse);

  /// Roommates (peers, no wife): the Nafaqah provider does not apply.
  bool get isRoommateHousehold => !isFamily && members.any((m) => m.isPeer);

  /// The provider while he is still a non-spouse member (mirrors the server's
  /// `nafaqah_husband_id`); null when none is set or he left.
  HouseholdMember? get nafaqahProvider {
    for (final m in members) {
      final isProvider = m.isNafaqahProvider || (nafaqahProviderUserId != null && m.userId == nafaqahProviderUserId);
      if (isProvider && !m.isSpouse) return m;
    }
    return null;
  }

  /// A family without a valid provider: wife-paid expenses are refused until
  /// an admin chooses one.
  bool get needsNafaqahProvider => isFamily && nafaqahProvider == null;

  /// Members an admin may choose as the provider: everyone but the wives.
  List<HouseholdMember> get nafaqahProviderCandidates => members.where((m) => !m.isSpouse).toList();
}
