// Who sees and who sets a wife's personal allowance (owner decision
// 2026-11-06).
//
// Her allowance (allocated, spent, remaining) is shown to her (her own only),
// to her husband and to an admin who is not a wife. A co-wife, even an admin,
// and an ordinary member see none of it. The set action is offered to the
// husband and to an admin who is not a wife, never to a wife. The server sends
// nothing else; the card hides, whatever a server sends, what the caller may
// not see or set.
//
// Everything at 320 px wide and text scale 2.0, in ar, ur and en, light and
// dark: nothing overflows.
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
const _cowife = 'u-cowife';
const _admin = 'u-admin';
const _member = 'u-member';

class _Accounts extends AccountProvider {
  @override
  Future<void> refresh({bool force = false}) async {}
}

Map<String, dynamic> _allowance(double allocated) =>
    {'cycle_key': '2026-11', 'is_set': true, 'allocated': allocated, 'spent': 80, 'remaining': allocated - 80, 'transaction_count': 1};

Map<String, dynamic> _wifeEntry(String id, String name, {double allocated = 750, bool? canDecide, bool? canRequest}) => {
      'id': id,
      'display_name': name,
      'reimbursement': {'gross_advanced': 500, 'reimbursed': 0, 'outstanding': 500, 'overpaid': 0, 'pending_requested': 0},
      'allowance': _allowance(allocated),
      'requests': const [],
      if (canDecide != null) 'can_decide': canDecide,
      if (canRequest != null) 'can_request': canRequest,
    };

Map<String, dynamic> _allowanceOnly(String id, String name, {double allocated = 750}) =>
    {'id': id, 'display_name': name, 'allowance': _allowance(allocated)};

/// What a server answers each caller: [wives] and [allowanceWives] as given.
NafaqahSummary _summary({
  required String role,
  required String me,
  List<Map<String, dynamic>> wives = const [],
  List<Map<String, dynamic>> allowanceWives = const [],
  bool canSetAllowance = false,
  bool canRecord = false,
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
      'former_member_debts': const [],
      'can_manage_former_member_debts': false,
    });

Future<Widget> _build(
  NafaqahSummary summary, {
  required String me,
  bool admin = false,
  String lang = 'en',
  bool dark = false,
  double scale = 1.0,
}) async {
  final accounts = _Accounts()
    ..setAccountsForTesting([
      const Account(
        id: 'a-bank',
        householdId: 'hh',
        ownerUserId: _husband,
        name: 'Al Rajhi current account',
        accountType: AccountType.bank,
        currency: 'SAR',
        balance: 2000,
        isSharedPool: false,
      ),
    ], householdId: 'hh');
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
            setAllowance: ({required String wifeUserId, required double amount, String? cycleKey}) async =>
                const AllowanceStatus(),
          ),
        ),
      ),
    ),
  );
}

String _t(String lang, String key) => AppLocalizations.localizedMap(lang)[key] ?? key;

Finder _card(String wife) => find.byKey(ValueKey('wife_allowance_$wife'));
Finder _setAction(String lang) =>
    find.textContaining(RegExp('${RegExp.escape(_t(lang, 'allowance_edit'))}|${RegExp.escape(_t(lang, 'allowance_set'))}'));

void main() {
  group('who sees a wife\'s allowance', () {
    testWidgets('an ordinary member sees none, even if a server sends it', (tester) async {
      final summary = _summary(role: 'member', me: _member, allowanceWives: [_allowanceOnly(_wife, 'Sara')]);
      await tester.pumpWidget(await _build(summary, me: _member));
      await tester.pumpAndSettle();
      expect(_card(_wife), findsNothing);
      expect(find.textContaining('750'), findsNothing);
    });

    testWidgets('an ordinary member sent a ledger entry sees no allowance in it', (tester) async {
      final summary = _summary(role: 'member', me: _member, canRecord: true, wives: [_wifeEntry(_wife, 'Sara', canDecide: true)]);
      await tester.pumpWidget(await _build(summary, me: _member));
      await tester.pumpAndSettle();
      expect(_card(_wife), findsNothing);
      expect(_setAction('en'), findsNothing);
    });

    testWidgets('a wife sees her own and no co-wife\'s, even if a server sends it', (tester) async {
      final summary = _summary(role: 'wife', me: _cowife, canSetAllowance: true,
          wives: [_wifeEntry(_cowife, 'Huda', canRequest: true, canDecide: false)],
          allowanceWives: [_allowanceOnly(_wife, 'Sara')]);
      await tester.pumpWidget(await _build(summary, me: _cowife, admin: true));
      await tester.pumpAndSettle();
      expect(_card(_cowife), findsOneWidget);
      expect(_card(_wife), findsNothing);
      expect(find.textContaining('Sara'), findsNothing);
    });

    testWidgets('the husband (not an admin) sees and sets every wife\'s', (tester) async {
      final summary = _summary(role: 'husband', me: _husband, canSetAllowance: true, canRecord: true, wives: [
        _wifeEntry(_wife, 'Sara', canDecide: true, canRequest: false),
        _wifeEntry(_cowife, 'Huda', canDecide: true, canRequest: false),
      ]);
      await tester.pumpWidget(await _build(summary, me: _husband));
      await tester.pumpAndSettle();
      expect(_card(_wife), findsOneWidget);
      expect(_card(_cowife), findsOneWidget);
      expect(_setAction('en'), findsNWidgets(2));
    });

    testWidgets('an admin who is not a wife sees and sets each wife\'s, with the husband there', (tester) async {
      final summary = _summary(role: 'member', me: _admin, canSetAllowance: true,
          allowanceWives: [_allowanceOnly(_wife, 'Sara'), _allowanceOnly(_cowife, 'Huda')]);
      await tester.pumpWidget(await _build(summary, me: _admin, admin: true));
      await tester.pumpAndSettle();
      expect(_card(_wife), findsOneWidget);
      expect(_card(_cowife), findsOneWidget);
      expect(_setAction('en'), findsNWidgets(2));
    });

    testWidgets('an admin who is not a wife, the husband gone: each wife\'s with her ledger', (tester) async {
      final summary = _summary(role: 'member', me: _admin, canSetAllowance: true, canRecord: true, wives: [
        _wifeEntry(_wife, 'Sara', canDecide: true, canRequest: false),
      ]);
      await tester.pumpWidget(await _build(summary, me: _admin, admin: true));
      await tester.pumpAndSettle();
      expect(_card(_wife), findsOneWidget);
      expect(_setAction('en'), findsOneWidget);
    });
  });

  group('who sets it: never a wife', () {
    testWidgets('a wife who is an admin is not offered to set her own, even if a server says so', (tester) async {
      final summary = _summary(role: 'wife', me: _wife, canSetAllowance: true,
          wives: [_wifeEntry(_wife, 'Sara', canRequest: true, canDecide: false)]);
      await tester.pumpWidget(await _build(summary, me: _wife, admin: true));
      await tester.pumpAndSettle();
      expect(_card(_wife), findsOneWidget);
      expect(_setAction('en'), findsNothing);
    });
  });

  group('320 px, text x2.0', () {
    for (final lang in ['ar', 'ur', 'en']) {
      for (final dark in [false, true]) {
        testWidgets('$lang${dark ? ' dark' : ''}: the member sees nothing, the admin sees and sets', (tester) async {
          tester.view.physicalSize = const Size(320 * 2, 800 * 2);
          tester.view.devicePixelRatio = 2;
          addTearDown(tester.view.reset);
          final member = _summary(role: 'member', me: _member, allowanceWives: [_allowanceOnly(_wife, 'Sara Abdulrahman Al-Qahtani')]);
          await tester.pumpWidget(await _build(member, me: _member, lang: lang, dark: dark, scale: 2.0));
          await tester.pumpAndSettle();
          expect(_card(_wife), findsNothing);
          expect(tester.takeException(), isNull);

          final admin = _summary(role: 'member', me: _admin, canSetAllowance: true,
              allowanceWives: [_allowanceOnly(_wife, 'Sara Abdulrahman Al-Qahtani', allocated: 1234567.89)]);
          await tester.pumpWidget(await _build(admin, me: _admin, admin: true, lang: lang, dark: dark, scale: 2.0));
          await tester.pumpAndSettle();
          expect(_card(_wife), findsOneWidget);
          expect(_setAction(lang), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
