// Theme pins for the widgets shown on (or opened from) the Settings page.
// Contrast is computed from the colours the widgets really use, composited over
// the surface they sit on, against WCAG AA (4.5:1 for text, 3:1 for graphics).
import 'dart:async';
import 'dart:io';

import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/screens/settings/help_support_screen.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/widgets/dashboard/family_reimbursement_card.dart';
import 'package:budget_tracker/widgets/dashboard/multi_roommate_settlement_card.dart';
import 'package:budget_tracker/widgets/settings/add_household_member_sheet.dart';
import 'package:budget_tracker/widgets/settings/household_management_card.dart';
import 'package:budget_tracker/widgets/settings/household_roles_card.dart';
import 'package:budget_tracker/widgets/settings/household_switch_sheet.dart';
import 'package:budget_tracker/widgets/settings/income_settings_card.dart';
import 'package:budget_tracker/widgets/settings/payday_settings_card.dart';
import 'package:budget_tracker/widgets/settings/role_invite_dialog.dart';
import 'package:budget_tracker/widgets/settings/rollover_settings_card.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The real scaler reaches routes (sheets, dialogs) through MaterialApp.builder.
Widget _app(Widget child, {String lang = 'en', bool dark = false, double scale = 1.0, bool scaffold = true}) => MaterialApp(
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
      home: scaffold ? Scaffold(body: SingleChildScrollView(child: child)) : child,
    );

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

Color? _fg(ButtonStyleButton b, [Set<WidgetState> s = const {}]) => b.style?.foregroundColor?.resolve(s);
Color? _bg(ButtonStyleButton b, [Set<WidgetState> s = const {}]) => b.style?.backgroundColor?.resolve(s);

const _family = NafaqahSummary(
  mode: 'family_nafaqah',
  callerRole: 'husband',
  callerUserId: 'u-h',
  canRecordReimbursement: true,
  wives: [NafaqahWife(id: 'u-w', reimbursement: ReimbursementBalance(grossAdvanced: 350, outstanding: 350))],
);

const _roommates = SettlementV2Summary(
  mode: 'multi_roommate',
  simplifiedDebts: [SimplifiedDebt(fromId: 'me', toId: 'u2', fromName: 'Me', toName: 'Faisal', amount: 120)],
  pairwiseDebts: [PairwiseDebt(fromId: 'me', toId: 'u2', fromName: 'Me', toName: 'Faisal', amount: 120)],
);

HouseholdRoster _roster() => const HouseholdRoster(
      householdId: 'hh',
      householdType: 'family',
      canChangeHouseholdType: true,
      canSetNafaqahProvider: true,
      callerIsPrimary: true,
      callerRole: 'admin',
      members: [
        HouseholdMember(userId: 'me', displayName: 'Me', role: 'admin', isPrimary: true, isSelf: true),
        HouseholdMember(userId: 'w', displayName: 'Noura', financialRole: 'spouse'),
      ],
    );

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    Future<BuildContext> pump(WidgetTester tester, Widget child, {String lang = 'en', double scale = 1.0}) async {
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(child, lang: lang, dark: dark, scale: scale));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      return tester.element(find.byWidget(child));
    }

    group('family reimbursement card ($mode)', () {
      testWidgets('the reimburse button text reads on its real background', (tester) async {
        await pump(tester, const FamilyReimbursementCard(householdId: 'hh', summary: _family));
        final btn = tester.widget<ElevatedButton>(find.ancestor(of: find.text('Reimburse Wife'), matching: find.byWidgetPredicate((w) => w is ElevatedButton)));
        expect(_contrast(_fg(btn)!, _bg(btn)!), greaterThanOrEqualTo(4.5));
      });

      testWidgets('history uses the accent, not the invisible default primary', (tester) async {
        final ctx = await pump(tester, const FamilyReimbursementCard(householdId: 'hh', summary: _family));
        final btn = tester.widget<TextButton>(find.ancestor(of: find.text('History'), matching: find.byWidgetPredicate((w) => w is TextButton)));
        expect(_contrast(_fg(btn)!, ctx.cardBg), greaterThanOrEqualTo(4.5));
      });

      testWidgets('the loading spinner is visible on the card', (tester) async {
        final never = Completer<NafaqahSummary>();
        final ctx = await pump(tester, FamilyReimbursementCard(householdId: 'hh', loadSummary: (_) => never.future));
        final spinner = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
        expect(_contrast(spinner.color!, ctx.cardBg), greaterThanOrEqualTo(3));
      });

      testWidgets('the repayment sheet: chips, copy button and saving state all read', (tester) async {
        final pending = Completer<double>();
        await pump(
          tester,
          FamilyReimbursementCard(
            householdId: 'hh',
            summary: _family,
            recordReimbursement: ({required double amount, required String paymentMethod, required String wifeUserId}) => pending.future,
          ),
        );
        await tester.tap(find.text('Reimburse Wife'));
        await tester.pumpAndSettle();
        final ctx = tester.element(find.text('Reimburse Wife'));

        final chip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'STC Pay'));
        final chipFill = Color.alphaBlend(chip.selectedColor!, ctx.cardBg);
        expect(_contrast((chip.avatar as Icon).color!, chipFill), greaterThanOrEqualTo(3));

        final copy = tester.widget<OutlinedButton>(find.ancestor(of: find.text(_copyNote), matching: find.byWidgetPredicate((w) => w is OutlinedButton)));
        expect(_contrast(_fg(copy)!, ctx.cardBg), greaterThanOrEqualTo(4.5));

        final recordFinder = find.ancestor(of: find.text(_recordPayment), matching: find.byWidgetPredicate((w) => w is ElevatedButton));
        await tester.ensureVisible(recordFinder);
        await tester.pump();
        await tester.tap(find.text(_recordPayment));
        await tester.pump(const Duration(milliseconds: 100));
        final record = tester.widget<ElevatedButton>(recordFinder);
        expect(record.onPressed, isNull);
        final spinner = tester.widget<CircularProgressIndicator>(
          find.descendant(of: recordFinder, matching: find.byType(CircularProgressIndicator)),
        );
        expect(
          _contrast(spinner.color!, _bg(record, {WidgetState.disabled}) ?? Colors.transparent),
          greaterThanOrEqualTo(3),
          reason: 'the saving spinner must not vanish into the disabled fill',
        );
      });

      testWidgets('an overpaid banner title reads on its wash', (tester) async {
        final ctx = await pump(
          tester,
          const FamilyReimbursementCard(
            householdId: 'hh',
            summary: NafaqahSummary(
              mode: 'family_nafaqah',
              callerRole: 'husband',
              callerUserId: 'u-h',
              wives: [NafaqahWife(id: 'u-w', reimbursement: ReimbursementBalance(grossAdvanced: 100, reimbursed: 200, overpaid: 100))],
            ),
          ),
        );
        final banner = find.byKey(const ValueKey('nafaqah_overpaid_u-w'));
        expect(banner, findsOneWidget);
        final title = tester.widgetList<Text>(find.descendant(of: banner, matching: find.byType(Text))).first;
        final box = tester.widget<Container>(find.descendant(of: banner, matching: find.byType(Container)).first);
        final wash = (box.decoration as BoxDecoration).color!;
        // The card behind it: the lighter gradient stop in dark, white in light.
        final card = ctx.isDark ? VelvetBurgundyColors.surfaceDarkGradientStart : VelvetBurgundyColors.surfaceLight;
        expect(_contrast(title.style!.color!, Color.alphaBlend(wash, card)), greaterThanOrEqualTo(4.5));
      });
    });

    group('roommate settlement card ($mode)', () {
      testWidgets('buttons use the primary pair; the sheet copes with long labels', (tester) async {
        final ctx = await pump(tester, const MultiRoommateSettlementCard(householdId: 'hh', summary: _roommates, currentUserId: 'me'));
        final settle = tester.widget<ElevatedButton>(find.ancestor(of: find.text('Settle'), matching: find.byWidgetPredicate((w) => w is ElevatedButton)));
        expect(_bg(settle), ctx.primaryButtonBg);
        expect(_fg(settle), ctx.primaryButtonFg);

        await tester.tap(find.text('Settle'));
        await tester.pumpAndSettle();
        final chip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'STC Pay'));
        expect(_contrast((chip.avatar as Icon).color!, Color.alphaBlend(chip.selectedColor!, ctx.cardBg)), greaterThanOrEqualTo(3));
        final copy = tester.widget<OutlinedButton>(find.ancestor(of: find.text(_copyNote), matching: find.byWidgetPredicate((w) => w is OutlinedButton)));
        expect(_contrast(_fg(copy)!, ctx.cardBg), greaterThanOrEqualTo(4.5));
      });

      for (final lang in ['en', 'ar', 'ur']) {
        testWidgets('the settle sheet fits in $lang at x2.0', (tester) async {
          await pump(tester, const MultiRoommateSettlementCard(householdId: 'hh', summary: _roommates, currentUserId: 'me'), lang: lang, scale: 2.0);
          final btn = find.byWidgetPredicate((w) => w is ElevatedButton);
          await tester.tap(btn.first);
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
        });
      }
    });

    group('household roles card ($mode)', () {
      testWidgets('text buttons and spinners do not fall back to the default primary', (tester) async {
        final ctx = await pump(tester, HouseholdRolesCard(householdId: 'hh', loadRoster: (_) async => _roster()));
        await tester.pump(const Duration(milliseconds: 50));
        final change = tester.widget<TextButton>(find.byKey(const ValueKey('household_type_change')));
        expect(_contrast(_fg(change)!, ctx.cardBg), greaterThanOrEqualTo(4.5));
        final choose = tester.widget<TextButton>(find.ancestor(of: find.text('Choose provider'), matching: find.byWidgetPredicate((w) => w is TextButton)));
        expect(_contrast(_fg(choose)!, ctx.cardBg), greaterThanOrEqualTo(4.5));
      });

      testWidgets('the loading spinner is visible', (tester) async {
        final never = Completer<HouseholdRoster>();
        final ctx = await pump(tester, HouseholdRolesCard(householdId: 'hh', loadRoster: (_) => never.future));
        final spinner = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
        expect(_contrast(spinner.color!, ctx.cardBg), greaterThanOrEqualTo(3));
      });

      testWidgets('retry after a failed load is visible', (tester) async {
        final ctx = await pump(tester, HouseholdRolesCard(householdId: 'hh', loadRoster: (_) async => throw Exception('x')));
        await tester.pump(const Duration(milliseconds: 50));
        final retry = tester.widget<TextButton>(find.byWidgetPredicate((w) => w is TextButton));
        expect(_contrast(_fg(retry)!, ctx.cardBg), greaterThanOrEqualTo(4.5));
      });
    });

    group('household management card ($mode)', () {
      Widget card({String role = 'member'}) => HouseholdManagementCard(
            householdName: 'Home',
            householdId: 'hh',
            inviteCode: 'ABCD1234',
            userRole: role,
            members: const [],
            onCopyInviteCode: () {},
            onShareInvite: () {},
            onLeaveHousehold: () {},
            onSwitchHousehold: () {},
            onCreateHousehold: () {},
          );

      testWidgets('the member badge text passes on its tinted fill', (tester) async {
        final ctx = await pump(tester, card());
        final badge = tester.widgetList<Text>(find.text('Member')).first;
        final fill = Color.alphaBlend(ctx.infoSubtleBg, ctx.isDark ? VelvetBurgundyColors.surfaceDarkGradientStart : ctx.cardBg);
        expect(_contrast(badge.style!.color!, fill), greaterThanOrEqualTo(4.5));
      });

      testWidgets('share and new household use the primary pair', (tester) async {
        final ctx = await pump(tester, card());
        for (final key in ['Share invite', 'New Household']) {
          final b = tester.widget<ElevatedButton>(find.ancestor(of: find.text(key), matching: find.byWidgetPredicate((w) => w is ElevatedButton)));
          expect(_fg(b), ctx.primaryButtonFg, reason: key);
        }
      });
    });

    group('add member sheet ($mode)', () {
      testWidgets('hints read on the input fill; submit uses the primary pair', (tester) async {
        final ctx = await pump(tester, const AddHouseholdMemberSheet());
        for (final key in ['add_member_name_input', 'add_member_allowance_input']) {
          final field = tester.widget<TextField>(find.byKey(Key(key)));
          expect(_contrast(field.decoration!.hintStyle!.color!, ctx.inputBg), greaterThanOrEqualTo(4.5), reason: key);
        }
        final submit = tester.widget<ElevatedButton>(find.byKey(const Key('add_member_submit_button')));
        expect(_fg(submit), ctx.primaryButtonFg);
        expect(_bg(submit, {WidgetState.disabled}), ctx.primaryButtonBg);
      });

      testWidgets('the inline error reads on the danger wash', (tester) async {
        final ctx = await pump(tester, const AddHouseholdMemberSheet());
        final submit = find.byKey(const Key('add_member_submit_button'));
        await tester.ensureVisible(submit);
        await tester.pump();
        await tester.tap(submit);
        await tester.pump();
        final error = tester.widget<Text>(find.text('Please enter a member name'));
        expect(_contrast(error.style!.color!, Color.alphaBlend(ctx.alertDangerBg, ctx.cardBg)), greaterThanOrEqualTo(4.5));
      });
    });

    group('saving states stay visible ($mode)', () {
      testWidgets('payday', (tester) async {
        final pending = Completer<bool>();
        final ctx = await pump(tester, PaydaySettingsCard(onSavePayday: (_) => pending.future));
        final finder = find.ancestor(of: find.byIcon(Icons.check_rounded), matching: find.byWidgetPredicate((w) => w is ElevatedButton));
        await tester.ensureVisible(finder);
        await tester.pump();
        await tester.tap(finder);
        await tester.pump();
        final btn = tester.widget<ElevatedButton>(find.byWidgetPredicate((w) => w is ElevatedButton));
        final spinner = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
        expect(_bg(btn, {WidgetState.disabled}), ctx.primaryButtonBg);
        expect(_fg(btn, {WidgetState.disabled}), ctx.primaryButtonFg);
        expect(spinner.color, ctx.primaryButtonFg);
        expect(_contrast(spinner.color!, ctx.primaryButtonBg), greaterThanOrEqualTo(3));
        pending.complete(false);
        await tester.pump(const Duration(seconds: 5));
      });

      testWidgets('income', (tester) async {
        final pending = Completer<bool>();
        final ctx = await pump(tester, IncomeSettingsCard(initialIncome: 100, onSaveIncome: (_) => pending.future));
        await tester.tap(find.byIcon(Icons.edit_rounded));
        await tester.pump();
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(_contrast(field.decoration!.floatingLabelStyle!.color!, ctx.cardBg), greaterThanOrEqualTo(4.5));
        await tester.tap(find.text('Save Income'));
        await tester.pump();
        final btn = tester.widget<ElevatedButton>(find.byWidgetPredicate((w) => w is ElevatedButton));
        final spinner = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
        expect(_bg(btn, {WidgetState.disabled}), ctx.primaryButtonBg);
        expect(spinner.color, ctx.primaryButtonFg);
        pending.complete(false);
        await tester.pump(const Duration(seconds: 5));
      });

      testWidgets('rollover: button and spinner share one foreground for either fill', (tester) async {
        final pending = Completer<bool>();
        final ctx = await pump(tester, RolloverSettingsCard(onSaveRule: (_) => pending.future));
        await tester.ensureVisible(find.text('Save Rollover Policy'));
        await tester.pump();
        await tester.tap(find.text('Save Rollover Policy'));
        await tester.pump();
        var btn = tester.widget<ElevatedButton>(find.byWidgetPredicate((w) => w is ElevatedButton));
        var spinner = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
        // Nothing changed yet: an outlined card button, so the spinner uses text ink.
        expect(_bg(btn, {WidgetState.disabled}), ctx.cardBg);
        expect(_contrast(spinner.color!, ctx.cardBg), greaterThanOrEqualTo(3));
        pending.complete(false);
        await tester.pump(const Duration(seconds: 5));

        await tester.tap(find.text(_rolloverFresh));
        await tester.pump(const Duration(milliseconds: 300));
        btn = tester.widget<ElevatedButton>(find.byWidgetPredicate((w) => w is ElevatedButton));
        expect(_fg(btn), ctx.primaryButtonFg);
      });
    });

    testWidgets('role invite dialog ($mode): buttons use tokens in both steps', (tester) async {
      final ctx = await pump(
        tester,
        RoleInviteDialog(
          householdId: 'hh',
          createInvite: (hid, role, {targetMemberId}) async => const HouseholdInvite(id: 'i', householdId: 'hh', inviteCode: 'ROLE1234', role: 'spouse'),
        ),
      );
      final generate = tester.widget<ElevatedButton>(find.byKey(const ValueKey('rid_generate')));
      expect(_fg(generate), ctx.primaryButtonFg);
      expect(_bg(generate, {WidgetState.disabled}), ctx.primaryButtonBg);

      await tester.tap(find.byKey(const ValueKey('rid_generate')));
      await tester.pump(const Duration(milliseconds: 300));
      final share = tester.widget<ElevatedButton>(find.byKey(const ValueKey('rid_share_invite')));
      expect(_fg(share), ctx.primaryButtonFg);
      final copy = tester.widget<OutlinedButton>(find.ancestor(of: find.text('Copy Code'), matching: find.byWidgetPredicate((w) => w is OutlinedButton)));
      expect(_contrast(_fg(copy)!, ctx.cardBg), greaterThanOrEqualTo(4.5));
    });

    testWidgets('household switch sheet ($mode): join button has a real foreground', (tester) async {
      final ctx = await pump(
        tester,
        SizedBox(
          height: 600,
          child: HouseholdSwitchSheetContent(
            memberships: const [],
            currentHouseholdId: 'hh',
            onSwitch: (_) {},
            onJoinNew: () {},
            onCreateNew: () {},
          ),
        ),
      );
      final join = tester.widget<OutlinedButton>(find.byWidgetPredicate((w) => w is OutlinedButton));
      expect(_contrast(_fg(join)!, ctx.cardBg), greaterThanOrEqualTo(4.5));
    });

    group('help and support ($mode)', () {
      Widget help() => const HelpSupportScreen();

      Future<void> pumpHelp(WidgetTester tester, {String lang = 'en', double scale = 1.0}) async {
        tester.view.physicalSize = const Size(390, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_app(help(), lang: lang, dark: dark, scale: scale, scaffold: false));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      testWidgets('FAQ chevrons use the accent when expanded', (tester) async {
        await pumpHelp(tester);
        final ctx = tester.element(find.byType(HelpSupportScreen));
        final tile = tester.widget<ExpansionTile>(find.byType(ExpansionTile).first);
        expect(_contrast(tile.iconColor!, ctx.cardBg), greaterThanOrEqualTo(3));
        expect(_contrast(tile.collapsedIconColor!, ctx.cardBg), greaterThanOrEqualTo(3));
      });

      for (final lang in ['en', 'ar', 'ur']) {
        testWidgets('both tabs fit in $lang at x2.0', (tester) async {
          await pumpHelp(tester, lang: lang, scale: 2.0);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byType(Tab).last);
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
        });
      }
    });
  }

  group('source guards for the settings scope', () {
    const files = [
      'lib/screens/settings/settings_screen.dart',
      'lib/screens/settings/help_support_screen.dart',
      'lib/widgets/settings/add_household_member_sheet.dart',
      'lib/widgets/settings/household_management_card.dart',
      'lib/widgets/settings/household_roles_card.dart',
      'lib/widgets/settings/household_switch_sheet.dart',
      'lib/widgets/settings/household_type_chooser.dart',
      'lib/widgets/settings/income_settings_card.dart',
      'lib/widgets/settings/payday_settings_card.dart',
      'lib/widgets/settings/reminder_settings_card.dart',
      'lib/widgets/settings/role_invite_dialog.dart',
      'lib/widgets/settings/rollover_settings_card.dart',
      'lib/widgets/settings/settings_section.dart',
      'lib/widgets/dashboard/family_reimbursement_card.dart',
      'lib/widgets/dashboard/multi_roommate_settlement_card.dart',
      'lib/widgets/dashboard/household_setup_card.dart',
      'lib/services/csv_export_service.dart',
      'lib/widgets/app_snackbar.dart',
    ];

    test('no off-palette colours, and no white forced onto a themed fill', () {
      final offenders = <String>[];
      final banned = RegExp(
        r'Colors\.(orange|redAccent|red|green|blue|amber)\b|foregroundColor: Colors\.(white|black)|color: Colors\.white\b'
        r'|Color\(0x|isDark \? Colors\.',
      );
      // Justified exceptions, as `path: exact trimmed line`.
      const allowed = {
        // TH-05 (whole_app_theme_sweep_test) pins black / white on this checkmark.
        'lib/widgets/settings/rollover_settings_card.dart': 'color: context.isDark ? Colors.black : Colors.white,',
      };
      for (final path in files) {
        final lines = File(path).readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (!banned.hasMatch(lines[i]) || allowed[path] == lines[i].trim()) continue;
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('accent and border pairs are spelled as tokens, not ternaries', () {
      final offenders = <String>[];
      final ternary = RegExp(
        r'isDark\s*\?\s*VelvetBurgundyColors\.(roseGoldGlow|roseBorderDark|primaryDark)\s*:\s*VelvetBurgundyColors\.(primaryLight|roseBorderLight)',
      );
      for (final path in files) {
        final text = File(path).readAsStringSync();
        if (ternary.hasMatch(text)) offenders.add(path);
      }
      expect(offenders, isEmpty);
    });
  });
}

const _copyNote = 'Copy STC Pay Note';
const _recordPayment = 'Record Settlement Payment';
const _rolloverFresh = 'Fresh Start (Zero Carryover)';
