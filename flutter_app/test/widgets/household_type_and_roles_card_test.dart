// Household settings: the household type is shown; admins change it and
// change members' financial roles (only roles the server lists as assignable,
// never "wife" for the Nafaqah provider); refusals are explained. Onboarding
// asks Family vs Roommates when creating a household.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/household_membership.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/onboarding/household_screen.dart';
import 'package:budget_tracker/services/api/household_roles_api_client.dart';
import 'package:budget_tracker/widgets/settings/household_roles_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _app(Widget child, {String lang = 'en'}) => MaterialApp(
      locale: Locale(lang),
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

HouseholdRoster _family({bool admin = true, String type = 'family', List<String>? assignable}) => HouseholdRoster(
      householdId: 'hh',
      householdType: type,
      callerRole: admin ? 'admin' : 'member',
      canManageAdmins: admin,
      canChangeHouseholdType: admin,
      canSetFinancialRoles: admin,
      assignableFinancialRoles: assignable ?? const ['spouse', 'family_member', 'dependent'],
      nafaqahProviderUserId: 'h',
      canSetNafaqahProvider: admin,
      members: const [
        HouseholdMember(userId: 's', displayName: 'Fahad', role: 'admin', financialRole: 'family_member', isPrimary: true, isSelf: true),
        HouseholdMember(userId: 'h', displayName: 'Ahmed', financialRole: 'provider', isNafaqahProvider: true),
        HouseholdMember(userId: 'w', displayName: 'Sara', financialRole: 'spouse'),
      ],
    );

class _QuietTransactions extends TransactionProvider {
  @override
  Future<void> init(String householdId) async {}
}

class _QuietBudgets extends BudgetProvider {
  @override
  Future<void> init(String householdId) async {}
}

Finder _menuOf(String userId) => find.descendant(
      of: find.byKey(ValueKey('role-member-$userId')),
      matching: find.byIcon(Icons.more_vert_rounded),
    );

void main() {
  group('household type', () {
    testWidgets('everyone sees the type; a member has no Change button', (tester) async {
      await tester.pumpWidget(_app(HouseholdRolesCard(householdId: 'hh', loadRoster: (_) async => _family(admin: false))));
      await tester.pumpAndSettle();
      expect(find.text('Household type: Family (Nafaqah)'), findsOneWidget);
      expect(find.byKey(const ValueKey('household_type_change')), findsNothing);
      expect(find.text('Wife / Spouse'), findsOneWidget, reason: "Sara's financial role chip");
    });

    testWidgets('an admin changes the type; the roster is reloaded', (tester) async {
      final calls = <String>[];
      var roster = _family();
      String? changedTo;
      await tester.pumpWidget(_app(HouseholdRolesCard(
        householdId: 'hh',
        loadRoster: (_) async => roster,
        setHouseholdType: (hh, type) async {
          calls.add('$hh:$type');
          roster = _family(type: type, assignable: const ['peer']);
          return type;
        },
        onHouseholdTypeChanged: (t) => changedTo = t,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('household_type_change')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('household_type_roommates')).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('household_type_save')));
      await tester.pumpAndSettle();

      expect(calls, ['hh:roommates']);
      expect(changedTo, 'roommates');
      expect(find.text('Household type: Roommates'), findsOneWidget);
      expect(find.text('Household type changed to Roommates.'), findsOneWidget);
    });

    testWidgets('a blocked change shows the server message', (tester) async {
      await tester.pumpWidget(_app(HouseholdRolesCard(
        householdId: 'hh',
        loadRoster: (_) async => _family(),
        setHouseholdType: (hh, type) async => throw const HouseholdRolesApiException(
          'type_change_blocked',
          'Server response error (409)',
          statusCode: 409,
          serverMessage: 'This family has a wife and Nafaqah records.',
        ),
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('household_type_change')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('household_type_roommates')).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('household_type_save')));
      await tester.pumpAndSettle();
      expect(find.text('This family has a wife and Nafaqah records.'), findsOneWidget);
      expect(find.text('Household type: Family (Nafaqah)'), findsOneWidget);
    });
  });

  group('financial roles', () {
    testWidgets('the provider is never offered "wife"; a change reloads the roster', (tester) async {
      final calls = <String>[];
      var loads = 0;
      await tester.pumpWidget(_app(HouseholdRolesCard(
        householdId: 'hh',
        loadRoster: (_) async {
          loads++;
          return _family();
        },
        setFinancialRole: (hh, uid, role) async {
          calls.add('$uid:$role');
          return role;
        },
      )));
      await tester.pumpAndSettle();

      await tester.tap(_menuOf('h'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change financial role'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fin-role-option-spouse')), findsNothing);
      expect(find.byKey(const ValueKey('fin-role-option-family_member')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fin-role-option-dependent')));
      await tester.pumpAndSettle();

      expect(calls, ['h:dependent']);
      expect(loads, 2);
      expect(find.text('Ahmed is now: Dependent.'), findsOneWidget);
    });

    testWidgets('only the roles the server lists are offered (roommates: roommate)', (tester) async {
      await tester.pumpWidget(_app(HouseholdRolesCard(
        householdId: 'hh',
        loadRoster: (_) async => _family(type: 'roommates', assignable: const ['peer']),
      )));
      await tester.pumpAndSettle();
      await tester.tap(_menuOf('w'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change financial role'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fin-role-option-peer')), findsOneWidget);
      expect(find.byKey(const ValueKey('fin-role-option-spouse')), findsNothing);
    });

    for (final c in [
      (const HouseholdRolesApiException('forbidden', '', statusCode: 403), "Only an admin can change a member's financial role."),
      (const HouseholdRolesApiException('not_found', '', statusCode: 404), 'This member is no longer in the household.'),
      (const HouseholdRolesApiException('invalid', '', statusCode: 422), 'This role is not valid for this household type.'),
      (const HouseholdRolesApiException('spouse_has_ledger', '', statusCode: 409), 'so her role cannot be changed'),
    ]) {
      testWidgets('refusal ${c.$1.code} is explained', (tester) async {
        await tester.pumpWidget(_app(HouseholdRolesCard(
          householdId: 'hh',
          loadRoster: (_) async => _family(),
          setFinancialRole: (hh, uid, role) async => throw c.$1,
        )));
        await tester.pumpAndSettle();
        await tester.tap(_menuOf('w'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Change financial role'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('fin-role-option-family_member')));
        await tester.pumpAndSettle();
        expect(find.textContaining(c.$2), findsOneWidget);
      });
    }

    testWidgets('a member has no financial-role action', (tester) async {
      await tester.pumpWidget(_app(HouseholdRolesCard(householdId: 'hh', loadRoster: (_) async => _family(admin: false))));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    });

    testWidgets('Arabic: the type row is localized and RTL renders', (tester) async {
      await tester.pumpWidget(_app(HouseholdRolesCard(householdId: 'hh', loadRoster: (_) async => _family()), lang: 'ar'));
      await tester.pumpAndSettle();
      expect(find.text('نوع المنزل: الأسرة (النفقة الشرعية)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('onboarding: create asks Family vs Roommates', () {
    Future<List<Map<String, dynamic>>> create(WidgetTester tester, {String? type}) async {
      final calls = <Map<String, dynamic>>[];
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<BudgetProvider>.value(value: _QuietBudgets()),
          ChangeNotifierProvider<TransactionProvider>.value(value: _QuietTransactions()),
        ],
        child: MaterialApp(
          localizationsDelegates: const [AppLocalizationsDelegate()],
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
          locale: const Locale('en'),
          home: HouseholdScreen(
            destinationBuilder: (_) => const Text('home-screen'),
            createRpc: (fn, params) async {
              calls.add(params);
              return {'id': 'hh-new', 'name': params['p_name'], 'invite_code': 'ABCD1234'};
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Al Noor');
      if (type != null) {
        await tester.tap(find.byKey(ValueKey('household_type_$type')));
        await tester.pump();
      }
      await tester.tap(find.text('Create Household'));
      await tester.pump();
      return calls;
    }

    testWidgets('without a choice nothing is created and the user is asked', (tester) async {
      final calls = await create(tester);
      expect(calls, isEmpty);
      expect(find.text('Choose Family or Roommates first.'), findsOneWidget);
    });

    testWidgets('the chosen type is sent with the name', (tester) async {
      final calls = await create(tester, type: 'roommates');
      expect(calls, [
        {'p_name': 'Al Noor', 'p_household_type': 'roommates'},
      ]);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
