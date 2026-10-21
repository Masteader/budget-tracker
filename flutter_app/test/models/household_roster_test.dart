// GET /households/{id}/members: financial role per membership and the
// explicit Nafaqah provider (FABLE-LOGIC-01 / -04).
import 'package:budget_tracker/models/household_membership.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _member(String id, String role, String financialRole, {bool provider = false, bool primary = false}) => {
      'user_id': id,
      'display_name': id.toUpperCase(),
      'role': role,
      'financial_role': financialRole,
      'is_primary': primary,
      'is_nafaqah_provider': provider,
      'is_self': false,
    };

void main() {
  test('parses the provider flag, the provider id and who may change it', () {
    final roster = HouseholdRoster.fromMap({
      'household_id': 'hh',
      'primary_admin_user_id': 'son',
      'nafaqah_provider_user_id': 'husband',
      'can_set_nafaqah_provider': true,
      'members': [
        _member('son', 'admin', 'provider', primary: true),
        _member('husband', 'member', 'provider', provider: true),
        _member('wife', 'member', 'spouse'),
      ],
    });

    expect(roster.nafaqahProviderUserId, 'husband');
    expect(roster.canSetNafaqahProvider, isTrue);
    expect(roster.members[1].isNafaqahProvider, isTrue);
    expect(roster.members[0].isNafaqahProvider, isFalse);
    expect(roster.members[2].isSpouse, isTrue);
    expect(roster.isFamily, isTrue);
    expect(roster.nafaqahProvider?.userId, 'husband');
    expect(roster.needsNafaqahProvider, isFalse);
    expect(roster.nafaqahProviderCandidates.map((m) => m.userId), ['son', 'husband'],
        reason: 'a wife is never offered as the provider');
  });

  test('a family whose provider is missing (or left) needs one', () {
    final roster = HouseholdRoster.fromMap({
      'household_id': 'hh',
      'nafaqah_provider_user_id': null,
      'members': [
        _member('a', 'admin', 'family_member', primary: true),
        _member('wife', 'member', 'spouse'),
      ],
    });
    expect(roster.isFamily, isTrue);
    expect(roster.needsNafaqahProvider, isTrue);
    expect(roster.canSetNafaqahProvider, isFalse);

    final gone = HouseholdRoster.fromMap({
      'household_id': 'hh',
      'nafaqah_provider_user_id': 'left-already',
      'members': [_member('wife', 'admin', 'spouse', primary: true)],
    });
    expect(gone.needsNafaqahProvider, isTrue);
  });

  test('roommates are neither a family nor in need of a provider', () {
    final roster = HouseholdRoster.fromMap({
      'household_id': 'hh',
      'nafaqah_provider_user_id': 'a',
      'members': [
        _member('a', 'admin', 'peer', primary: true, provider: true),
        _member('b', 'member', 'peer'),
      ],
    });
    expect(roster.isFamily, isFalse);
    expect(roster.isRoommateHousehold, isTrue);
    expect(roster.needsNafaqahProvider, isFalse);
  });

  test('older servers without provider fields parse safely', () {
    final roster = HouseholdRoster.fromMap({
      'household_id': 'hh',
      'members': [
        {'user_id': 'a', 'role': 'admin'},
      ],
    });
    expect(roster.nafaqahProviderUserId, isNull);
    expect(roster.canSetNafaqahProvider, isFalse);
    expect(roster.members.single.isNafaqahProvider, isFalse);
    expect(roster.isFamily, isFalse);
  });
}
