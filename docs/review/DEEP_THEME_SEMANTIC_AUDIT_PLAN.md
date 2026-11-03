# Deep Theme Semantic & Component Contrast Audit & Implementation Plan

**Reference Document:** `docs/review/DEEP_THEME_SEMANTIC_AUDIT_PLAN.md`  
**Classification:** Sensitive: YES (Touches financial tools screen, settings household chooser, budget management prior spend dialog, and receipt scanner sheets)  
**Target:** Elimination of all semantic component-level contrast collisions, 3D puck icon invisibility in Light Mode, and low-contrast green tokens across all 18 screens and 73 widgets.

---

## 1. Problem Scope & Root Causes

A comprehensive audit of all 18 screens and 73 widgets identified **7 concrete functional contrast defects** resulting from:
1. **Semantic Component Collision:** Tokens designed for light surfaces (e.g. `context.accentText` returning `#4A0E1E` in Light Mode) being passed into components that are internally dark (e.g. `ThreeDIconPuck` returning `#4A0E1E` background), resulting in a **1.0:1 contrast (complete invisibility)** in Light Mode.
2. **Hardcoded Text/Button Colors:** White text on light cards (`receipt_scanner_sheet.dart` "Try Again" button), and black text on dark maroon buttons (`budget_management_screen.dart` prior spend dialog).
3. **Low-Contrast Mint Green on White Surfaces:** Static `AppThemes.success` (`#34D399`) used as foreground text/icons on white cards (`#FFFFFF`) yielding **1.9:1 contrast** (failing WCAG AA >= 4.5:1).

---

## 2. Inventory of Defects & Solutions (DEF-01 to DEF-07)

| ID | File & Line | Component | Current Flawed Code | Remediated Code & Contrast |
| :--- | :--- | :--- | :--- | :--- |
| **DEF-01** | `flutter_app/lib/screens/tools/tools_screen.dart:183` | `ToolsScreen` tool tile pucks | `ThreeDIconPuck(iconColor: tool.color)` (**1.0:1** in Light Mode) | `iconColor: context.isDark ? tool.color : Colors.white`<br>Achieves **11.8:1 contrast** (WCAG AAA) on dark maroon puck in Light Mode. |
| **DEF-02** | `flutter_app/lib/widgets/settings/household_type_chooser.dart:61` | Settings > Household Setup model pucks | `iconColor: selected ? color : context.textSecondary` (**1.0:1** selected, **2.1:1** unselected in Light Mode) | `iconColor: context.isDark ? (selected ? color : context.textSecondary) : (selected ? Colors.white : Colors.white.withValues(alpha: 0.7))`<br>Achieves **11.8:1 contrast** (selected) and **6.5:1** (unselected) in Light Mode. |
| **DEF-03** | `flutter_app/lib/screens/home/budget_management_screen.dart:669-672` | "Record Prior Spend" dialog save button | `backgroundColor: context.electricTeal`<br>`foregroundColor: Colors.black` (**1.2:1** in Light Mode) | `backgroundColor: context.primaryButtonBg`<br>`foregroundColor: context.primaryButtonFg`<br>Achieves **11.8:1 contrast** in Light Mode and **6.75:1** in Dark Mode. |
| **DEF-04** | `flutter_app/lib/screens/scanner/receipt_scanner_sheet.dart:1547-1549` | Camera permission error card "Try Again" button | `OutlinedButton.styleFrom(foregroundColor: Colors.white)` (**1.1:1** in Light Mode) | `foregroundColor: context.textPrimary`<br>Achieves **12.1:1 contrast** in Light Mode and **15.5:1** in Dark Mode. |
| **DEF-05** | `flutter_app/lib/widgets/simulator/affordability_simulator_sheet.dart:654-656` | "Record Expense" action button | `backgroundColor: context.cardBg`<br>`foregroundColor: AppThemes.success`<br>`side: BorderSide(color: AppThemes.success)` (**1.9:1** on white in Light Mode) | `backgroundColor: context.cardBg`<br>`foregroundColor: context.successText`<br>`side: BorderSide(color: context.successText)`<br>Achieves **7.8:1 contrast** in Light Mode (`#065F46` on white) and **8.5:1** in Dark Mode. |
| **DEF-06** | `flutter_app/lib/screens/analytics/grocery_price_intelligence_screen.dart:78, 313, 319` | Top AppBar basket icon & "Cheapest" label | `color: AppThemes.success` on `scaffoldBg` & white cards (**1.9:1** in Light Mode) | Migrate to `context.successText`<br>Achieves **7.8:1 contrast** in Light Mode. |
| **DEF-07** | `receipt_scanner_sheet.dart:426, 1226`, `multi_page_receipt_scanner_screen.dart:251`, `chat_entry_screen.dart:736` | Sheet header icons & ZATCA scanner icons on light surfaces | `color: AppThemes.success` (**1.9:1** in Light Mode) | Migrate to `context.successText`<br>Achieves **7.8:1 contrast** in Light Mode. |

---

## 3. Test-Driven Verification Strategy

1. **New Automated Test Suite:**
   Add tests in `flutter_app/test/theme/deep_theme_semantic_test.dart` to verify:
   - `ToolsScreen` tool pucks contrast >= 4.5:1 in Light and Dark modes.
   - `HouseholdTypeChooser` pucks contrast >= 4.5:1 in Light and Dark modes (both selected and unselected).
   - `BudgetManagementScreen` prior spend dialog button contrast >= 4.5:1.
   - `ReceiptScannerSheet` "Try Again" button contrast >= 4.5:1 in Light and Dark modes.
   - `AffordabilitySimulatorSheet` record expense button contrast >= 4.5:1 in Light Mode.
   - `GroceryPriceIntelligenceScreen` cheapest tag and basket button contrast >= 4.5:1.
2. **Multi-Round Review Pipeline:**
   - Round 1 (Claude Opus 5.5 High): Spec fidelity against this plan.
   - Round 2 (Claude Opus 5.5 High Adversarial): Break-testing dynamic theme toggle, extreme text scaling (1.75x–2.0x), and RTL layout.
   - Round 3 (Fable High Sensitive Audit): Invariants verification.
3. **Release Compilation:**
   - Compile fresh release APKs via `flutter build apk --split-per-abi`.
