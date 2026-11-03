# Implementation Plan: Theme Contrast Sweep, Hardcoded Colors & Dashboard Dark Icons

**Sensitive:** yes, because it touches primary financial HUD widgets (`budget_hero_card.dart`, `accounts_summary_card.dart`, `family_reimbursement_card.dart`, `recurring_bills_card.dart`, `account_card.dart`).

---

## 1. Summary of Changes

1. **Dashboard Dark Icons Fix:**
   - In `ThreeDIconPuck` (`three_d_icon_puck.dart:128-130`), make `isRoseGold` icon color theme-aware (`isDark ? Colors.white : const Color(0xFF4A0E1E)`), eliminating dark muddy maroon icons on the dark dashboard (`AccountsSummaryCard`, `FamilyReimbursementCard`, `MultiRoommateSettlementCard`).
   - Fix `ChoiceChip` avatar icons in `FamilyReimbursementCard` and `MultiRoommateSettlementCard` from dark plum/black to theme-adaptive foreground.
   - Fix invisible `CircularProgressIndicator` (`color: AppThemes.deepGlacial`) in `FamilyReimbursementCard` and `WifeAllowanceCard`.

2. **Light Mode Pale Pink on White Fix ("Funded"-Case Pattern):**
   - In `AccountCard` (`account_card.dart:46, 51`), replace static dark-mode tokens `AppThemes.electricTeal` and `AppThemes.iceCyan` with dynamic `context.electricTeal` and `context.successText`.
   - In `WifeAllowanceCard` (`wife_allowance_card.dart:88, 91, 170-171`), replace `AppThemes.iceCyan` with `context.accentText`.
   - In `GroceryPriceIntelligenceScreen` (`grocery_price_intelligence_screen.dart:443`), replace `Colors.white` fallback with `context.textPrimary`.

3. **Black-on-Dark Maroon Text & Icon Fixes:**
   - In `RecurringBillsCard` (`recurring_bills_card.dart:472`), remove hardcoded `color: Colors.black` on the "Confirm Paid" button text.
   - In `RecurringBillsCard` (`recurring_bills_card.dart:617`), make due-day selector text theme-aware when selected.
   - In `SettingsScreen` (`settings_screen.dart:1592`), make language switcher selected text theme-aware (`context.isDark ? Colors.black : Colors.white`).
   - In `RolloverSettingsCard` (`rollover_settings_card.dart:255`), fix save button icon color.
   - In `BudgetManagementScreen` (`budget_management_screen.dart:1004`), fix deactivate confirmation button contrast.
   - In `AccountsOverviewScreen` (`accounts_overview_screen.dart:324, 345`), fix button text/background contrast.

---

## 2. Testing & Multi-Round Review Pipeline
- Add `test/theme/dashboard_icon_contrast_test.dart` and `test/theme/light_mode_contrast_sweep_test.dart`.
- Verify `flutter analyze` (0 issues) and `flutter test` (100% pass).
- Multi-round review: Round 1 (Opus 5.5 High), Round 2 (Opus 5.5 High Adversarial), Round 3 (Fable High).

