// Every repayment to the wife is tracked; she asks, he approves; corrections
// are reversals (owner decisions 2026-11-06, migration 20261105001300).
//
// The reimburse sheet, the approval of her request and a former member's
// "Record payment" ask which account the money leaves: one of his own, or a
// shared pool when he is an admin. There is no "not tracked" choice; with no
// account the sheet says so and offers to add one. The wife marks what she
// received (a pending request) and can cancel it; the husband approves it from
// an account or declines it. The history shows "Reversed" and offers Reverse,
// after a confirmation that says the money goes back and the amount is owed
// again. Every sheet lays out at 320 px and 2x text, in every language and
// theme.
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

const _pending = {'id': 'q-1', 'amount': 30, 'payment_method': 'cash', 'status': 'pending', 'created_at': '2026-11-05T10:00:00Z'};
const _declined = {
  'id': 'q-2', 'amount': 10, 'payment_method': 'cash', 'status': 'declined', 'reason': 'Not yet',
  'created_at': '2026-11-04T10:00:00Z', 'decided_at': '2026-11-04T12:00:00Z',
};

NafaqahSummary _summary({
  String role = 'husband',
  double outstanding = 500.5,
  List<Map<String, dynamic>> debts = const [],
  List<Map<String, dynamic>> requests = const [],
}) =>
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
          'reimbursement': {
            'gross_advanced': outstanding + 100, 'reimbursed': 100.0, 'outstanding': outstanding, 'overpaid': 0,
            'pending_requested': requests.where((r) => r['status'] == 'pending').fold<num>(0, (s, r) => s + (r['amount'] as num)),
          },
          'allowance': {'cycle_key': '2026-11', 'is_set': true, 'allocated': 1000, 'spent': 0, 'remaining': 1000, 'transaction_count': 0},
          'requests': requests,
          'can_request': role == 'wife',
          'can_decide': role != 'wife',
        }
      ],
      'can_set_allowance': role != 'wife',
      'can_record_reimbursement': role != 'wife',
      'can_request_reimbursement': role == 'wife',
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
    {'id': 'e-legacy', 'kind': 'payment', 'amount': 300, 'payment_method': 'cash', 'remaining_after': 600,
     'created_at': '2026-11-02T09:00:00Z', 'moved_balance': false},
    {'id': 'e-bank', 'kind': 'payment', 'amount': 200, 'payment_method': 'bank_transfer', 'remaining_after': 400,
     'created_at': '2026-11-03T09:00:00Z', 'moved_balance': true, 'account_id': 'a-bank', 'can_reverse': true},
  ],
};

NafaqahLedger _ledger() => NafaqahLedger.fromMap({
      'balance': {'gross_advanced': 600, 'reimbursed': 100, 'outstanding': 500},
      'history': [
        {'type': 'reimbursement', 'kind': 'payment', 'id': 'r1', 'amount': 40, 'payment_method': 'bank_transfer',
         'timestamp': '2026-11-05T10:00:00Z', 'moved_balance': true, 'account_id': 'a-bank', 'can_reverse': true},
        {'type': 'reimbursement', 'kind': 'reversal', 'id': 'r2b', 'amount': 25, 'payment_method': 'cash',
         'timestamp': '2026-11-04T12:00:00Z', 'moved_balance': true, 'account_id': 'a-pool'},
        {'type': 'reimbursement', 'kind': 'payment', 'id': 'r2', 'amount': 25, 'payment_method': 'cash',
         'timestamp': '2026-11-04T10:00:00Z', 'moved_balance': true, 'account_id': 'a-pool', 'reversed': true},
        {'type': 'reimbursement', 'kind': 'payment', 'id': 'r3', 'amount': 30, 'payment_method': 'cash',
         'timestamp': '2026-11-03T10:00:00Z', 'moved_balance': false},
      ],
    });

typedef _Repay = ({double amount, String method, String accountId, String requestKey});
typedef _Pay = ({String debtId, double amount, String accountId, String requestKey});

class _Harness {
  final repays = <_Repay>[];
  final pays = <_Pay>[];
  final asks = <({double amount, String method, String requestKey})>[];
  final cancels = <String>[];
  final approvals = <({String requestId, String accountId, String requestKey})>[];
  final declines = <({String requestId, String? reason})>[];
  final reversals = <({String id, String requestKey})>[];
  final fmdReversals = <({String debtId, String eventId, String requestKey})>[];
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
    List<Map<String, dynamic>> requests = const [],
  }) async {
    accounts = _Accounts()..setAccountsForTesting(accountList ?? _all, householdId: 'hh');
    final roles = HouseholdRoleProvider(
      loadMemberships: () async => [
        HouseholdMembership(householdId: 'hh', householdName: 'Home', inviteCode: '', role: admin ? 'admin' : 'member', isActive: true),
      ],
      currentUserId: () => role == 'wife' ? _wife : _husband,
    );
    await roles.load('hh');
    final summary = _summary(role: role, debts: debts, requests: requests);
    Future<void> maybeFail() async {
      if (failWith != null) throw failWith!;
    }

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
              loadLedger: (_, __) async => _ledger(),
              recordReimbursement: ({
                required double amount,
                required String paymentMethod,
                required String wifeUserId,
                required String accountId,
                required String requestKey,
              }) async {
                repays.add((amount: amount, method: paymentMethod, accountId: accountId, requestKey: requestKey));
                await maybeFail();
                return 0;
              },
              createRequest: ({required double amount, required String paymentMethod, required String requestKey}) async {
                asks.add((amount: amount, method: paymentMethod, requestKey: requestKey));
                await maybeFail();
              },
              cancelRequest: ({required String requestId}) async {
                cancels.add(requestId);
                await maybeFail();
              },
              approveRequest: ({required String requestId, required String accountId, required String requestKey}) async {
                approvals.add((requestId: requestId, accountId: accountId, requestKey: requestKey));
                await maybeFail();
                return 470.5;
              },
              declineRequest: ({required String requestId, String? reason}) async {
                declines.add((requestId: requestId, reason: reason));
                await maybeFail();
              },
              reverseReimbursement: ({required String reimbursementId, required String requestKey}) async {
                reversals.add((id: reimbursementId, requestKey: requestKey));
                await maybeFail();
                return 540.5;
              },
              recordFormerMemberDebtPayment: ({
                required String debtId,
                required double amount,
                required String paymentMethod,
                required String requestKey,
                required String accountId,
              }) async {
                pays.add((debtId: debtId, amount: amount, accountId: accountId, requestKey: requestKey));
                await maybeFail();
                return FormerMemberDebtReceipt.fromMap({
                  'status': 'open',
                  'debt_id': debtId,
                  'amount': amount,
                  'payment_method': paymentMethod,
                  'remaining': 400 - amount,
                  'account_id': accountId,
                });
              },
              reverseFormerMemberDebtPayment: ({required String debtId, required String eventId, required String requestKey}) async {
                fmdReversals.add((debtId: debtId, eventId: eventId, requestKey: requestKey));
                await maybeFail();
                return FormerMemberDebtReceipt.fromMap({'status': 'open', 'debt_id': debtId, 'amount': 200, 'remaining': 600});
              },
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openReimburse(WidgetTester tester) => _tapKey(tester, 'nafaqah_reimburse_$_wife');

Future<void> _submitReimburse(WidgetTester tester) async {
  final button = find.text('Record Settlement Payment');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _openHistory(WidgetTester tester) async {
  await tester.tap(find.text('History').first);
  await tester.pumpAndSettle();
}

void main() {
  late _Harness h;
  setUp(() => h = _Harness());

  group('the husband repays from an account', () {
    testWidgets('lists his own accounts and, for an admin, the pools; there is no untracked choice', (tester) async {
      await tester.pumpWidget(await h.build(tester));
      await tester.pumpAndSettle();
      await _openReimburse(tester);

      expect(find.text('Paid from'), findsOneWidget);
      expect(find.text('Al Rajhi'), findsOneWidget);
      expect(find.text('Balance: SAR 800.00'), findsOneWidget);
      expect(find.text('Wallet cash'), findsOneWidget);
      expect(find.text('Shared Household Pool · Balance: SAR 1,000.00'), findsOneWidget);
      expect(find.byKey(const ValueKey('repay_source_not_tracked')), findsNothing);
      expect(find.textContaining('not tracked'), findsNothing);
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

    testWidgets('nothing is recorded until he says which account it leaves', (tester) async {
      await tester.pumpWidget(await h.build(tester));
      await tester.pumpAndSettle();
      await _openReimburse(tester);
      await _submitReimburse(tester);
      expect(find.text('Choose where the money comes from.'), findsOneWidget);
      expect(h.repays, isEmpty);
    });

    testWidgets('paying from his account sends it with a request key; hers never moves; the balances reload', (tester) async {
      await tester.pumpWidget(await h.build(tester));
      await tester.pumpAndSettle();
      await _openReimburse(tester);
      await _tapKey(tester, 'repay_source_a-bank');
      expect(find.text('Al Rajhi goes down by SAR 500.50. Her account and the budgets do not change.'), findsOneWidget);
      await _submitReimburse(tester);

      expect(h.repays.single.accountId, 'a-bank');
      expect(h.repays.single.amount, 500.5);
      expect(_uuidV4.hasMatch(h.repays.single.requestKey), isTrue);
      expect(h.accounts.refreshes, 1);
      expect(find.text('Recorded SAR 500.50, paid from Al Rajhi'), findsOneWidget);
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
      ('app_update_required', 'This version of the app can no longer record repayments. Please update the app.'),
    ]) {
      testWidgets('the server refusing it ($code) is explained', (tester) async {
        h.failWith = NafaqahApiException(code, 'refused', statusCode: code == 'account_forbidden' ? 403 : 409);
        await tester.pumpWidget(await h.build(tester));
        await tester.pumpAndSettle();
        await _openReimburse(tester);
        await _tapKey(tester, 'repay_source_a-bank');
        await _submitReimburse(tester);
        expect(find.text(text), findsOneWidget);
        expect(h.accounts.refreshes, code == 'app_update_required' ? 0 : 1);
      });
    }

    testWidgets('with no account in the app it says so, offers to add one, and records nothing', (tester) async {
      await tester.pumpWidget(await h.build(tester, accountList: const []));
      await tester.pumpAndSettle();
      await _openReimburse(tester);
      expect(find.byKey(const ValueKey('repay_no_accounts')), findsOneWidget);
      expect(find.byKey(const ValueKey('repay_add_account')), findsOneWidget);
      expect(find.text('Add Account'), findsOneWidget);
      await _submitReimburse(tester);
      expect(find.textContaining('Add one first: a cash payment comes out of your Cash account.'), findsWidgets);
      expect(h.repays, isEmpty);
    });
  });

  group('the history', () {
    testWidgets('says where each repayment came from or went back to, and marks reversals', (tester) async {
      await tester.pumpWidget(await h.build(tester));
      await tester.pumpAndSettle();
      await _openHistory(tester);
      expect(find.textContaining('From Al Rajhi'), findsOneWidget);
      expect(find.textContaining('Back to Home pool'), findsOneWidget);
      expect(find.text('Reversal'), findsOneWidget);
      expect(find.byKey(const ValueKey('rev_badge_r2')), findsOneWidget);
      expect(find.text('Reversed'), findsOneWidget);
      expect(find.textContaining('Not tracked in the app'), findsOneWidget, reason: 'a row from before tracking');
      expect(find.byKey(const ValueKey('rev_action_r1')), findsOneWidget);
      expect(find.byKey(const ValueKey('rev_action_r2')), findsNothing, reason: 'already reversed');
      expect(find.byKey(const ValueKey('rev_action_r3')), findsNothing, reason: 'the server says who may reverse');
    });

    testWidgets('Reverse asks first, saying the money goes back and the amount is owed again', (tester) async {
      await tester.pumpWidget(await h.build(tester));
      await tester.pumpAndSettle();
      await _openHistory(tester);
      await _tapKey(tester, 'rev_action_r1');
      expect(
        find.text('SAR 40.00 goes back to Al Rajhi, and SAR 40.00 is owed to her again. The repayment stays in the history, '
            'marked Reversed. Then record the correct amount.'),
        findsOneWidget,
      );
      await _tapKey(tester, 'rev_confirm_cancel');
      expect(h.reversals, isEmpty);

      await _tapKey(tester, 'rev_action_r1');
      await _tapKey(tester, 'rev_confirm_ok');
      expect(h.reversals.single.id, 'r1');
      expect(_uuidV4.hasMatch(h.reversals.single.requestKey), isTrue);
      expect(h.accounts.refreshes, 1);
      expect(find.text('Reversed. SAR 40.00 is owed again and the money is back in its account.'), findsOneWidget);
    });

    for (final (code, text) in [
      ('already_reversed', 'This repayment is already reversed.'),
      ('reversal_account_unavailable', 'The account it was paid from is archived or deleted, so it cannot be reversed.'),
      ('reversal_not_tracked', 'This repayment moved no money in the app, so there is nothing to return.'),
    ]) {
      testWidgets('a refused reversal ($code) is explained', (tester) async {
        h.failWith = NafaqahApiException(code, 'refused', statusCode: 409);
        await tester.pumpWidget(await h.build(tester));
        await tester.pumpAndSettle();
        await _openHistory(tester);
        await _tapKey(tester, 'rev_action_r1');
        await _tapKey(tester, 'rev_confirm_ok');
        expect(find.text(text), findsOneWidget);
        expect(h.accounts.refreshes, 0);
      });
    }
  });

  group('the wife asks', () {
    testWidgets('she marks what she received instead of recording a repayment', (tester) async {
      await tester.pumpWidget(await h.build(tester, role: 'wife', requests: [_pending]));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nafaqah_reimburse_$_wife')), findsNothing);
      await _tapKey(tester, 'nafaqah_mark_received_$_wife');
      expect(find.text('What did you receive?'), findsOneWidget);
      expect(find.text('Paid from'), findsNothing, reason: 'she picks no account');
      // What is owed less what she already asked for.
      expect(find.widgetWithText(TextField, '470.50'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('req_amount_field')), '120');
      await _tapKey(tester, 'req_send');
      expect(h.asks.single.amount, 120);
      expect(_uuidV4.hasMatch(h.asks.single.requestKey), isTrue);
      expect(h.repays, isEmpty);
      expect(find.text('Sent. It shows as pending until it is approved.'), findsOneWidget);
    });

    testWidgets('a request above what she can still ask for is refused before the server', (tester) async {
      await tester.pumpWidget(await h.build(tester, role: 'wife', requests: [_pending]));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'nafaqah_mark_received_$_wife');
      await tester.enterText(find.byKey(const ValueKey('req_amount_field')), '470.51');
      await _tapKey(tester, 'req_send');
      expect(find.text('With your pending requests this is more than is owed. You can ask for up to SAR 470.50.'), findsOneWidget);
      expect(h.asks, isEmpty);
    });

    testWidgets('her pending request shows with Cancel, and her answered ones with their outcome', (tester) async {
      await tester.pumpWidget(await h.build(tester, role: 'wife', requests: [_pending, _declined]));
      await tester.pumpAndSettle();
      expect(find.text('SAR 30.00 pending'), findsOneWidget, reason: 'the pending indicator');
      expect(find.text('Awaiting approval: 1'), findsOneWidget);
      expect(find.text('SAR 30.00 received (Cash)'), findsOneWidget);
      expect(find.text('SAR 10.00 · Declined: Not yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('req_approve_q-1')), findsNothing);
      await _tapKey(tester, 'req_cancel_q-1');
      expect(h.cancels, ['q-1']);
      expect(find.text('Request cancelled.'), findsOneWidget);
    });
  });

  group('the husband decides', () {
    testWidgets('he sees her pending request with Approve and Decline, never Cancel', (tester) async {
      await tester.pumpWidget(await h.build(tester, requests: [_pending, _declined]));
      await tester.pumpAndSettle();
      expect(find.text('SAR 30.00 pending'), findsOneWidget);
      expect(find.byKey(const ValueKey('req_approve_q-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('req_decline_q-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('req_cancel_q-1')), findsNothing);
      expect(find.textContaining('Declined: Not yet'), findsNothing, reason: 'he sees what is pending');
    });

    testWidgets('approval pays exactly the requested amount from the account he picks', (tester) async {
      await tester.pumpWidget(await h.build(tester, requests: [_pending]));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'req_approve_q-1');
      expect(find.text('Approve SAR 30.00'), findsOneWidget);
      await _tapKey(tester, 'req_approve_submit');
      expect(find.text('Choose where the money comes from.'), findsOneWidget);
      expect(h.approvals, isEmpty);
      await _tapKey(tester, 'repay_source_a-cash');
      await _tapKey(tester, 'req_approve_submit');
      expect(h.approvals.single.requestId, 'q-1');
      expect(h.approvals.single.accountId, 'a-cash');
      expect(_uuidV4.hasMatch(h.approvals.single.requestKey), isTrue);
      expect(h.accounts.refreshes, 1);
      expect(find.text('Approved: SAR 30.00 paid from Wallet cash'), findsOneWidget);
    });

    testWidgets('an approval above what is owed now is explained', (tester) async {
      h.failWith = const NafaqahApiException('request_exceeds_outstanding', 'refused', statusCode: 409, outstanding: 12.5);
      await tester.pumpWidget(await h.build(tester, requests: [_pending]));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'req_approve_q-1');
      await _tapKey(tester, 'repay_source_a-bank');
      await _tapKey(tester, 'req_approve_submit');
      expect(find.text('Only SAR 12.50 is owed now, less than this request. Decline it and record the right amount.'), findsOneWidget);
    });

    testWidgets('he declines with a short reason; nothing moves', (tester) async {
      await tester.pumpWidget(await h.build(tester, requests: [_pending]));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'req_decline_q-1');
      expect(find.text('Decline this request?'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('req_decline_reason')), 'Not yet');
      await _tapKey(tester, 'req_decline_ok');
      expect(h.declines.single, (requestId: 'q-1', reason: 'Not yet'));
      expect(h.accounts.refreshes, 0);
      expect(find.text('Request declined.'), findsOneWidget);
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
      expect(find.byKey(const ValueKey('repay_source_not_tracked')), findsNothing);
      await _tapKey(tester, 'repay_source_a-bank');
      expect(find.text('Al Rajhi goes down by SAR 400.00. Budgets do not change.'), findsOneWidget);
      await _tapKey(tester, 'fmd_pay_submit');
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Al Rajhi goes down by SAR 400.00. Budgets do not change.')),
          findsOneWidget);
      await _tapKey(tester, 'fmd_confirm_ok');
      expect(h.pays.single.accountId, 'a-bank');
      expect(h.pays.single.amount, 400);
      expect(h.accounts.refreshes, 1);
      expect(find.text('Recorded SAR 400.00, paid from Al Rajhi'), findsOneWidget);
    });

    testWidgets('a payment needs an account', (tester) async {
      await openPayment(tester);
      await _tapKey(tester, 'fmd_pay_submit');
      expect(find.text('Choose where the money comes from.'), findsOneWidget);
      expect(h.pays, isEmpty);
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

    testWidgets('the history offers Reverse on a tracked payment, after saying what it does', (tester) async {
      await tester.pumpWidget(await h.build(tester, debts: [_openDebt]));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'fmd_history_d-open');
      expect(find.textContaining('Not tracked in the app'), findsOneWidget);
      expect(find.textContaining('From Al Rajhi'), findsOneWidget);
      expect(find.byKey(const ValueKey('fmd_reverse_e-legacy')), findsNothing);
      await _tapKey(tester, 'fmd_reverse_e-bank');
      expect(
        find.text('SAR 200.00 goes back to Al Rajhi, and SAR 200.00 is owed on this record again; a settled record opens again. '
            'The payment stays in the history, marked Reversed.'),
        findsOneWidget,
      );
      await _tapKey(tester, 'rev_confirm_ok');
      expect(h.fmdReversals.single.eventId, 'e-bank');
      expect(h.fmdReversals.single.debtId, 'd-open');
      expect(h.accounts.refreshes, 1);
    });

    testWidgets('a reversal after her waiver is explained', (tester) async {
      h.failWith = const NafaqahApiException('reversal_after_waiver', 'refused', statusCode: 409);
      await tester.pumpWidget(await h.build(tester, debts: [_openDebt]));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'fmd_history_d-open');
      await _tapKey(tester, 'fmd_reverse_e-bank');
      await _tapKey(tester, 'rev_confirm_ok');
      expect(find.text('She waived what remained after this payment, so it cannot be reversed.'), findsOneWidget);
    });
  });

  group('every language and theme at 320 px and 2x text', () {
    for (final lang in ['en', 'ar', 'ur']) {
      for (final dark in [false, true]) {
        testWidgets('$lang ${dark ? 'dark' : 'light'}: the sheets, requests and history lay out without overflow', (tester) async {
          tester.view.physicalSize = const Size(960, 2400);
          tester.view.devicePixelRatio = 3.0;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(await h.build(tester, lang: lang, dark: dark, scale: 2.0, debts: [_openDebt], requests: [_pending]));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          await _tapKey(tester, 'nafaqah_reimburse_$_wife');
          await _tapKey(tester, 'repay_source_a-bank');
          expect(find.byKey(const ValueKey('repay_source_effect')), findsOneWidget);
          expect(tester.takeException(), isNull);
          final rtl = Directionality.of(tester.element(find.byKey(const ValueKey('repay_source_a-bank'))));
          expect(rtl, lang == 'en' ? TextDirection.ltr : TextDirection.rtl);
          Navigator.of(tester.element(find.byKey(const ValueKey('repay_source_a-bank')))).pop();
          await tester.pumpAndSettle();

          await _tapKey(tester, 'req_approve_q-1');
          await _tapKey(tester, 'repay_source_a-pool');
          expect(tester.takeException(), isNull);
          Navigator.of(tester.element(find.byKey(const ValueKey('repay_source_a-pool')))).pop();
          await tester.pumpAndSettle();

          await _tapKey(tester, 'req_decline_q-1');
          expect(tester.takeException(), isNull);
          await _tapKey(tester, 'req_decline_cancel');

          final l10n = AppLocalizations(Locale(lang));
          await tester.tap(find.text(l10n.get('nafaqah_history')).first);
          await tester.pumpAndSettle();
          await _tapKey(tester, 'rev_action_r1');
          expect(find.byKey(const ValueKey('rev_confirm_body')), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _tapKey(tester, 'rev_confirm_cancel');
          // The reversed repayment further down, with its badge.
          await tester.scrollUntilVisible(find.byKey(const ValueKey('rev_badge_r2')), 200,
              scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).last);
          expect(tester.takeException(), isNull);
          Navigator.of(tester.element(find.byKey(const ValueKey('rev_badge_r2')))).pop();
          await tester.pumpAndSettle();

          await _tapKey(tester, 'fmd_pay_d-open');
          await _tapKey(tester, 'repay_source_a-pool');
          await _tapKey(tester, 'fmd_pay_submit');
          expect(find.byKey(const ValueKey('fmd_confirm_source')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });

        testWidgets('$lang ${dark ? 'dark' : 'light'}: the wife\'s card and request sheet lay out without overflow', (tester) async {
          tester.view.physicalSize = const Size(960, 2400);
          tester.view.devicePixelRatio = 3.0;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
              await h.build(tester, role: 'wife', lang: lang, dark: dark, scale: 2.0, requests: [_pending, _declined]));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('req_cancel_q-1')), findsOneWidget);
          expect(find.byKey(const ValueKey('req_outcome_q-2')), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _tapKey(tester, 'nafaqah_mark_received_$_wife');
          expect(find.byKey(const ValueKey('req_send')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
