// Every repayment to the wife, approval of her request and payment of a former
// member's record leaves an account (owner decision 2026-11-06, migration
// 20261105001300). Tests that record one wrap their app in [withPayerAccount]
// and choose it with [pickPayerAccount] before saving.
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/providers/household_role_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const kPayerAccountId = 'a-payer';
const kPayerAccountName = 'Payer bank';

/// Counts the reloads a repayment asks for, instead of reaching the server.
class PayerAccounts extends AccountProvider {
  int refreshes = 0;

  @override
  Future<void> refresh({bool force = false}) async => refreshes++;
}

/// The wives the older tests name, each with one wife account (her husband's,
/// migration 20261105001300 section 12): every repayment credits one, and the
/// sheets pick her only one for him.
const kTestWifeIds = ['u-wife', 'u-w', 'w', 'w1', 'w2', 'wife'];

/// Her wife account in [kTestWifeIds]' default set.
String testWifeAccountId(String wifeId) => 'wa-$wifeId';

/// [app] (a MaterialApp) with the viewer [userId] owning one personal SAR
/// account in [householdId], holding [balance], and the wives' wife accounts
/// ([wifeAccounts]; by default one for each of [kTestWifeIds]).
Widget withPayerAccount(
  Widget app, {
  String userId = 'u-husband',
  String householdId = 'hh',
  double balance = 100000,
  PayerAccounts? accounts,
  List<Account>? wifeAccounts,
}) {
  final provider = (accounts ?? PayerAccounts())
    ..setAccountsForTesting([
      Account(
        id: kPayerAccountId,
        householdId: householdId,
        ownerUserId: userId,
        name: kPayerAccountName,
        accountType: AccountType.bank,
        currency: 'SAR',
        balance: balance,
      ),
      ...(wifeAccounts ??
          [
            for (final w in kTestWifeIds)
              Account(
                id: testWifeAccountId(w),
                householdId: householdId,
                ownerUserId: 'u-husband',
                name: 'Her account',
                accountType: AccountType.wife,
                currency: 'SAR',
                assignedWifeId: w,
              ),
          ]),
    ], householdId: householdId);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AccountProvider>.value(value: provider),
      ChangeNotifierProvider<HouseholdRoleProvider>(
        create: (_) => HouseholdRoleProvider(loadMemberships: () async => const [], currentUserId: () => userId),
      ),
    ],
    child: app,
  );
}

/// Chooses the payer's account in the open sheet.
Future<void> pickPayerAccount(WidgetTester tester) async {
  final tile = find.byKey(const ValueKey('repay_source_$kPayerAccountId'));
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}
