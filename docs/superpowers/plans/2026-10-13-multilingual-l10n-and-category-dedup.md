# Implementation Plan: Multilingual (AR / UR / EN) Complete Localization & Category Deduplication

- **Proposed Date:** 2026-10-13
- **Branch:** `main`
- **Scope:** Complete Arabic, Urdu, and English localization across all app screens and widgets, fix dual item name display (display single language matching active locale), remove duplicate "تموينات" sub-category and clean up budget allocations.

---

## 1. Objectives

1. **Strict Single-Language Item Names:**
   - Eliminate all dual English + Arabic stacked text in sub-budget allocation dialog and other sheets.
   - If app language is Arabic (`ar`), display only Arabic name.
   - If Urdu (`ur`), display Urdu name (or Arabic/English fallback).
   - If English (`en`), display English name.
2. **Database & Catalog Deduplication:**
   - Delete duplicate `sub--------` ("تموينات") from `cost_control_sub_categories` in Supabase.
   - Reallocate any amounts in household `budgets.sub_allocations` from `sub--------` to `pantry_staples`.
   - Audit all standard categories and sub-categories to ensure clean, consistent naming.
3. **Comprehensive Multilingual Localization (EN, AR, UR):**
   - Expand `AppLocalizations` in `flutter_app/lib/l10n/app_localizations.dart` with extensive keys covering all screens:
     - Categories & Sub-categories dictionary.
     - Budget allocation dialogs & sub-budget breakdown sheets.
     - Dashboard summary, salary cycle bars, and financial cards.
     - Transaction feeds, filters, editing sheets, and attribution chips.
     - Receipt scanners, multi-shot flows, camera permission dialogs.
     - Settings, household dependents, income, payday, and help & support.
     - Grocery price intelligence & smart shopping basket.
4. **Verification & Delivery:**
   - All tests in `flutter test` passing (0 errors, 0 warnings).
   - Generate release ARM64 APKs (`BudgetTracker-v1.0.0-arm64.apk` and `v1.0.1`).
   - Git commit and push to `origin main`.

---

## 2. Proposed Changes

### Phase 1: Database & Catalog Deduplication
- Run cleanup script targeting Supabase:
  - Remove `sub--------` from `cost_control_sub_categories`.
  - In `budgets`, inspect `sub_allocations` for any category where `sub--------` is present, transfer amount to `pantry_staples`, and remove key `sub--------`.
  - Normalize default local catalog `kDefaultSubCategoriesCatalog` in `sub_budget_allocation_dialog.dart`.

### Phase 2: Category Localization Engine & AppLocalizations
- `flutter_app/lib/l10n/app_localizations.dart`:
  - Add translations for English, Arabic, and Urdu for all main categories:
    - `OPEX-GROCERY`: Groceries & Supermarkets / البقالة والتموينات / گروسری اور سپر مارکیٹ
    - `OPEX-DINING`: Dining & Cafes / المطاعم والمقاهي / ریسٹورینٹ اور کیفے
    - `OPEX-FUEL`: Fuel & Transport / الوقود والمواصلات / ایندھن اور ٹرانسپورٹ
    - `OPEX-UTILITIES`: Utilities & Bills / الفواتير والخدمات / یوٹیلیٹیز اور بلز
    - `OPEX-HEALTH`: Health & Pharmacy / الصحة والصيدلية / صحت اور فارمیسی
    - `OPEX-SHOPPING`: Shopping & Retail / التسوق والمشتريات / شاپنگ اور ریٹیل
    - `OPEX-ENTERTAINMENT`: Entertainment / الترفيه والأنشطة / تفریح اور سرگرمیاں
    - `CAPEX-EDUCATION`: Education / التعليم والرسوم / تعلیم اور فیس
    - `OPEX-GOV`: Government & Fees / الخدمات الحكومية والرسوم / حکومتی فیس اور خدمات
    - `OPEX-MISC`: Miscellaneous / مصاريف متنوعة / متفرق اخراجات
  - Add translations for all sub-categories (English, Arabic, Urdu).
  - Add helper `context.localizedCategory(codeOrName)` and `context.localizedSubCategory(parentCode, subCodeOrName)`.
  - Add missing UI strings across all screens (dialogs, cards, headers, buttons, alerts).

### Phase 3: Screen & Widget Upgrades (Single Language & Complete Strings)
- `widgets/sub_budget_allocation_dialog.dart`:
  - Fix lines 897–944: replace dual Text widgets with single localized title based on active locale.
  - Localize dialog header, total category budget card, buttons, add sub-category dialog, edit/delete prompts.
- `widgets/sub_budget_breakdown_sheet.dart`:
  - Localize header, base allocation, rollover surplus/overspend badges, transaction counts, empty states.
- `screens/home/budget_management_screen.dart` & `widgets/dashboard/category_budget_card.dart`:
  - Use localized category names and strings throughout cards, copy dialogs, and progress bars.
- `screens/home/dashboard_screen.dart`, `widgets/salary_cycle_widget.dart`, `widgets/dashboard/salary_cycle_selector_bar.dart`:
  - Localize salary cycle titles, days remaining, allowable daily, burn rate, action speed dial.
- `widgets/dashboard/recurring_bills_card.dart` & `widgets/dashboard/installment_plans_card.dart`:
  - Localize filter tabs, status badges, due dates, actions.
- `screens/home/transaction_feed_screen.dart` & `screens/home/edit_transaction_sheet.dart`:
  - Localize transaction filters, attribution pills, children chips, edit sheets, delete confirmations.
- `screens/scanner/receipt_scanner_sheet.dart` & `screens/scanner/multi_page_receipt_scanner_screen.dart`:
  - Localize scanner instructions, camera permission dialog, item breakdowns, merchant tags.
- `screens/settings/ingestion_settings_screen.dart` & all settings cards:
  - Localize cards (Income, Payday, Household Management, SMS patterns, Telegram, Help & Support).
- `screens/analytics/grocery_price_intelligence_screen.dart` & `widgets/analytics/smart_shopping_basket_sheet.dart`:
  - Localize price intelligence comparisons, basket quick suggestions, unit pricing, item strike-throughs.

### Phase 4: Testing & Analysis
- `flutter_app/test/services/app_localizations_test.dart`:
  - Test all new keys across English, Arabic, and Urdu.
  - Test single-language category and sub-category resolution.
- Run `flutter analyze` (target 0 errors, 0 warnings).
- Run `flutter test` (all 87+ tests pass).

### Phase 5: Production Build & Delivery
- Build ARM64 APK with release configuration.
- Copy to `BudgetTracker-v1.0.0-arm64.apk` and `BudgetTracker-v1.0.1-arm64.apk`.
- Commit and push to `origin main`.
