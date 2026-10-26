# AI Chat Scoping, Anti-Chit-Chat Guardrails & Interactive Setup Tutor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restrict AI entry chat strictly to financial transactions, affordability simulations, and app support with a 3-strike/15-minute cooldown and developer email notification, support direct in-chat app explanation with navigation action buttons, and replace the generic walkthrough with a forceful 5-stage interactive App Setup Tutor.

**Architecture:** 
- In `ai_service`: add intent classification (`transaction`, `simulation_or_app_help`, `off_topic`), track strikes per user in Redis/memory sliding window, issue 15-minute lockout on Strike 3, log audit details and email `fmscoinfo@fmsco.com.sa`, and route app guidance queries to `support_agent` returning `status: "app_guidance"` with structured action descriptors.
- In `flutter_app`: render live lockout countdown timer and disable inputs in `ChatEntryScreen`, render interactive action buttons below guidance messages, and build `AppSetupTutorDialog` with 5 actionable setup stages forcefully presented on first-run and available in Settings.

**Tech Stack:** Python FastAPI, LiteLLM, Redis / in-memory rate limiting, Flutter Dart, Provider, Supabase PostgreSQL, Velvet Burgundy Design Tokens.

**Spec:** [`docs/superpowers/specs/2026-10-26-ai-chat-scoping-and-app-tutor-design.md`](file:///c:/Users/A/OneDrive/Python%20projects/budget-tracker/docs/superpowers/specs/2026-10-26-ai-chat-scoping-and-app-tutor-design.md)

## Global Constraints
- Main branch protection: work strictly on branch `feat/ai-chat-guardrails-and-setup-tutor`.
- Strict trilingual localization: zero hardcoded strings (`ui_l10n_guard_test.dart` must pass 100%).
- All test suites green: zero `flutter analyze` errors, `flutter test` passes, `pytest -v` passes.
- Zero SMS permissions and Islamic Nafaqah compliance maintained.

---

### Task 1: AI Service Off-Topic Classification, 3-Strike Warning, and 15-Minute Lockout

**Files:**
- Create: `ai_service/tests/test_chat_scoping.py`
- Modify: `ai_service/chat_parser.py`
- Modify: `ai_service/routes/chat.py`
- Modify: `ai_service/rate_limiter.py`

**Interfaces:**
- Produces: `chat_transaction()` handling for `off_topic` intent returning `status: "off_topic_warning"` (strikes 1-2) or HTTP 429 `code: "chat_locked_out"` with `retry_after_seconds` (strike 3).

- [ ] **Step 1: Write failing test for off-topic detection and 3-strike lockout**

In `ai_service/tests/test_chat_scoping.py`:
```python
import pytest
from unittest.mock import patch, AsyncMock
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_off_topic_message_triggers_strike_warning():
    with patch("auth.get_current_user_id", return_value="u-test-scope"), \
         patch("auth.verify_household_access", new_callable=AsyncMock):
        # First off-topic message
        res = client.post(
            "/agent/chat-transaction",
            json={"message": "tell me a bedtime story about dragons", "household_id": "00000000-0000-0000-0000-000000000001"},
            headers={"Authorization": "Bearer mock-token"},
        )
        assert res.status_code == 200
        data = res.json()
        assert data.get("status") == "off_topic_warning"
        assert data.get("strikes") == 1
        assert "warning" in data.get("message", "").lower() or "مخصص" in data.get("message", "")
```

- [ ] **Step 2: Run test to verify failure**

Run: `pytest tests/test_chat_scoping.py -v`  
Expected: FAIL (missing `off_topic_warning` status).

- [ ] **Step 3: Implement intent classification and strike tracking**

In `ai_service/chat_parser.py`:
- Update `ParsedChatExpense` to include `intent: str = Field("transaction", description="'transaction' | 'app_guidance' | 'off_topic'")`.
- In `parse_chat_message()`, instruct the LLM to classify casual non-financial banter as `off_topic`.
- In `ai_service/rate_limiter.py`, add `record_offtopic_strike(user_id: str) -> tuple[int, bool, int]` returning `(current_strikes, is_locked, retry_after)`.
- In `ai_service/routes/chat.py`, verify lockout before parsing, and record strike if intent is `off_topic`.

- [ ] **Step 4: Re-run test to verify it passes**

Run: `pytest tests/test_chat_scoping.py -v`  
Expected: PASS.

- [ ] **Step 5: Commit Task 1**

```bash
git add ai_service/chat_parser.py ai_service/routes/chat.py ai_service/rate_limiter.py ai_service/tests/test_chat_scoping.py
git commit -m "feat(ai): add intent classification and 3-strike 15-minute chat lockout"
```

---

### Task 2: AI Service Developer Violation Logging and Email Alert

**Files:**
- Create: `ai_service/tests/test_chat_scoping_notification.py`
- Modify: `ai_service/routes/chat.py`
- Modify: `ai_service/rate_limiter.py`

**Interfaces:**
- Consumes: Strike 3 trigger from `record_offtopic_strike()`.
- Produces: Asynchronous trigger of `mail_service.send_email` to `SUPPORT_EMAIL = "fmscoinfo@fmsco.com.sa"` with user email, UUID, and offending messages.

- [ ] **Step 1: Write failing test for developer email dispatch on Strike 3 lockout**

In `ai_service/tests/test_chat_scoping_notification.py`:
```python
from unittest.mock import patch, AsyncMock
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_strike_three_dispatches_developer_notification():
    with patch("auth.get_current_user_id", return_value="u-test-lockout"), \
         patch("auth.get_verified_claims", return_value={"sub": "u-test-lockout", "email": "violator@example.com"}), \
         patch("auth.verify_household_access", new_callable=AsyncMock), \
         patch("mail_service.send_email", new_callable=AsyncMock) as mock_send:
        # Simulate strikes 1, 2, 3
        for i in range(3):
            res = client.post(
                "/agent/chat-transaction",
                json={"message": f"write python code #{i}", "household_id": "00000000-0000-0000-0000-000000000001"},
                headers={"Authorization": "Bearer mock-token"},
            )
        assert res.status_code == 429
        assert res.json()["detail"]["code"] == "chat_locked_out"
        mock_send.assert_called_once()
```

- [ ] **Step 2: Run test to verify failure**

Run: `pytest tests/test_chat_scoping_notification.py -v`  
Expected: FAIL (missing mock_send invocation).

- [ ] **Step 3: Implement developer alert email on lockout**

In `ai_service/routes/chat.py`:
When `is_locked` is triggered on strike 3:
- Retrieve user email from `get_verified_claims(request)`.
- Schedule `asyncio.create_task(notify_developer_of_lockout(user_id, email, messages))`.

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_chat_scoping_notification.py -v`  
Expected: PASS.

- [ ] **Step 5: Commit Task 2**

```bash
git add ai_service/routes/chat.py ai_service/rate_limiter.py ai_service/tests/test_chat_scoping_notification.py
git commit -m "feat(ai): notify developer via email on user chat lockout violation"
```

---

### Task 3: AI Service In-Chat App Guidance Intent & Action Descriptors

**Files:**
- Create: `ai_service/tests/test_chat_app_guidance.py`
- Modify: `ai_service/chat_parser.py`
- Modify: `ai_service/routes/chat.py`

**Interfaces:**
- Produces: Response with `status: "app_guidance"`, `message: str`, and `actions: list[dict]`.

- [ ] **Step 1: Write failing test for app guidance intent**

In `ai_service/tests/test_chat_app_guidance.py`:
```python
from unittest.mock import patch, AsyncMock
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_app_guidance_query_returns_guidance_and_actions():
    with patch("auth.get_current_user_id", return_value="u-test-guide"), \
         patch("auth.verify_household_access", new_callable=AsyncMock), \
         patch("support_agent.handle_support_query", return_value=("لإعداد الميزانية انتقل لإدارة الميزانيات", False, "NONE")):
        res = client.post(
            "/agent/chat-transaction",
            json={"message": "كيف أسوي ميزانية الشهر؟", "household_id": "00000000-0000-0000-0000-000000000001"},
            headers={"Authorization": "Bearer mock-token"},
        )
        assert res.status_code == 200
        data = res.json()
        assert data.get("status") == "app_guidance"
        assert len(data.get("actions", [])) > 0
        action_names = [a["action"] for a in data["actions"]]
        assert "open_budgets" in action_names or "open_tutor" in action_names
```

- [ ] **Step 2: Run test to verify failure**

Run: `pytest tests/test_chat_app_guidance.py -v`  
Expected: FAIL.

- [ ] **Step 3: Implement guidance routing and action mapping**

In `chat_parser.py` and `routes/chat.py`:
- Detect when intent is `app_guidance`.
- Invoke `support_agent.handle_support_query()`.
- Attach structured action descriptors mapping keywords (`budget` -> `open_budgets`, `payday` -> `open_payday`, `account`/`saving` -> `open_accounts`, `nafaqah`/`roommate` -> `open_roles`, plus `open_tutor`).

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_chat_app_guidance.py -v`  
Expected: PASS.

- [ ] **Step 5: Commit Task 3**

```bash
git add ai_service/chat_parser.py ai_service/routes/chat.py ai_service/tests/test_chat_app_guidance.py
git commit -m "feat(ai): support in-chat app guidance with structured action descriptors"
```

---

### Task 4: Flutter Trilingual Localizations

**Files:**
- Modify: `flutter_app/lib/l10n/app_localizations.dart`
- Test: `flutter_app/test/ui_l10n_guard_test.dart`

**Interfaces:**
- Produces: Localized keys for chat warnings, lockouts, action buttons, and tutor stages in English, Arabic, and Urdu.

- [ ] **Step 1: Add translation keys across EN, AR, and UR**

Add keys:
- `chat_offtopic_warning`: Strike warning message with `{strike}` and `{max}`.
- `chat_locked_out_banner`: Lockout message with `{time}` countdown.
- `chat_action_open_tutor`: "Launch Setup Tutor" / "بدء جولة الإعداد" / "سیٹ اپ ٹیوٹر شروع کریں"
- `chat_action_open_payday`: "Payday Settings" / "إعدادات يوم الراتب" / "تنخواہ کی ترتیبات"
- `chat_action_open_budgets`: "Manage Envelopes" / "إدارة الميزانيات" / "بجٹ کا انتظام کریں"
- `chat_action_open_accounts`: "Add Bank / Savings" / "إضافة حساب / ادخار" / "بینک / بچت کھاتہ شامل کریں"
- `chat_action_open_roles`: "Household Mode" / "نظام السكن" / "گھریلو نظام"
- `tutor_stage_1_title` through `tutor_stage_5_desc`: Titles, concepts, and button labels for the 5-stage setup sequence.

- [ ] **Step 2: Run localization guard test**

Run: `flutter test test/ui_l10n_guard_test.dart`  
Expected: PASS (all keys symmetric, valid Arabic/Urdu scripts, no hardcoded strings).

- [ ] **Step 3: Commit Task 4**

```bash
git add flutter_app/lib/l10n/app_localizations.dart
git commit -m "feat(l10n): add trilingual keys for chat lockout, app guidance actions, and setup tutor"
```

---

### Task 5: Flutter Chat Lockout Countdown and Interactive Action Pills in `ChatEntryScreen`

**Files:**
- Modify: `flutter_app/lib/screens/chat/chat_entry_screen.dart`
- Create: `flutter_app/test/widgets/chat_guidance_actions_test.dart`
- Create: `flutter_app/test/widgets/chat_lockout_test.dart`

**Interfaces:**
- Consumes: `status == "app_guidance"` with `actions`, and HTTP 429 `chat_locked_out`.
- Produces: In-chat action button pills and live lockout timer banner disabling chat input.

- [ ] **Step 1: Write widget tests for guidance action buttons and lockout banner**

In `flutter_app/test/widgets/chat_guidance_actions_test.dart` and `chat_lockout_test.dart`:
- Verify action buttons render when status is `app_guidance` and trigger navigation callbacks.
- Verify lockout countdown timer renders and disables input textfield when locked out.

- [ ] **Step 2: Run tests to verify failure**

Run: `flutter test test/widgets/chat_guidance_actions_test.dart test/widgets/chat_lockout_test.dart`  
Expected: FAIL.

- [ ] **Step 3: Implement guidance actions and lockout banner in `ChatEntryScreen`**

In `flutter_app/lib/screens/chat/chat_entry_screen.dart`:
- Add `_lockoutSecondsRemaining` state and `Timer` countdown.
- Disable input field and mic button when `_lockoutSecondsRemaining > 0`, rendering top lockout banner.
- Handle `status == 'app_guidance'`: render assistant bubble and action pill wrap.
- Implement action pill router:
  - `open_tutor` -> `AppSetupTutorDialog.show(context)`
  - `open_budgets` -> `Navigator.push(BudgetManagementScreen)`
  - `open_accounts` -> `Navigator.push(AccountsOverviewScreen)`
  - `open_payday` / `open_roles` -> open relevant settings sheets.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widgets/chat_guidance_actions_test.dart test/widgets/chat_lockout_test.dart`  
Expected: PASS.

- [ ] **Step 5: Commit Task 5**

```bash
git add flutter_app/lib/screens/chat/chat_entry_screen.dart flutter_app/test/widgets/chat_guidance_actions_test.dart flutter_app/test/widgets/chat_lockout_test.dart
git commit -m "feat(chat): implement live lockout countdown timer and guidance action buttons"
```

---

### Task 6: Rebuilt Interactive 5-Stage App Setup Tutor Wizard

**Files:**
- Create: `flutter_app/lib/widgets/onboarding/app_setup_tutor_dialog.dart`
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart`
- Modify: `flutter_app/lib/screens/settings/settings_screen.dart`
- Modify: `flutter_app/lib/screens/settings/help_support_screen.dart`
- Create: `flutter_app/test/widgets/app_setup_tutor_dialog_test.dart`

**Interfaces:**
- Produces: `AppSetupTutorDialog.show(context)` and `showIfFirstTime(context)` replacing the old 5-slide generic walkthrough with the new 5-stage setup wizard.

- [ ] **Step 1: Write failing widget test for `AppSetupTutorDialog`**

In `flutter_app/test/widgets/app_setup_tutor_dialog_test.dart`:
- Verify all 5 setup stages can be navigated with next/previous buttons.
- Verify action buttons exist for each stage (`Set Payday`, `Add Accounts`, `Configure Envelopes`, `Household Roles`, `Finish`).
- Verify SharedPreferences flag `has_seen_setup_tutor_v2` is persisted on completion.

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/widgets/app_setup_tutor_dialog_test.dart`  
Expected: FAIL.

- [ ] **Step 3: Implement `AppSetupTutorDialog` and integrate into Dashboard & Settings**

- Create `flutter_app/lib/widgets/onboarding/app_setup_tutor_dialog.dart`:
  - 5 rich stages with Velvet Burgundy gradient cards, step indicators (`Step 1 of 5`), clear explanations, and direct action buttons.
- In `dashboard_screen.dart`: Call `AppSetupTutorDialog.showIfFirstTime(context)`.
- In `settings_screen.dart` & `help_support_screen.dart`: Add `[📖 App Setup Guide & Tutor]` menu item.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/app_setup_tutor_dialog_test.dart`  
Expected: PASS.

- [ ] **Step 5: Commit Task 6**

```bash
git add flutter_app/lib/widgets/onboarding/app_setup_tutor_dialog.dart flutter_app/lib/screens/home/dashboard_screen.dart flutter_app/lib/screens/settings/settings_screen.dart flutter_app/lib/screens/settings/help_support_screen.dart flutter_app/test/widgets/app_setup_tutor_dialog_test.dart
git commit -m "feat(onboarding): build 5-stage interactive App Setup Tutor and connect to dashboard & settings"
```

---

### Task 7: Comprehensive Verification & Regression Sweep

- [ ] **Step 1: Run Python test suite**
  Run: `cd ai_service && pytest -v`
  Expected: All tests pass.

- [ ] **Step 2: Run Flutter analyzer**
  Run: `cd flutter_app && flutter analyze`
  Expected: 0 issues found.

- [ ] **Step 3: Run Flutter localization guard**
  Run: `cd flutter_app && flutter test test/ui_l10n_guard_test.dart`
  Expected: All tests pass.

- [ ] **Step 4: Run full Flutter test suite**
  Run: `cd flutter_app && flutter test`
  Expected: All 950+ tests pass.

- [ ] **Step 5: Commit any final test fixtures or adjustments**
