// The setup tutor shows each person the steps for their role, with the
// app's exact button names, fits a 320px screen at text scale 2.0 and uses
// the Velvet Burgundy theme.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/household_membership.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/widgets/onboarding/app_setup_tutor_dialog.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

HouseholdMember _m(String id, {bool self = false, bool admin = false, String? financialRole, bool provider = false}) =>
    HouseholdMember(
      userId: id,
      displayName: id,
      role: admin ? 'admin' : 'member',
      financialRole: financialRole,
      isSelf: self,
      isNafaqahProvider: provider,
    );

final _rosters = <String, HouseholdRoster>{
  'husband': HouseholdRoster(
    householdId: 'h1',
    householdType: kHouseholdTypeFamily,
    callerRole: 'admin',
    nafaqahProviderUserId: 'h',
    members: [_m('h', self: true, admin: true, provider: true), _m('w', financialRole: 'spouse')],
  ),
  'wife': HouseholdRoster(
    householdId: 'h1',
    householdType: kHouseholdTypeFamily,
    callerRole: 'member',
    nafaqahProviderUserId: 'h',
    members: [_m('h', admin: true, provider: true), _m('w', self: true, financialRole: 'spouse')],
  ),
  'roommate': HouseholdRoster(
    householdId: 'h1',
    householdType: kHouseholdTypeRoommates,
    callerRole: 'member',
    members: [_m('a', admin: true, financialRole: 'peer'), _m('b', self: true, financialRole: 'peer')],
  ),
  'husbandMember': HouseholdRoster(
    householdId: 'h1',
    householdType: kHouseholdTypeFamily,
    callerRole: 'member',
    nafaqahProviderUserId: 'h',
    members: [_m('a', admin: true), _m('h', self: true, provider: true), _m('w', financialRole: 'spouse')],
  ),
  'member': HouseholdRoster(
    householdId: 'h1',
    householdType: kHouseholdTypeFamily,
    callerRole: 'member',
    nafaqahProviderUserId: 'h',
    members: [_m('h', admin: true, provider: true), _m('s', self: true, financialRole: 'family_member')],
  ),
};

class _NoNavigator extends TutorNavigator {
  @override
  Future<void> open(BuildContext context, TutorAction action, String householdId, {int? paydayDay}) async {}
}

Widget _app({
  required String lang,
  bool dark = false,
  double scale = 1.0,
  HouseholdRoster? roster,
  bool firstTime = false,
  TutorRosterLoader? loadRoster,
  bool fallbackIsAdmin = false,
}) =>
    MaterialApp(
      locale: Locale(lang),
      theme: dark ? AppThemes.darkTheme : AppThemes.lightTheme,
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const ValueKey('open'),
              onPressed: () => firstTime
                  ? AppSetupTutorDialog.showIfFirstTime(context, householdId: 'h1', roster: roster, navigator: _NoNavigator())
                  : AppSetupTutorDialog.show(
                      context,
                      householdId: 'h1',
                      roster: roster,
                      fallbackIsAdmin: fallbackIsAdmin,
                      navigator: _NoNavigator(),
                      loadRoster: loadRoster ?? (_) async => throw StateError('offline'),
                    ),
              child: const SizedBox(width: 40, height: 40),
            ),
          ),
        ),
      ),
    );

Future<void> _open(WidgetTester tester, Widget app, {Size size = const Size(1080, 2400), double ratio = 2.0, bool settle = true}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('open')));
  if (!settle) return;
  await tester.pumpAndSettle();
  expect(find.byType(AppSetupTutorDialog), findsOneWidget);
}

double _luminance(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Every text shown on every page of the open tutor, walking forward.
Future<List<String>> _walk(WidgetTester tester, {void Function(int page)? onPage}) async {
  final texts = <String>[];
  for (var page = 0; page < 10; page++) {
    onPage?.call(page);
    for (final t in tester.widgetList<Text>(find.descendant(of: find.byType(PageView), matching: find.byType(Text)))) {
      texts.add(t.data ?? t.textSpan?.toPlainText() ?? '');
    }
    if (find.byKey(const ValueKey('tutor_action_finish')).evaluate().isNotEmpty) break;
    await tester.tap(find.byKey(const ValueKey('tutor_next')));
    await tester.pumpAndSettle();
  }
  return texts;
}

bool _anyContains(List<String> texts, String part) => texts.any((t) => t.contains(part));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('role steps', () {
    for (final lang in ['en', 'ar', 'ur']) {
      final l = AppLocalizations(Locale(lang));

      testWidgets('[$lang] a wife sees no admin action, the admin note and her own step', (tester) async {
        await _open(tester, _app(lang: lang, roster: _rosters['wife']));
        final actions = <String>{};
        final texts = await _walk(tester, onPage: (_) {
          for (final a in TutorAction.values) {
            if (find.byKey(ValueKey('tutor_action_${a.name}')).evaluate().isNotEmpty) actions.add(a.name);
          }
        });
        expect(actions, isNot(contains('payday')));
        expect(actions, isNot(contains('budgets')));
        expect(actions, isNot(contains('roles')));
        expect(actions, containsAll(['income', 'accounts']));
        expect(_anyContains(texts, l.get('tutor_admin_sets_note')), isTrue);
        expect(texts, contains(l.get('tutor_role_wife_title')));
        for (final key in ['nafaqah_q_title', 'nafaqah_w_opt_shared', 'nafaqah_w_opt_personal', 'reimburse_wife', 'nafaqah_mark_received']) {
          expect(_anyContains(texts, l.get(key)), isTrue, reason: '$lang wife step names $key');
        }
        expect(texts, isNot(contains(l.get('tutor_role_husband_title'))));
      });

      testWidgets('[$lang] the husband sees his step with the wife-ledger buttons', (tester) async {
        await _open(tester, _app(lang: lang, roster: _rosters['husband']));
        final actions = <String>{};
        final texts = await _walk(tester, onPage: (_) {
          for (final a in TutorAction.values) {
            if (find.byKey(ValueKey('tutor_action_${a.name}')).evaluate().isNotEmpty) actions.add(a.name);
          }
        });
        expect(actions, containsAll(['payday', 'income', 'accounts', 'budgets', 'roles']));
        expect(texts, contains(l.get('tutor_role_husband_title')));
        for (final key in ['wife_acc_add_title', 'accounts_balances', 'reimburse_wife', 'nafaqah_mark_received', 'req_approve', 'req_decline', 'rev_action']) {
          expect(_anyContains(texts, l.get(key)), isTrue, reason: '$lang husband step names $key');
        }
        expect(_anyContains(texts, l.get('tutor_admin_sets_note')), isFalse);
      });

      testWidgets('[$lang] a roommate sees the split and settle step', (tester) async {
        await _open(tester, _app(lang: lang, roster: _rosters['roommate']));
        final texts = await _walk(tester);
        expect(texts, contains(l.get('tutor_role_roommate_title')));
        for (final key in ['roommate_split_all', 'roommate_split_personal', 'simplify_debts', 'settle_now']) {
          expect(_anyContains(texts, l.get(key)), isTrue, reason: '$lang roommate step names $key');
        }
        expect(texts, isNot(contains(l.get('tutor_role_wife_title'))));
      });
    }

    testWidgets('a husband who is not an admin gets his step, the member steps and no admin action', (tester) async {
      final l = AppLocalizations(const Locale('en'));
      await _open(tester, _app(lang: 'en', roster: _rosters['husbandMember']));
      final actions = <String>{};
      final texts = await _walk(tester, onPage: (_) {
        for (final a in TutorAction.values) {
          if (find.byKey(ValueKey('tutor_action_${a.name}')).evaluate().isNotEmpty) actions.add(a.name);
        }
      });
      expect(texts, contains(l.get('tutor_role_husband_title')));
      expect(_anyContains(texts, l.get('reimburse_wife')), isTrue);
      expect(_anyContains(texts, l.get('tutor_admin_sets_note')), isTrue);
      expect(actions, {'income', 'accounts'});
    });

    testWidgets('the step badge counts the steps shown', (tester) async {
      await _open(tester, _app(lang: 'en', roster: _rosters['member']));
      expect(find.text('Step 1 of 5'), findsOneWidget);
    });

    testWidgets('without a roster the tutor falls back to the member steps', (tester) async {
      await _open(tester, _app(lang: 'en'));
      expect(find.text('Step 1 of 5'), findsOneWidget);
      expect(find.byKey(const ValueKey('tutor_action_payday')), findsNothing);
      expect(find.byKey(const ValueKey('tutor_action_income')), findsOneWidget);
    });
  });

  group('loading the member list', () {
    testWidgets('a small card with a spinner while it loads; it can be closed', (tester) async {
      final pending = Completer<HouseholdRoster>();
      await _open(tester, _app(lang: 'en', loadRoster: (_) => pending.future), settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(AppSetupTutorDialog), findsNothing);
      final card = find.ancestor(of: find.byType(CircularProgressIndicator), matching: find.byType(Container)).last;
      expect(tester.getSize(card).height, lessThan(260), reason: 'the loading card does not fill the dialog');

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      pending.complete(_rosters['wife']!);
    });

    testWidgets('once loaded, the steps for the role', (tester) async {
      final pending = Completer<HouseholdRoster>();
      await _open(tester, _app(lang: 'en', loadRoster: (_) => pending.future), settle: false);
      await tester.pump();
      pending.complete(_rosters['wife']!);
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 6'), findsOneWidget);
    });

    testWidgets('if loading fails, the cached admin flag decides', (tester) async {
      await _open(tester, _app(lang: 'en', fallbackIsAdmin: true, loadRoster: (_) async => throw StateError('offline')));
      expect(find.text('Step 1 of 5'), findsOneWidget);
      expect(find.byKey(const ValueKey('tutor_action_payday')), findsOneWidget);
    });
  });

  group('layout and theme', () {
    for (final viewer in _rosters.keys) {
      for (final lang in ['en', 'ar', 'ur']) {
        for (final dark in [false, true]) {
          testWidgets('$viewer, $lang, ${dark ? 'dark' : 'light'}: no overflow at 320x568 and text scale 2.0', (tester) async {
            await _open(
              tester,
              _app(lang: lang, dark: dark, scale: 2.0, roster: _rosters[viewer]),
              size: const Size(640, 1136),
            );
            expect(tester.takeException(), isNull);
            await _walk(tester, onPage: (page) {
              expect(tester.takeException(), isNull);
              // No text in the tutor is cut off: the step badge, the step
              // itself and the footer buttons (review R2-4).
              for (final p in tester.renderObjectList<RenderParagraph>(
                find.descendant(of: find.byType(AppSetupTutorDialog), matching: find.byType(RichText)),
              )) {
                expect(p.didExceedMaxLines, isFalse, reason: 'page $page: "${p.text.toPlainText()}" is cut off');
              }
            });
            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    for (final dark in [false, true]) {
      testWidgets('${dark ? 'dark' : 'light'}: burgundy buttons, no emerald fill', (tester) async {
        await _open(tester, _app(lang: 'en', dark: dark, roster: _rosters['husband']));
        final ctx = tester.element(find.byType(AppSetupTutorDialog));
        for (final key in ['tutor_next', 'tutor_action_payday']) {
          final button = tester.widget<ButtonStyleButton>(find.byKey(ValueKey(key)));
          expect(button.style?.backgroundColor?.resolve({}), ctx.primaryButtonBg, reason: key);
          expect(button.style?.foregroundColor?.resolve({}), ctx.primaryButtonFg, reason: key);
        }
        final fills = <Color>[];
        for (final box in tester.widgetList<Container>(find.descendant(of: find.byType(AppSetupTutorDialog), matching: find.byType(Container)))) {
          final d = box.decoration;
          if (d is BoxDecoration) {
            if (d.color != null) fills.add(d.color!);
            if (d.gradient != null) fills.addAll(d.gradient!.colors);
          }
        }
        expect(fills, isNot(contains(AppThemes.success)));

        // The hero icon keeps at least 4.5:1 against every colour of its badge.
        final hero = tester.widget<Container>(find.byKey(const ValueKey('tutor_hero')));
        final icon = tester.widget<Icon>(find.descendant(of: find.byKey(const ValueKey('tutor_hero')), matching: find.byType(Icon)));
        for (final c in (hero.decoration as BoxDecoration).gradient!.colors) {
          expect(_contrast(icon.color!, c), greaterThanOrEqualTo(4.5), reason: '$c');
        }
        for (final off in const [Color(0xFF1E3A8A), Color(0xFF3B82F6), Color(0xFF065F46), Color(0xFF581C87), Color(0xFF9333EA), Color(0xFF9A3412), Color(0xFFF97316)]) {
          expect(fills, isNot(contains(off)));
        }
      });
    }
  });

  group('copy', () {
    test('no tutor text implies a split between spouses, and titles carry no number', () {
      for (final lang in ['en', 'ar', 'ur']) {
        final l = AppLocalizations(Locale(lang));
        for (final key in [
          for (var i = 1; i <= 5; i++) ...['tutor_stage_${i}_title', 'tutor_stage_${i}_desc'],
          'tutor_stage_1_desc_member',
          'tutor_stage_3_desc_member',
          'tutor_admin_sets_note',
          for (final r in ['wife', 'husband', 'roommate']) ...['tutor_role_${r}_title', 'tutor_role_${r}_desc'],
        ]) {
          final v = l.get(key);
          expect(v, isNot(key), reason: '$lang $key missing');
          expect(v.contains('50/50') || v.contains('%'), isFalse, reason: '$lang $key');
          if (key.endsWith('_title')) expect(RegExp(r'^\s*[0-9٠-٩۰-۹]').hasMatch(v), isFalse, reason: '$lang $key');
        }
      }
    });

    test('Urdu says category budget, not a transliterated "envelope"; stage 3 says mid-cycle', () {
      final ur = AppLocalizations(const Locale('ur'));
      final ar = AppLocalizations(const Locale('ar'));
      for (final key in ['tutor_stage_3_title', 'tutor_stage_3_desc', 'tutor_stage_1_desc', 'tutor_stage_3_btn']) {
        expect(ur.get(key), isNot(contains('اینولپ')), reason: key);
      }
      expect(ar.get('tutor_stage_3_title'), isNot(contains('الشهر')));
      expect(ar.get('tutor_stage_3_title'), contains('الدورة'));
      expect(ur.get('tutor_stage_3_title'), isNot(contains('مہینے')));
      expect(ur.get('tutor_stage_3_title'), contains('سائیکل'));
    });

    test('step 1 speaks of income in every language, and step 5 keeps its chat example', () {
      expect(AppLocalizations(const Locale('en')).get('tutor_stage_1_desc'), contains('{income}'));
      expect(AppLocalizations(const Locale('ar')).get('tutor_stage_1_desc'), contains('{income}'));
      expect(AppLocalizations(const Locale('ur')).get('tutor_stage_1_desc'), contains('{income}'));
      expect(AppLocalizations(const Locale('ur')).get('tutor_stage_5_desc'), contains('91'));
    });
  });

  group('first run (owner decision D1)', () {
    testWidgets('someone who saw the old tutor sees the new one once, then not again', (tester) async {
      SharedPreferences.setMockInitialValues({'has_seen_setup_tutor_v2': true});
      await _open(tester, _app(lang: 'en', roster: _rosters['member'], firstTime: true));
      await tester.tap(find.byKey(const ValueKey('tutor_skip')));
      await tester.pumpAndSettle();
      expect(find.byType(AppSetupTutorDialog), findsNothing);

      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      expect(find.byType(AppSetupTutorDialog), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(AppSetupTutorDialog.prefKey), isTrue);
      expect(AppSetupTutorDialog.prefKey, isNot('has_seen_setup_tutor_v2'));
      expect(prefs.getBool('has_seen_setup_tutor_v2'), isTrue, reason: 'the old flag is left as it was');
    });
  });
}
