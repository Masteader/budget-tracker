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
  final String? financialRole;
  final bool isPrimary;
  final bool isSelf;

  const HouseholdMember({
    required this.userId,
    this.displayName,
    this.role = 'member',
    this.financialRole,
    this.isPrimary = false,
    this.isSelf = false,
  });

  bool get isAdmin => role.toLowerCase() == 'admin';

  factory HouseholdMember.fromMap(Map<String, dynamic> map) => HouseholdMember(
        userId: map['user_id'] as String? ?? '',
        displayName: map['display_name'] as String?,
        role: map['role'] as String? ?? 'member',
        financialRole: map['financial_role'] as String?,
        isPrimary: map['is_primary'] as bool? ?? false,
        isSelf: map['is_self'] as bool? ?? false,
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
  final List<HouseholdMember> members;

  const HouseholdRoster({
    required this.householdId,
    this.primaryAdminUserId,
    this.callerRole,
    this.callerIsPrimary = false,
    this.canManageAdmins = false,
    this.canTransferPrimary = false,
    this.members = const [],
  });

  factory HouseholdRoster.fromMap(Map<String, dynamic> map) => HouseholdRoster(
        householdId: map['household_id'] as String? ?? '',
        primaryAdminUserId: map['primary_admin_user_id'] as String?,
        callerRole: map['caller_role'] as String?,
        callerIsPrimary: map['caller_is_primary'] as bool? ?? false,
        canManageAdmins: map['can_manage_admins'] as bool? ?? false,
        canTransferPrimary: map['can_transfer_primary'] as bool? ?? false,
        members: ((map['members'] as List?) ?? const [])
            .map((e) => HouseholdMember.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  /// Role actions the caller may take on [member].
  bool canPromote(HouseholdMember member) => canManageAdmins && !member.isAdmin;
  bool canRevoke(HouseholdMember member) => canManageAdmins && member.isAdmin && !member.isPrimary;
  bool canMakePrimary(HouseholdMember member) => canTransferPrimary && !member.isSelf && !member.isPrimary;
}
