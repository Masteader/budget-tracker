// Round 3 review fixes of tracked repayments (owner decisions 2026-11-06).
//
// R3-01: the app shows a wife's repayment ledger (what is owed, her requests,
// the actions on them) only to her and to those who settle it (her husband;
// an admin who is not a wife once he is gone), and a former member's record
// only to the latter. The server is the source of truth and sends nothing
// else; the card hides, whatever a server sends, what the caller cannot use: a
// co-wife's entry, a ledger the caller may not decide on, a record the caller
// may not manage. An admin who reads no ledger still sets each wife's
// allowance (allowance_wives).
//
// R3-02: the approval sheet keeps its request key, and the account it sent,
// past closing and reopening while its answer is unknown, as its sibling
// sheets do (UnconfirmedPayments.approvalSlot), until a definite answer.
//
// Everything at 320 px wide and text scale 2.0, in ar, ur and en, light and
// dark: nothing overflows.
import 'dart:async';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/household_dues.dart';
import 'package:budget_tracker/models/household_membership.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/providers/household_role_provider.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/widgets/dashboard/family_reimbursement_card.dart';
import 'package:budget_tracker/widgets/nafaqah/unconfirmed_payments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _husband = 'u-husband';
const _wife = 'u-wife';
const _cowife = 'u-cowife';
const _admin = 'u-admin';
const _big = 1234567.89;

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
  // Her wife account (migration 20261105001300, section 12): every repayment credits it.
  const Account(id: 'wa-$_wife', householdId: 'hh', ownerUserId: 'u-husband', name: 'Her account', accountType: AccountType.wife, assignedWifeId: _wife),
  const Account(id: 'wa-$_cowife', householdId: 'hh', ownerUserId: 'u-husband', name: 'Her account', accountType: AccountType.wife, assignedWifeId: _cowife),
  _acct('a-bank', 'Al Rajhi current account'),
  _acct('a-pool', 'Home pool shared by the family', owner: _admin, pool: true),
];

Map<String, dynamic> _wifeEntry(String id, String name, {double outstanding = 500, List<Map<String, dynamic>> requests = const [],
        bool? canRequest, bool? canDecide}) =>
    {
      'id': id,
      'display_name': name,
      'reimbursement': {'gross_advanced': outstanding, 'reimbursed': 0, 'outstanding': outstanding, 'overpaid': 0,
                        'pending_requested': requests.fold<num>(0, (s, r) => s + (r['amount'] as num))},
      'allowance': {'cycle_key': '2026-11', 'is_set': true, 'allocated': 750, 'spent': 80, 'remaining': 670, 'transaction_count': 1},
      'requests': requests,
      if (canRequest != null) 'can_request': canRequest,
      if (canDecide != null) 'can_decide': canDecide,
    };

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
      'events': const [],
    };

class _Harness {
  final approvals = <({String requestId, String accountId, String requestKey})>[];
  final failNext = <Object>[];
  late _Accounts accounts;

  Future<Widget> build(
    NafaqahSummary summary, {
    required String me,
    bool admin = true,
    String lang = 'en',
    bool dark = false,
    double scale = 1.0,
  }) async {
    accounts = _Accounts()..setAccountsForTesting(_all, householdId: 'hh');
    final roles = HouseholdRoleProvider(
      loadMemberships: () async => [
        HouseholdMembership(householdId: 'hh', householdName: 'Home', inviteCode: '', role: admin ? 'admin' : 'member', isActive: true),
      ],
      currentUserId: () => me,
    );
    await roles.load('hh');
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
              approveRequest: ({required String requestId, required String accountId, required String requestKey, String? wifeAccountId}) async {
                approvals.add((requestId: requestId, accountId: accountId, requestKey: requestKey));
                if (failNext.isNotEmpty) throw failNext.removeAt(0);
                return 0;
              },
              declineRequest: ({required String requestId, String? reason}) async {},
              setAllowance: ({required String wifeUserId, required double amount, String? cycleKey}) async =>
                  const AllowanceStatus(),
            ),
          ),
        ),
      ),
    );
  }
}

/// What a server answers each caller (review R3-01): [wives] and [allowanceWives] as given.
NafaqahSummary _summary({
  required String role,
  required String me,
  List<Map<String, dynamic>> wives = const [],
  List<Map<String, dynamic>> allowanceWives = const [],
  List<Map<String, dynamic>> debts = const [],
  bool canManageDebts = false,
  bool canRecord = false,
  bool canSetAllowance = false,
}) =>
    NafaqahSummary.fromMap({
      'mode': 'family_nafaqah',
      'caller_role': role,
      'caller_user_id': me,
      'cycle_key': '2026-11',
      'husband': {'id': _husband, 'display_name': 'Ahmed'},
      'wives': wives,
      'allowance_wives': allowanceWives,
      'can_set_allowance': canSetAllowance,
      'can_record_reimbursement': canRecord,
      'can_request_reimbursement': role == 'wife',
      'provider_user_id': _husband,
      'needs_provider': false,
      'can_set_provider': false,
      'former_member_debts': debts,
      'can_manage_former_member_debts': canManageDebts,
    });

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _closeSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(5, 5));
  await tester.pumpAndSettle();
}

String _t(String lang, String key) => AppLocalizations.localizedMap(lang)[key] ?? key;

const _lost = NafaqahApiException('network', 'no answer', noResponse: true);
const _refused = NafaqahApiException('insufficient_funds', 'refused', statusCode: 409);

void main() {
  late _Harness h;
  setUp(() {
    h = _Harness();
    UnconfirmedPayments.reset();
  });

  group('R3-02 the approval sheet keeps its key past closing while its answer is unknown', () {
    NafaqahSummary husbandView() => _summary(
          role: 'husband',
          me: _husband,
          canRecord: true,
          canSetAllowance: true,
          wives: [_wifeEntry(_wife, 'Sara', requests: [_request(120)], canDecide: true, canRequest: false)],
        );

    for (final failure in <String, Object Function()>{
      'no response': () => _lost,
      'TimeoutException': () => TimeoutException('no answer'),
    }.entries) {
      testWidgets('${failure.key}: closed and reopened, the same key and account', (tester) async {
        h.failNext.add(failure.value());
        await tester.pumpWidget(await h.build(husbandView(), me: _husband));
        await tester.pumpAndSettle();
        await _tapKey(tester, 'req_approve_q-1');
        await _tapKey(tester, 'repay_source_a-bank');
        await _tapKey(tester, 'req_approve_submit');
        expect(find.byKey(const ValueKey('req_approve_unconfirmed')), findsOneWidget);
        await _closeSheet(tester);

        await _tapKey(tester, 'req_approve_q-1');
        expect(find.byKey(const ValueKey('req_approve_unconfirmed')), findsOneWidget, reason: 'reopened, it holds it still');
        await _tapKey(tester, 'req_approve_submit');
        expect(h.approvals, hasLength(2));
        expect(h.approvals[1], h.approvals[0], reason: 'a new key could approve (and pay) twice if the first went through');
      });
    }

    testWidgets('a definite answer ends it: reopened after a refusal, a new key', (tester) async {
      h.failNext.addAll([_lost, _refused]);
      await tester.pumpWidget(await h.build(husbandView(), me: _husband));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'req_approve_q-1');
      await _tapKey(tester, 'repay_source_a-bank');
      await _tapKey(tester, 'req_approve_submit');
      await _tapKey(tester, 'req_approve_submit'); // refused: nothing was stored under it
      await _closeSheet(tester);

      await _tapKey(tester, 'req_approve_q-1');
      expect(find.byKey(const ValueKey('req_approve_unconfirmed')), findsNothing);
      await _tapKey(tester, 'repay_source_a-bank');
      await _tapKey(tester, 'req_approve_submit');
      expect(h.approvals, hasLength(3));
      expect(h.approvals[2].requestKey, isNot(h.approvals[0].requestKey));
    });

    test('one slot per request, apart from the other sheets', () {
      final approval = UnconfirmedPayments.approvalSlot('hh', 'q-1');
      expect(approval, isNot(UnconfirmedPayments.approvalSlot('hh', 'q-2')));
      expect(approval, isNot(UnconfirmedPayments.repaymentSlot('hh', 'q-1')));
      expect(approval, isNot(UnconfirmedPayments.requestSlot('hh', 'q-1')));
    });
  });

  group('R3-01 the card shows a ledger only to her and those who settle it', () {
    testWidgets('a co-wife sees her own entry only, even if a server sends another', (tester) async {
      final summary = _summary(role: 'wife', me: _cowife, wives: [
        _wifeEntry(_wife, 'Sara', requests: [_request(120)], canRequest: false, canDecide: false),
        _wifeEntry(_cowife, 'Huda', outstanding: 100, canRequest: true, canDecide: false),
      ]);
      await tester.pumpWidget(await h.build(summary, me: _cowife, admin: false));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nafaqah_mark_received_$_cowife')), findsOneWidget);
      expect(find.textContaining('Sara'), findsNothing, reason: "no entry for her co-wife");
      expect(find.byKey(const ValueKey('req_approve_q-1')), findsNothing);
      expect(find.byKey(const ValueKey('wife_allowance_$_wife')), findsNothing);
      expect(nafaqahDueLines(summary).map((l) => l.kind), [DueKind.owedToMe]);
    });

    testWidgets('a co-wife with no entry of her own sees no one else\'s', (tester) async {
      final summary = _summary(role: 'wife', me: _cowife, wives: [
        _wifeEntry(_wife, 'Sara', requests: [_request(120)], canRequest: false, canDecide: false),
      ]);
      await tester.pumpWidget(await h.build(summary, me: _cowife, admin: false));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wife_allowance_$_wife')), findsNothing);
      expect(find.byKey(const ValueKey('req_section_$_wife')), findsNothing);
      expect(find.text(_t('en', 'nafaqah_owed_to_you_label')), findsNothing);
      expect(nafaqahDueLines(summary), isEmpty);
    });

    testWidgets('an admin while the husband is there: no ledger, but her allowance to set', (tester) async {
      final summary = _summary(role: 'member', me: _admin, canSetAllowance: true, allowanceWives: [
        {'id': _wife, 'display_name': 'Sara',
         'allowance': {'cycle_key': '2026-11', 'is_set': true, 'allocated': 750, 'spent': 80, 'remaining': 670, 'transaction_count': 1}},
      ]);
      await tester.pumpWidget(await h.build(summary, me: _admin));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wife_allowance_$_wife')), findsOneWidget);
      expect(find.text(_t('en', 'allowance_edit')), findsOneWidget, reason: 'he still sets it (rule 04)');
      expect(find.byKey(const ValueKey('nafaqah_reimburse_$_wife')), findsNothing);
      expect(find.text(_t('en', 'husband_owes_wife_label')), findsNothing);
      expect(nafaqahDueLines(summary), isEmpty);
    });

    testWidgets('a ledger the caller may not decide on is not shown, whatever a server sends', (tester) async {
      final summary = _summary(role: 'member', me: _admin, wives: [
        _wifeEntry(_wife, 'Sara', requests: [_request(120)], canRequest: false, canDecide: false),
      ]);
      await tester.pumpWidget(await h.build(summary, me: _admin));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('req_section_$_wife')), findsNothing);
      expect(find.text(_t('en', 'husband_owes_wife_label')), findsNothing);
      expect(nafaqahDueLines(summary), isEmpty);
    });

    testWidgets('a former member\'s record only for who manages it', (tester) async {
      final hidden = _summary(role: 'member', me: _admin, debts: [_debt(400)]);
      await tester.pumpWidget(await h.build(hidden, me: _admin));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fmd_panel_d-open')), findsNothing);

      final shown = _summary(role: 'member', me: _admin, debts: [_debt(400)], canManageDebts: true);
      await tester.pumpWidget(await h.build(shown, me: _admin));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fmd_panel_d-open')), findsOneWidget);
    });

    testWidgets('the husband gone: the admin settles every wife', (tester) async {
      final summary = _summary(role: 'member', me: _admin, canRecord: true, canSetAllowance: true, canManageDebts: true,
          debts: [_debt(400)], wives: [
            _wifeEntry(_wife, 'Sara', requests: [_request(120)], canDecide: true, canRequest: false),
            _wifeEntry(_cowife, 'Huda', outstanding: 100, canDecide: true, canRequest: false),
          ]);
      await tester.pumpWidget(await h.build(summary, me: _admin));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nafaqah_reimburse_$_wife')), findsOneWidget);
      expect(find.byKey(const ValueKey('nafaqah_reimburse_$_cowife')), findsOneWidget);
      expect(find.byKey(const ValueKey('req_approve_q-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('fmd_panel_d-open')), findsOneWidget);
      expect(nafaqahDueLines(summary), hasLength(2));
    });
  });

  group('320 px, text x2.0, SAR 1,234,567.89', () {
    Future<void> at320(WidgetTester tester) async {
      tester.view.physicalSize = const Size(320 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
    }

    for (final lang in ['ar', 'ur', 'en']) {
      for (final dark in [false, true]) {
        testWidgets('$lang${dark ? ' dark' : ''}: an admin with only the allowance, and the approval sheet held', (tester) async {
          await at320(tester);
          final admin = _summary(role: 'member', me: _admin, canSetAllowance: true, allowanceWives: [
            {'id': _wife, 'display_name': 'Sara Abdulrahman Al-Qahtani',
             'allowance': {'cycle_key': '2026-11', 'is_set': true, 'allocated': _big, 'spent': _big, 'remaining': 0, 'transaction_count': 3}},
          ]);
          await tester.pumpWidget(await h.build(admin, me: _admin, lang: lang, dark: dark, scale: 2.0));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          h.failNext.add(_lost);
          final husband = _summary(role: 'husband', me: _husband, canRecord: true, wives: [
            _wifeEntry(_wife, 'Sara', outstanding: _big, requests: [_request(_big)], canDecide: true, canRequest: false),
          ]);
          await tester.pumpWidget(await h.build(husband, me: _husband, lang: lang, dark: dark, scale: 2.0));
          await tester.pumpAndSettle();
          await _tapKey(tester, 'req_approve_q-1');
          await _tapKey(tester, 'repay_source_a-bank');
          await _tapKey(tester, 'req_approve_submit');
          expect(find.byKey(const ValueKey('req_approve_unconfirmed')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
