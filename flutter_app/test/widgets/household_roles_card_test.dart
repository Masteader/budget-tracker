// Members & admins section of household settings (DB-16 / DB-18): admins
// promote/revoke co-admins, only the primary admin transfers primary admin,
// co-admins get no action against the primary admin, refusals are explained.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/household_membership.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/household_roles_api_client.dart';
import 'package:budget_tracker/widgets/settings/household_roles_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

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

HouseholdRoster _roster({required String self, bool canManage = false, bool canTransfer = false, String? coAdmin}) {
  HouseholdMember m(String id, String name, String role, {bool primary = false}) =>
      HouseholdMember(userId: id, displayName: name, role: role, isPrimary: primary, isSelf: id == self);
  return HouseholdRoster(
    householdId: 'hh',
    primaryAdminUserId: 'p',
    canManageAdmins: canManage,
    canTransferPrimary: canTransfer,
    members: [
      m('p', 'Ali', 'admin', primary: true),
      m('c', 'Saad', coAdmin == 'c' ? 'admin' : 'member'),
      m('m', 'Majed', 'member'),
    ],
  );
}

Finder _menuOf(String userId) => find.descendant(
      of: find.byKey(ValueKey('role-member-$userId')),
      matching: find.byIcon(Icons.more_vert_rounded),
    );

void main() {
  testWidgets('a member sees the roles but no actions', (tester) async {
    await tester.pumpWidget(_app(HouseholdRolesCard(
      householdId: 'hh',
      loadRoster: (_) async => _roster(self: 'm'),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Members & Admins'), findsOneWidget);
    expect(find.text('Primary admin'), findsOneWidget);
    expect(find.text('Majed (You)'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
  });

  testWidgets('a co-admin manages members but has no action on the primary admin', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(_app(HouseholdRolesCard(
      householdId: 'hh',
      loadRoster: (_) async => _roster(self: 'c', canManage: true, coAdmin: 'c'),
      promote: (hh, uid) async {
        calls.add('promote:$uid');
        return _roster(self: 'c', canManage: true, coAdmin: 'c');
      },
    )));
    await tester.pumpAndSettle();

    expect(_menuOf('p'), findsNothing);
    await tester.tap(_menuOf('m'));
    await tester.pumpAndSettle();
    expect(find.text('Make admin'), findsOneWidget);
    expect(find.text('Make primary admin'), findsNothing);
    await tester.tap(find.text('Make admin'));
    await tester.pumpAndSettle();
    expect(calls, ['promote:m']);
    expect(find.text('Roles updated'), findsOneWidget);
  });

  testWidgets('the primary admin transfers primary admin after confirming', (tester) async {
    final calls = <String>[];
    var changed = 0;
    await tester.pumpWidget(_app(HouseholdRolesCard(
      householdId: 'hh',
      loadRoster: (_) async => _roster(self: 'p', canManage: true, canTransfer: true),
      transferPrimary: (hh, uid) async {
        calls.add('transfer:$uid');
        return _roster(self: 'p', canManage: true);
      },
      onRolesChanged: () => changed++,
    )));
    await tester.pumpAndSettle();

    expect(_menuOf('p'), findsNothing, reason: 'no action on oneself as primary');
    await tester.tap(_menuOf('m'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make primary admin'));
    await tester.pumpAndSettle();
    expect(find.text('Transfer primary admin?'), findsOneWidget);
    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();
    expect(calls, ['transfer:m']);
    expect(changed, 1);
  });

  testWidgets('a server refusal is explained and nothing changes', (tester) async {
    await tester.pumpWidget(_app(HouseholdRolesCard(
      householdId: 'hh',
      loadRoster: (_) async => _roster(self: 'p', canManage: true, canTransfer: true, coAdmin: 'c'),
      revoke: (hh, uid) async => throw const HouseholdRolesApiException('forbidden', 'Forbidden', statusCode: 403),
    )));
    await tester.pumpAndSettle();

    await tester.tap(_menuOf('c'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove admin'));
    await tester.pumpAndSettle();
    expect(find.text("You don't have permission to change this role."), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
  });

  testWidgets('load failure offers a retry', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(_app(HouseholdRolesCard(
      householdId: 'hh',
      loadRoster: (_) async {
        attempts++;
        if (attempts == 1) throw Exception('offline');
        return _roster(self: 'm');
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('Could not load members.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Majed (You)'), findsOneWidget);
  });

  testWidgets('renders right-to-left and translated in Arabic and Urdu', (tester) async {
    for (final lang in ['ar', 'ur']) {
      await tester.pumpWidget(_app(
        HouseholdRolesCard(householdId: 'hh', loadRoster: (_) async => _roster(self: 'm')),
        lang: lang,
      ));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(HouseholdRolesCard));
      expect(Directionality.of(ctx), TextDirection.rtl);
      expect(find.text('Members & Admins'), findsNothing);
      expect(find.text('Primary admin'), findsNothing);
    }
    expect(find.text('مرکزی ایڈمن'), findsOneWidget);
  });

  group('HouseholdRolesApiClient', () {
    test('calls the role endpoints and maps refusals', () async {
      final base = _FakeBase();
      final client = HouseholdRolesApiClient(baseClient: base);

      base.response = {'household_id': 'hh', 'members': [{'user_id': 'p', 'role': 'admin', 'is_primary': true}]};
      final roster = await client.fetchMembers('hh');
      expect(base.calls.last, 'GET /households/hh/members');
      expect(roster.members.single.isPrimary, isTrue);

      await client.promoteToAdmin('hh', 'm');
      expect(base.calls.last, 'POST /households/hh/members/m/admin');
      await client.revokeAdmin('hh', 'c');
      expect(base.calls.last, 'DELETE /households/hh/members/c/admin');
      await client.transferPrimaryAdmin('hh', 'm');
      expect(base.calls.last, 'POST /households/hh/primary-admin {new_primary_user_id: m}');

      base.response = {'status': 'error', 'status_code': 409, 'message': 'A household needs at least one admin.'};
      expect(
        () => client.revokeAdmin('hh', 'p'),
        throwsA(isA<HouseholdRolesApiException>().having((e) => e.code, 'code', 'last_admin')),
      );
      base.response = {'status': 'error', 'status_code': 403, 'message': 'Forbidden'};
      expect(
        () => client.promoteToAdmin('hh', 'm'),
        throwsA(isA<HouseholdRolesApiException>().having((e) => e.code, 'code', 'forbidden')),
      );
    });
  });
}

class _FakeBase extends BaseApiClient {
  Map<String, dynamic> response = const {};
  final calls = <String>[];

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? queryParams, Duration timeout = const Duration(seconds: 15)}) async {
    calls.add('GET $path');
    return response;
  }

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body,
      {bool shouldSign = true, Duration timeout = const Duration(seconds: 20), Map<String, String>? extraHeaders}) async {
    calls.add(body.isEmpty ? 'POST $path' : 'POST $path $body');
    return response;
  }

  @override
  Future<Map<String, dynamic>> delete(String path, {Map<String, dynamic>? queryParams, Duration timeout = const Duration(seconds: 15)}) async {
    calls.add('DELETE $path');
    return response;
  }
}
