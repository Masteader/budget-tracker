# Implementation Plan: Rename Nafaqah to Wife Expenses (UI, Web & Documentation)

Renaming all user-facing instances of the term "Nafaqah" (and its Arabic "النفقة" / Urdu "نفقہ" equivalents) across the Flutter mobile app, Web app, and documentation to "Wife Expenses" (Arabic: "مصاريف الزوجة", Urdu: "اہلیہ کے اخراجات"), keeping internal database columns and API endpoints intact.

## Proposed Changes

### Flutter Mobile App

#### [app_localizations.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/l10n/app_localizations.dart)
Update English, Arabic, and Urdu localization maps:
- `partner_settlement_desc`: 'Shared living debts or wife expense reimbursement ledger.'
- `family_nafaqah_title`: 'Family & Wife Expenses'
- `family_nafaqah_subtitle`: 'Husband maintenance responsibility & wife expenses'
- `all_nafaqah_settled`: 'All wife expenses are settled'
- `household_model_family`: 'Family (Wife Expenses)'
- `nafaqah_me_hint`: 'Husband covers family expenses (Wife owes 0 debt).'
- `nafaqah_banner_husband`: 'Household expense: husband\'s responsibility, no debt.'
- `psc_family_household`: 'Household (husband): {amount}'
- `wife_spouse_desc`: 'Can advance household expenses & receive expense reimbursements.'
- `faq_household_a1`: Update reference from "(see 'Nafaqah & the wife's allowance')" to "(see 'Wife expenses & allowance')".
- `nafaqah_no_wife_configured_title`: 'No Wife Role Configured'
- `nafaqah_no_wife_configured_desc`: 'To track wife personal allowances and expense reimbursements, assign a wife role in Household & Membership above.'
- `settle_nafaqah_all_settled`: 'All wife expenses are settled! Wife has no pending household reimbursements.'
- `settle_nafaqah_note`: 'Wife Expense Reimbursement - SAR {amount}'
- `nafaqah_reimbursement_note`: 'Wife Expense Reimbursement - SAR {amount}'
- `wt5_title`: 'Wife expenses, allowance & roommate settling'
- `rid_spouse_desc`: 'Family household: husband provides family necessities, wife reimbursed for advanced expenses.'
- `faq_cat_nafaqah`: 'Wife expenses & personal allowance'
- `faq_nafaqah_q1`: 'Who covers the household\'s expenses?'
- `faq_nafaqah_a1`: 'In a family household, household maintenance is the husband\'s responsibility: housing, food, clothing, and the children\'s needs. The app never splits an expense between husband and wife. Whatever the husband pays for the home is an ordinary household expense, not a debt to anyone.'
- Provider role labels:
  - `household_roles_nafaqah_provider_badge`: 'Household provider (husband)'
  - `household_roles_nafaqah_provider_dialog_title`: 'Who is the household provider (husband)?'
  - `household_roles_nafaqah_provider_updated`: 'Household provider updated'
  - `household_roles_nafaqah_provider_admin_only`: 'Only a household admin can choose the household provider.'
  - `household_roles_nafaqah_provider_ineligible`: 'That member cannot be the household provider (a wife, or no longer in the household).'
  - `household_roles_nafaqah_provider_missing_banner`: 'This family has no household provider (husband). Choose one so that expenses the wife pays can be recorded.'
  - `household_roles_nafaqah_provider_not_set`: 'This family has no household provider (husband). Ask an admin to set one.'
  - `household_roles_nafaqah_provider_choose_in_settings`: 'This family has no household provider (husband). Choose one in Settings, under Members & Admins.'
  - `household_setup_nafaqah_provider_button`: 'Choose who provides (household maintenance)'
  - `household_setup_nafaqah_provider_header`: 'Household Provider'
  - `household_setup_nafaqah_provider_description`: 'Choose which household member is responsible for household maintenance.'
- Arabic and Urdu equivalents for all keys above.

#### Flutter Tests
Update test assertions in the following files to match the new string values:
- `flutter_app/test/widgets/user_guide_walkthrough_test.dart`
- `flutter_app/test/widgets/app_setup_tutor_dialog_test.dart`
- `flutter_app/test/widgets/card_error_states_test.dart`
- `flutter_app/test/widgets/edit_transaction_sheet_test.dart`
- `flutter_app/test/widgets/family_reimbursement_card_test.dart`
- `flutter_app/test/widgets/household_roles_card_test.dart`
- `flutter_app/test/widgets/household_setup_card_test.dart`
- `flutter_app/test/widgets/household_type_and_roles_card_test.dart`
- `flutter_app/test/widgets/partner_settlement_card_test.dart`
- `flutter_app/test/services/nafaqah_write_errors_test.dart`

---

### Web App

#### [translations.ts](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/web_app/src/i18n/translations.ts)
- Replace English and Arabic copies of "Nafaqah" with "Wife Expenses" and "مصاريف الزوجة".
- Update navigation links, section title, descriptions, cases, and FAQs.

#### [NewTransactionModal.tsx](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/web_app/src/components/portal/NewTransactionModal.tsx)
- Change category prompt: `lang === 'ar' ? 'تصنيف مصاريف الزوجة (اختياري)' : 'Wife Expense Category (Optional)'`.

#### [BudgetsView.tsx](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/web_app/src/components/portal/BudgetsView.tsx)
- Change tooltip: "Personal expenses are deducted from this allowance according to family expense rules."

---

### Documentation & Agent Rules

- Update user-facing naming in `AGENTS.md`, `GEMINI.md`, `README.md`, and `.agents/rules/` to refer to "Wife expenses / family maintenance (Nafaqah)" preserving backend context while removing "Nafaqah" from all user-facing product descriptions.

---

## Verification Plan

### Automated Tests
1. **Flutter Analysis**:
   ```powershell
   cd flutter_app
   flutter analyze
   ```
2. **Flutter Widget Tests**:
   ```powershell
   cd flutter_app
   flutter test test/widgets/user_guide_walkthrough_test.dart
   flutter test test/widgets/household_roles_card_test.dart
   flutter test test/widgets/family_reimbursement_card_test.dart
   flutter test test/widgets/household_type_and_roles_card_test.dart
   flutter test test/widgets/card_error_states_test.dart
   flutter test test/widgets/partner_settlement_card_test.dart
   flutter test test/services/nafaqah_write_errors_test.dart
   ```
3. **Web App Build & Lint**:
   ```powershell
   cd web_app
   npm run lint
   npm run build
   ```
4. **Git Diff Audit**:
   Confirm no SQL migrations or backend endpoints (`/households/{id}/nafaqah`) were modified.

