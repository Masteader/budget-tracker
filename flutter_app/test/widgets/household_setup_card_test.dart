// UX-02: a new household gets a guided setup (payday, income, starter budgets,
// invite, Nafaqah provider in family mode) instead of a 0.00 hero that points
// "below" at nothing.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/household_membership.dart';
import 'package:budget_tracker/models/household_setup.dart';
import 'package:budget_tracker/widgets/accounts/record_income_sheet.dart';
import 'package:budget_tracker/widgets/dashboard/household_setup_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

HouseholdRoster _roster({String type = 'family', bool admin = true, int members = 1, bool provider = true}) =>
    HouseholdRoster.fromMap({
      'household_id': 'hh',
      'household_type': type,
      'caller_role': admin ? 'admin' : 'member',
      'nafaqah_provider_user_id': provider ? 'u-1' : null,
      'members': [
        {'user_id': 'u-1', 'display_name': 'Ahmed', 'role': admin ? 'admin' : 'member', 'is_self': true, 'financial_role': 'provider'},
        for (var i = 1; i < members; i++) {'user_id': 'u-${i + 1}', 'display_name': 'M$i', 'role': 'member'},
      ],
    });

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      locale: locale,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('HouseholdSetupData', () {
    test('family household: five steps, provider included', () {
      final d = HouseholdSetupData(paydayDay: 27, monthlyIncome: 0, roster: _roster());
      expect(d.steps, SetupStep.values);
      expect(d.isDone(SetupStep.payday, hasBudgets: false), isFalse);
      expect(d.isDone(SetupStep.income, hasBudgets: false), isFalse);
      expect(d.isDone(SetupStep.budgets, hasBudgets: false), isFalse);
      expect(d.isDone(SetupStep.invite, hasBudgets: false), isFalse);
      expect(d.isDone(SetupStep.provider, hasBudgets: false), isTrue);
      expect(d.doneCount(hasBudgets: false), 1);
    });

    test('roommates: no Nafaqah provider step', () {
      final d = HouseholdSetupData(roster: _roster(type: 'roommates'));
      expect(d.steps, isNot(contains(SetupStep.provider)));
    });

    test('complete once every step is done', () {
      final d = HouseholdSetupData(paydayConfirmed: true, monthlyIncome: 12000, roster: _roster(members: 2));
      expect(d.isComplete(hasBudgets: true), isTrue);
      expect(d.isComplete(hasBudgets: false), isFalse);
    });

    test('starter budgets follow the income, rounded to 50', () {
      final rows = starterBudgetTemplate(10000);
      final byCode = {for (final r in rows) r.categoryCode: r.amount};
      expect(byCode['OPEX-UTILITIES'], 2500);
      expect(byCode['OPEX-GROCERY'], 2000);
      expect(byCode['OPEX-FUEL'], 800);
      expect(byCode['OPEX-HEALTH'], 400);
      expect(rows.fold<double>(0, (s, r) => s + r.amount), lessThan(10000), reason: 'leaves room for savings');
      expect(starterBudgetTemplate(null).every((r) => r.amount == 0), isTrue);
    });
  });

  testWidgets('admin of a new household sees the checklist, not a dead end', (tester) async {
    await tester.pumpWidget(_app(HouseholdSetupCard(
      householdId: 'hh',
      data: HouseholdSetupData(paydayDay: 27, monthlyIncome: 0, roster: _roster()),
      hasBudgets: false,
      onChanged: () {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('Set up your household in two minutes'), findsOneWidget);
    expect(find.text('1 of 5 done'), findsOneWidget);
    expect(find.text('Payday: day 27 of the month'), findsOneWidget);
    expect(find.text('Monthly income'), findsOneWidget);
    expect(find.text('Starter budgets'), findsOneWidget);
    expect(find.text('Invite your wife'), findsOneWidget);
    expect(find.text('Choose who provides (Nafaqah)'), findsOneWidget);
    expect(find.text('Hide'), findsNothing, reason: 'cannot be hidden before budgets exist');
  });

  testWidgets('confirming the payday marks the step done', (tester) async {
    var confirmed = 0;
    var changed = 0;
    await tester.pumpWidget(_app(HouseholdSetupCard(
      householdId: 'hh',
      data: HouseholdSetupData(paydayDay: 27, monthlyIncome: 0, roster: _roster()),
      hasBudgets: false,
      onChanged: () => changed++,
      confirmPayday: () async => confirmed++,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setup_confirm_payday')));
    await tester.pumpAndSettle();
    expect(confirmed, 1);
    expect(changed, 1);
  });

  testWidgets('the income step opens the income editor', (tester) async {
    // The settings card's display row needs more than the default test width
    // with the test font (its layout belongs to the settings screen).
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(HouseholdSetupCard(
      householdId: 'hh',
      data: HouseholdSetupData(paydayDay: 27, monthlyIncome: 0, roster: _roster()),
      hasBudgets: false,
      onChanged: () {},
      saveIncome: (_) async => true,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monthly income'));
    await tester.pumpAndSettle();
    expect(find.byType(RecordIncomeSheet), findsOneWidget);
  });

  testWidgets('starter budgets: amounts from the income, created through the API seam', (tester) async {
    final created = <String, double>{};
    await tester.pumpWidget(_app(HouseholdSetupCard(
      householdId: 'hh',
      data: HouseholdSetupData(paydayDay: 27, paydayConfirmed: true, monthlyIncome: 10000, roster: _roster()),
      hasBudgets: false,
      onChanged: () {},
      createBudget: (code, name, amount) async {
        created[code] = amount;
        return code != 'OPEX-MISC'; // one category refused
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Starter budgets'));
    await tester.pumpAndSettle();
    expect(find.text('Suggested budgets'), findsOneWidget);
    expect(find.widgetWithText(TextField, '2500'), findsOneWidget);

    // Skip fuel.
    await tester.enterText(find.byKey(const Key('starter_amount_OPEX-FUEL')), '0');
    await tester.tap(find.text('Create budgets'));
    await tester.pumpAndSettle();
    expect(created.keys, isNot(contains('OPEX-FUEL')));
    expect(created['OPEX-GROCERY'], 2000);
    expect(find.textContaining('Some budgets could not be created'), findsOneWidget);
    expect(find.textContaining('Miscellaneous'), findsWidgets);
  });

  testWidgets('a member who is not an admin is told the admin sets things up', (tester) async {
    await tester.pumpWidget(_app(HouseholdSetupCard(
      householdId: 'hh',
      data: HouseholdSetupData(paydayDay: 27, monthlyIncome: 0, roster: _roster(admin: false)),
      hasBudgets: false,
      onChanged: () {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('Budgets not set up yet'), findsOneWidget);
    expect(find.text('Starter budgets'), findsNothing);
  });

  testWidgets('with budgets the checklist can be hidden', (tester) async {
    var hidden = 0;
    await tester.pumpWidget(_app(HouseholdSetupCard(
      householdId: 'hh',
      data: HouseholdSetupData(paydayDay: 27, monthlyIncome: 0, roster: _roster()),
      hasBudgets: true,
      onChanged: () {},
      onHide: () => hidden++,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide'));
    expect(hidden, 1);
  });

  testWidgets('Arabic checklist', (tester) async {
    await tester.pumpWidget(_app(
      HouseholdSetupCard(
        householdId: 'hh',
        data: HouseholdSetupData(paydayDay: 27, monthlyIncome: 0, roster: _roster()),
        hasBudgets: false,
        onChanged: () {},
      ),
      locale: const Locale('ar'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('جهّز منزلك في دقيقتين'), findsOneWidget);
    expect(find.text('اختيار المكلّف بالنفقة'), findsOneWidget);
  });

  testWidgets('HouseholdSetupPrefs setHidden and isHidden toggle correctly', (tester) async {
    SharedPreferences.setMockInitialValues({});
    expect(await HouseholdSetupPrefs.isHidden('hh-test'), isFalse);

    await HouseholdSetupPrefs.setHidden('hh-test', true);
    expect(await HouseholdSetupPrefs.isHidden('hh-test'), isTrue);

    await HouseholdSetupPrefs.setHidden('hh-test', false);
    expect(await HouseholdSetupPrefs.isHidden('hh-test'), isFalse);
  });

  testWidgets('showChecklistSheet opens bottom sheet and restores checklist to dashboard', (tester) async {
    SharedPreferences.setMockInitialValues({
      'setup_hidden_hh-sheet': true,
    });
    var restored = false;

    await tester.pumpWidget(_app(
      Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () => HouseholdSetupCard.showChecklistSheet(
            ctx,
            householdId: 'hh-sheet',
            onRestored: () => restored = true,
          ),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('restore_setup_checklist_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('restore_setup_checklist_button')));
    await tester.pumpAndSettle();

    expect(restored, isTrue);
    expect(await HouseholdSetupPrefs.isHidden('hh-sheet'), isFalse);
  });
}
