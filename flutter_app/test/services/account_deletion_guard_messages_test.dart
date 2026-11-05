// The grace-period guards refuse joins, claims, invites, promotions, primary
// transfers and Nafaqah provider changes, by database hint or by the API's 409.
// Each surface must say why in the user's language and never show the server text.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/household_membership.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/household_roles_api_client.dart';
import 'package:budget_tracker/services/household_join.dart';
import 'package:budget_tracker/widgets/settings/household_roles_card.dart';
import 'package:budget_tracker/widgets/settings/role_invite_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

const _hints = {
  'account_pending_deletion': 'del_err_account_pending',
  'household_pending_deletion': 'del_err_household_pending',
  'successor_pending_deletion': 'del_err_successor_pending',
};

const _rawText = 'raw database text';

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

HouseholdRoster _roster() => const HouseholdRoster(
      householdId: 'hh',
      primaryAdminUserId: 'p',
      canManageAdmins: true,
      canTransferPrimary: true,
      canSetNafaqahProvider: true,
      householdType: 'family',
      nafaqahProviderUserId: 'p',
      members: [
        HouseholdMember(userId: 'p', displayName: 'Ali', role: 'admin', isPrimary: true, isSelf: true, financialRole: 'provider', isNafaqahProvider: true),
        HouseholdMember(userId: 'm', displayName: 'Majed', role: 'member', financialRole: 'family_member'),
      ],
    );

void main() {
  group('joining and claiming', () {
    _hints.forEach((hint, key) {
      test('a database refusal with hint $hint', () {
        final error = PostgrestException(message: _rawText, code: '22023', hint: hint);
        expect(householdRefusalKey(error), key);
      });

      test('a join result carrying code $hint', () {
        expect(householdRefusalKey(HouseholdJoinException(_rawText, code: hint)), key);
      });
    });

    test('a claim refused with 409 stops the join with the guard code', () {
      expect(
        () => checkInviteClaimResponse({
          'status': 'error',
          'status_code': 409,
          'detail': {'code': 'account_pending_deletion', 'message': _rawText},
        }),
        throwsA(isA<HouseholdJoinException>().having((e) => householdRefusalKey(e), 'key', 'del_err_account_pending')),
      );
      expect(
        () => checkInviteClaimResponse({
          'status': 'error',
          'status_code': 409,
          'detail': {'code': 'household_pending_deletion', 'message': _rawText},
        }),
        throwsA(isA<HouseholdJoinException>().having((e) => householdRefusalKey(e), 'key', 'del_err_household_pending')),
      );
    });

    test('another 409 still falls through to the join that follows', () {
      expect(
        () => checkInviteClaimResponse({
          'status': 'error',
          'status_code': 409,
          'detail': {'code': 'something_else'},
        }),
        returnsNormally,
      );
    });

    test('the text the claim route re-raises alone is still recognised', () {
      expect(householdRefusalKey(const HouseholdJoinException('This account is scheduled for deletion.')), 'del_err_account_pending');
      expect(householdRefusalKey(const HouseholdJoinException('This household is scheduled for deletion.')), 'del_err_household_pending');
      expect(
        householdRefusalKey(const PostgrestException(message: 'This household is scheduled for deletion and takes no new members')),
        'del_err_household_pending',
      );
    });

    testWidgets('three languages, and never the server text', (tester) async {
      for (final lang in const ['en', 'ar', 'ur']) {
        final l = AppLocalizations(Locale(lang));
        late String shown;
        await tester.pumpWidget(_app(Builder(builder: (context) {
          shown = householdJoinErrorText(
            context,
            const PostgrestException(message: _rawText, code: '22023', hint: 'household_pending_deletion'),
          );
          return const SizedBox();
        }), lang: lang));
        await tester.pump();
        expect(shown, l.get('del_err_household_pending'));
        expect(shown, isNot(contains(_rawText)));
      }
    });

    test('other refusals are unchanged', () {
      expect(householdRefusalKey(const PostgrestException(message: 'Invite code has expired')), 'hh_invite_expired');
      expect(householdRefusalKey(const PostgrestException(message: 'Something else', hint: 'other_hint')), isNull);
    });
  });

  group('the API exceptions keep the guard code', () {
    Map<String, dynamic> conflict(String code) => {
          'status': 'error',
          'status_code': 409,
          'message': 'Server response error (409)',
          'detail': {'code': code, 'message': _rawText},
        };

    test('role calls', () {
      expect(HouseholdRolesApiException.fromResponse(conflict('account_pending_deletion')).code, 'account_pending_deletion');
      expect(HouseholdRolesApiException.fromResponse(conflict('successor_pending_deletion')).code, 'successor_pending_deletion');
    });

    test('the Nafaqah provider call', () {
      expect(NafaqahApiException.fromResponse(conflict('account_pending_deletion')).code, 'account_pending_deletion');
    });
  });

  group('the roles card', () {
    Future<void> pumpCard(
      WidgetTester tester, {
      String lang = 'en',
      required Object refusal,
    }) async {
      tester.view.physicalSize = const Size(600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        HouseholdRolesCard(
          householdId: 'hh',
          loadRoster: (_) async => _roster(),
          promote: (_, __) async => throw refusal,
          transferPrimary: (_, __) async => throw refusal,
          setNafaqahProvider: (_, __) async => throw refusal,
        ),
        lang: lang,
      ));
      await tester.pumpAndSettle();
    }

    Future<void> runAction(WidgetTester tester, String actionKey) async {
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('role-member-m')), matching: find.byIcon(Icons.more_vert_rounded)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppLocalizations(const Locale('en')).get(actionKey)).last);
      await tester.pumpAndSettle();
    }

    testWidgets('promoting a pending member says why', (tester) async {
      final l = AppLocalizations(const Locale('en'));
      await pumpCard(
        tester,
        refusal: const HouseholdRolesApiException('account_pending_deletion', _rawText, statusCode: 409, serverMessage: _rawText),
      );
      await runAction(tester, 'roles_make_admin');
      expect(find.text(l.get('del_err_account_pending')), findsOneWidget);
      expect(find.textContaining(_rawText), findsNothing);
    });

    testWidgets('handing primary admin to a pending member says why', (tester) async {
      final l = AppLocalizations(const Locale('en'));
      await pumpCard(
        tester,
        refusal: const HouseholdRolesApiException('successor_pending_deletion', _rawText, statusCode: 409, serverMessage: _rawText),
      );
      await runAction(tester, 'roles_make_primary');
      await tester.tap(find.text(l.get('roles_transfer_confirm')));
      await tester.pumpAndSettle();
      expect(find.text(l.get('del_err_successor_pending')), findsOneWidget);
      expect(find.textContaining(_rawText), findsNothing);
    });

    testWidgets('naming a pending member Nafaqah provider says why', (tester) async {
      final l = AppLocalizations(const Locale('en'));
      await pumpCard(
        tester,
        refusal: const NafaqahApiException('account_pending_deletion', _rawText, statusCode: 409),
      );
      final change = find.text(l.get('nafaqah_provider_change'));
      await tester.ensureVisible(change);
      await tester.tap(change);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('provider-option-m')));
      await tester.pumpAndSettle();
      expect(find.text(l.get('del_err_account_pending')), findsOneWidget);
      expect(find.textContaining(_rawText), findsNothing);
    });
  });

  group('the invite dialog', () {
    for (final lang in const ['en', 'ar', 'ur']) {
      testWidgets('$lang: a new invite on a marked household says why', (tester) async {
        final l = AppLocalizations(Locale(lang));
        await tester.pumpWidget(_app(
          RoleInviteDialog(
            householdId: 'hh',
            createInvite: (_, __, {targetMemberId}) async => throw const ApiRequestException(
              _rawText,
              statusCode: 409,
              code: 'household_pending_deletion',
            ),
          ),
          lang: lang,
        ));
        await tester.pump();
        final generate = find.byType(ElevatedButton).first;
        await tester.ensureVisible(generate);
        await tester.tap(generate);
        await tester.pumpAndSettle();
        expect(find.text(l.get('del_err_household_pending')), findsOneWidget);
        expect(find.textContaining(_rawText), findsNothing);
      });
    }
  });
}
