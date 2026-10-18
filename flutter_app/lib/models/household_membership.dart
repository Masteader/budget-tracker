/// Household membership model representing a user's role and link to a household.
class HouseholdMembership {
  final String householdId;
  final String householdName;
  final String inviteCode;
  final String role;
  final bool isActive;

  const HouseholdMembership({
    required this.householdId,
    required this.householdName,
    required this.inviteCode,
    this.role = 'member',
    this.isActive = false,
  });

  bool get isAdmin => role.toLowerCase() == 'admin';

  factory HouseholdMembership.fromMap(Map<String, dynamic> map) {
    return HouseholdMembership(
      householdId: map['household_id'] as String? ?? '',
      householdName: map['household_name'] as String? ?? 'Household',
      inviteCode: map['invite_code'] as String? ?? '',
      role: map['role'] as String? ?? 'member',
      isActive: map['is_active'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'household_id': householdId,
      'household_name': householdName,
      'invite_code': inviteCode,
      'role': role,
      'is_active': isActive,
    };
  }
}
