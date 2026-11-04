// Pins found by review of the Settings work: surfaces that had no test, Urdu at
// double text size, and word integrity under real font metrics.
import 'dart:async';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/household_setup.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/screens/settings/help_support_screen.dart';
import 'package:budget_tracker/services/api/support_api_client.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/widgets/dashboard/family_reimbursement_card.dart';
import 'package:budget_tracker/widgets/dashboard/household_setup_card.dart';
import 'package:budget_tracker/widgets/dashboard/multi_roommate_settlement_card.dart';
import 'package:budget_tracker/widgets/settings/add_household_member_sheet.dart';
import 'package:budget_tracker/widgets/settings/household_roles_card.dart';
import 'package:budget_tracker/widgets/settings/household_type_chooser.dart';
import 'package:budget_tracker/widgets/settings/role_invite_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/settings_test_app.dart';

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

const _rosterNoProvider = HouseholdRoster(
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

const _rosterWithProvider = HouseholdRoster(
  householdId: 'hh',
  householdType: 'family',
  canChangeHouseholdType: true,
  canSetNafaqahProvider: true,
  callerIsPrimary: true,
  callerRole: 'admin',
  nafaqahProviderUserId: 'me',
  members: [
    HouseholdMember(userId: 'me', displayName: 'Me', role: 'admin', isPrimary: true, isSelf: true, isNafaqahProvider: true),
    HouseholdMember(userId: 'w', displayName: 'Noura', financialRole: 'spouse'),
  ],
);

const _setupData = HouseholdSetupData(
  paydayDay: 27,
  paydayConfirmed: false,
  monthlyIncome: 0,
  roster: _rosterNoProvider,
);

class _PendingSupport extends SupportApiClient {
  final Completer<SupportInquiryResult> pending = Completer();
  @override
  Future<SupportInquiryResult> sendSupportInquiry({required String message, String? locale, String? householdId}) => pending.future;
  @override
  Future<Map<String, dynamic>> postSupportChat({required String message, String? householdId, String? userId, List<Map<String, String>>? history, String? language}) async =>
      throw Exception('offline');
}

Finder _button<T extends Widget>(Finder label) => find.ancestor(of: label, matching: find.byWidgetPredicate((w) => w is T));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<BuildContext> pump(WidgetTester tester, Widget child, {String lang = 'en', bool dark = false, double scale = 1.0, double width = 390}) async {
    useViewport(tester, width: width);
    await tester.pumpWidget(settingsTestApp(child, lang: lang, dark: dark, scale: scale));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return tester.element(find.byWidget(child));
  }

  group('item 6: Urdu at double size, 390px', () {
    testWidgets('role invite dialog, opened as a real dialog', (tester) async {
      useViewport(tester);
      await tester.pumpWidget(settingsTestApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(context: context, builder: (_) => const RoleInviteDialog(householdId: 'hh')),
            child: const Text('open'),
          ),
        ),
        lang: 'ur',
        scale: 2.0,
      ));
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('rid_generate')), findsOneWidget);
    });

    testWidgets('setup checklist with the payday confirm button', (tester) async {
      await pump(
        tester,
        HouseholdSetupCard(householdId: 'hh', data: _setupData, hasBudgets: false, onChanged: () {}),
        lang: 'ur',
        scale: 2.0,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('setup_confirm_payday')), findsOneWidget);
    });
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    group('item 9 holes ($mode)', () {
      testWidgets('starter sheet: focused labels and the saving state', (tester) async {
        final pending = Completer<bool>();
        final ctx = await pump(
          tester,
          StarterBudgetSheet(monthlyIncome: 1000, createBudget: (_, __, ___) => pending.future, onCreated: () {}),
          dark: dark,
        );
        final field = tester.widget<TextField>(find.byType(TextField).first);
        expect(field.decoration!.floatingLabelStyle!.color, ctx.accentText);

        final create = _button<ElevatedButton>(find.text(AppLocalizations(const Locale('en')).get('starter_budgets_create')));
        await tester.ensureVisible(create);
        await tester.pump();
        await tester.tap(create);
        await tester.pump();
        final btn = tester.widget<ElevatedButton>(find.byWidgetPredicate((w) => w is ElevatedButton));
        expect(btn.onPressed, isNull);
        expect(btn.style!.backgroundColor!.resolve({WidgetState.disabled}), ctx.primaryButtonBg);
        expect(btn.style!.foregroundColor!.resolve({WidgetState.disabled}), ctx.primaryButtonFg);
        final spinner = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
        expect(spinner.color, ctx.primaryButtonFg);
        pending.complete(true);
        await tester.pump();
      });

      testWidgets('roles card: the missing-provider title uses text ink and reads', (tester) async {
        final ctx = await pump(tester, HouseholdRolesCard(householdId: 'hh', loadRoster: (_) async => _rosterNoProvider), dark: dark);
        await tester.pump(const Duration(milliseconds: 50));
        final l = AppLocalizations(const Locale('en'));
        final title = tester.widget<Text>(find.text(l.get('nafaqah_provider_missing_title')));
        expect(title.style!.color, ctx.textPrimary);
        final box = tester.widget<Container>(find.byKey(const ValueKey('roles_needs_provider')));
        final wash = Color.alphaBlend((box.decoration! as BoxDecoration).color!, surfaceCardBg(ctx));
        expect(contrast(title.style!.color!, wash), greaterThanOrEqualTo(4.5));
      });

      testWidgets('family sheet: focused label, selected chip label and checkmark', (tester) async {
        await pump(tester, const FamilyReimbursementCard(householdId: 'hh', summary: _family), dark: dark);
        await tester.tap(find.text('Reimburse Wife'));
        await tester.pumpAndSettle();
        final ctx = tester.element(find.text('Reimburse Wife'));

        final field = tester.widget<TextField>(find.byKey(const ValueKey('reimburse_amount_field')));
        expect(field.decoration!.floatingLabelStyle!.color, ctx.accentText);

        final selected = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'STC Pay'));
        expect(selected.labelStyle!.color, ctx.accentText);
        expect(selected.checkmarkColor, ctx.accentText);
        final other = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Cash'));
        expect(other.labelStyle!.color, ctx.textPrimary);
      });

      testWidgets('roommate sheet: focused label, selected chip label and checkmark', (tester) async {
        await pump(tester, const MultiRoommateSettlementCard(householdId: 'hh', summary: _roommates, currentUserId: 'me'), dark: dark);
        await tester.tap(find.text('Settle'));
        await tester.pumpAndSettle();
        final ctx = tester.element(find.text('Settle'));

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.decoration!.floatingLabelStyle!.color, ctx.accentText);

        final selected = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'STC Pay'));
        expect(selected.labelStyle!.color, ctx.accentText);
        expect(selected.checkmarkColor, ctx.accentText);
        final other = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Cash'));
        expect(other.labelStyle!.color, ctx.textPrimary);
      });

      group('help', () {
        late _PendingSupport support;
        late ApiService original;

        setUp(() {
          support = _PendingSupport();
          original = ApiService.instance;
          ApiService.instance = ApiService(support: support);
        });
        tearDown(() {
          if (!support.pending.isCompleted) support.pending.complete(const SupportInquiryResult(SupportInquiryOutcome.network));
          ApiService.instance = original;
        });

        Future<void> pumpHelp(WidgetTester tester, {String lang = 'en', double scale = 1.0}) async {
          useViewport(tester, height: 3000);
          await tester.pumpWidget(settingsTestApp(HelpSupportScreen(supportClient: support), lang: lang, dark: dark, scale: scale, scaffold: false));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }

        testWidgets('inquiry dialog: hint reads; the sending state keeps its fill', (tester) async {
          await pumpHelp(tester);
          final send = find.text('Send to Developer');
          await tester.tap(send.first);
          await tester.pumpAndSettle();
          final ctx = tester.element(find.byType(AlertDialog));

          final field = tester.widget<TextField>(find.byKey(const ValueKey('support-inquiry-message')));
          expect(contrast(field.decoration!.hintStyle!.color!, ctx.subtleCardBg), greaterThanOrEqualTo(4.5));

          await tester.enterText(find.byKey(const ValueKey('support-inquiry-message')), 'Hello');
          await tester.tap(find.byKey(const ValueKey('support-inquiry-send')));
          await tester.pump();
          final btn = tester.widget<ElevatedButton>(find.byKey(const ValueKey('support-inquiry-send')));
          expect(btn.onPressed, isNull);
          expect(btn.style!.backgroundColor!.resolve({WidgetState.disabled}), ctx.primaryButtonBg);
          expect(btn.style!.foregroundColor!.resolve({WidgetState.disabled}), ctx.primaryButtonFg);
          support.pending.complete(const SupportInquiryResult(SupportInquiryOutcome.network));
          await tester.pump();
        });

        for (final lang in ['en', 'ar', 'ur']) {
          testWidgets('escalation card renders and fits in $lang at x2.0', (tester) async {
            final l = AppLocalizations(Locale(lang));
            await pumpHelp(tester, lang: lang, scale: 2.0);
            await tester.tap(find.byType(Tab).last);
            await tester.pumpAndSettle();
            tester.widget<ActionChip>(find.byType(ActionChip).first).onPressed!();
            await settleFrames(tester);
            expect(tester.takeException(), isNull);
            // In Urdu the card's title and its button happen to read the same.
            expect(find.text(l.get('support_escalate')), findsWidgets);
            final ctx = tester.element(find.byType(HelpSupportScreen));
            final btn = tester.widget<ElevatedButton>(_button<ElevatedButton>(find.text(l.get('support_inquiry_send'))));
            expect(btn.style!.foregroundColor!.resolve({}), ctx.primaryButtonFg);
            final title = tester.widget<Text>(find.text(l.get('support_escalate')).first);
            expect(contrast(title.style!.color!, ctx.subtleCardBg), greaterThanOrEqualTo(4.5));
          });
        }
      });
    });

    group('item 8 ($mode)', () {
      testWidgets('the household type pucks are at AA in every state', (tester) async {
        final ctx = await pump(tester, HouseholdTypeChooser(value: 'family', onChanged: (_) {}), dark: dark);
        // The lightest and darkest stops of the burgundy puck, both modes.
        final stops = ctx.isDark
            ? const [Color(0xFF6E162F), VelvetBurgundyColors.primaryDark, Color(0xFF29040D)]
            : const [Color(0xFF65172C), VelvetBurgundyColors.primaryLight, VelvetBurgundyColors.primaryDarkMaroon];
        for (final icon in tester.widgetList<Icon>(find.byIcon(Icons.family_restroom_rounded)).followedBy(tester.widgetList<Icon>(find.byIcon(Icons.group_outlined)))) {
          for (final stop in stops) {
            expect(contrast(Color.alphaBlend(icon.color!, stop), stop), greaterThanOrEqualTo(4.5));
          }
        }
      });

      testWidgets('one ink on the fixed rose-gold fill, in both places', (tester) async {
        await pump(tester, const FamilyReimbursementCard(householdId: 'hh', summary: _family), dark: dark);
        final cardBtn = tester.widget<ElevatedButton>(_button<ElevatedButton>(find.text('Reimburse Wife')));
        expect(cardBtn.style!.foregroundColor!.resolve({}), VelvetBurgundyColors.primaryLight);
        await tester.tap(find.text('Reimburse Wife'));
        await tester.pumpAndSettle();
        final sheetBtn = tester.widget<ElevatedButton>(_button<ElevatedButton>(find.text('Record Settlement Payment')));
        expect(sheetBtn.style!.foregroundColor!.resolve({}), VelvetBurgundyColors.primaryLight);
        expect(contrast(VelvetBurgundyColors.primaryLight, AppThemes.champagneGold), greaterThanOrEqualTo(4.5));
      });
    });

    group('item 10 ($mode)', () {
      testWidgets('add member: every role icon reaches 3:1 on its disc, selected or not', (tester) async {
        final ctx = await pump(tester, const AddHouseholdMemberSheet(), dark: dark);
        void check() {
          for (final id in ['spouse', 'roommate', 'child']) {
            final row = find.byKey(Key('role_chip_$id'));
            final containers = tester.widgetList<Container>(find.descendant(of: row, matching: find.byType(Container))).toList();
            final rowFill = (containers[0].decoration! as BoxDecoration).color!;
            final disc = (containers[1].decoration! as BoxDecoration).color!;
            final icon = tester.widgetList<Icon>(find.descendant(of: row, matching: find.byType(Icon))).first;
            final fill = Color.alphaBlend(disc, Color.alphaBlend(rowFill, ctx.cardBg));
            expect(contrast(icon.color!, fill), greaterThanOrEqualTo(3), reason: id);
          }
        }

        check();
        // The roommate row is the one that came in at 2.92:1, selected.
        await tester.ensureVisible(find.byKey(const Key('role_chip_roommate')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('role_chip_roommate')));
        await tester.pump();
        check();
      });
    });
  }

  group('item 7: word integrity under real font metrics', () {
    setUpAll(loadRealFontMetrics);

    for (final lang in ['en', 'ar', 'ur']) {
      for (final scale in [1.5, 2.0]) {
        testWidgets('roles card, $lang x$scale, 390px', (tester) async {
          await pump(tester, HouseholdRolesCard(householdId: 'hh', loadRoster: (_) async => _rosterNoProvider), lang: lang, scale: scale);
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.takeException(), isNull);
          expect(brokenWords(tester, find.byType(HouseholdRolesCard)), isEmpty);
        });

        testWidgets('roles card with a provider, $lang x$scale, 390px', (tester) async {
          await pump(tester, HouseholdRolesCard(householdId: 'hh', loadRoster: (_) async => _rosterWithProvider), lang: lang, scale: scale);
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.takeException(), isNull);
          expect(brokenWords(tester, find.byType(HouseholdRolesCard)), isEmpty);
        });

        testWidgets('role invite dialog, $lang x$scale, 390px', (tester) async {
          useViewport(tester);
          await tester.pumpWidget(settingsTestApp(
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => RoleInviteDialog(
                    householdId: 'hh',
                    createInvite: (hid, role, {targetMemberId}) async => const HouseholdInvite(id: 'i', householdId: 'hh', inviteCode: 'ROLE1234', role: 'spouse'),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
            lang: lang,
            scale: scale,
          ));
          await tester.pump();
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          expect(brokenWords(tester, find.byType(RoleInviteDialog)), isEmpty);
          await tester.tap(find.byKey(const ValueKey('rid_generate')));
          await tester.pumpAndSettle();
          expect(brokenWords(tester, find.byType(RoleInviteDialog), ignore: (t) => t == 'ROLE1234'), isEmpty);
        });

        testWidgets('setup checklist, $lang x$scale, 390px', (tester) async {
          await pump(tester, HouseholdSetupCard(householdId: 'hh', data: _setupData, hasBudgets: false, onChanged: () {}), lang: lang, scale: scale);
          expect(brokenWords(tester, find.byType(HouseholdSetupCard)), isEmpty);
        });

        testWidgets('roommate debts, $lang x$scale, 390px', (tester) async {
          await pump(tester, const MultiRoommateSettlementCard(householdId: 'hh', summary: _roommates, currentUserId: 'me'), lang: lang, scale: scale);
          expect(brokenWords(tester, find.byType(MultiRoommateSettlementCard)), isEmpty);
        });
      }
    }
  });
}
