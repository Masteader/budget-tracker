# Design Spec: Multilingual Engine, Theming System, AI Support Agent Fix & Smart Savings Reserve

**Date:** 2026-10-10  
**Status:** Approved  
**Author:** AI Engineering & Pair Programming  

---

## 1. Executive Summary

This specification addresses four interconnected system capabilities:
1. **AI Support Assistant Fix:** Rectify the issue causing the `/support/chat` endpoint to always return a canned fallback greeting by standardizing on `litellm` (compatible with `gemini/gemini-2.0-flash`), capturing full chat history, supporting multi-turn dialogues, and providing detailed error logging.
2. **Multilingual Architecture (Arabic, English, Urdu):** Introduce full multilingual support across the Flutter app. General app UI adapts to the selected app language (English, Arabic, or Urdu) with automatic RTL/LTR layout mirroring and localized typography. Independently, the AI Support Chat and AI Bill Entry provide localized session overrides at the top of their respective screens, allowing users to converse in a different language than the global UI setting.
3. **Theme System (System Default, Light, Dark):** Introduce dynamic theming in Flutter via a dedicated `ThemeProvider`. Maintain the current high-contrast GitHub-Dark emerald aesthetic, while introducing a light mode palette with clean slate backgrounds (`#F8FAFC`), pure white cards (`#FFFFFF`), and refined emerald accents (`#00A87D`). Persist user choice in `SharedPreferences`.
4. **Smart Income Allocation & Savings Reserve (Option C - Hybrid):** Allow users to configure their Monthly Household Salary / Income in Settings alongside the payday date. In the Budget Management interface, compute and display the **Savings Reserve** (Income minus Total Allocated Budgets) in real time. Incorporate an overdraft safety net where deficits exceeding all flexible budgets can draw from the Savings Reserve buffer with clear audit attribution (`is_reallocated: true, reallocated_from: 'SAVINGS'`).

---

## 2. Technical Architecture & Component Design

### 2.1 Backend AI Support Agent Fix (`ai_service`)

#### Current Defect:
[`support_agent.py`](file:///c:/Users/A/OneDrive/Python%20projects/budget-tracker/ai_service/support_agent.py) attempts `from google import genai`, which is not included in [`requirements.txt`](file:///c:/Users/A/OneDrive/Python%20projects/budget-tracker/ai_service/requirements.txt). The import fails, triggering `except Exception: pass`, which leaves `reply` blank and causes the method to fall back to the fixed string:
```
أهلاً بك في تطبيق ميزانية الأسرة! يمكنك الاستفسار عن فواتيرك...
```

#### Architecture:
- Replace `google.genai` with `litellm.completion` using `os.environ.get("LITELLM_MODEL", "gemini/gemini-2.0-flash")`.
- Accept an optional `language: str = "ar"` field in `SupportChatRequest` (`ar`, `en`, `ur`).
- Format user history (`history: List[Dict[str, str]]`) directly into the `litellm` message array (`system`, `user`, `assistant` roles).
- If the LLM throws an exception, log the full traceback via `logger.error` and return a language-specific graceful error message with developer escalation info.

```
Flutter Client (HelpSupportScreen)
       │  POST /support/chat { message, language: "ar"|"en"|"ur", history }
       ▼
FastAPI support_chat() (main.py)
       │
       ▼
support_agent.py: handle_support_query()
       │
       ├─► litellm.completion(model="gemini/gemini-2.0-flash", messages=[...])
       │       │
       │       ▼ (Parses [ESCALATE: TRUE|FALSE] & [SUMMARY: ...])
       ▼
Response: SupportChatResponse(reply, escalate_to_developer, summary, support_email)
```

---

### 2.2 Multilingual Engine (Arabic, English, Urdu)

#### App-Wide Localization:
- **Languages Supported:**
  - `en`: English (LTR)
  - `ar`: Arabic (RTL, Saudi dialect friendly)
  - `ur`: Urdu (RTL, Urdu Nastaliq/Arabic script friendly)
- **`LocaleProvider`:**
  - Exposes `Locale currentLocale`.
  - Methods: `setLocale(Locale locale)`.
  - Stored in `SharedPreferences` with key `app_language_code` (`'en'`, `'ar'`, `'ur'`). Defaults to `WidgetsBinding.instance.platformDispatcher.locale` if supported, else `'en'`.
- **Localization Dictionary:**
  - Create a structured `AppLocalizations` helper providing keys for dashboard, navigation, settings, transactions, budgets, and dialogues across `en`, `ar`, and `ur`.
- **RTL / Typography Handling:**
  - `MaterialApp` configured with `supportedLocales`, `localizationsDelegates` (`GlobalMaterialLocalizations`, `GlobalWidgetsLocalizations`, `GlobalCupertinoLocalizations`).
  - Google Fonts: Dynamically switch or combine font fallbacks (`GoogleFonts.outfit` for Latin, `GoogleFonts.cairo` for Arabic and Urdu) so RTL glyphs render without truncation.

#### Independent Session Overrides:
- **`HelpSupportScreen`:**
  - Add top AppBar language selector toggle pill `[🇸🇦 ع | 🇺🇸 EN | 🇵🇰 اردو]`.
  - Initializes to `localeProvider.currentLocale.languageCode`, but switching updates a local state `_selectedLanguage` for this chat session only.
  - Sends `language: _selectedLanguage` to `ApiService.instance.support.postSupportChat`.
- **`ChatEntryScreen`:**
  - Update top AppBar toggle pill to include Urdu: `[🇸🇦 ع | 🇺🇸 EN | 🇵🇰 اردو]`.
  - Sends language to `/agent/chat-transaction` / `ChatApiClient`.

---

### 2.3 Theming System (System Default, Light, Dark)

#### Architecture:
- **`ThemeProvider`:**
  - Exposes `ThemeMode themeMode` (`ThemeMode.system`, `ThemeMode.light`, `ThemeMode.dark`).
  - Method: `setThemeMode(ThemeMode mode)`.
  - Stored in `SharedPreferences` with key `app_theme_mode` (`'system'`, `'light'`, `'dark'`).
- **`AppThemes` Specification:**
  - **Dark Theme (Default):**
    - Scaffold background: `#0D1117`
    - Card color: `#161B22`
    - Primary accent: `#00C896` (Emerald)
    - Border / Divider: `#30363D`
    - Text: Primary `#FFFFFF`, Secondary `#8B949E`
  - **Light Theme:**
    - Scaffold background: `#F8FAFC` (Slate 50)
    - Card color: `#FFFFFF` (Pure white)
    - Primary accent: `#00A87D` (Slightly darker emerald for contrast on white)
    - Border / Divider: `#E2E8F0` (Slate 200)
    - Text: Primary `#0F172A` (Slate 900), Secondary `#64748B` (Slate 500)
- **Settings UI (`IngestionSettingsScreen`):**
  - Add an "App Appearance" card with a 3-segment switcher `[ Auto (System) | Light | Dark ]`.

---

### 2.4 Smart Income & Savings Reserve (Option C - Hybrid)

#### Database Schema:
- Add `monthly_income NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (monthly_income >= 0)` to `public.households`.
- SQL Migration: `supabase/migrations/20261010_add_household_monthly_income.sql`.

#### Backend / API:
- FastAPI endpoints in [`ai_service/main.py`](file:///c:/Users/A/OneDrive/Python%20projects/budget-tracker/ai_service/main.py):
  - `GET /households/{household_id}/income` -> `{ "household_id": ..., "monthly_income": 15000.0 }`
  - `POST /households/{household_id}/income` with payload `{ "monthly_income": 15000.0 }` -> updates DB and returns status.
- `BudgetApiClient` & `ApiService` methods:
  - `fetchHouseholdIncome(String householdId)`
  - `updateHouseholdIncome(String householdId, double income)`

#### UI / UX Workflow:
1. **Settings Screen (`IngestionSettingsScreen`):**
   - Enhance the payday card or add a companion `HouseholdIncomeCard` allowing users to view and update their monthly salary/income with instant currency formatting (e.g. `15,000 SAR`).
2. **Budget Management Screen (`BudgetManagementScreen`):**
   - Income & Savings Reserve Banner:
     - Shows `Total Income`, `Total Budgeted`, and `Savings Reserve` (`Income - Budgeted`).
     - If `Total Budgeted <= Income`: Displays green positive indicator: `"Savings Reserve: +3,500.00 SAR"`.
     - If `Total Budgeted > Income`: Displays amber/red indicator: `"Overallocated: -500.00 SAR"`.
3. **Deficit Cascade:**
   - When all flexible category budgets are exhausted during expense reallocation, the system attributes remaining deficit to the Household Savings Reserve (`reallocated_from: 'SAVINGS'`).

---

## 3. Verification & Testing Strategy

1. **Python AI Service:**
   - Unit tests in `ai_service/tests/test_support_agent.py` covering:
     - LLM generation in English, Arabic, and Urdu.
     - Fallback error handling when LLM fails without crashing.
     - Escalation detection keywords across English and Arabic.
2. **Flutter Unit & Widget Tests:**
   - `test/providers/theme_provider_test.dart`: Theme switching and persistence.
   - `test/providers/locale_provider_test.dart`: Locale switching and persistence.
   - `test/screens/help_support_screen_test.dart`: Language override pill rendering, multilingual messaging, and API payload verification.
   - `test/widgets/income_settings_card_test.dart`: Editing and saving monthly household income.
