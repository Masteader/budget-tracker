// Chevrons point the way the reading direction moves: right in English, left in
// Arabic and Urdu. Asserted on what is painted, because a mirrored glyph and a
// double flip both look fine by icon name alone (S5).
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/household_dues.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/household_role_provider.dart';
import 'package:budget_tracker/providers/installment_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/home/budget_management_screen.dart';
import 'package:budget_tracker/screens/tools/tools_screen.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';
import 'package:budget_tracker/widgets/dashboard/budget_hero_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/localized_app.dart';
import '../support/painted_direction.dart';

const _languages = {'en': Pointing.right, 'ar': Pointing.left, 'ur': Pointing.left};

Pointing _opposite(Pointing p) => p == Pointing.right ? Pointing.left : Pointing.right;

Budget _budget(String code, double allocated, double spent) => Budget.fromMap({
      'id': code,
      'household_id': 'hh',
      'month': '2026-11-01',
      'category_code': code,
      'allocated_amount': allocated,
      'spent_amount': spent,
      'remaining_amount': allocated - spent,
      'cycle_key': '2026-11',
    });

Future<void> _pumpHero(WidgetTester tester, String lang) async {
  tester.view.physicalSize = const Size(600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(localizedApp(
    BudgetHeroCard(
      budgets: [_budget('OPEX-GROCERY', 3000, 500)],
      now: DateTime.utc(2026, 11, 6, 9),
      monthlyIncome: 9000,
      operatingCash: 5000,
      dueLines: const [DueLine(kind: DueKind.iOwe, name: 'Faisal', amount: 50)],
      onDueTap: () {},
      pendingCommitments: 200,
      onCommitmentsTap: () {},
    ),
    lang: lang,
  ));
  await tester.pumpAndSettle();
}

Future<void> _pumpBudgets(WidgetTester tester, String lang) async {
  tester.view.physicalSize = const Size(600, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final cycleKey = SalaryCycleService.currentCycle().key;
  final account = Account(
    id: 'acc-1',
    householdId: 'hh-1',
    ownerUserId: 'u-1',
    name: 'Main',
    accountType: AccountType.bank,
    currency: 'SAR',
    balance: 3000,
    isSharedPool: true,
    colorHex: '#10B981',
    iconName: 'account_balance',
    isArchived: false,
    createdAt: DateTime(2026, 1, 1),
  );
  final accounts = AccountProvider()..setAccountsForTesting([account], householdId: 'hh-1', cycleKey: cycleKey);
  final staticData = BudgetStaticData(
    householdId: 'hh-1',
    isAdmin: true,
    allCodes: const [
      {'code': 'OPEX-GROCERY', 'category': 'Groceries', 'is_system': 'true'},
    ],
    monthlyIncome: 9000,
    accounts: [account],
  );
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AccountProvider>.value(value: accounts),
      ChangeNotifierProvider<TransactionProvider>(create: (_) => TransactionProvider()),
      ChangeNotifierProvider<RecurringBillsProvider>(create: (_) => RecurringBillsProvider()),
      ChangeNotifierProvider<BudgetProvider>(create: (_) => BudgetProvider()),
      ChangeNotifierProvider<InstallmentProvider>(create: (_) => InstallmentProvider()),
      ChangeNotifierProvider<HouseholdRoleProvider>(create: (_) => HouseholdRoleProvider()),
    ],
    child: localizedApp(
      BudgetManagementScreen(
        initialStaticData: staticData,
        loadStaticDataOverride: () async => staticData,
        budgetStreamOverride: (_) => Stream.value([
          {
            'id': 'b-1',
            'household_id': 'hh-1',
            'category_code': 'OPEX-GROCERY',
            'allocated_amount': 1000.0,
            'spent_amount': 100.0,
            'is_active': true,
            'cycle_key': cycleKey,
            'month': '$cycleKey-01',
            'account_id': 'acc-1',
          }
        ]),
      ),
      lang: lang,
      scaffold: false,
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  _languages.forEach((lang, forward) {
    final l = AppLocalizations(Locale(lang));

    group('$lang points ${forward.name}', () {
      testWidgets('Tools rows', (tester) async {
        await tester.pumpWidget(localizedApp(const ToolsScreen(householdId: 'hh'), lang: lang, scaffold: false));
        await tester.pumpAndSettle();
        final chevrons = find.byIcon(Icons.chevron_right_rounded);
        expect(chevrons, findsWidgets);
        for (final element in chevrons.evaluate()) {
          expect(paintedPointing(tester, find.byElementPredicate((e) => e == element)), forward);
        }
        expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
      });

      testWidgets('hero card dues row', (tester) async {
        await _pumpHero(tester, lang);
        final chevron = find.byWidgetPredicate((w) => w is Icon && (w.icon == Icons.chevron_right_rounded || w.icon == Icons.chevron_left_rounded));
        expect(chevron, findsOneWidget);
        expect(paintedPointing(tester, chevron), forward);
      });

      testWidgets('hero card commitments tip', (tester) async {
        await _pumpHero(tester, lang);
        final arrow = find.byWidgetPredicate((w) => w is Icon && (w.icon == Icons.arrow_forward_ios_rounded || w.icon == Icons.arrow_back_ios_rounded));
        expect(arrow, findsOneWidget);
        expect(paintedPointing(tester, arrow), forward);
      });

      testWidgets('budget cycle navigation: next goes forward, previous back', (tester) async {
        await _pumpBudgets(tester, lang);
        Finder iconOf(String tooltip) => find.descendant(of: find.byTooltip(tooltip), matching: find.byType(Icon));
        expect(paintedPointing(tester, iconOf(l.get('a11y_next'))), forward);
        expect(paintedPointing(tester, iconOf(l.get('a11y_previous'))), _opposite(forward));
      });

      testWidgets('budget category row', (tester) async {
        await _pumpBudgets(tester, lang);
        final row = find.byWidgetPredicate(
          (w) => w is Icon && w.size == 18 && (w.icon == Icons.chevron_right_rounded || w.icon == Icons.chevron_left_rounded),
        );
        expect(row, findsWidgets);
        for (final element in row.evaluate()) {
          expect(paintedPointing(tester, find.byElementPredicate((e) => e == element)), forward);
        }
      });
    });
  });
}
