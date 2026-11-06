// A repayment to the wife moves money out of the account he picks (owner
// decision 2026-11-06, migration 20261105001300). The reimburse sheet and a
// former member's "Record payment" ask where the money comes from: one of his
// own accounts, a shared pool when he is an admin, or "cash, not tracked in
// the app", which records the amount only. Each shows its balance; the choice
// is required; after a repayment from an account the balances reload.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/household_membership.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/providers/household_role_provider.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/widgets/dashboard/family_reimbursement_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _husband = 'u-husband';
const _wife = 'u-wife';
final _uuidV4 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

/// Counts the reloads a repayment asks for, instead of reaching the server.
class _Accounts extends AccountProvider {
  int refreshes = 0;

  @override
  Future<void> refresh({bool force = false}) async => refreshes++;
}

Account _acct(
  String id,
  String name, {
  String owner = _husband,
  double balance = 800,
  bool pool = false,
  bool archived = false,
  String currency = 'SAR',
  String household = 'hh',
  AccountType type = AccountType.bank,
}) =>
    Account(
      id: id,
      householdId: household,
      ownerUserId: owner,
      name: name,
      accountType: pool ? AccountType.sharedPool : type,
      currency: currency,
      balance: balance,
      isSharedPool: pool,
      isArchived: archived,
    );

final _all = [
  _acct('a-bank', 'Al Rajhi'),
  _acct('a-cash', 'Wallet cash', balance: 50, type: AccountType.cash),
  _acct('a-pool', 'Home pool', owner: 'u-coadmin', balance: 1000, pool: true),
  _acct('a-hers', 'Her bank', owner: _wife),
  _acct('a-son', 'Son bank', owner: 'u-son'),
  _acct('a-old', 'Old card', archived: true),
  _acct('a-usd', 'Dollar card', currency: 'USD'),
  _acct('a-away', 'Other home', household: 'hh-2'),
];

NafaqahSummary _summary({String role = 'husband', double outstanding = 500.5, List<Map<String, dynamic>> debts = const []}) =>
    NafaqahSummary.fromMap({
      'mode': 'family_nafaqah',
      'caller_role': role,
      'caller_user_id': role == 'wife' ? _wife : _husband,
      'cycle_key': '2026-11',
      'husband': {'id': _husband, 'display_name': 'Ahmed'},
      'wives': [
        {
          'id': _wife,
          'display_name': 'Sara',
          'reimbursement': {'gross_advanced': outstanding + 100, 'reimbursed': 100.0, 'outstanding': outstanding, 'overpaid': 0},
          'allowance': {'cycle_key': '2026-11', 'is_set': true, 'allocated': 1000, 'spent': 0, 'remaining': 1000, 'transaction_count': 0},
        }
      ],
      'can_set_allowance': role != 'wife',
      'can_record_reimbursement': true,
      'provider_user_id': _husband,
      'needs_provider': false,
      'can_set_provider': role != 'wife',
      'former_member_debts': debts,
      'can_manage_former_member_debts': role != 'wife',
    });

const _openDebt = {
  'id': 'd-open',
  'original_amount': 900,
  'paid_amount': 500,
  'remaining': 400,
  'status': 'open',
  'created_at': '2026-11-01T09:00:00Z',
  'closed_at': null,
  'events': [
    {'kind': 'payment', 'amount': 300, 'payment_method': 'cash', 'remaining_after': 600, 'created_at': '2026-11-02T09:00:00Z', 'moved_balance': false},
    {'kind': 'payment', 'amount': 200, 'payment_method': 'bank_transfer', 'remaining_after': 400, 'created_at': '2026-11-03T09:00:00Z', 'moved_balance': true, 'account_id': 'a-bank'},
  ],
};

typedef _Repay = ({double amount, String method, String? accountId, String requestKey});
typedef _Pay = ({String debtId, double amount, String? accountId, String requestKey});

class _Harness {
  final repays = <_Repay>[];
  final pays = <_Pay>[];
  Object? failWith;
  late _Accounts accounts;

  Future<Widget> build(
    WidgetTester tester, {
    List<Account>? accountList,
    bool admin = true,
    String role = 'husband',
    String lang = 'en',
    bool dark = false,
    double scale = 1.0,
    List<Map<String, dynamic>> debts = const [],
    NafaqahLedgerLoader? loadLedger,
  }) async {
    accounts = _Accounts()..setAccountsForTesting(accountList ?? _all, householdId: 'hh');
    final roles = HouseholdRoleProvider(
      loadMemberships: () async => [
        HouseholdMembership(householdId: 'hh', householdName: 'Home', inviteCode: '', role: admin ? 'admin' : 'member', isActive: true),
      ],
      currentUserId: () => role == 'wife' ? _wife : _husband,
    );
    await roles.load('hh');
    final summary = _summary(role: role, debts: debts);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AccountProvider>.value(value: accounts),
        ChangeNotifierProvider<HouseholdRoleProvider>.value(value: roles),
      ],
      child: MaterialApp(
        locale: Locale(lang),
        theme: dark ? AppThemes.darkTheme : AppThemes.lightTheme,
        supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, page) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: page!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: FamilyReimbursementCard(
              householdId: 'hh',
              summary: summary,
              loadSummary: (_) async => summary,
              loadLedger: loadLedger,
              recordReimbursement: ({
                required double amount,
                required String paymentMethod,
                required String wifeUserId,
                required String? accountId,
                required String requestKey,
              }) async {
                repays.add((amount: amount, method: paymentMethod, accountId: accountId, requestKey: requestKey));
                if (failWith != null) throw failWith!;
                return 0;
              },
              recordFormerMemberDebtPayment: ({
                required String debtId,
                required double amount,
                required String paymentMethod,
                required String requestKey,
                required String? accountId,
              }) async {
                pays.add((debtId: debtId, amount: amount, accountId: accountId, requestKey: requestKey));
                if (failWith != null) throw failWith!;
                return FormerMemberDebtReceipt.fromMap({
                  'status': 'open',
                  'debt_id': debtId,
                  'amount': amount,
                  'payment_method': paymentMethod,
                  'remaining': 400 - amount,
                  'account_id': accountId,
                });
              },
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _openReimburse(WidgetTester tester, {String role = 'husband'}) async {
  await tester.tap(find.text(role == 'wife' ? 'Record amount received' : 'Reimburse Wife'));
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _submitReimburse(WidgetTester tester) async {
  final button = find.text('Record Settlement Payment');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  late _Harness h;
  setUp(() => h = _Harness());

  group('repaying the wife', () {
    testWidgets('lists his own accounts and, for an admin, the pools, each with its balance', (tester) async {
      await tester.pumpWidget(await h.build(tester));
      await tester.pumpAndSettle();
      await _openReimburse(tester);

      expect(find.text('Paid from'), findsOneWidget);
      expect(find.text('Al Rajhi'), findsOneWidget);
      expect(find.text('Balance: SAR 800.00'), findsOneWidget);
      expect(find.text('Wallet cash'), findsOneWidget);
      expect(find.text('Home pool'), findsOneWidget);
      expect(find.text('Shared Household Pool · Balance: SAR 1,000.00'), findsOneWidget);
      expect(find.text('Cash, not tracked in the app'), findsOneWidget);
      expect(find.text('Records the amount only. No balance changes.'), findsOneWidget);
      for (final hidden in ['Her bank', 'Son bank', 'Old card', 'Dollar card', 'Other home']) {
        expect(find.text(hidden), findsNothing, reason: hidden);
      }
    });

    testWidgets('a member who is not an admin is not offered a pool', (tester) async {
      await tester.pumpWidget(await h.build(tester, admin: false));
      await tester.pumpAndSettle();
      await _openReimburse(tester);
      expect(find.text('Al Rajhi'), findsOneWidget);
      expect(find.text('Home pool'), findsNothing);
    });

    testWidgets('nothing is recorded until he says where the money comes from', (tester) async {
      await tester.pumpWidget(await h.build(tester));
      await tester.pumpAndSettle();
      await _openReimburse(tester);
      await _submitReimburse(tester);
      expect(find.text('Choose where the money comes from.'), findsOneWidget);
      expect(h.repays, isEmpty);
    });

    testWidgets('paying from his account sends it with a request key, then the balances reload', (tester) async {
      await tester.pumpWidget(await h.build(tester));
      await tester.pumpAndSettle();
      await _openReimburse(tester);
      await _tapKey(tester, 'repay_source_a-bank');
      expect(
        find.text('Al Rajhi goes down by SAR 500.50. If she has her own account in the app, it goes up by the same amount. '
            'Budgets do not change.'),
        findsOneWidget,
      );
      await _submitReimburse(tester);

      expect(h.repays, hasLength(1));
      expect(h.repays.single.accountId, 'a-bank');
      expect(h.repays.single.amount, 500.5);
      expect(_uuidV4.hasMatch(h.repays.single.requestKey), isTrue);
      expect(h.accounts.refreshes, 1);
      expect(find.text('Recorded SAR 500.50, paid from Al Rajhi'), findsOneWidget);
    });

    testWidgets('not tracked in the app records the amount only and reloads nothing', (tester) async {
      await tester.pumpWidget(await h.build(tester));
      await tester.pumpAndSettle();
      await _openReimburse(tester);
      await _tapKey(tester, 'repay_source_not_tracked');
      expect(find.byKey(const ValueKey('repay_source_effect')), findsNothing);
      await _submitReimburse(tester);
      expect(h.repays.single.accountId, isNull);
      expect(h.accounts.refreshes, 0);
    });

    testWidgets('an account that does not hold the amount is refused before the server', (tester) async {
      await tester.pumpWidget(await h.build(tester));
      await tester.pumpAndSettle();
      await _openReimburse(tester);
      expect(find.text('Not enough in this account'), findsOneWidget, reason: 'the 50 SAR wallet, against 500.50');
      await _tapKey(tester, 'repay_source_a-cash');
      await _submitReimburse(tester);
      expect(find.text('Wallet cash holds SAR 50.00, less than SAR 500.50.'), findsOneWidget);
      expect(h.repays, isEmpty);
    });

    for (final (code, text) in [
      ('insufficient_funds', 'This account does not hold the amount. Choose another one.'),
      ('account_unavailable', 'This account cannot be used. Choose another one.'),
      ('account_forbidden', 'You cannot pay from this account. Choose one of your own.'),
    ]) {
      testWidgets('the server refusing the account ($code) is explained and the balances reload', (tester) async {
        h.failWith = NafaqahApiException(code, 'refused', statusCode: code == 'account_forbidden' ? 403 : 409);
        await tester.pumpWidget(await h.build(tester));
        await tester.pumpAndSettle();
        await _openReimburse(tester);
        await _tapKey(tester, 'repay_source_a-bank');
        await _submitReimburse(tester);
        expect(find.text(text), findsOneWidget);
        expect(h.accounts.refreshes, 1);
      });
    }

    testWidgets('with no account in the app, not tracked is the choice already made', (tester) async {
      await tester.pumpWidget(await h.build(tester, accountList: const []));
      await tester.pumpAndSettle();
      await _openReimburse(tester);
      expect(find.text('You have no account in the app to pay this from.'), findsOneWidget);
      await _submitReimburse(tester);
      expect(h.repays.single.accountId, isNull);
    });

    testWidgets('the wife records what she received without an account', (tester) async {
      await tester.pumpWidget(await h.build(tester, role: 'wife'));
      await tester.pumpAndSettle();
      await _openReimburse(tester, role: 'wife');
      expect(find.text('Paid from'), findsNothing);
      expect(find.text('Recording what you received changes no balance.'), findsOneWidget);
      await _submitReimburse(tester);
      expect(h.repays.single.accountId, isNull);
      expect(_uuidV4.hasMatch(h.repays.single.requestKey), isTrue);
    });

    testWidgets('the history says where each repayment came from', (tester) async {
      await tester.pumpWidget(await h.build(
        tester,
        loadLedger: (_, __) async => NafaqahLedger.fromMap({
          'balance': {'gross_advanced': 600, 'reimbursed': 100, 'outstanding': 500},
          'history': [
            {'type': 'reimbursement', 'id': 'r1', 'amount': 40, 'payment_method': 'bank_transfer', 'timestamp': '2026-11-05T10:00:00Z',
             'moved_balance': true, 'account_id': 'a-bank'},
            {'type': 'reimbursement', 'id': 'r2', 'amount': 30, 'payment_method': 'cash', 'timestamp': '2026-11-04T10:00:00Z',
             'moved_balance': true, 'account_id': 'a-not-mine'},
            {'type': 'reimbursement', 'id': 'r3', 'amount': 30, 'payment_method': 'cash', 'timestamp': '2026-11-03T10:00:00Z',
             'moved_balance': false},
          ],
        }),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('History').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('From Al Rajhi'), findsOneWidget);
      expect(find.textContaining('From an account in the app'), findsOneWidget);
      expect(find.textContaining('Not tracked in the app'), findsOneWidget);
    });
  });

  group("a former member's record", () {
    Future<void> openPayment(WidgetTester tester) async {
      await tester.pumpWidget(await h.build(tester, debts: [_openDebt]));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'fmd_pay_d-open');
    }

    testWidgets('a payment is taken from the chosen account, which reloads', (tester) async {
      await openPayment(tester);
      expect(find.text('Al Rajhi'), findsOneWidget);
      await _tapKey(tester, 'repay_source_a-bank');
      expect(find.text('Al Rajhi goes down by SAR 400.00. Budgets do not change.'), findsOneWidget);
      await _tapKey(tester, 'fmd_pay_submit');
      expect(find.byKey(const ValueKey('fmd_confirm_source')), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Al Rajhi goes down by SAR 400.00. Budgets do not change.')),
          findsOneWidget);
      await _tapKey(tester, 'fmd_confirm_ok');
      expect(h.pays.single.accountId, 'a-bank');
      expect(h.pays.single.amount, 400);
      expect(h.accounts.refreshes, 1);
      expect(find.text('Recorded SAR 400.00, paid from Al Rajhi'), findsOneWidget);
    });

    testWidgets('a payment needs a source, and not tracked says no balance changes', (tester) async {
      await openPayment(tester);
      await _tapKey(tester, 'fmd_pay_submit');
      expect(find.text('Choose where the money comes from.'), findsOneWidget);
      expect(h.pays, isEmpty);
      await _tapKey(tester, 'repay_source_not_tracked');
      await _tapKey(tester, 'fmd_pay_submit');
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Records the amount only. No balance changes.')),
          findsOneWidget);
      await _tapKey(tester, 'fmd_confirm_ok');
      expect(h.pays.single.accountId, isNull);
      expect(h.accounts.refreshes, 0);
    });

    testWidgets('the server refusing the account is explained', (tester) async {
      h.failWith = const NafaqahApiException('insufficient_funds', 'refused', statusCode: 409);
      await openPayment(tester);
      await _tapKey(tester, 'repay_source_a-bank');
      await _tapKey(tester, 'fmd_pay_submit');
      await _tapKey(tester, 'fmd_confirm_ok');
      expect(find.text('This account does not hold the amount. Choose another one.'), findsOneWidget);
      expect(h.accounts.refreshes, 1);
    });

    testWidgets('the history says which payments came from an account', (tester) async {
      await tester.pumpWidget(await h.build(tester, debts: [_openDebt]));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'fmd_history_d-open');
      expect(find.textContaining('Not tracked in the app'), findsOneWidget);
      expect(find.textContaining('From Al Rajhi'), findsOneWidget);
    });
  });

  group('every language and theme at 320 px and 2x text', () {
    for (final lang in ['en', 'ar', 'ur']) {
      for (final dark in [false, true]) {
        testWidgets('$lang ${dark ? 'dark' : 'light'}: both sheets lay out without overflow', (tester) async {
          tester.view.physicalSize = const Size(960, 2400);
          tester.view.devicePixelRatio = 3.0;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(await h.build(tester, lang: lang, dark: dark, scale: 2.0, debts: [_openDebt]));
          await tester.pumpAndSettle();

          final l10n = AppLocalizations(Locale(lang));
          final open = find.text(l10n.get('reimburse_wife')).first;
          await tester.ensureVisible(open);
          await tester.pumpAndSettle();
          await tester.tap(open);
          await tester.pumpAndSettle();
          await _tapKey(tester, 'repay_source_a-bank');
          expect(find.byKey(const ValueKey('repay_source_effect')), findsOneWidget);
          expect(tester.takeException(), isNull);
          final rtl = Directionality.of(tester.element(find.byKey(const ValueKey('repay_source_a-bank'))));
          expect(rtl, lang == 'en' ? TextDirection.ltr : TextDirection.rtl);
          Navigator.of(tester.element(find.byKey(const ValueKey('repay_source_a-bank')))).pop();
          await tester.pumpAndSettle();

          await _tapKey(tester, 'fmd_pay_d-open');
          await _tapKey(tester, 'repay_source_a-pool');
          await _tapKey(tester, 'fmd_pay_submit');
          expect(find.byKey(const ValueKey('fmd_confirm_source')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
