// Shared-pool withdrawals are admin-only (DB-16); members' transactions by
// others show as read-only (DB-18).
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/widgets/accounts/account_transfer_sheet.dart';
import 'package:budget_tracker/widgets/transaction_item_breakdown_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _accounts = [
  Account(id: 'pool', householdId: 'hh', ownerUserId: 'p', name: 'Flat Pool', accountType: AccountType.sharedPool, balance: 900, isSharedPool: true),
  Account(id: 'bank', householdId: 'hh', ownerUserId: 'm', name: 'My Bank', accountType: AccountType.bank, balance: 300),
  Account(id: 'cash', householdId: 'hh', ownerUserId: 'm', name: 'My Cash', accountType: AccountType.cash, balance: 50),
];

Future<void> _pumpSheet(WidgetTester tester, {required bool isAdmin, required String userId}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AccountTransferSheet(
        householdId: 'hh',
        isAdmin: isAdmin,
        currentUserId: userId,
        loadAccounts: (_) async => _accounts,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

List<String?> _sourceIds(WidgetTester tester) {
  final source = tester.widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>)).first;
  return source.items!.map((i) => i.value).toList();
}

void main() {
  testWidgets('a member cannot pick the shared pool as the source', (tester) async {
    await _pumpSheet(tester, isAdmin: false, userId: 'm');
    expect(_sourceIds(tester), ['bank', 'cash']);
    expect(find.text('Shared pools are hidden: only admins can move money out of them.'), findsOneWidget);

    // The pool stays available as a destination (paying dues into it).
    final destination = tester.widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>)).last;
    expect(destination.items!.map((i) => i.value), contains('pool'));
  });

  testWidgets('an admin may move money out of the shared pool', (tester) async {
    await _pumpSheet(tester, isAdmin: true, userId: 'p');
    expect(_sourceIds(tester), contains('pool'));
    expect(find.text('Shared pools are hidden: only admins can move money out of them.'), findsNothing);
  });

  testWidgets("another member's transaction shows a lock note instead of edit/delete", (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TransactionItemBreakdownCard(
            merchant: 'Panda',
            amount: 40,
            initiallyExpanded: true,
            lockedNote: 'Added by another member · only admins can change it',
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Added by another member · only admins can change it'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });
}
