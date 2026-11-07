# Onboarding guide and Help FAQ update (Qawam Money / قوام المال)

**Sensitive:** no, because it changes only display code, navigation and translation strings. It changes no permissions, no money or ledger logic, no payday or cycle maths, and no path listed in `docs/sensitive.md`. It only *reads* roles that the app already loads (`HouseholdRoster` from `GET /households/{id}/members`, and `viewerIsAdminOf` from `household_role_provider.dart`) to decide which tutor steps to show. Files it must not edit: `household_role_provider.dart`, `household_permissions.dart`, `budget_management_screen.dart`, `salary_cycle_service.dart`, `account_service.dart`, `family_reimbursement_card.dart`, `wife_account_picker.dart`, and everything under `lib/services/api/` and `lib/screens/auth/`. If any section has to edit one of them, stop and re-classify the work as sensitive. Classification can be raised, never lowered.

**Review:** Round 1 (Opus 5.5 high, spec fidelity) and Round 2 (Opus 5.5 high, adversarial) run on the full branch diff after section 6. Fable is not needed unless the classification is raised. Rule 06 §4.1 applies: one agent at a time, and one section at a time with the owner's go-ahead.

**Gates for each code section:** `cd flutter_app && flutter analyze` (No issues found!) and `flutter test` (all pass). No other suites. Section 6 changes docs only, so it runs no tests.

**Where:** worktree `.claude/worktrees/onboarding-guide-update`, branch `feat/onboarding-guide-update`, from `main` `11d0063`. Don't use `git stash` and don't push. Each section is one or more conventional commits that end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

**Sources of truth:** `docs/HOW_IT_WORKS.md` (§1, §2, §3, §5, §7, §8, §9, §13, §14, §16, §18) and rule 02 (family mode rules 1 to 4: no split between spouses, the wife ledger's exact button names).

---

## 0. Review findings, re-verified at `11d0063`

| # | Finding | Verified | Notes |
|---|---|---|---|
| 1 | The tutor's action buttons are broken | Yes | No caller passes `onActionTriggered` (`dashboard_screen.dart:208`, `settings_screen.dart:1209`, `help_support_screen.dart:295,385`, `chat_entry_screen.dart:127`, all through `UserGuideWalkthroughDialog.show`). `_handleStepAction` (`app_setup_tutor_dialog.dart:161-196`) calls `_finish()` without awaiting it. `_finish` awaits `SharedPreferences` before it calls `onDismiss`, so the `push` runs first and `Navigator.of(ctx).pop()` (line 43) pops the pushed screen. No caller passes `householdId`, so `open_accounts` falls back to Settings. The test covers only the callback (`app_setup_tutor_dialog_test.dart:71-85`). |
| 2 | The FAQ hard-codes the 27th; `faq_salary_a2` is wrong | Yes | Also `faq_cat_salary` ("Salary Cycle & Payday (27th)", in ar and ur too). |
| 3 | The walkthrough widget is dead code | Yes | `wt2_tag2` is still used by `lib/widgets/chat/purchase_simulation_card.dart:59`, so it stays. |
| 4 | The tutor is the same for everyone | Yes | `HouseholdRoster` already has everything we need: `callerIsAdmin`, `effectiveHouseholdType`, the caller's own member row (`isSelf` / `isSpouse`), and `nafaqahProvider?.isSelf`. |
| 5 | Step 1 asks for income but opens Settings | Yes | The checklist already has a payday editor sheet (`household_setup_card.dart:347-361`) and `RecordIncomeSheet.show`. |
| 6 | The household screen overflows | Yes, and it is worse | The whole page is a fixed `Column` (title, subtitle, tabs, then an `Expanded` `TabBarView`). With the keyboard open at 320×568 and text scale 2.0, the outer column overflows as well, not only the Join tab. |
| 7 | FAQ errors | Yes, plus more | Also wrong: `faq_bills_a3` ("green Pay button": the button is burgundy, `recurring_bills_card.dart:729`), `faq_bills_q2`/`a2` and `faq_cat_bills` (a fixed 400 SAR Iqama fee, which `ai_service/support_agent.py:92` already calls wrong for most households), `faq_household_a2` ("Settings → Household"), `faq_bnpl_a1`, and `faq_salary_q3` ("daily allowance" is easily confused with the wife's allowance). `faq_receipts_a3` is correct: the scanner's `DuplicateCandidateCard` does offer Enrich. HOW_IT_WORKS §6 says it doesn't, and section 6 corrects the doc. |
| 8 | Theme | Partly | Line 82 is already burgundy to rose (`#800020`→`#B76E79`), just hard-coded rather than a token. Lines 92, 102, 112 and 122 are off-palette (blue, green, purple, orange). The Next button is emerald with black text (lines 437-438). In `household_screen.dart`, emerald is used at lines 322-323 (tab indicator and label) and 448 (`_BigButton`). |
| 9 | Language | Yes, plus more | The Urdu `tutor_stage_3_title` and `_desc` also say "mid-month" (مہینے کے درمیان). The step titles have their numbers baked into the text ("1. …"), which breaks once the number of steps varies by role. `set_replay_5_step_interactive_feature` and `tutor_subtitle` say "5 steps". |
| 10 | New FAQs | n/a | Added in section 4. |
| 11 | Keep the checklist and the type chooser | n/a | Neither is touched. |

---

## Section 1. Remove the dead walkthrough and point every entry point at the tutor

**Goal:** finding 3. There is one tutor. Every entry point opens it directly and passes the household.

**Files**
- Delete `flutter_app/lib/widgets/onboarding/user_guide_walkthrough_dialog.dart` (the owner decided this in the brief).
- Delete `flutter_app/test/widgets/user_guide_walkthrough_test.dart`.
- `lib/screens/home/dashboard_screen.dart`: change the import at :48 and the call at :208 to `AppSetupTutorDialog.showIfFirstTime(context)`. Section 3 moves this call.
- `lib/screens/settings/settings_screen.dart`: change the import at :35 and the call at :1209 to `AppSetupTutorDialog.show(context, householdId: _householdId)`.
- `lib/screens/settings/help_support_screen.dart`: change the import at :10 and the calls at :295 and :385 to `AppSetupTutorDialog.show(context, householdId: widget.householdId)`. The replay card title (:428) uses `tutor_title`.
- `lib/screens/chat/chat_entry_screen.dart`: change the import at :31 and the call at :127 to `AppSetupTutorDialog.show(context, householdId: _householdId)`.
- `lib/l10n/app_localizations.dart` (en, ar, ur).

**String keys**
- Removed (all three languages):
  - `wt1_title`, `wt1_desc`, `wt1_tag1`–`wt1_tag3`;
  - `wt2_title`, `wt2_desc`, `wt2_tag1`, `wt2_tag3` (keep `wt2_tag2`);
  - `wt3_title`, `wt3_tag1`–`wt3_tag3`;
  - `wt4_*`;
  - `wt5_title`, `wt5_tag1`–`wt5_tag3`;
  - `wt_feature_x_of_y`, `wt_get_started`, `wt_next`, `wt_skip`;
  - `support_walkthrough_title` (replaced by the existing `tutor_title`, "Interactive Setup Tutor").
- Kept for now: `wt3_desc` and `wt5_desc`. Section 3 moves their reviewed copy into tutor keys and then deletes them.
- Changed: `support_walkthrough_desc` → "Replay the setup tutor: payday, accounts, budgets, your household and the ways to record an expense."

**Tests**
- `test/screens/help_support_screen_test.dart`, new test: tapping **Replay** opens an `AppSetupTutorDialog`. The same check applies to the AppBar play icon.
- The existing `ui_l10n_guard_test.dart` checks that every key still used exists and that the three languages have the same keys.

**Checklist**
- [x] Write the Help replay test (it opens `AppSetupTutorDialog`)
- [x] Repoint the four entry points and pass `householdId` where the screen has it
- [x] Delete the widget file and its test
- [x] Remove the unused `wt*` keys (keep `wt2_tag2`, `wt3_desc`, `wt5_desc`) and `support_walkthrough_title`, and fix `support_walkthrough_desc`
- [x] Gates: `flutter analyze` and `flutter test`
- [x] Commit `refactor(onboarding): remove the dead walkthrough, open the tutor everywhere`

**Size:** S. About −420 / +40 lines, 1–2 hours.

---

## Section 2. Fix the tutor's navigation (TDD)

**Goal:** finding 1, and the routing part of finding 5. The dialog never navigates. It closes with the chosen action, and the caller's context opens the screen once the dialog route has gone. There is no Settings fallback.

**Design**
- In the tutor file, add `enum TutorAction { payday, income, accounts, budgets, roles }`.
- `AppSetupTutorDialog` gets `onClose(TutorAction?)` in place of `onDismiss` and `onActionTriggered`, both of which go. Closing writes the "seen" preference and awaits it, then calls `onClose`.
- `static Future<void> show(BuildContext context, {String? householdId, HouseholdRoster? roster, @visibleForTesting TutorNavigator? navigator, @visibleForTesting RosterLoader? loadRoster})`:
  - It runs `final action = await showDialog<TutorAction>(…)`, and the dialog pops itself with `Navigator.of(ctx).pop(action)`.
  - If `action != null && context.mounted`, it then runs `await (navigator ?? const TutorNavigator()).open(context, action, householdId!)`.
- New `lib/widgets/onboarding/tutor_navigator.dart` (`TutorNavigator.open`):
  - `payday` → `HouseholdSetupCard.openPaydayEditor(context, householdId: …)`. This is a new public static, and it is the existing `_open(SetupStep.payday)` body moved unchanged. `_open` calls it too. The save path (`ApiService.setHouseholdPayday`, `SalaryCycleService.cachePayday`) is not changed.
  - `income` → `RecordIncomeSheet.show(context, householdId: …)`.
  - `accounts` → push `AccountsOverviewScreen(householdId: …)`.
  - `budgets` → push `BudgetManagementScreen()`. This only imports the file; it does not edit it.
  - `roles` → a bottom sheet with `HouseholdRolesCard(householdId: …)` (**Members & Admins**), the same editor the checklist's provider step opens.
- Without a `householdId`, the dialog shows no button that needs one (`payday`, `income`, `accounts`, `roles`).
- `showIfFirstTime` takes the same `householdId` and `roster` and keeps the key `has_seen_setup_tutor_v2` (see decision D1).

**Files:** `lib/widgets/onboarding/app_setup_tutor_dialog.dart`, new `lib/widgets/onboarding/tutor_navigator.dart`, `lib/widgets/dashboard/household_setup_card.dart` (the extraction only), and the entry points from section 1 where a signature changes.

**String keys:** none in this section. The button labels change in section 3.

**Tests (written first, red for the intended reason)**
- New `test/widgets/app_setup_tutor_navigation_test.dart`:
  1. With a fake `TutorNavigator` that pushes a page reading "OPENED", tapping a step's button closes the dialog. After `pumpAndSettle`, "OPENED" is still showing: this is the regression for the pop race. The same check runs for every action.
  2. The "seen" preference is `true` before the dialog's route is gone.
  3. Close, Skip and Finish open nothing (the navigator is never called).
  4. With `householdId: null`, the buttons that need a household are absent, and nothing pushes `SettingsScreen`.
- `test/widgets/app_setup_tutor_dialog_test.dart`: replace the `onActionTriggered` test with the `onClose(TutorAction.payday)` test.
- `test/widgets/household_setup_card_test.dart` (existing): the payday step still opens the editor and saves. Run it unchanged.

**Checklist**
- [x] Write the navigation tests and see them fail
- [x] Add `TutorAction`, `onClose` and the `show` result; remove the in-dialog navigation
- [x] Add `TutorNavigator`; extract `HouseholdSetupCard.openPaydayEditor`
- [x] Hide the household-bound buttons when there is no household
- [x] Gates: `flutter analyze` and `flutter test`
- [x] Commit `fix(onboarding): tutor buttons open their screen after the dialog closes`

**Size:** M. About +180 code / +150 test lines, about 3 hours.

---

## Section 3. A role-aware tutor, the new role steps, the tutor copy and its theme (TDD)

**Goal:** findings 4 and 5 (the copy), 8 (the tutor's part) and 9 (the tutor strings).

**Who sees what** (new pure model `lib/models/tutor_viewer.dart`, display only, no permission logic of its own)
- `TutorViewer.from({HouseholdRoster? roster, required bool fallbackIsAdmin})`:
  - `isAdmin` = `roster?.callerIsAdmin ?? fallbackIsAdmin`. The fallback is `viewerIsAdminOf(context, householdId)`.
  - `roleStep`:
    - `roommate` when `roster.effectiveHouseholdType == roommates`;
    - otherwise `wife` when the caller's own member row `isSpouse`;
    - otherwise `husband` when `roster.nafaqahProvider?.isSelf`;
    - otherwise `none`.
  - Without a roster, `roleStep` is `none`.
- When `show` gets no roster but has a household, it loads one with `ApiService.instance.getHouseholdMembers`. That loader is injectable. While it loads, the dialog shows a small spinner; if the load fails, the dialog falls back to the role provider.
- The dashboard passes the roster it already has, so it makes no extra request.

**Steps**

| Step | Admin | Not an admin |
|---|---|---|
| Payday & Income | `tutor_stage_1_desc`; **Set Payday** (payday) plus **Record Income** (income) | `tutor_stage_1_desc_member`; **Record Income** |
| Accounts | `tutor_stage_2_desc`; **Set Up Bank & Savings** (accounts) | Same |
| Budgets | `tutor_stage_3_desc`; **Configure Envelopes** (budgets) | `tutor_stage_3_desc_member`, plus `tutor_admin_sets_note`; no button (D5) |
| Living model | `tutor_stage_4_desc`; **Members & Admins** (roles, the `roles_title` key) | `tutor_stage_4_desc`, plus `tutor_admin_sets_note`; no button |
| Role step (only one of these) | wife: `tutor_role_wife_*`, no button. Husband: `tutor_role_husband_*`, **Accounts & Balances** (accounts). Roommate: `tutor_role_roommate_*`, no button | Same |
| Three ways to record | `tutor_stage_5_desc`; **Start Using Qawam Money** | Same |

- A wife who is an admin gets the admin steps and the wife step.
- The step badge counts the steps actually shown.

**First run:** move the dashboard call from `initState`'s post-frame callback into `_loadDashboardData`, after `_fetchSetup`. It runs once per dashboard state (`_tutorChecked`) and calls `showIfFirstTime(context, householdId: hid, roster: setup?.roster)`.

**Theme** (Velvet Burgundy tokens only, light and dark)
- Remove `_TutorStep.gradient`. Every hero badge uses `context.icedAccentGradient`, and its shadow uses `context.primaryButtonBg`.
- The Next/Finish button and the step buttons use `context.primaryButtonBg` and `context.primaryButtonFg`. The secondary **Record Income** button is an `OutlinedButton` with `context.accentText`.
- The tutor uses neither `AppThemes.success` nor any literal colour.
- The bottom bar padding becomes `EdgeInsetsDirectional`.

**Copy.** Exact UI names are inserted with placeholders from the existing label keys, so they always match the buttons in each language. The ar and ur values are natural rewrites, not literal translations.

- Changed:
  - `tutor_stage_1_title` → "Payday & Income".
  - `tutor_stage_2_title` → "Operating Accounts vs. Savings Vaults".
  - `tutor_stage_3_title` → "Envelope Budgeting & Joining Mid-Cycle". In ar, "منتصف الدورة"; in ur, "سائیکل کے درمیان"; in ur, "envelope" becomes "کیٹیگری بجٹ".
  - `tutor_stage_4_title` → "Living Model: Family & Roommates".
  - `tutor_stage_5_title` → "Three Ways to Record". The leading numbers are dropped from every title.
  - `tutor_stage_1_desc` → "Each salary cycle runs from your household's payday to the day before the next one, and the home screen shows what is left until then and a safe amount per day. Set the payday here (it is also in {payday} in Settings), and record your salary and other income with {income} in Tools." Placeholders: `{payday}`=`pds_title`, `{income}`=`record_income`. This is built on the reviewed `wt3_desc` copy, and it fixes the Urdu value, which dropped the income part.
  - `tutor_stage_1_btn` → "Set Payday".
  - `tutor_stage_3_desc` → "Give each category its budget for the cycle (Groceries, Housing, Bills). Joining mid-cycle? Use {prior} on the Budgets tab so what is left matches your bank." Placeholder: `{prior}`=`apply_prior_spend_adjustment`.
  - `tutor_stage_4_desc` → the reviewed `wt5_desc` copy in all three languages: "In a family the husband covers the household; what his wife pays for the home is owed back to her, and her personal purchases come from her allowance. Nothing is split between them. Roommates see who owes whom, with as few transfers as possible."
  - `tutor_stage_5_desc` → "Tap {add}: {voice} (type or say it, for example "Filled 91 petrol 60 SAR from SASCO"), {scan} (photos and the ZATCA QR code) or {manual}. The centre button of the bottom bar opens the AI chat too." Placeholders: `add_expense`, `voice_chat`, `scan_receipt`, `manual_log`. The Urdu value gets its chat example back. The "in 1 second" claim is dropped.
  - `set_replay_5_step_interactive_feature` → "Replay the setup tutor for your household".
- New:
  - `tutor_stage_1_desc_member`: "Each salary cycle runs from your household's payday to the day before the next one, and the home screen shows what is left until then. Your admin sets the payday. You can record your own income with {income} in Tools."
  - `tutor_stage_3_desc_member`: "Your admin gives each category its budget for the cycle. You can see them on the Budgets tab, and the household expenses you record count against them."
  - `tutor_admin_sets_note`: "Your household's admin sets this up."
  - `tutor_role_wife_title`: "Your expenses as a wife".
  - `tutor_role_wife_desc`: "When you record an expense, "{whoPaid}" asks who it was for. "{shared}" is owed to you by your husband. "{personal}" comes out of your allowance, which your husband or an admin who is not a wife sets. Nothing is split between you. When he pays you back, tap "{received}" on the family card and he approves it." Placeholders: `nafaqah_q_title`, `nafaqah_w_opt_shared`, `nafaqah_w_opt_personal`, `nafaqah_mark_received`.
  - `tutor_role_husband_title`: "Paying your wife back".
  - `tutor_role_husband_desc`: "What your wife pays for the home is owed to her; nothing is split between you. First add her wife account with "{addWife}" on {accounts} (it appears once she has joined). Then tap "{reimburse}" on the family card: the money leaves your account and goes into her wife account. When she taps "{received}", you {approve} or {decline} it. A wrong repayment is corrected with "{reverse}"." Placeholders: `wife_acc_add_title`, `accounts_balances`, `reimburse_wife`, `nafaqah_mark_received`, `req_approve`, `req_decline`, `rev_action`.
  - `tutor_role_roommate_title`: "Sharing with roommates".
  - `tutor_role_roommate_desc`: "Each expense says who paid and whether it is "{splitAll}" or "{personal}". The roommates card shows who owes whom, with "{fewest}" so fewer payments are needed. "{settle}" records a payment between you; it does not move any account balance in the app." Placeholders: `roommate_split_all`, `roommate_split_personal`, `simplify_debts`, `settle_now`.
- Removed: `tutor_stage_4_btn` (replaced by `roles_title`), `tutor_subtitle` (unused, and it said "5 steps"), `wt3_desc` and `wt5_desc` (their copy has moved).
- Kept: `tutor_stage_5_btn`, which the brand guard requires to contain "Qawam Money".

**Tests (written first)**
- New `test/models/tutor_viewer_test.dart`:
  - admin husband (family) → payday, accounts, budgets, living, husband, record, all with their actions;
  - wife, not an admin → member steps plus the wife step, and no payday, budgets or roles action;
  - roommate member → member steps plus the roommate step;
  - family member who is an admin and not the provider → five admin steps, no role step;
  - no roster with the fallback `false` → member, no role step; with `true` → admin.
- New `test/widgets/app_setup_tutor_roles_test.dart`:
  - A wife walks every page. She never sees **Set Payday**, **Configure Envelopes** or **Members & Admins**, and sees `tutor_admin_sets_note` instead. Her step shows the exact en, ar and ur values of `nafaqah_q_title`, `nafaqah_w_opt_shared`, `nafaqah_w_opt_personal` and `nafaqah_mark_received`.
  - A husband's step shows `reimburse_wife` and `wife_acc_add_title`, and its button opens accounts.
  - A roommate's step shows the split and settle labels.
  - No layout overflow at 320×568 and text scale 2.0, for the 4 viewers × en, ar and ur × light and dark, walking every page (`tester.takeException()` is null).
  - Theme: no widget in the tutor is filled with `AppThemes.success`, and the Next button's background is `context.primaryButtonBg` in light and dark.
- Copy guards in the same file:
  - no `tutor_*` value in any language contains "50/50" or "%";
  - no Urdu value contains "اینولپ";
  - the ar and ur stage 3 titles don't say "month" (الشهر / مہینے);
  - no title starts with a digit.
- `app_setup_tutor_dialog_test.dart`: update the titles (no numbers) and "Set Payday".
- Dashboard: a test with `HouseholdSetupPrefs.loadOverride` checks that the tutor opens after setup has loaded, with the wife variant when the roster's caller is a wife. Seed `has_seen_setup_tutor_v2: true` in any dashboard test that breaks because the dialog now opens later.

**Files:** `app_setup_tutor_dialog.dart`, new `lib/models/tutor_viewer.dart`, `dashboard_screen.dart`, `app_localizations.dart`, and the tests above.

**Checklist**
- [x] Write the `TutorViewer` unit tests and the role widget tests; see them fail
- [x] Add `TutorViewer` and the step builder; load the roster in `show`
- [x] Add the role steps and the member variants; fill the placeholders from the label keys
- [x] Rewrite the tutor copy in en, ar and ur; remove the old keys
- [x] Theme tokens; overflow and theme tests
- [x] Move the dashboard first-run call after setup loads
- [x] Gates: `flutter analyze` and `flutter test`
- [x] Commit `feat(onboarding): role-aware setup tutor with wife, husband and roommate steps`

**Size:** L. About +250 code / +300 test lines; 13 new and 12 changed keys × 3 languages; 5–6 hours.

---

## Section 4. Fix the Help FAQ and add five FAQs

**Goal:** findings 2, 7 and 10, and the extra FAQ errors from §0.

**Files:** `lib/l10n/app_localizations.dart`, and `lib/screens/settings/help_support_screen.dart` (the new questions plus one new group, `faq_cat_privacy`, with `Icons.lock_outline_rounded` and `context.accentText`).

**Changed keys (en text; ar and ur rewritten to match)**
- `faq_cat_salary`: "Salary Cycle & Payday".
- `faq_salary_a1`: "Each household has its own payday: the 27th unless an admin changes it in Settings → Salary & Payday Cycle. A cycle runs from payday to the day before the next payday. If the payday is past the end of a short month, it falls on the month's last day."
- `faq_salary_a2`: "Your money stays in your accounts. When a new cycle starts, the budgets are copied with the same amounts and nothing spent. Only a category or sub-category marked "Accumulate unspent (Sinking fund)" carries its unspent amount into the next cycle." This drops the rollover choice and the savings reserve that the app doesn't show.
- `faq_salary_q3`: "How is the daily amount worked out?"
- `faq_salary_a3`: "What is left until payday, minus the bills and installments still due this cycle, divided by the days left until your household's next payday, today included."
- `faq_receipts_a1`: "Tap Add Expense, then Scan Receipt. Take one or more photos (Snap Photo, Snap Next Page) or pick from Gallery, and add the receipt's ZATCA QR code if it has one. The photos are read on the server by the AI model the app is set up with, and you check the merchant, items and VAT before saving."
- `faq_cat_bills`: "Recurring Bills & Reserves".
- `faq_bills_a1`: "On the dashboard's Recurring Bills & Reserves card, tap Configure, then Manage Recurring Bills. Switch a budgeted sub-category on as a recurring bill and pick its due day."
- `faq_bills_q2`: "Where do I track government fees such as Iqama and dependants' fees?" (D4)
- `faq_bills_a2`: "Under the Government category, which has Iqama & Visas, Vehicle Registration and Government Fees. Give the one you pay a budget, and mark it as a recurring bill if it comes every month." (D4)
- `faq_bills_a3`: "Tap Pay on an unpaid bill on the dashboard card, then Confirm Paid. It records the bill's usual amount as an expense in its category; no account balance changes."
- `faq_bnpl_a1`: "On the dashboard's Installments & BNPL card, tap Add Installment Plan (Tamara, Tabby or Bank / Other), or turn an expense into a plan with Convert to BNPL Installment Plan when you edit it. The card shows each plan's next date and how many installments are paid."
- `faq_household_a2`: "An admin opens Settings → HOUSEHOLD & MEMBERSHIP and shares the household code, or taps Invite with Role for one person (Wife / Spouse, Family Dependent or Roommate / Flatmate; valid for 7 days). The other person enters the code on Your Household after signing in."
- `faq_nafaqah_a3`: "…Your husband or an admin who is not a wife sets it; no wife sets it, for herself or for a co-wife. …" The rest of the answer is unchanged.

**New keys (en)**
- `faq_household_q3`: "What can each person in the household do?"
- `faq_household_a3`: "The primary admin created or took over the household and is the only one who can hand that role on. Co-admins can do everything else an admin does: payday, budgets, invites and members. Members record and change their own expenses and see what the household shares. In a family, the household provider (husband) is responsible for household expenses, and each wife has her own allowance and record of what is owed to her. Roles are in Settings → Members & Admins."
- `faq_household_q4`: "What kinds of accounts are there?"
- `faq_household_a4`: "A personal account (bank, cash, e-wallet, savings) is yours alone: only you see it and spend from it. A Shared Household Pool belongs to the household: every member sees it and can pay into it, and only admins move money out. In a family, a wife account is one her husband makes with "Add wife account" on his Accounts & Balances screen: she spends from it, and every repayment to her goes into it. A Savings Vault is not counted as money to spend."
- `faq_nafaqah_q4`: "How does my husband pay me back?"
- `faq_nafaqah_a4`: "He first adds your wife account. Then he taps "Reimburse Wife" on the family card and picks the account the money leaves; it goes into your wife account and what is owed goes down. You can also tap "Mark as received" when you have been paid: he approves it (the money then moves the same way) or declines it, and nothing moves until he approves. A wrong repayment is never edited: he taps "Reverse", and the amount is owed to you again."
- `faq_cat_privacy`: "Privacy & your account".
- `faq_privacy_q1`: "Who can see what?"
- `faq_privacy_a1`: "Ordinary expenses and shared pools are seen by the whole household, including the expenses a wife pays for the home. Your personal accounts are seen only by you. A wife's allowance and personal purchases are seen by her, her husband and admins who are not wives. What is owed to her, her repayments and her wife account are seen only by her and her husband (or an admin who is not a wife if he has left). A co-wife never sees another wife's records, even as an admin. Nobody can change a record they cannot see."
- `faq_privacy_q2`: "What happens if I delete my account?"
- `faq_privacy_a2`: "Use Settings → Delete account. Your account is deleted 30 days later; until then it works as usual, and "Cancel the deletion" stops it at any time before deleting starts. Signing in does not cancel it. Your profile, personal accounts and their entries are deleted. Expenses you recorded in a household that stays are kept and shown as "Deleted member". If you run a household with other members, you choose to hand it over or delete it." It makes no promise of an email (rule 04 §6).

**Tests**
- New `test/screens/help_faq_accuracy_test.dart`:
  - `faq_salary_a1`, `a2` and `a3` and `faq_cat_salary` say nothing about a fixed payday: only `a1` names the 27th, and only as the default an admin can change;
  - `a2` names no rollover choice or savings reserve;
  - `faq_receipts_a1` contains the `add_expense` and `scan_receipt` values in each language and no "Gemini" or "green";
  - `faq_bills_a1` contains `rb_configure` and `rb_manage_title`;
  - `faq_nafaqah_a4` contains `reimburse_wife`, `nafaqah_mark_received` and `rev_action`, and `faq_household_a4` contains `wife_acc_add_title`, all per language;
  - `faq_privacy_a2` contains no "email", "بريد" or "ای میل";
  - no FAQ value contains "400";
  - the no-split guard of `help_nafaqah_faq_test.dart` is extended to `faq_nafaqah_a4`, `faq_household_a3` and `a4`, and `faq_privacy_a1`.
- `help_support_screen_test.dart`: the privacy group and its two questions are listed (ar), and a search for the en word "delete" finds `faq_privacy_q2`.

**Checklist**
- [x] Write the accuracy tests and see them fail
- [x] Rewrite the changed FAQ values in en, ar and ur
- [x] Add the five FAQs and the privacy group
- [x] Gates: `flutter analyze` and `flutter test`
- [x] Commit `fix(help): accurate FAQ answers and new FAQs on roles, accounts, repayments, privacy and deletion`

**Size:** M. 5 new FAQs plus 1 group, 13 changed keys × 3 languages, about +30 code / +120 test lines, about 3 hours.

---

## Section 5. Household screen layout and theme

**Goal:** finding 6, and finding 8 on `household_screen.dart`.

**Changes in `lib/screens/onboarding/household_screen.dart`**
- The whole page scrolls as one: a `SingleChildScrollView` with `keyboardDismissBehavior: onDrag` holds the header, the `TabBar` and the content of the selected tab. That content comes from a `ListenableBuilder` on `_tab` in place of the `Expanded` `TabBarView`, so the tabs are tapped, not swiped (D3).
- The deletion link stays at the end.
- `_BigButton`: `ConstrainedBox(minHeight: 52)` in place of `height: 52`. The label wraps and is centred.
- Colours: the `TabBar` indicator and label use `context.accentText`. `_BigButton` uses `context.primaryButtonBg` and `context.primaryButtonFg`, and its loading spinner uses `context.primaryButtonFg`. Emerald no longer appears on this screen.
- The claim banner's margin uses `EdgeInsetsDirectional`.
- The `HouseholdTypeChooser` and its Family and Roommates descriptions are not touched (finding 11).

**String keys:** none.

**Tests:** new `test/widgets/household_screen_layout_test.dart`.
- At 320×568 and text scale 2.0, for en, ar and ur:
  - Create tab, and Join tab with the keyboard open (`tester.view.viewInsets` bottom 300 logical);
  - Join tab with the claim banner showing (the mock inspect client from `household_screen_claim_test.dart`).
- Each case expects no exception, and **Join Household** and **Create Household** can be scrolled to and tapped.
- A wrapped button label is fully painted: the button is taller than 52.
- Light and dark: the `_BigButton` background is `primaryButtonBg`, and the `TabBar` indicator is `accentText`.
- The existing back-button and claim tests still pass.

**Checklist**
- [ ] Write the layout and theme tests and see them fail
- [ ] Make the page scroll as one, replace the fixed button height, swap the colours
- [ ] Gates: `flutter analyze` and `flutter test`
- [ ] Commit `fix(onboarding): household screen scrolls at large text and uses the burgundy theme`

**Size:** S–M. About +60 code / +120 test lines, about 2 hours.

---

## Section 6. Translation review CSV and the docs

**Goal:** hand the new and changed ar and ur copy to the owner's paid native review, and bring HOW_IT_WORKS up to date.

**Files**
- New `docs/review/onboarding_guide_translation_review.csv`:
  - The same columns as `account_deletion_translation_review.csv`: `key,where_it_appears,english,arabic,urdu,reviewer_notes`.
  - One row for each new or changed key from sections 1, 3 and 4. Values with placeholders are shown with their `{names}`, and a reviewer note says what each placeholder becomes.
  - Removed keys are not listed.
  - These strings join the owner's paid native review. Until it comes back, the ar and ur copy is a natural draft and has not been reviewed by a native speaker.
- `docs/HOW_IT_WORKS.md`:
  - §1 "The first run": the tutor opens after the household has loaded, with steps for the viewer's role.
  - §14: the new step list per role; the buttons and what they open (payday editor, Record Income, Accounts & Balances, Budgets, Members & Admins); seven FAQ groups.
  - §6: the scanner's duplicate card also offers Enrich.
  - §19: remove "The setup tutor's step 2" from "Found while writing this guide".
  - Update "Last checked".
- This plan: tick the boxes.

**Checklist**
- [ ] Write the CSV from the final `app_localizations.dart` values
- [ ] Update HOW_IT_WORKS §1, §6, §14 and §19
- [ ] Commit `docs(onboarding): translation review sheet and how-it-works update`
- [ ] Then Round 1 and Round 2 reviews on the full branch diff (fresh subagents, spec plus diff only)

**Size:** S. About 55 CSV rows and the doc edits, about 1 hour. No test runs (docs only).

---

## Decisions for the owner

- **D1. Show the new tutor again to current users?** Default: no. Keep `has_seen_setup_tutor_v2`, so only new phones see it automatically and everyone else can use Replay. The alternative is to change the key to `v3`, so every user sees the fixed, role-aware tutor once.
- **D2. The husband step before his wife has joined.** Default: show it, with "(it appears once she has joined)". The alternative is to show it only when the household has a wife.
- **D3. Household screen tabs.** Default: tap to switch, no swipe, so the whole page can scroll with the keyboard open. The alternative is to keep swiping with a more complex nested scroll.
- **D4. The 400 SAR Iqama fee FAQ.** Default: reword it without a fixed amount, pointing to the real Government sub-categories. The alternative is to keep the 400 SAR figure.
- **D5. Budgets step for members.** Default: no button, just "Your household's admin sets this up." The alternative is a view-only "Open Budgets" button.
