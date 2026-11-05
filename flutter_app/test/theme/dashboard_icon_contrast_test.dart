import 'dart:async';

import 'package:budget_tracker/core/widgets/three_d_icon_puck.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/models/operating_cash.dart';
import 'package:budget_tracker/services/account_service.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/widgets/dashboard/accounts_summary_card.dart';
import 'package:budget_tracker/widgets/dashboard/family_reimbursement_card.dart';
import 'package:budget_tracker/widgets/dashboard/multi_roommate_settlement_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAccountService extends AccountService {
  final StreamController<List<Account>> _controller =
      StreamController<List<Account>>.broadcast();
  List<Account> accounts = [];

  @override
  Stream<List<Account>> streamAccounts(String householdId) =>
      _controller.stream;

  @override
  Future<List<Account>> getAccounts(String householdId) async => accounts;

  void emit(List<Account> accs) {
    accounts = accs;
    _controller.add(accs);
  }

  void close() => _controller.close();
}

Widget _app(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppThemes.darkTheme,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      locale: const Locale('en'),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('ThreeDIconPuck Theme Adaptation', () {
    testWidgets('isRoseGold: true renders Colors.white icon in dark mode',
        (tester) async {
      await tester.pumpWidget(
        _app(
          const ThreeDIconPuck(
            icon: Icons.account_balance_wallet_rounded,
            isRoseGold: true,
          ),
          theme: AppThemes.darkTheme,
        ),
      );
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, Colors.white);
    });

    testWidgets(
        'isRoseGold: true renders Color(0xFF4A0E1E) dark maroon icon in light mode',
        (tester) async {
      await tester.pumpWidget(
        _app(
          const ThreeDIconPuck(
            icon: Icons.account_balance_wallet_rounded,
            isRoseGold: true,
          ),
          theme: AppThemes.lightTheme,
        ),
      );
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, const Color(0xFF4A0E1E));
    });

    testWidgets('isRoseGold: true renders dark metallic gradient with >= 4.5:1 contrast against white icon in dark mode',
        (tester) async {
      await tester.pumpWidget(
        _app(
          const ThreeDIconPuck(
            icon: Icons.account_balance_wallet_rounded,
            isRoseGold: true,
          ),
          theme: AppThemes.darkTheme,
        ),
      );
      await tester.pumpAndSettle();

      final container = tester.widget<Container>(
        find.descendant(of: find.byType(ThreeDIconPuck), matching: find.byType(Container)).first,
      );
      final decoration = container.decoration as BoxDecoration;
      final gradient = decoration.gradient as LinearGradient;

      double contrast(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
      }

      for (final color in gradient.colors) {
        expect(contrast(Colors.white, color), greaterThanOrEqualTo(4.5),
            reason: 'White icon must reach >= 4.5:1 contrast on gradient color $color');
      }
    });
  });

  group('Dashboard HUD Header Icons in Dark Mode', () {
    late _FakeAccountService fakeAccountService;

    setUp(() {
      fakeAccountService = _FakeAccountService();
      AccountService.instance = fakeAccountService;
    });

    tearDown(() {
      fakeAccountService.close();
      AccountService.instance = AccountService();
    });

    testWidgets('AccountsSummaryCard wallet header icon is white in dark mode',
        (tester) async {
      const accounts = <Account>[
        Account(
          id: 'acc-1',
          householdId: 'hh1',
          ownerUserId: 'u1',
          name: 'Main Account',
          balance: 5000.0,
          currency: 'SAR',
          accountType: AccountType.bank,
        ),
      ];
      fakeAccountService.accounts = accounts;

      await tester.pumpWidget(
        _app(
          const AccountsSummaryCard(
            householdId: 'hh1',
            minAccounts: 1,
            snapshotOverride: OperatingCashSnapshot(
              householdId: 'hh1',
              cycleKey: '2026-11',
              liquidHalalas: 500000,
              pendingCommitmentsHalalas: 0,
              cycleIncomeHalalas: 500000,
              accountsCount: 1,
            ),
          ),
          theme: AppThemes.darkTheme,
        ),
      );
      await tester.pump();
      fakeAccountService.emit(accounts);
      await tester.pump();
      await tester.pumpAndSettle();

      final puckFinder = find.byWidgetPredicate(
        (w) =>
            w is ThreeDIconPuck &&
            w.isRoseGold == true &&
            w.icon == Icons.account_balance_wallet_rounded,
      );
      expect(puckFinder, findsOneWidget);

      final iconFinder = find.descendant(
        of: puckFinder,
        matching: find.byType(Icon),
      );
      expect(iconFinder, findsOneWidget);
      final icon = tester.widget<Icon>(iconFinder);
      expect(icon.color, Colors.white);
    });

    testWidgets(
        'FamilyReimbursementCard family header icon is white in dark mode',
        (tester) async {
      final summary = NafaqahSummary.fromMap({
        'mode': 'family_nafaqah',
        'caller_role': 'husband',
        'caller_user_id': 'u-husband',
        'cycle_key': '2026-11',
        'husband': {'id': 'u-husband', 'display_name': 'Ahmed'},
        'wives': [
          {
            'id': 'u-wife',
            'display_name': 'Sara',
            'reimbursement': {
              'household_id': 'hh1',
              'wife_user_id': 'u-wife',
              'current_balance': 300.0,
              'currency': 'SAR',
              'last_updated': '2026-11-01T00:00:00Z',
            },
            'allowance': {
              'cycle_key': '2026-11',
              'is_set': true,
              'allocated': 1000.0,
              'spent': 200.0,
              'remaining': 800.0,
            },
          }
        ],
      });

      await tester.pumpWidget(
        _app(
          FamilyReimbursementCard(householdId: 'hh1', summary: summary),
          theme: AppThemes.darkTheme,
        ),
      );
      await tester.pumpAndSettle();

      final puckFinder = find.byWidgetPredicate(
        (w) =>
            w is ThreeDIconPuck &&
            w.isRoseGold == true &&
            w.icon == Icons.family_restroom_rounded,
      );
      expect(puckFinder, findsOneWidget);

      final iconFinder = find.descendant(
        of: puckFinder,
        matching: find.byType(Icon),
      );
      expect(iconFinder, findsOneWidget);
      final icon = tester.widget<Icon>(iconFinder);
      expect(icon.color, Colors.white);
    });

    testWidgets(
        'MultiRoommateSettlementCard group header icon is white in dark mode',
        (tester) async {
      const summary = SettlementV2Summary(
        mode: 'multi_roommate',
        pairwiseDebts: [],
        simplifiedDebts: [],
        roommateBalances: {},
      );

      await tester.pumpWidget(
        _app(
          const MultiRoommateSettlementCard(
            householdId: 'hh1',
            summary: summary,
          ),
          theme: AppThemes.darkTheme,
        ),
      );
      await tester.pumpAndSettle();

      final puckFinder = find.byWidgetPredicate(
        (w) =>
            w is ThreeDIconPuck &&
            w.isRoseGold == true &&
            w.icon == Icons.group_outlined,
      );
      expect(puckFinder, findsOneWidget);

      final iconFinder = find.descendant(
        of: puckFinder,
        matching: find.byType(Icon),
      );
      expect(iconFinder, findsOneWidget);
      final icon = tester.widget<Icon>(iconFinder);
      expect(icon.color, Colors.white);
    });
  });
}
