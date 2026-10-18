import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/household_membership.dart';

void main() {
  group('HouseholdMembership Model Tests', () {
    test('parses from map correctly', () {
      final map = {
        'household_id': 'hh-123',
        'household_name': 'Riyadh Flat',
        'invite_code': 'RF123456',
        'role': 'admin',
        'is_active': true,
      };

      final m = HouseholdMembership.fromMap(map);
      expect(m.householdId, 'hh-123');
      expect(m.householdName, 'Riyadh Flat');
      expect(m.inviteCode, 'RF123456');
      expect(m.role, 'admin');
      expect(m.isAdmin, true);
      expect(m.isActive, true);
    });

    test('serializes to map correctly', () {
      const m = HouseholdMembership(
        householdId: 'hh-456',
        householdName: "Parents' Villa",
        inviteCode: 'PV654321',
        role: 'member',
        isActive: false,
      );

      final map = m.toMap();
      expect(map['household_id'], 'hh-456');
      expect(map['role'], 'member');
      expect(m.isAdmin, false);
      expect(map['is_active'], false);
    });
  });
}
