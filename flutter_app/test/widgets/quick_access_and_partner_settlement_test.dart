import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/screens/home/dashboard_screen.dart';
import 'package:budget_tracker/widgets/dashboard/family_reimbursement_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildTestApp(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  group('QuickAccessStrip Widget Tests', () {
    testWidgets('renders in English with dynamic counts and triggers taps', (tester) async {
      var accountsTapped = false;
      var nafaqahTapped = false;
      var billsTapped = false;
      var basketTapped = false;
      var viewAllTapped = false;

      await tester.pumpWidget(
        _buildTestApp(
          QuickAccessStrip(
            accountsCount: 3,
            billsCount: 4,
            wifeAllowance: 420.0,
            onAccountsTap: () => accountsTapped = true,
            onNafaqahTap: () => nafaqahTapped = true,
            onBillsTap: () => billsTapped = true,
            onSmartBasketTap: () => basketTapped = true,
            onViewAllTap: () => viewAllTapped = true,
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Check English localized headers
      expect(find.text('Quick Access'), findsOneWidget);
      expect(find.text('Show all'), findsOneWidget);

      // Check dynamic count pills
      expect(find.text('Accounts (3)'), findsOneWidget);
      expect(find.textContaining('Wife Allowance'), findsOneWidget);
      expect(find.text('Bills (4)'), findsOneWidget);
      expect(find.text('Smart Basket'), findsOneWidget);

      // Test tap interactions
      await tester.tap(find.text('Accounts (3)'));
      expect(accountsTapped, isTrue);

      await tester.tap(find.textContaining('Wife Allowance'));
      expect(nafaqahTapped, isTrue);

      await tester.tap(find.text('Bills (4)'));
      expect(billsTapped, isTrue);

      await tester.tap(find.text('Smart Basket'));
      expect(basketTapped, isTrue);

      await tester.tap(find.text('Show all'));
      expect(viewAllTapped, isTrue);
    });

    testWidgets('renders in Arabic without hardcoded English and handles zero counts cleanly', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          QuickAccessStrip(
            accountsCount: null,
            billsCount: 0,
            wifeAllowance: null,
            onAccountsTap: () {},
            onNafaqahTap: () {},
            onBillsTap: () {},
            onSmartBasketTap: () {},
            onViewAllTap: () {},
          ),
          locale: const Locale('ar'),
        ),
      );
      await tester.pumpAndSettle();

      // Check Arabic localized headers
      expect(find.text('وصول سريع'), findsOneWidget);
      expect(find.text('عرض الكل'), findsOneWidget);

      // Check that without counts, it displays clean localized titles without fake numbers
      expect(find.text('الحسابات'), findsOneWidget);
      expect(find.text('مصروف الزوجة'), findsOneWidget);
      expect(find.text('الفواتير'), findsOneWidget);
      expect(find.text('السلة الذكية'), findsOneWidget);
    });
  });

  group('FamilyReimbursementCard emptyPlaceholder Tests', () {
    testWidgets('renders emptyPlaceholder when in family mode with no wives configured', (tester) async {
      final summaryNoWives = NafaqahSummary.fromMap({
        'mode': 'family_nafaqah',
        'caller_role': 'husband',
        'caller_user_id': 'u-husband',
        'cycle_key': '2026-11',
        'husband': {'id': 'u-husband', 'display_name': 'Ahmed'},
        'wives': [],
      });

      const placeholderKey = Key('no_wife_placeholder');

      await tester.pumpWidget(
        _buildTestApp(
          FamilyReimbursementCard(
            householdId: 'hh-1',
            summary: summaryNoWives,
            emptyPlaceholder: const Text('No wife configured', key: placeholderKey),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(placeholderKey), findsOneWidget);
      expect(find.text('No wife configured'), findsOneWidget);
    });

    testWidgets('returns SizedBox.shrink when emptyPlaceholder is omitted', (tester) async {
      final summaryNoWives = NafaqahSummary.fromMap({
        'mode': 'family_nafaqah',
        'caller_role': 'husband',
        'caller_user_id': 'u-husband',
        'cycle_key': '2026-11',
        'husband': {'id': 'u-husband', 'display_name': 'Ahmed'},
        'wives': [],
      });

      await tester.pumpWidget(
        _buildTestApp(
          FamilyReimbursementCard(
            householdId: 'hh-1',
            summary: summaryNoWives,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FamilyReimbursementCard), findsOneWidget);
      expect(find.text('No wife configured'), findsNothing);
    });
  });
}
