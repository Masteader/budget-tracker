// Client mirror of the household permission rules (DB-16 / DB-18).
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/services/api/household_roles_api_client.dart';
import 'package:budget_tracker/services/household_permissions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Account _account(String id, String owner, {bool pool = false}) => Account(
      id: id,
      householdId: 'hh',
      ownerUserId: owner,
      name: id,
      accountType: pool ? AccountType.sharedPool : AccountType.bank,
      balance: 100,
      isSharedPool: pool,
    );

void main() {
  group('canModifyTransaction', () {
    test('a member edits only their own transactions', () {
      expect(HouseholdPermissions.canModifyTransaction(currentUserId: 'm', creatorUserId: 'm', isAdmin: false), isTrue);
      expect(HouseholdPermissions.canModifyTransaction(currentUserId: 'm', creatorUserId: 'p', isAdmin: false), isFalse);
    });

    test('legacy rows without a creator are admin-only', () {
      expect(HouseholdPermissions.canModifyTransaction(currentUserId: 'm', creatorUserId: null, isAdmin: false), isFalse);
      expect(HouseholdPermissions.canModifyTransaction(currentUserId: 'a', creatorUserId: null, isAdmin: true), isTrue);
    });

    test('admins (primary or co-admin) edit any transaction; signed-out users none', () {
      expect(HouseholdPermissions.canModifyTransaction(currentUserId: 'a', creatorUserId: 'm', isAdmin: true), isTrue);
      expect(HouseholdPermissions.canModifyTransaction(currentUserId: null, creatorUserId: 'm', isAdmin: true), isFalse);
    });
  });

  group('shared pool withdrawals', () {
    final accounts = [
      _account('pool', 'p', pool: true),
      _account('mine', 'm'),
      _account('mine2', 'm'),
    ];

    test('members withdraw from their own accounts only, never from a pool', () {
      final ids = HouseholdPermissions.withdrawableAccounts(accounts, currentUserId: 'm', isAdmin: false).map((a) => a.id);
      expect(ids, ['mine', 'mine2']);
    });

    test('admins may also move pool money', () {
      final ids = HouseholdPermissions.withdrawableAccounts(accounts, currentUserId: 'p', isAdmin: true).map((a) => a.id);
      expect(ids, ['pool']);
    });

    test('an account typed shared_pool counts as a pool', () {
      const typed = Account(
        id: 'typed',
        householdId: 'hh',
        ownerUserId: 'm',
        name: 'typed',
        accountType: AccountType.sharedPool,
      );
      expect(HouseholdPermissions.canWithdrawFrom(typed, currentUserId: 'm', isAdmin: false), isFalse);
    });
  });

  group('isPermissionDenied', () {
    test('recognises PostgREST 42501 and API 403', () {
      expect(HouseholdPermissions.isPermissionDenied(const PostgrestException(message: 'Forbidden: x', code: '42501')), isTrue);
      expect(HouseholdPermissions.isPermissionDenied(const HouseholdRolesApiException('forbidden', 'no', statusCode: 403)), isTrue);
    });

    test('other failures are not permission refusals', () {
      expect(HouseholdPermissions.isPermissionDenied(const PostgrestException(message: 'timeout', code: '57014')), isFalse);
      expect(HouseholdPermissions.isPermissionDenied(Exception('network')), isFalse);
    });
  });

  group('models', () {
    test('Transaction keeps its creator through fromMap / toMap / copyWith', () {
      final tx = Transaction.fromMap({
        'id': 't1',
        'household_id': 'hh',
        'user_id': 'm',
        'amount': 10,
        'timestamp': '2026-10-20T10:00:00Z',
        'created_at': '2026-10-20T10:00:00Z',
      });
      expect(tx.userId, 'm');
      expect(tx.toMap()['user_id'], 'm');
      expect(tx.copyWith(amount: 12).userId, 'm');
    });

    test('HouseholdMembership reads is_primary', () {
      final m = HouseholdMembership.fromMap({'household_id': 'hh', 'role': 'admin', 'is_primary': true});
      expect(m.isAdmin, isTrue);
      expect(m.isPrimary, isTrue);
    });

    test('HouseholdRoster exposes only the actions the server accepts', () {
      const primary = HouseholdMember(userId: 'p', role: 'admin', isPrimary: true);
      const co = HouseholdMember(userId: 'c', role: 'admin', isSelf: true);
      const member = HouseholdMember(userId: 'm');

      const coAdminView = HouseholdRoster(householdId: 'hh', canManageAdmins: true);
      expect(coAdminView.canRevoke(primary), isFalse);
      expect(coAdminView.canMakePrimary(member), isFalse);
      expect(coAdminView.canPromote(member), isTrue);
      expect(coAdminView.canRevoke(co), isTrue);

      const primaryView = HouseholdRoster(householdId: 'hh', canManageAdmins: true, canTransferPrimary: true);
      expect(primaryView.canMakePrimary(member), isTrue);
      expect(primaryView.canMakePrimary(co), isFalse, reason: 'not to oneself');
      expect(primaryView.canMakePrimary(primary), isFalse);

      const memberView = HouseholdRoster(householdId: 'hh');
      expect(memberView.canPromote(member), isFalse);
      expect(memberView.canRevoke(co), isFalse);
    });
  });
}
