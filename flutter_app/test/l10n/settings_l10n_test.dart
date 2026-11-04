// Localization and RTL pins for the Settings page's scope.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/household_membership.dart';
import 'package:budget_tracker/models/household_setup.dart';
import 'package:budget_tracker/widgets/dashboard/household_setup_card.dart';
import 'package:budget_tracker/widgets/settings/household_management_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/localized_app.dart';

Set<String> _placeholders(String s) => RegExp(r'\{[a-zA-Z_]+\}').allMatches(s).map((m) => m.group(0)!).toSet();

void main() {
  group('section title and export keys', () {
    const keys = {
      'set_money_section': 'SALARY & ACCOUNTS',
      'set_account_section': 'ACCOUNT',
      'set_partner_settlement_section': 'PARTNER SETTLEMENT',
      'set_reminders_section': 'REMINDERS',
      'set_export_monthly_label': 'Monthly Export',
      'csv_export_title': 'Export Report ({label})',
      'csv_export_current': 'Current',
      'csv_export_summary': '{transactions} • Total {amount}',
      'csv_copy': 'Copy CSV',
      'csv_copied_title': 'Report Copied',
      'csv_copied_msg': 'CSV report copied to clipboard. Ready to paste into Excel or Google Sheets.',
      'undo_action': 'UNDO',
    };

    keys.forEach((key, english) {
      test('$key resolves in en, ar and ur, translated', () {
        final en = AppLocalizations(const Locale('en')).get(key);
        final ar = AppLocalizations(const Locale('ar')).get(key);
        final ur = AppLocalizations(const Locale('ur')).get(key);
        expect(en, english);
        for (final v in [ar, ur]) {
          expect(v, isNot(key));
          expect(v, isNot(en));
          expect(RegExp('[؀-ۿ]').hasMatch(v), isTrue, reason: v);
        }
        expect(_placeholders(ar), _placeholders(en));
        expect(_placeholders(ur), _placeholders(en));
      });
    });

  });

  test('the language subtitle names all three languages (verified, stays that way)', () {
    const key = 'set_general_application_language_en_ar';
    expect(AppLocalizations(const Locale('en')).get(key), contains('UR'));
    expect(AppLocalizations(const Locale('ar')).get(key), contains('الأردية'));
    expect(AppLocalizations(const Locale('ur')).get(key), contains('اردو'));
  });

  group('setup checklist', () {
    const data = HouseholdSetupData(
      paydayDay: 27,
      paydayConfirmed: true,
      monthlyIncome: 0,
      roster: HouseholdRoster(
        householdId: 'hh',
        householdType: 'family',
        callerRole: 'admin',
        members: [HouseholdMember(userId: 'me', role: 'admin', isSelf: true)],
      ),
      hidden: false,
    );

    for (final lang in ['en', 'ar', 'ur']) {
      testWidgets('$lang: the step chevron points forward (the SDK icon mirrors itself)', (tester) async {
        SharedPreferences.setMockInitialValues({});
        await tester.pumpWidget(localizedApp(
          HouseholdSetupCard(householdId: 'hh', data: data, hasBudgets: false, onChanged: () {}),
          lang: lang,
        ));
        await tester.pump();
        // matchTextDirection flips chevron_right in RTL; choosing chevron_left
        // there as well would flip it back to pointing the wrong way.
        expect(Icons.chevron_right_rounded.matchTextDirection, isTrue);
        expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
      });
    }

    testWidgets('the sheet close button has a localized tooltip', (tester) async {
      HouseholdSetupPrefs.loadOverride = (_) async => data;
      addTearDown(() => HouseholdSetupPrefs.loadOverride = null);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(localizedApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => HouseholdSetupCard.showChecklistSheet(context, householdId: 'hh'),
            child: const Text('open'),
          ),
        ),
        lang: 'ar',
      ));
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 400));
      final close = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close_rounded));
      expect(close.tooltip, AppLocalizations(const Locale('ar')).get('close'));
    });
  });

  group('starter budget failure list', () {
    for (final (lang, comma) in [('en', ', '), ('ar', '، '), ('ur', '، ')]) {
      testWidgets('$lang joins categories with its own comma', (tester) async {
        tester.view.physicalSize = const Size(390, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(localizedApp(
          StarterBudgetSheet(monthlyIncome: 10000, createBudget: (_, __, ___) async => false, onCreated: () {}),
          lang: lang,
        ));
        await tester.pump();
        final l = AppLocalizations(Locale(lang));
        final create = find.text(l.get('starter_budgets_create'));
        await tester.ensureVisible(create);
        await tester.pump();
        await tester.tap(create);
        await tester.pumpAndSettle();
        final message = find.textContaining(l.get('starter_budgets_partial').split('{categories}').first);
        expect(message, findsOneWidget);
        final shown = tester.widget<Text>(message).data!;
        expect(shown, contains(comma), reason: shown);
        if (lang != 'en') expect(shown, isNot(contains(', ')), reason: shown);
      });
    }
  });

  group('leave household exit icon', () {
    for (final (lang, scaleX) in [('en', 1.0), ('ar', -1.0), ('ur', -1.0)]) {
      testWidgets('$lang: mirrored only in RTL', (tester) async {
        tester.view.physicalSize = const Size(390, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(localizedApp(
          HouseholdManagementCard(
            householdName: 'Home',
            inviteCode: 'ABCD1234',
            userRole: 'member',
            members: const [],
            onCopyInviteCode: () {},
            onLeaveHousehold: () {},
            onSwitchHousehold: () {},
            onCreateHousehold: () {},
          ),
          lang: lang,
        ));
        await tester.pump();
        final flip = tester.widget<Transform>(
          find.ancestor(of: find.byIcon(Icons.logout_rounded), matching: find.byType(Transform)).first,
        );
        expect(flip.transform.storage[0], scaleX);
      });
    }
  });
}
