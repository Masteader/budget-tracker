// Round 2 review fixes of tracked repayments (owner decisions 2026-11-06).
//
// R2-02: the direct repayment sheet treats any failure that is not one of the
// API's definite answers (a timeout, a lost socket, a bug) as an unknown
// outcome, as its sibling sheets do: it keeps its key and what it sent,
// offers "Try again" and reloads the balances and the card. Closing and
// reopening a sheet whose answer was lost does not mint a new key: it reopens
// holding the same key and values until a definite answer (her request and a
// former member's payment too).
//
// The other repayment and former member sheets at 320 px wide and text scale
// 2.0, with SAR 1,234,567.89, in ar, ur and en: nothing overflows.
import 'dart:async';
import 'dart:io';

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
const _big = 1234567.89;

/// Counts the reloads a repayment asks for, instead of reaching the server.
class _Accounts extends AccountProvider {
  int refreshes = 0;

  @override
  Future<void> refresh({bool force = false}) async => refreshes++;
}

Account _acct(String id, String name, {String owner = _husband, double balance = 2000000, bool pool = false}) => Account(
      id: id,
      householdId: 'hh',
      ownerUserId: owner,
      name: name,
      accountType: pool ? AccountType.sharedPool : AccountType.bank,
      currency: 'SAR',
      balance: balance,
      isSharedPool: pool,
    );

final _all = [
  _acct('a-bank', 'Al Rajhi current account'),
  _acct('a-pool', 'Home pool shared by the family', owner: 'u-coadmin', pool: true),
];

Map<String, dynamic> _request(double amount) =>
    {'id': 'q-1', 'amount': amount, 'payment_method': 'bank_transfer', 'status': 'pending', 'created_at': '2026-11-05T10:00:00Z'};

Map<String, dynamic> _debt(double remaining) => {
      'id': 'd-open',
      'original_amount': remaining + 500,
      'paid_amount': 500,
      'remaining': remaining,
      'status': 'open',
      'created_at': '2026-11-01T09:00:00Z',
      'closed_at': null,
      'events': [
        {'id': 'e-bank', 'kind': 'payment', 'amount': 500, 'payment_method': 'bank_transfer', 'remaining_after': remaining,
         'created_at': '2026-11-03T09:00:00Z', 'moved_balance': true, 'account_id': 'a-bank', 'can_reverse': true},
      ],
    };

NafaqahSummary _summary({String role = 'husband', double outstanding = 500.5, List<Map<String, dynamic>> requests = const [],
        List<Map<String, dynamic>> debts = const []}) =>
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
          'allowance': {'cycle_key': '2026-11', 'is_set': true, 'allocated': outstanding, 'spent': 0, 'remaining': outstanding,
                        'transaction_count': 0},
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

NafaqahLedger _ledger(double amount) => NafaqahLedger.fromMap({
      'balance': {'gross_advanced': amount + 100, 'reimbursed': 100, 'outstanding': amount},
      'history': [
        {'type': 'advance', 'id': 't1', 'amount': amount, 'merchant': 'Panda Hypermarket Riyadh', 'timestamp': '2026-11-06T10:00:00Z'},
        {'type': 'reimbursement', 'kind': 'payment', 'id': 'r1', 'amount': amount, 'payment_method': 'bank_transfer',
         'timestamp': '2026-11-05T10:00:00Z', 'moved_balance': true, 'account_id': 'a-bank', 'can_reverse': true},
        {'type': 'reimbursement', 'kind': 'reversal', 'id': 'r2b', 'amount': amount, 'payment_method': 'cash',
         'timestamp': '2026-11-04T12:00:00Z', 'moved_balance': true, 'account_id': 'a-pool'},
        {'type': 'reimbursement', 'kind': 'payment', 'id': 'r2', 'amount': amount, 'payment_method': 'cash',
         'timestamp': '2026-11-04T10:00:00Z', 'moved_balance': true, 'account_id': 'a-pool', 'reversed': true},
      ],
    });

typedef _Repay = ({double amount, String method, String accountId, String requestKey});

class _Harness {
  final repays = <_Repay>[];
  final asks = <({double amount, String method, String requestKey})>[];
  final pays = <({String debtId, double amount, String accountId, String requestKey})>[];

  /// Failures for the next calls, one each.
  final failNext = <Object>[];
  int summaryLoads = 0;
  late _Accounts accounts;

  Future<Widget> build({
    String role = 'husband',
    String lang = 'en',
    bool dark = false,
    double scale = 1.0,
    double outstanding = 500.5,
    List<Map<String, dynamic>> requests = const [],
    List<Map<String, dynamic>> debts = const [],
    double ledgerAmount = 40,
  }) async {
    accounts = _Accounts()..setAccountsForTesting(_all, householdId: 'hh');
    final roles = HouseholdRoleProvider(
      loadMemberships: () async => [
        HouseholdMembership(householdId: 'hh', householdName: 'Home', inviteCode: '', role: role == 'wife' ? 'member' : 'admin', isActive: true),
      ],
      currentUserId: () => role == 'wife' ? _wife : _husband,
    );
    await roles.load('hh');
    final summary = _summary(role: role, outstanding: outstanding, requests: requests, debts: debts);
    Future<void> maybeFail() async {
      if (failNext.isNotEmpty) throw failNext.removeAt(0);
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
              loadLedger: (_, __) async => _ledger(ledgerAmount),
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
              cancelRequest: ({required String requestId}) async {},
              approveRequest: ({required String requestId, required String accountId, required String requestKey}) async => 0,
              declineRequest: ({required String requestId, String? reason}) async {},
              reverseReimbursement: ({required String reimbursementId, required String requestKey}) async => 0,
              recordFormerMemberDebtPayment: ({
                required String debtId,
                required double amount,
                required String paymentMethod,
                required String requestKey,
                required String accountId,
              }) async {
                pays.add((debtId: debtId, amount: amount, accountId: accountId, requestKey: requestKey));
                await maybeFail();
                return FormerMemberDebtReceipt.fromMap(
                    {'status': 'open', 'debt_id': debtId, 'amount': amount, 'payment_method': paymentMethod, 'remaining': 0, 'account_id': accountId});
              },
              waiveFormerMemberDebt: ({required String debtId, required String requestKey}) async =>
                  FormerMemberDebtReceipt.fromMap({'status': 'waived', 'debt_id': debtId, 'remaining': 0}),
              reverseFormerMemberDebtPayment: ({required String debtId, required String eventId, required String requestKey}) async =>
                  FormerMemberDebtReceipt.fromMap({'status': 'open', 'debt_id': debtId, 'amount': 500, 'remaining': 0}),
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

String _t(String lang, String key) => AppLocalizations.localizedMap(lang)[key] ?? key;

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text).last;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openReimburse(WidgetTester tester) => _tapKey(tester, 'nafaqah_reimburse_$_wife');

Future<void> _submitReimburse(WidgetTester tester, {String lang = 'en'}) => _tapText(tester, _t(lang, 'settle_record_payment'));

Future<void> _closeSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(5, 5));
  await tester.pumpAndSettle();
}

const _lost = NafaqahApiException('network', 'no answer', noResponse: true);
const _refused = NafaqahApiException('insufficient_funds', 'refused', statusCode: 409);

void main() {
  late _Harness h;
  setUp(() => h = _Harness());

  group('R2-02 the direct repayment sheet: a failure that is not a definite answer', () {
    final failures = <String, Object Function()>{
      'TimeoutException': () => TimeoutException('no answer'),
      'SocketException': () => const SocketException('reset'),
      'StateError': () => StateError('boom'),
      'no response': () => _lost,
    };
    for (final entry in failures.entries) {
      testWidgets('${entry.key}: it holds what it sent, offers Try again and reloads', (tester) async {
        h.failNext.add(entry.value());
        await tester.pumpWidget(await h.build());
        await tester.pumpAndSettle();
        final loadsBefore = h.summaryLoads;
        await _openReimburse(tester);
        await _tapKey(tester, 'repay_source_a-bank');
        await _submitReimburse(tester);
        expect(find.byKey(const ValueKey('reimburse_unconfirmed')), findsOneWidget,
            reason: 'it may have been recorded: the sheet holds what it sent');
        expect(find.text(_t('en', 'try_again')), findsOneWidget);
        expect(h.accounts.refreshes, 1, reason: 'the balances reload');
        expect(h.summaryLoads, greaterThan(loadsBefore), reason: 'the card reloads');

        await _submitTryAgain(tester);
        expect(h.repays, hasLength(2));
        expect(h.repays[1], h.repays[0], reason: 'the same key, amount, method and account again');
      });

      testWidgets('${entry.key}: closed and reopened, it still holds the same key', (tester) async {
        h.failNext.add(entry.value());
        await tester.pumpWidget(await h.build());
        await tester.pumpAndSettle();
        await _openReimburse(tester);
        await _tapKey(tester, 'repay_source_a-bank');
        await tester.enterText(find.byKey(const ValueKey('reimburse_amount_field')), '120');
        await _submitReimburse(tester);
        await _closeSheet(tester);

        await _openReimburse(tester);
        expect(find.byKey(const ValueKey('reimburse_unconfirmed')), findsOneWidget, reason: 'reopened, it holds it still');
        await _submitTryAgain(tester);
        expect(h.repays, hasLength(2));
        expect(h.repays[1], h.repays[0], reason: 'a new key could record a second repayment if the first went through');
        expect(h.repays[1].amount, 120);
      });
    }

    testWidgets('a definite answer ends it: reopened after a success, a new key', (tester) async {
      h.failNext.add(TimeoutException('no answer'));
      await tester.pumpWidget(await h.build());
      await tester.pumpAndSettle();
      await _openReimburse(tester);
      await _tapKey(tester, 'repay_source_a-bank');
      await _submitReimburse(tester);
      await _submitTryAgain(tester); // recorded (or replayed): the sheet closes
      expect(find.byKey(const ValueKey('reimburse_unconfirmed')), findsNothing);

      await _openReimburse(tester);
      expect(find.byKey(const ValueKey('reimburse_unconfirmed')), findsNothing);
      await _tapKey(tester, 'repay_source_a-bank');
      await _submitReimburse(tester);
      expect(h.repays, hasLength(3));
      expect(h.repays[2].requestKey, isNot(h.repays[0].requestKey));
    });

    testWidgets('a definite refusal ends it too: reopened, a new key', (tester) async {
      h.failNext.addAll([TimeoutException('no answer'), _refused]);
      await tester.pumpWidget(await h.build());
      await tester.pumpAndSettle();
      await _openReimburse(tester);
      await _tapKey(tester, 'repay_source_a-bank');
      await _submitReimburse(tester);
      await _submitTryAgain(tester); // refused: nothing was recorded under it
      await _closeSheet(tester);

      await _openReimburse(tester);
      expect(find.byKey(const ValueKey('reimburse_unconfirmed')), findsNothing);
      await _tapKey(tester, 'repay_source_a-bank');
      await _submitReimburse(tester);
      expect(h.repays, hasLength(3));
      expect(h.repays[2].requestKey, isNot(h.repays[0].requestKey));
    });
  });

  group('R2-02 the other sheets that send a key', () {
    testWidgets("her request: closed and reopened after a lost answer, the same key", (tester) async {
      h.failNext.add(TimeoutException('no answer'));
      await tester.pumpWidget(await h.build(role: 'wife'));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'nafaqah_mark_received_$_wife');
      await tester.enterText(find.byKey(const ValueKey('req_amount_field')), '75');
      await _tapKey(tester, 'req_send');
      expect(find.byKey(const ValueKey('req_unconfirmed')), findsOneWidget);
      await _closeSheet(tester);

      await _tapKey(tester, 'nafaqah_mark_received_$_wife');
      expect(find.byKey(const ValueKey('req_unconfirmed')), findsOneWidget);
      await _tapKey(tester, 'req_send');
      expect(h.asks, hasLength(2));
      expect(h.asks[1], h.asks[0], reason: 'a new key would leave two requests for the same money');
    });

    testWidgets("a former member's payment: closed and reopened after a lost answer, the same key", (tester) async {
      h.failNext.add(const SocketException('reset'));
      await tester.pumpWidget(await h.build(debts: [_debt(400)]));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'fmd_pay_d-open');
      await tester.enterText(find.byKey(const ValueKey('fmd_amount_field')), '150');
      await _tapKey(tester, 'repay_source_a-bank');
      await _tapKey(tester, 'fmd_pay_submit');
      await _tapKey(tester, 'fmd_confirm_ok');
      expect(find.byKey(const ValueKey('fmd_pay_unconfirmed')), findsOneWidget);
      await _closeSheet(tester);

      await _tapKey(tester, 'fmd_pay_d-open');
      expect(find.byKey(const ValueKey('fmd_pay_unconfirmed')), findsOneWidget);
      await _tapKey(tester, 'fmd_pay_submit');
      expect(h.pays, hasLength(2));
      expect(h.pays[1], h.pays[0], reason: 'a new key could pay the record twice');
    });
  });

  group('the other repayment and former member sheets at 320 px, text x2.0, SAR 1,234,567.89', () {
    Future<void> at320(WidgetTester tester) async {
      tester.view.physicalSize = const Size(320 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
    }

    for (final lang in ['ar', 'ur', 'en']) {
      testWidgets('$lang: the card, the repayment sheet and its account picker', (tester) async {
        await at320(tester);
        await tester.pumpWidget(await h.build(lang: lang, dark: true, scale: 2.0, outstanding: _big, debts: [_debt(_big)]));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _openReimburse(tester);
        await _tapKey(tester, 'repay_source_a-pool');
        expect(tester.takeException(), isNull);
      });

      testWidgets('$lang: the approval sheet and the decline dialog', (tester) async {
        await at320(tester);
        await tester.pumpWidget(await h.build(lang: lang, scale: 2.0, outstanding: _big, requests: [_request(_big)]));
        await tester.pumpAndSettle();
        await _tapKey(tester, 'req_approve_q-1');
        await _tapKey(tester, 'repay_source_a-bank');
        expect(tester.takeException(), isNull);
        await _closeSheet(tester);
        await _tapKey(tester, 'req_decline_q-1');
        expect(tester.takeException(), isNull);
      });

      testWidgets('$lang: her request sheet', (tester) async {
        await at320(tester);
        await tester.pumpWidget(await h.build(role: 'wife', lang: lang, scale: 2.0, outstanding: _big));
        await tester.pumpAndSettle();
        await _tapKey(tester, 'nafaqah_mark_received_$_wife');
        expect(tester.takeException(), isNull);
      });

      testWidgets('$lang: the history and its reversal', (tester) async {
        await at320(tester);
        await tester.pumpWidget(await h.build(lang: lang, dark: true, scale: 2.0, outstanding: _big, ledgerAmount: _big));
        await tester.pumpAndSettle();
        await _tapText(tester, _t(lang, 'nafaqah_history'));
        expect(tester.takeException(), isNull);
        // The list builds what it shows: at x2.0 the repayment may be further down.
        await tester.dragUntilVisible(
            find.byKey(const ValueKey('rev_action_r1')), find.byType(Scrollable).last, const Offset(0, -120));
        await tester.pumpAndSettle();
        await _tapKey(tester, 'rev_action_r1');
        expect(tester.takeException(), isNull);
      });

      testWidgets("$lang: a former member's record, its history, payment and waiver", (tester) async {
        await at320(tester);
        await tester.pumpWidget(await h.build(lang: lang, scale: 2.0, debts: [_debt(_big)]));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _tapKey(tester, 'fmd_history_d-open');
        expect(tester.takeException(), isNull);
        await _closeSheet(tester);
        await _tapKey(tester, 'fmd_pay_d-open');
        await _tapKey(tester, 'repay_source_a-bank');
        await _tapKey(tester, 'fmd_pay_submit');
        expect(tester.takeException(), isNull, reason: 'the confirmation');
        await _tapKey(tester, 'fmd_confirm_cancel');
        await _closeSheet(tester);
        await _tapKey(tester, 'fmd_waive_d-open');
        expect(tester.takeException(), isNull);
      });
    }
  });
}

Future<void> _submitTryAgain(WidgetTester tester) => _tapText(tester, _t('en', 'try_again'));
