// The signed-in user's household role drives which edit/delete and transfer
// actions the app offers (DB-16 / DB-18).
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/providers/household_role_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Transaction _tx(String id, {String? userId, String householdId = 'hh'}) => Transaction(
      id: id,
      householdId: householdId,
      amount: 10,
      currency: 'SAR',
      timestamp: DateTime.utc(2026, 10, 20),
      isReallocated: false,
      createdAt: DateTime.utc(2026, 10, 20),
      userId: userId,
    );

void main() {
  group('HouseholdRoleProvider', () {
    test('a member may change only their own transactions', () async {
      final roles = HouseholdRoleProvider(
        loadMemberships: () async => const [
          HouseholdMembership(householdId: 'hh', householdName: 'Flat', inviteCode: '', role: 'member', isActive: true),
        ],
        currentUserId: () => 'm',
      );
      await roles.load('hh');
      expect(roles.isLoaded, isTrue);
      expect(roles.isAdmin, isFalse);
      expect(roles.canModify(_tx('own', userId: 'm')), isTrue);
      expect(roles.canModify(_tx('other', userId: 'p')), isFalse);
      expect(roles.canModify(_tx('legacy')), isFalse);
    });

    test('an admin of the active household may change any of its transactions', () async {
      final roles = HouseholdRoleProvider(
        loadMemberships: () async => const [
          HouseholdMembership(householdId: 'other', householdName: 'Other', inviteCode: '', role: 'member'),
          HouseholdMembership(householdId: 'hh', householdName: 'Family', inviteCode: 'X', role: 'admin', isActive: true, isPrimary: true),
        ],
        currentUserId: () => 'h',
      );
      await roles.load('hh');
      expect(roles.isAdmin, isTrue);
      expect(roles.isPrimary, isTrue);
      expect(roles.canModify(_tx('wife', userId: 'w')), isTrue);
      expect(roles.canModify(_tx('elsewhere', userId: 'w', householdId: 'other')), isFalse);
    });

    test('keeps the last known role when the server cannot be reached', () async {
      var online = true;
      final roles = HouseholdRoleProvider(
        loadMemberships: () async {
          if (!online) throw Exception('offline');
          return const [HouseholdMembership(householdId: 'hh', householdName: 'H', inviteCode: '', role: 'admin', isActive: true)];
        },
        currentUserId: () => 'a',
      );
      await roles.load('hh');
      online = false;
      await roles.refresh();
      expect(roles.isAdmin, isTrue);

      roles.reset();
      expect(roles.isAdmin, isFalse);
      expect(roles.isLoaded, isFalse);
    });
  });

  group('TransactionProvider permission refusals', () {
    test('a refused delete rolls back and is reported as a permission refusal', () async {
      final provider = TransactionProvider(
        deleteRow: (_) async => throw const PostgrestException(
          message: "Forbidden: only household admins can edit or delete another member's transactions",
          code: '42501',
        ),
      );
      provider.addTransaction(_tx('t1', userId: 'p'));

      final ok = await provider.deleteTransaction('t1');
      expect(ok, isFalse);
      expect(provider.lastWriteDenied, isTrue);
      expect(provider.transactions.map((t) => t.id), ['t1']);
    });

    test('a network failure is not reported as a permission refusal', () async {
      final provider = TransactionProvider(deleteRow: (_) async => throw Exception('offline'));
      provider.addTransaction(_tx('t1', userId: 'm'));
      expect(await provider.deleteTransaction('t1'), isFalse);
      expect(provider.lastWriteDenied, isFalse);
    });
  });
}
