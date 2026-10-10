# Multilingual Engine, Theming System, AI Support Agent Fix & Smart Savings Reserve Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the AI support chat repetitive fallback bug using LiteLLM, introduce full multilingual support (English, Arabic, Urdu with chat overrides), build dynamic theming (System/Light/Dark), and implement hybrid smart salary income tracking with an automated savings reserve.

**Architecture:** 
1. Backend AI service refactored to use `litellm` for support chat with language parameter, history management, and multi-lingual error fallbacks.
2. Flutter `ThemeProvider` managing `ThemeMode.system|light|dark` with emerald-accented light and dark palettes.
3. Flutter `LocaleProvider` providing English, Arabic, and Urdu with RTL support and independent session language override pills for Support Chat and Bill Entry.
4. Supabase schema + FastAPI endpoints for household monthly income, coupled with a real-time Savings Reserve gauge and deficit overdraft safety net in the Flutter app.

**Tech Stack:** Python 3.11+, FastAPI, LiteLLM, Flutter 3.22+, Provider, SharedPreferences, Supabase PostgreSQL.

**Spec:** [`docs/superpowers/specs/2026-10-10-multilingual-theming-support-and-savings-design.md`](file:///c:/Users/A/OneDrive/Python%20projects/budget-tracker/docs/superpowers/specs/2026-10-10-multilingual-theming-support-and-savings-design.md)

## Global Constraints
- Target platform: Windows / Android / iOS via Flutter.
- Strict test execution: Backend tests via `$env:PYTHONPATH="."; .\venv\Scripts\pytest tests/test_support_agent.py`, Flutter tests via `flutter test`.
- Preservation of existing styles and behavior: Dark theme retains emerald `#00C896` / `#0D1117` aesthetic.
- Zero SMS permissions policy preserved.

---

### Task 1: Fix AI Support Agent via LiteLLM & Add Multilingual Prompting

**Files:**
- Modify: `ai_service/support_agent.py`
- Modify: `ai_service/main.py:901-920`
- Modify: `ai_service/models.py:210-230`
- Test: `ai_service/tests/test_support_agent.py`

**Interfaces:**
- Consumes: `SupportChatRequest(message: str, household_id: Optional[str], user_id: Optional[str], history: Optional[List[Dict[str, str]]], language: Optional[str] = "ar")`
- Produces: `SupportChatResponse(reply: str, escalate_to_developer: bool, summary: Optional[str], support_email: str)`

- [ ] **Step 1: Write failing/updated unit tests for multilingual support agent**

In `ai_service/tests/test_support_agent.py`:
Add tests for English, Arabic, and Urdu queries, mocking `litellm.completion` to verify that `litellm` is called with appropriate system prompt and messages.

- [ ] **Step 2: Run tests to verify failure**

Run: `cd ai_service; $env:PYTHONPATH="."; .\venv\Scripts\pytest tests/test_support_agent.py`

- [ ] **Step 3: Refactor `support_agent.py` to use LiteLLM**

Replace `google.genai` with `litellm.completion(model=os.environ.get("LITELLM_MODEL", "gemini/gemini-2.0-flash"), messages=...)`. Include conversation history, respect `language` parameter ("ar", "en", "ur"), log errors properly with `logger.error`, and supply localized fallback messages.

- [ ] **Step 4: Update `models.py` and `main.py`**

Add `language: Optional[str] = "ar"` to `SupportChatRequest` in `models.py` and pass it to `handle_support_query`.

- [ ] **Step 5: Run tests to verify PASS**

Run: `cd ai_service; $env:PYTHONPATH="."; .\venv\Scripts\pytest tests/test_support_agent.py`
Expected: PASS (All tests green).

- [ ] **Step 6: Commit**

```bash
git add ai_service/
git commit -m "fix(ai_service): replace google.genai with litellm and add multilingual support in support_agent"
```

---

### Task 2: Implement Flutter Theming Engine (System, Light, Dark)

**Files:**
- Create: `flutter_app/lib/providers/theme_provider.dart`
- Create: `flutter_app/lib/theme/app_themes.dart`
- Modify: `flutter_app/lib/main.dart:40-100`
- Modify: `flutter_app/lib/screens/settings/ingestion_settings_screen.dart`
- Test: `flutter_app/test/providers/theme_provider_test.dart`

**Interfaces:**
- Produces: `ThemeProvider` with `ThemeMode themeMode`, `setThemeMode(ThemeMode mode)`
- Produces: `AppThemes.darkTheme`, `AppThemes.lightTheme`

- [ ] **Step 1: Write unit test for `ThemeProvider`**

Create `flutter_app/test/providers/theme_provider_test.dart` verifying initial mode, persistence, and state notification.

- [ ] **Step 2: Implement `AppThemes` and `ThemeProvider`**

1. Create `flutter_app/lib/theme/app_themes.dart` defining `lightTheme` and `darkTheme` matching the design specification.
2. Create `flutter_app/lib/providers/theme_provider.dart` with `SharedPreferences` persistence (`theme_mode`).

- [ ] **Step 3: Wire `ThemeProvider` into `main.dart`**

Add `ChangeNotifierProvider(create: (_) => ThemeProvider()..init())` to `MultiProvider` and bind `MaterialApp` to `themeProvider.themeMode`, `theme: AppThemes.lightTheme`, and `darkTheme: AppThemes.darkTheme`.

- [ ] **Step 4: Add Theme switcher to `IngestionSettingsScreen`**

Add an "Appearance" card in the settings screen providing a 3-way toggle for `System`, `Light`, and `Dark`.

- [ ] **Step 5: Run tests and verify**

Run: `cd flutter_app; flutter test test/providers/theme_provider_test.dart`

- [ ] **Step 6: Commit**

```bash
git add flutter_app/
git commit -m "feat(flutter): implement dynamic theming with System, Light, and Dark modes"
```

---

### Task 3: Implement Multilingual Engine (Arabic, English, Urdu) with Independent Chat Overrides

**Files:**
- Create: `flutter_app/lib/providers/locale_provider.dart`
- Create: `flutter_app/lib/l10n/app_localizations.dart`
- Modify: `flutter_app/lib/main.dart`
- Modify: `flutter_app/lib/services/api/support_api_client.dart`
- Modify: `flutter_app/lib/screens/settings/help_support_screen.dart`
- Modify: `flutter_app/lib/screens/chat/chat_entry_screen.dart`
- Modify: `flutter_app/lib/screens/settings/ingestion_settings_screen.dart`
- Test: `flutter_app/test/providers/locale_provider_test.dart`

**Interfaces:**
- Produces: `LocaleProvider` with `Locale currentLocale`, `setLocale(Locale)`
- Produces: `AppLocalizations` strings for `en`, `ar`, and `ur`.
- Consumes: Independent language override pills in `HelpSupportScreen` and `ChatEntryScreen`.

- [ ] **Step 1: Write unit test for `LocaleProvider`**

Test default locale, updating locale, and persistence in `SharedPreferences`.

- [ ] **Step 2: Implement `AppLocalizations` & `LocaleProvider`**

Create `AppLocalizations` with dictionary translations across Arabic, English, and Urdu. Configure RTL text direction support.

- [ ] **Step 3: Wire `LocaleProvider` into `main.dart`**

Add `LocaleProvider` to `MultiProvider`. Set `locale: localeProvider.currentLocale`, `supportedLocales`, and `localizationsDelegates` on `MaterialApp`.

- [ ] **Step 4: Update `HelpSupportScreen` & `ChatEntryScreen` Language Pills**

1. In `HelpSupportScreen`: Add an independent language pill in the AppBar: `[🇸🇦 ع | 🇺🇸 EN | 🇵🇰 اردو]`. Pass `language: _selectedLanguage` to `postSupportChat`.
2. In `ChatEntryScreen`: Update the top pill to 3-way `[🇸🇦 ع | 🇺🇸 EN | 🇵🇰 اردو]`.
3. In `IngestionSettingsScreen`: Add App Language selection dropdown/tile (`English`, `العربية`, `اردو`).

- [ ] **Step 5: Run tests**

Run: `cd flutter_app; flutter test test/providers/locale_provider_test.dart`

- [ ] **Step 6: Commit**

```bash
git add flutter_app/
git commit -m "feat(flutter): add multilingual engine (EN, AR, UR) and independent chat language toggles"
```

---

### Task 4: Implement Smart Salary / Income & Savings Reserve (Option C - Hybrid)

**Files:**
- Create: `supabase/migrations/20261010_add_household_monthly_income.sql`
- Modify: `ai_service/main.py`
- Modify: `flutter_app/lib/services/api/budget_api_client.dart`
- Modify: `flutter_app/lib/services/api_service.dart`
- Create: `flutter_app/lib/widgets/settings/income_settings_card.dart`
- Modify: `flutter_app/lib/screens/settings/ingestion_settings_screen.dart`
- Modify: `flutter_app/lib/screens/home/budget_management_screen.dart`
- Test: `flutter_app/test/widgets/income_settings_card_test.dart`

**Interfaces:**
- Consumes: `GET /households/{id}/income` and `POST /households/{id}/income`
- Produces: `IncomeSettingsCard` widget and real-time Savings Reserve calculation `max(0, income - totalAllocated)` in `BudgetManagementScreen`.

- [ ] **Step 1: Create Supabase SQL migration for `monthly_income`**

Add column `monthly_income NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (monthly_income >= 0)` to `public.households`.

- [ ] **Step 2: Add API endpoints in `ai_service/main.py`**

Implement `GET /households/{household_id}/income` and `POST /households/{household_id}/income`.

- [ ] **Step 3: Update `BudgetApiClient` & `ApiService`**

Add `fetchHouseholdIncome` and `updateHouseholdIncome` methods.

- [ ] **Step 4: Create `IncomeSettingsCard` and integrate into `IngestionSettingsScreen`**

Allow users to view and update monthly income with instant currency formatting.

- [ ] **Step 5: Integrate Savings Reserve gauge in `BudgetManagementScreen`**

Display total monthly income, total budget allocation, and the calculated **Savings Reserve** (`Income - Allocated`). If overallocated, show warning badge.

- [ ] **Step 6: Run tests and verify**

Run: `cd flutter_app; flutter test test/widgets/income_settings_card_test.dart`

- [ ] **Step 7: Commit**

```bash
git add supabase/ ai_service/ flutter_app/
git commit -m "feat: implement smart monthly income tracking and automated savings reserve"
```

---

### Task 5: End-to-End Verification and Regression Suite

**Files:**
- All touched files in Tasks 1–4.

- [ ] **Step 1: Run full Python AI service test suite**

Run: `cd ai_service; $env:PYTHONPATH="."; .\venv\Scripts\pytest`

- [ ] **Step 2: Run Flutter test suite**

Run: `cd flutter_app; flutter test`

- [ ] **Step 3: Final clean commit**

```bash
git commit --allow-empty -m "chore: completed multilingual, theming, support agent fix, and savings reserve implementation"
```
