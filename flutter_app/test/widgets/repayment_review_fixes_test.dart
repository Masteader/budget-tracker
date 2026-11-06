// Round 1 review fixes of tracked repayments (owner decisions 2026-11-06).
//
// R1-01: a wife is offered nothing to decide, pay or reverse, whatever the
// server says. R1-03: a request closed because it no longer fits says so in
// her language. R1-06: a sheet whose answer was lost stays open with what it
// sent and its key, offers a safe retry and reloads the balances; Reverse
// keeps its key per repayment. R1-09: the refusals these flows bring have
// their own words, and the decline reason is counted in Unicode code points.
// R1-12: labels carry their own, localized punctuation.
//
// The harness is the picker test's, with one-off failures.
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

NafaqahSummary _summary({
  String role = 'husband',
  double outstanding = 500.5,
  List<Map<String, dynamic>> debts = const [],
  List<Map<String, dynamic>> requests = const [],
  bool? serverSaysDecide,
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
          'can_decide': serverSaysDecide ?? role != 'wife',
        }
      ],
      'can_set_allowance': role != 'wife',
      'can_record_reimbursement': role != 'wife',
      'can_request_reimbursement': role == 'wife',
      'provider_user_id': _husband,
      'needs_provider': false,
      'can_set_provider': role != 'wife',
      'former_member_debts': debts,
      'can_manage_former_member_debts': serverSaysDecide ?? role != 'wife',
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

  /// Failures for the next calls, one each, before any [failWith].
  final failNext = <Object>[];

  /// How many times the card reloaded its summary.
  int summaryLoads = 0;
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
    bool? serverSaysDecide,
    NafaqahLedger Function()? ledger,
  }) async {
    accounts = _Accounts()..setAccountsForTesting(accountList ?? _all, householdId: 'hh');
    final roles = HouseholdRoleProvider(
      loadMemberships: () async => [
        HouseholdMembership(householdId: 'hh', householdName: 'Home', inviteCode: '', role: admin ? 'admin' : 'member', isActive: true),
      ],
      currentUserId: () => role == 'wife' ? _wife : _husband,
    );
    await roles.load('hh');
    final summary = _summary(role: role, debts: debts, requests: requests, serverSaysDecide: serverSaysDecide);
    Future<void> maybeFail() async {
      if (failNext.isNotEmpty) throw failNext.removeAt(0);
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
              loadSummary: (_) async {
                summaryLoads++;
                return summary;
              },
              loadLedger: (_, __) async => (ledger ?? _ledger)(),
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

const _lost = NafaqahApiException('network', 'no answer', noResponse: true);

String _en(String key) => AppLocalizations.localizedMap('en')[key] ?? key;

void main() {
  late _Harness h;
  setUp(() => h = _Harness());

  group('R1-01: a wife decides nothing, whatever the server says', () {
    testWidgets('no repayment, approval, payment, waiver or reversal is offered to her', (tester) async {
      await tester.pumpWidget(await h.build(tester,
          role: 'wife', serverSaysDecide: true, debts: [_openDebt], requests: [_pending]));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nafaqah_reimburse_$_wife')), findsNothing);
      expect(find.byKey(const ValueKey('nafaqah_mark_received_$_wife')), findsOneWidget);
      expect(find.byKey(const ValueKey('req_approve_q-1')), findsNothing);
      expect(find.byKey(const ValueKey('req_decline_q-1')), findsNothing);
      expect(find.byKey(const ValueKey('fmd_pay_d-open')), findsNothing);
      expect(find.byKey(const ValueKey('fmd_waive_d-open')), findsNothing);
      // A former member's record is not hers to see at all (review R3-01).
      expect(find.byKey(const ValueKey('fmd_panel_d-open')), findsNothing);
      expect(find.byKey(const ValueKey('fmd_history_d-open')), findsNothing);

      await tester.tap(find.text('History').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rev_action_r1')), findsNothing);
    });
  });

  group('R1-03: a request that no longer fits', () {
    for (final (lang, label) in [('en', 'Already repaid'), ('ar', 'سُدِّد بالفعل'), ('ur', 'پہلے ہی ادا ہو چکا')]) {
      testWidgets('$lang: she sees it closed as already repaid', (tester) async {
        await tester.pumpWidget(await h.build(tester, role: 'wife', lang: lang, requests: [
          {'id': 'q-3', 'amount': 80, 'payment_method': 'cash', 'status': 'already_repaid',
           'created_at': '2026-11-05T10:00:00Z', 'decided_at': '2026-11-06T10:00:00Z'},
        ]));
        await tester.pumpAndSettle();
        final line = tester.widget<Text>(find.byKey(const ValueKey('req_outcome_q-3'))).data!;
        expect(line, contains(label));
      });
    }
  });

  group('R1-06: a lost answer keeps the sheet, its key and what it sent', () {
    testWidgets('a repayment: the sheet stays with a safe retry, the balances reload, the same key goes again', (tester) async {
      h.failNext.add(_lost);
      await tester.pumpWidget(await h.build(tester));
      await tester.pumpAndSettle();
      await _openReimburse(tester);
      await _tapKey(tester, 'repay_source_a-bank');
      await _submitReimburse(tester);

      expect(find.byKey(const ValueKey('reimburse_unconfirmed')), findsOneWidget);
      expect(h.accounts.refreshes, 1, reason: 'the account may have moved');
      expect(h.summaryLoads, greaterThanOrEqualTo(1), reason: 'the card shows what is stored');
      // What was sent stays: another account cannot be chosen under the same key.
      await _tapKey(tester, 'repay_source_a-cash');
      final retry = find.text(_en('try_again'));
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(h.repays, hasLength(2));
      expect(h.repays[1], h.repays[0], reason: 'the same amount, method, account and key');
      expect(find.text('Recorded SAR 500.50, paid from Al Rajhi'), findsOneWidget);
      expect(find.byKey(const ValueKey('reimburse_unconfirmed')), findsNothing);
    });

    testWidgets('an approval: the same key and account again, and the balances reload', (tester) async {
      h.failNext.add(_lost);
      await tester.pumpWidget(await h.build(tester, requests: [_pending]));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'req_approve_q-1');
      await _tapKey(tester, 'repay_source_a-cash');
      await _tapKey(tester, 'req_approve_submit');

      expect(find.byKey(const ValueKey('req_approve_unconfirmed')), findsOneWidget);
      expect(h.accounts.refreshes, 1);
      await _tapKey(tester, 'repay_source_a-bank');
      await _tapKey(tester, 'req_approve_submit');
      expect(h.approvals, hasLength(2));
      expect(h.approvals[1], h.approvals[0]);
      expect(h.approvals[1].accountId, 'a-cash');
    });

    testWidgets('a reversal: Reverse again sends the same key, and the balances reload', (tester) async {
      h.failNext.add(_lost);
      await tester.pumpWidget(await h.build(tester));
      await tester.pumpAndSettle();
      await _openHistory(tester);
      await _tapKey(tester, 'rev_action_r1');
      await _tapKey(tester, 'rev_confirm_ok');
      expect(h.accounts.refreshes, 1);
      expect(find.text(_en('fmd_unconfirmed_msg')), findsOneWidget);

      await _tapKey(tester, 'rev_action_r1');
      await _tapKey(tester, 'rev_confirm_ok');
      expect(h.reversals, hasLength(2));
      expect(h.reversals[1].requestKey, h.reversals[0].requestKey);
    });

    testWidgets("a former member's payment: the balances reload, and a retry sends what was sent", (tester) async {
      h.failNext.add(_lost);
      await tester.pumpWidget(await h.build(tester, debts: [_openDebt]));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'fmd_pay_d-open');
      await _tapKey(tester, 'repay_source_a-bank');
      await _tapKey(tester, 'fmd_pay_submit');
      await _tapKey(tester, 'fmd_confirm_ok');

      expect(find.byKey(const ValueKey('fmd_pay_unconfirmed')), findsOneWidget);
      expect(h.accounts.refreshes, 1);
      await _tapKey(tester, 'repay_source_a-cash');
      await _tapKey(tester, 'fmd_pay_submit');
      expect(h.pays, hasLength(2));
      expect(h.pays[1], h.pays[0]);
    });

    testWidgets("a former member's reversal: Reverse again sends the same key", (tester) async {
      h.failNext.add(_lost);
      await tester.pumpWidget(await h.build(tester, debts: [_openDebt]));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'fmd_history_d-open');
      await _tapKey(tester, 'fmd_reverse_e-bank');
      await _tapKey(tester, 'rev_confirm_ok');
      expect(h.accounts.refreshes, 1);
      await _tapKey(tester, 'fmd_reverse_e-bank');
      await _tapKey(tester, 'rev_confirm_ok');
      expect(h.fmdReversals, hasLength(2));
      expect(h.fmdReversals[1].requestKey, h.fmdReversals[0].requestKey);
    });

    testWidgets('a decline: the dialog stays with its reason, the card reloads, declining again is safe', (tester) async {
      h.failNext.add(_lost);
      await tester.pumpWidget(await h.build(tester, requests: [_pending]));
      await tester.pumpAndSettle();
      final loads = h.summaryLoads;
      await _tapKey(tester, 'req_decline_q-1');
      await tester.enterText(find.byKey(const ValueKey('req_decline_reason')), 'Not yet');
      await _tapKey(tester, 'req_decline_ok');

      expect(find.text('Decline this request?'), findsOneWidget);
      expect(find.text(_en('repay_unconfirmed_hold')), findsOneWidget);
      expect(h.summaryLoads, greaterThan(loads));
      await _tapKey(tester, 'req_decline_ok');
      expect(h.declines, hasLength(2));
      expect(h.declines[1], h.declines[0]);
    });

    testWidgets('her request: the sheet keeps the amount and the key', (tester) async {
      h.failNext.add(_lost);
      await tester.pumpWidget(await h.build(tester, role: 'wife'));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'nafaqah_mark_received_$_wife');
      await tester.enterText(find.byKey(const ValueKey('req_amount_field')), '20');
      await _tapKey(tester, 'req_send');
      expect(find.byKey(const ValueKey('req_unconfirmed')), findsOneWidget);
      await _tapKey(tester, 'req_send');
      expect(h.asks, hasLength(2));
      expect(h.asks[1], h.asks[0]);
    });

    testWidgets('her cancel: she is told it may have gone through, and the card reloads', (tester) async {
      h.failNext.add(_lost);
      await tester.pumpWidget(await h.build(tester, role: 'wife', requests: [_pending]));
      await tester.pumpAndSettle();
      final loads = h.summaryLoads;
      await _tapKey(tester, 'req_cancel_q-1');
      expect(find.text(_en('fmd_unconfirmed_msg')), findsOneWidget);
      expect(h.summaryLoads, greaterThan(loads));
    });
  });

  group('R1-09: every refusal has its words; the reason counts code points', () {
    testWidgets('a key reused with other details is explained', (tester) async {
      h.failWith = const NafaqahApiException('request_key_reused', 'refused', statusCode: 409);
      await tester.pumpWidget(await h.build(tester));
      await tester.pumpAndSettle();
      await _openReimburse(tester);
      await _tapKey(tester, 'repay_source_a-bank');
      await _submitReimburse(tester);
      expect(find.text('This was already sent with different details. Close this, check the balance, then try again.'), findsOneWidget);
    });

    testWidgets('a reason over the limit is explained', (tester) async {
      h.failWith = const NafaqahApiException('invalid_reason', 'refused', statusCode: 422);
      await tester.pumpWidget(await h.build(tester, requests: [_pending]));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'req_decline_q-1');
      await _tapKey(tester, 'req_decline_ok');
      expect(find.text('The reason is too long: at most 200 characters.'), findsOneWidget);
    });

    testWidgets('an Arabic reason with harakat stops at 200 code points, as the server counts', (tester) async {
      await tester.pumpWidget(await h.build(tester, requests: [_pending]));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'req_decline_q-1');
      final marked = '${'بِ' * 100}ب'; // 201 code points, 101 graphemes
      await tester.enterText(find.byKey(const ValueKey('req_decline_reason')), marked);
      await tester.pumpAndSettle();
      await _tapKey(tester, 'req_decline_ok');
      expect(h.declines.single.reason!.runes.length, 200);
    });
  });

  group('R1-12: labels carry their own localized punctuation', () {
    for (final lang in ['en', 'ar', 'ur']) {
      testWidgets('$lang: what is owed, and what remains of a record', (tester) async {
        await tester.pumpWidget(await h.build(tester, lang: lang, debts: [_openDebt]));
        await tester.pumpAndSettle();
        final map = AppLocalizations.localizedMap(lang);
        expect(map['husband_owes_wife_label'], isNotNull);
        expect(map['fmd_remaining_label'], isNotNull);
        expect(find.text(map['husband_owes_wife_label']!), findsOneWidget);
        expect(find.text(map['fmd_remaining_label']!), findsOneWidget);
      });
    }
  });
}
