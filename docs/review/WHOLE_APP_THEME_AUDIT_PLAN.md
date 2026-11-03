# Whole-App Theme (Light & Dark Mode) Contrast Audit & Implementation Plan

**Reference Document:** `docs/review/WHOLE_APP_THEME_AUDIT_PLAN.md`  
**Classification:** Sensitive: YES (Touches financial screens, transaction sheets, Nafaqah cards, settings, and authentication HUD elements)  
**Target:** Elimination of all remaining hardcoded colors, static legacy tokens, invisible spinners, and contrast defects across both Light and Dark modes.

---

## 1. Executive Summary & Problem Scope

A comprehensive automated and manual code scan across all 72 Dart UI files in `flutter_app/lib/` identified **102 suspicious color instances** and **12 concrete functional contrast defects** where text, spinners, icons, or buttons break legibility or fail WCAG 2.1 AA (contrast < 4.5:1) in Light Mode, Dark Mode, or both.

### Primary Defect Categories
1. **Severe Invisibility in Light Mode (Contrast < 1.5:1):**
   - Navy text (`0xFF0A0F1D`) on dark velvet maroon button backgrounds (`0xFF4A0E1E`) in `BatchItemReviewSheet` and `BatchReceiptScannerScreen` (**1.05:1 contrast**).
   - White text on pale pink buttons (`#E598B0`) in `WifeAllowanceCard` and `FamilyReimbursementCard` (**1.45:1 contrast**).
2. **Invisible Circular Progress Indicators (Black Spinners on Dark Buttons):**
   - `EditTransactionSheet`, `BudgetManagementScreen`, `InstallmentPlansCard`, `BatchItemReviewSheet`, and `BatchReceiptScannerScreen` use `color: Colors.black` inside buttons styled with `context.primaryButtonBg` (`#4A0E1E`). While processing, the spinner is black-on-maroon (**1.2:1 contrast**).
3. **Black-on-Dark Checkmarks & Selected States in Light Mode:**
   - In `RolloverSettingsCard`, the radio button checkmark is hardcoded `color: Colors.black` on an `iconColor` circle that is dark velvet maroon (`#4A0E1E`) in Light Mode (**1.2:1 contrast**).
4. **Dark Maroon Icons on Dark Wave Headers in Light Mode:**
   - In `IncomeSpendingReportScreen`, the savings action icon uses `context.electricTeal` (`#4A0E1E` in Light Mode) on `VelvetWaveHeader`, which is dark burgundy in both modes (**1.1:1 contrast**).
5. **Legacy Old-Navy Theme Tokens in Auth Screens:**
   - `ForgotPasswordScreen` and `UpdatePasswordScreen` still reference `AppThemes.electricTeal` and `AppThemes.brandDarkBg` (`#0A0F1D` slate navy) instead of the Velvet Burgundy theme system.
6. **Static Pale Pink Tokens on White Cards in Light Mode:**
   - "Transfer Out" in `AccountCard` uses static `AppThemes.electricTeal` (`#F0A3BC`), yielding pale pink text on white (**1.8:1 contrast**).
   - Allowance progress bar in `WifeAllowanceCard` and Nafaqah radio option in `NafaqahClassSelector` use static `AppThemes.iceCyan` on light surfaces (**< 2:1 contrast**).
7. **Hardware & App Permissions Badges & Buttons in Dark Mode:**
   - "NOT GRANTED" status badge in `SettingsScreen` uses raw `Colors.orange` on dark card (`#1E0B12`), appearing muddy, while "Grant Access" button renders as bright pale pink (`#F9D2D9`).

---

## 2. Detailed Findings & Remediation Inventory

| ID | File & Lines | Defect Description | Mode Affected | Current Flawed Code | Required Remediation |
| :--- | :--- | :--- | :---: | :--- | :--- |
| **TH-01** | `lib/widgets/scanner/batch_item_review_sheet.dart:581, 761` | "Save & Next" and "Return to Dashboard" buttons have dark navy text on dark maroon button | **Light** (1.05:1) | `backgroundColor: context.electricTeal`<br>`foregroundColor: AppThemes.brandDarkBg` | Use `context.primaryButtonBg` and `context.primaryButtonFg` (clean white text on maroon) |
| **TH-02** | `lib/widgets/scanner/batch_item_review_sheet.dart:591` | Black progress spinner inside save button | **Light & Dark** | `CircularProgressIndicator(strokeWidth: 2, color: Colors.black)` | `color: context.primaryButtonFg` |
| **TH-03** | `lib/widgets/scanner/batch_item_review_sheet.dart:474, 492, 507, 524` | Input fields use static `AppThemes.deepGlacial` and `Colors.grey.shade100` | **Both** | `fillColor: context.isDark ? AppThemes.deepGlacial : Colors.grey.shade100` | `fillColor: context.inputBg`, `border: OutlineInputBorder(borderSide: BorderSide(color: context.borderColor))` |
| **TH-04** | `lib/screens/scanner/batch_receipt_scanner_screen.dart:596-597` | "Process Queue" button has dark navy text on dark maroon | **Light** (1.05:1) | `backgroundColor: context.electricTeal`<br>`foregroundColor: AppThemes.brandDarkBg` | `backgroundColor: context.primaryButtonBg`<br>`foregroundColor: context.primaryButtonFg` |
| **TH-05** | `lib/widgets/settings/rollover_settings_card.dart:380` | Radio circle checkmark is black on dark maroon | **Light** (1.2:1) | `color: Colors.black` on `iconColor` (maroon) | `color: context.isDark ? Colors.black : Colors.white` |
| **TH-06** | `lib/widgets/nafaqah/wife_allowance_card.dart:326-327` | "Save" allowance button is white on pale pink | **Light** (1.45:1) | `backgroundColor: AppThemes.iceCyan`<br>`foregroundColor: context.isDark ? AppThemes.deepGlacial : Colors.white` | `backgroundColor: context.primaryButtonBg`<br>`foregroundColor: context.primaryButtonFg` |
| **TH-07** | `lib/widgets/nafaqah/wife_allowance_card.dart:66` | Progress bar uses static pale pink on white card | **Light** (< 2:1) | `final barColor = st.isOverspent ? context.dangerColor : AppThemes.iceCyan;` | `context.isDark ? context.accentText : VelvetBurgundyColors.primaryLight` |
| **TH-08** | `lib/widgets/accounts/account_card.dart:302` | "Transfer Out" text button is pale pink on white card | **Light** (1.8:1) | `foregroundColor: AppThemes.electricTeal` | `foregroundColor: context.accentText` |
| **TH-09** | `lib/widgets/accounts/account_card.dart:112` | "Shared Pool" tag background uses static token | **Light** | `color: AppThemes.electricTeal.withValues(alpha: 0.15)` | `color: context.accentText.withValues(alpha: 0.15)` |
| **TH-10** | `lib/widgets/nafaqah/nafaqah_class_selector.dart:55` | Wife personal option radio and icon are pale pink on light container | **Light** (< 2:1) | `case kWifePersonal: return AppThemes.iceCyan;` | Adapt to brightness: in light mode return `VelvetBurgundyColors.primaryLight`, in dark mode `context.accentText` |
| **TH-11** | `lib/screens/home/edit_transaction_sheet.dart:1344` | Convert to BNPL confirm button has black spinner on dark maroon | **Light & Dark** | `CircularProgressIndicator(strokeWidth: 2, color: Colors.black)` | `color: context.primaryButtonFg` |
| **TH-12** | `lib/screens/home/budget_management_screen.dart:1510` | "Copy Previous" button has black spinner on dark maroon | **Light & Dark** | `CircularProgressIndicator(strokeWidth: 2, color: Colors.black)` | `color: context.primaryButtonFg` |
| **TH-13** | `lib/widgets/dashboard/installment_plans_card.dart:908` | "Confirm Plan" button has black spinner on dark maroon | **Light & Dark** | `CircularProgressIndicator(strokeWidth: 2, color: Colors.black)` | `color: context.primaryButtonFg` |
| **TH-14** | `lib/screens/analytics/income_spending_report_screen.dart:148` | Savings action icon on dark wave header is dark maroon | **Light** (1.1:1) | `color: context.electricTeal` on `VelvetWaveHeader` | `color: context.isDark ? context.electricTeal : Colors.white` |
| **TH-15** | `lib/widgets/dashboard/family_reimbursement_card.dart:397, 785` | Champagne gold button uses white text in light mode | **Light** (2.1:1) | `foregroundColor: context.isDark ? AppThemes.deepGlacial : Colors.white` | `foregroundColor: context.isDark ? AppThemes.deepGlacial : const Color(0xFF4A0E1E)` |
| **TH-16** | `lib/screens/auth/forgot_password_screen.dart` & `update_password_screen.dart` | Legacy navy tokens across reset forms | **Both** | `AppThemes.electricTeal`, `AppThemes.brandDarkBg` | Migrate buttons and input borders to `context.primaryButtonBg`, `context.primaryButtonFg`, `context.inputBg` |
| **TH-17** | `lib/screens/settings/settings_screen.dart:1625, 1657, 1679` | Permissions card "NOT GRANTED" status badge and "Grant Access" button | **Both** | `Colors.orange` badge, `activeColor` button (`#F9D2D9` in dark) | `context.isDark ? context.warnText : VelvetBurgundyColors.amberCautionTextLight` for badge; `context.primaryButtonBg` for button |

---

## 3. Test-Driven Verification Strategy

1. **New Automated Test Suite:**
   Create `flutter_app/test/theme/whole_app_theme_sweep_test.dart` to programmatically verify:
   - `BatchItemReviewSheet`: "Save & Next" button foreground and progress indicator contrast > 4.5:1 on background in Light and Dark modes.
   - `RolloverSettingsCard`: Selected checkmark contrast > 4.5:1 on `iconColor` circle in Light mode.
   - `WifeAllowanceCard`: Allowance save button and progress indicator contrast > 4.5:1.
   - `AccountCard`: "Transfer Out" text button contrast > 4.5:1 on white card in Light mode.
   - `IncomeSpendingReportScreen`: `VelvetWaveHeader` actions contrast > 4.5:1 in Light and Dark modes.
   - `FamilyReimbursementCard`: Champagne gold button foreground contrast > 4.5:1 in Light and Dark modes.
   - Spinners in `EditTransactionSheet`, `BudgetManagementScreen`, and `InstallmentPlansCard` adopt `primaryButtonFg` (no `Colors.black`).
2. **Regression Gate:**
   - `flutter analyze` &rarr; 0 issues.
   - `flutter test` &rarr; 100% pass (all 1,193+ tests).

---

## 4. Multi-Round Review Pipeline
- **Round 1 (Opus 5.5 High):** Specification fidelity against this plan.
- **Round 2 (Opus 5.5 High Adversarial):** Break-testing dynamic theme toggle, extreme font scaling, RTL.
- **Round 3 (Fable High Sensitive Audit):** Invariants verification (Rule 02 Islamic Nafaqah, Rule 04 Zero SMS).
- **Final Release APK Compilation:** Generate fresh `app-arm64-v8a-release.apk`.
