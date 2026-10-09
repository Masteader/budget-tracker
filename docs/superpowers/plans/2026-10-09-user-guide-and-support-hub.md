# User Guide Walkthrough & Help/Support Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a 5-step visual onboarding walkthrough for new users and an interactive Help & Support Center with searchable FAQs, an AI Support Assistant, and 1-tap developer email escalation.

**Architecture:** A FastAPI `/support/chat` endpoint powered by Gemini 2.0 Flash with app domain grounding, consumed by a Flutter `SupportApiClient`, with a rich 5-step onboarding walkthrough carousel modal, and a dedicated `HelpSupportScreen` integrated into `DashboardScreen` and `IngestionSettingsScreen`.

**Tech Stack:** Python 3.11/FastAPI, Gemini 2.0 Flash (via LiteLLM / Google GenAI), Flutter 3.22+, SharedPreferences, Google Fonts (Outfit).

**Spec:** `docs/superpowers/specs/2026-10-09-user-guide-and-support-hub-design.md`

## Global Constraints

- Zero SMS background processes or permissions — do not touch or introduce any SMS code.
- Support email recipient: `fmscoinfo@fmsco.com.sa`.
- Maintain dark-mode visual hierarchy (`#0D1117`, `#161B22`, `#00C896`, `#30363D`).
- 5 Walkthrough steps: (1) AI Receipt Scanner, (2) Voice & Chat, (3) Salary Cycle, (4) Recurring Bills & Installments, (5) Household & 2D Partner Split.
- All Flutter tests (`flutter test`) and backend tests (`pytest`) must pass after every task.

---

### Task 1: Backend Support Agent & Endpoint (`/support/chat`)

**Files:**
- Create: `ai_service/support_agent.py`
- Modify: `ai_service/models.py`
- Modify: `ai_service/main.py`
- Test: `ai_service/tests/test_support_agent.py`

**Interfaces:**
- Produces: `POST /support/chat` accepting `SupportChatRequest(message, household_id, user_id, history)` and returning `SupportChatResponse(reply, escalate_to_developer, summary, support_email)`.

- [ ] **Step 1: Write the failing test**

```python
# ai_service/tests/test_support_agent.py
import pytest
from httpx import AsyncClient, ASGITransport
from main import app

@pytest.mark.asyncio
async def test_support_chat_general_faq():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        res = await ac.post("/support/chat", json={
            "message": "How does the salary cycle work in this app?",
            "household_id": "test-house-1",
        })
    assert res.status_code == 200
    data = res.json()
    assert "reply" in data
    assert data["support_email"] == "fmscoinfo@fmsco.com.sa"
    assert data["escalate_to_developer"] is False

@pytest.mark.asyncio
async def test_support_chat_bug_escalation():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        res = await ac.post("/support/chat", json={
            "message": "The app crashed when scanning invoice, please fix this bug or let me talk to developer",
            "household_id": "test-house-1",
        })
    assert res.status_code == 200
    data = res.json()
    assert data["escalate_to_developer"] is True
    assert "summary" in data
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.\venv\Scripts\python.exe -m pytest tests/test_support_agent.py`
Expected: FAIL (404 Not Found on `/support/chat`)

- [ ] **Step 3: Implement Support Agent and Endpoint**

Add models in `ai_service/models.py`:
```python
class SupportChatRequest(BaseModel):
    message: str
    household_id: Optional[str] = None
    user_id: Optional[str] = None
    history: Optional[List[Dict[str, str]]] = None

class SupportChatResponse(BaseModel):
    reply: str
    escalate_to_developer: bool = False
    summary: Optional[str] = None
    support_email: str = "fmscoinfo@fmsco.com.sa"
```

Create `ai_service/support_agent.py`:
```python
import os
import re
from typing import Optional, List, Dict, Tuple

SUPPORT_EMAIL = "fmscoinfo@fmsco.com.sa"

SUPPORT_SYSTEM_PROMPT = """You are the AI Support Assistant for the Budget Tracker mobile application for Saudi households.
You provide clear, friendly, and practical guidance in Saudi Arabic or English.
App capabilities:
1. Receipt Scanner: Multi-page photos & Saudi ZATCA QR codes (TLV). Automatic OCR line-items.
2. Voice & Dialect: Saudi colloquial speech or text (e.g. 'قهوة 16 ريال وحلا 12') and affordability checks ('أقدر أشتري آيباد بـ 1200؟').
3. Salary Cycles: 27th of Gregorian month payday, automatic carryovers, daily burn-rate.
4. Recurring Bills & BNPL: Track rent, SEC electricity, fiber, Iqama fees (400 SAR) with 1-tap payments, plus Tabby/Tamara installments.
5. 2D Attribution: Tracks who paid ('paid_by') vs who benefited ('beneficiary') with instant net settlements.
6. Privacy: Zero SMS interception, zero SMS permissions.

If the user reports a bug, app crash, unresolvable defect, or explicitly asks to contact the developer:
Set ESCALATE: TRUE and provide a one-line SUMMARY of their issue. Otherwise set ESCALATE: FALSE.
Format your output as:
[ESCALATE: TRUE|FALSE]
[SUMMARY: brief summary or NONE]
<Your helpful conversational reply to the user>
"""

async def handle_support_query(
    message: str,
    household_id: Optional[str] = None,
    user_id: Optional[str] = None,
    history: Optional[List[Dict[str, str]]] = None,
) -> Tuple[str, bool, Optional[str]]:
    # Escalation keyword heuristics + LLM fallback
    bug_keywords = ["crash", "bug", "broken", "error", "defect", "developer", "contact developer", "خلل", "عطل", "مشكلة في النظام", "تواصل مع المطور"]
    is_escalation_candidate = any(kw in message.lower() for kw in bug_keywords)

    api_key = os.environ.get("GOOGLE_API_KEY", "")
    reply = ""
    escalate = is_escalation_candidate
    summary = message[:100] if is_escalation_candidate else None

    if api_key:
        try:
            from google import genai
            client = genai.Client(api_key=api_key)
            prompt = f"{SUPPORT_SYSTEM_PROMPT}\n\nUser Question: {message}"
            res = client.models.generate_content(
                model="gemini-2.0-flash",
                contents=prompt,
            )
            raw_text = res.text or ""
            if "[ESCALATE: TRUE]" in raw_text:
                escalate = True
            m_sum = re.search(r"\[SUMMARY:\s*(.+?)\]", raw_text)
            if m_sum and m_sum.group(1).strip() != "NONE":
                summary = m_sum.group(1).strip()
            
            # Strip metadata tags from final reply
            clean_reply = re.sub(r"\[ESCALATE:\s*(TRUE|FALSE)\]", "", raw_text)
            clean_reply = re.sub(r"\[SUMMARY:\s*.+?\]", "", clean_reply).strip()
            if clean_reply:
                reply = clean_reply
        except Exception:
            pass

    if not reply:
        if is_escalation_candidate:
            reply = "نعتذر عن هذه المشكلة! يمكنك التواصل مباشرة مع المطور عبر الزر أدناه وسيتم فتح بريدك الإلكتروني مع كافة تفاصيل المشكلة."
            escalate = True
            summary = message[:100]
        else:
            reply = "أهلاً بك في تطبيق ميزانية الأسرة! يمكنك الاستفسار عن فواتيرك، دورة الرواتب (27 من كل شهر)، فواتير الأقساط، أو كيفية مسح الفواتير."

    return reply, escalate, summary
```

Wire into `ai_service/main.py`:
```python
from models import SupportChatRequest, SupportChatResponse
from support_agent import handle_support_query, SUPPORT_EMAIL

@app.post("/support/chat", response_model=SupportChatResponse)
async def support_chat(payload: SupportChatRequest) -> SupportChatResponse:
    reply, escalate, summary = await handle_support_query(
        message=payload.message,
        household_id=payload.household_id,
        user_id=payload.user_id,
        history=payload.history,
    )
    return SupportChatResponse(
        reply=reply,
        escalate_to_developer=escalate,
        summary=summary,
        support_email=SUPPORT_EMAIL,
    )
```

- [ ] **Step 4: Run test to verify it passes**

Run: `.\venv\Scripts\python.exe -m pytest tests/test_support_agent.py`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ai_service/support_agent.py ai_service/models.py ai_service/main.py ai_service/tests/test_support_agent.py
git commit -m "feat(ai_service): add support chat endpoint with auto-escalation detection"
```

---

### Task 2: Flutter `SupportApiClient` & `ApiService` Facade

**Files:**
- Create: `flutter_app/lib/services/api/support_api_client.dart`
- Modify: `flutter_app/lib/services/api_service.dart`
- Test: `flutter_app/test/services/support_api_client_test.dart`

**Interfaces:**
- Produces: `ApiService.instance.support.postSupportChat({required String message, String? householdId, String? userId, List<Map<String, String>>? history})` returning `Map<String, dynamic>`.

- [ ] **Step 1: Write the failing test**

```dart
// flutter_app/test/services/support_api_client_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/services/api/support_api_client.dart';
import 'package:budget_tracker/services/api_service.dart';

void main() {
  test('SupportApiClient exposes postSupportChat and ApiService facade', () {
    final client = SupportApiClient();
    expect(client, isNotNull);
    expect(ApiService.instance.support, isNotNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/support_api_client_test.dart`
Expected: Compilation failure (SupportApiClient not found)

- [ ] **Step 3: Implement `SupportApiClient` and update `ApiService`**

Create `flutter_app/lib/services/api/support_api_client.dart`:
```dart
import '../../supabase_config.dart';
import 'base_api_client.dart';

class SupportApiClient {
  final BaseApiClient baseClient;

  SupportApiClient({BaseApiClient? baseClient})
      : baseClient = baseClient ?? BaseApiClient();

  Future<Map<String, dynamic>> postSupportChat({
    required String message,
    String? householdId,
    String? userId,
    List<Map<String, String>>? history,
  }) async {
    final url = '$fastapiBaseUrl/support/chat';
    return baseClient.post(
      url,
      {
        'message': message,
        if (householdId != null) 'household_id': householdId,
        if (userId != null) 'user_id': userId,
        if (history != null) 'history': history,
      },
      shouldSign: false,
      timeout: const Duration(seconds: 20),
    );
  }
}
```

Update `flutter_app/lib/services/api_service.dart`:
Add `import 'api/support_api_client.dart';`
Add `late final SupportApiClient support = SupportApiClient(baseClient: base);`

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/support_api_client_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/services/api/support_api_client.dart flutter_app/lib/services/api_service.dart flutter_app/test/services/support_api_client_test.dart
git commit -m "feat(flutter): add SupportApiClient and integrate into ApiService"
```

---

### Task 3: 5-Step Modern User Guide Walkthrough Widget (`UserGuideWalkthroughDialog`)

**Files:**
- Create: `flutter_app/lib/widgets/onboarding/user_guide_walkthrough_dialog.dart`
- Test: `flutter_app/test/widgets/user_guide_walkthrough_test.dart`

**Features:**
- 5 Swipeable cards:
  1. 🧾 **AI Invoice & ZATCA Scanner**: Multi-page photos & Saudi QR code TLV validation.
  2. 🎙️ **Voice & Dialect Chat**: Saudi colloquial expense logging & affordability simulations.
  3. 📅 **Salary Cycles & Payday Alignment**: Saudi 27th payday alignment & burn rate pacing.
  4. 💳 **Recurring Bills & Installments (BNPL)**: Reserve tracking for Rent, Utilities, Iqama fee (400 SAR), and Tabby/Tamara installments.
  5. 👥 **Household & 2D Partner Split**: Joint household tracking (`paid_by` vs `beneficiary`) with instant settlements.
- Navigation: Dot page indicators, "Skip" button, "Next" / "Get Started" buttons.
- Helper method `UserGuideWalkthroughDialog.showIfFirstTime(BuildContext context)` with `SharedPreferences` persistence under key `has_seen_user_guide_v1`.

- [ ] **Step 1: Write the failing test**

```dart
// flutter_app/test/widgets/user_guide_walkthrough_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/onboarding/user_guide_walkthrough_dialog.dart';

void main() {
  testWidgets('UserGuideWalkthroughDialog displays 5 steps with next and skip', (tester) async {
    bool dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserGuideWalkthroughDialog(
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );

    // Initial step 1: Scanner
    expect(find.text('AI Invoice & ZATCA Scanner'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    // Tap Next through the cards
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Voice & Dialect Chat'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Salary Cycles & Payday (27th)'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Recurring Bills & Installments'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Household & 2D Partner Split'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);

    // Tap Get Started
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/user_guide_walkthrough_test.dart`
Expected: Compilation failure (UserGuideWalkthroughDialog not found)

- [ ] **Step 3: Implement `UserGuideWalkthroughDialog`**

Implement `flutter_app/lib/widgets/onboarding/user_guide_walkthrough_dialog.dart` with PageView, 5 structured steps, smooth animated indicators, dark theme colors (`#161B22`, `#00C896`), and static method `show(context)` and `showIfFirstTime(context)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/user_guide_walkthrough_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/onboarding/user_guide_walkthrough_dialog.dart flutter_app/test/widgets/user_guide_walkthrough_test.dart
git commit -m "feat(flutter): create 5-step user guide walkthrough dialog with persistence"
```

---

### Task 4: Help & Support Center Screen (`HelpSupportScreen`)

**Files:**
- Create: `flutter_app/lib/screens/settings/help_support_screen.dart`
- Test: `flutter_app/test/screens/help_support_screen_test.dart`

**Features:**
- **Tab 1: FAQs & Knowledge Base**:
  - Filterable search bar.
  - Expandable accordion tiles for common questions:
    - 27th Payday & Burn-rate rollover
    - Adding Recurring Bills & 400 SAR Iqama fee
    - ZATCA QR & Multi-page Receipt Scanning
    - Partner attribution & monthly net balance
    - Tabby & Tamara installment plans
  - Card to "Replay App Guide" (opens `UserGuideWalkthroughDialog`).
  - Button to "Email Developer" (`fmscoinfo@fmsco.com.sa`).
- **Tab 2: AI Support Assistant**:
  - Chat dialogue with quick prompt suggestion chips.
  - Sends query to `ApiService.instance.support.postSupportChat`.
  - When `escalate_to_developer == true`, renders an interactive `DeveloperContactCard` with 1-tap email launcher with pre-filled device & issue diagnostics.

- [ ] **Step 1: Write the failing test**

```dart
// flutter_app/test/screens/help_support_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/screens/settings/help_support_screen.dart';

void main() {
  testWidgets('HelpSupportScreen renders FAQ tab and AI Chat tab', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HelpSupportScreen(),
      ),
    );

    expect(find.text('Help & Support'), findsOneWidget);
    expect(find.text('FAQs & Guide'), findsOneWidget);
    expect(find.text('AI Assistant'), findsOneWidget);

    // Verify FAQ items appear
    expect(find.textContaining('Salary Cycle'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/help_support_screen_test.dart`
Expected: Compilation failure (HelpSupportScreen not found)

- [ ] **Step 3: Implement `HelpSupportScreen`**

Implement `flutter_app/lib/screens/settings/help_support_screen.dart` with TabBar, searchable FAQs, AI Chat state with API connection, and direct mail launcher to `fmscoinfo@fmsco.com.sa`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/help_support_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/settings/help_support_screen.dart flutter_app/test/screens/help_support_screen_test.dart
git commit -m "feat(flutter): implement Help & Support Center with FAQs and AI Assistant"
```

---

### Task 5: Integration into Settings & Dashboard Screen

**Files:**
- Modify: `flutter_app/lib/screens/settings/ingestion_settings_screen.dart`
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart`
- Test: `flutter_app/test/screens/settings_support_integration_test.dart`

**Features:**
- Add **HELP & SUPPORT** section in `IngestionSettingsScreen`:
  - 📖 **App Guide & Tutorial**: Opens `UserGuideWalkthroughDialog`.
  - 💬 **Help Center & AI Support**: Navigates to `HelpSupportScreen`.
  - ✉️ **Contact Developer**: Directly launches email to `fmscoinfo@fmsco.com.sa`.
- In `DashboardScreen`:
  - Add help icon button in AppBar to open `HelpSupportScreen`.
  - Auto-check and trigger `UserGuideWalkthroughDialog.showIfFirstTime(context)` when entering the dashboard.

- [ ] **Step 1: Write the failing test**

```dart
// flutter_app/test/screens/settings_support_integration_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/screens/settings/ingestion_settings_screen.dart';

void main() {
  testWidgets('IngestionSettingsScreen contains HELP & SUPPORT section with Help Center', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: IngestionSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Help & Support section
    expect(find.text('HELP & SUPPORT'), findsOneWidget);
    expect(find.text('App Guide & Tutorial'), findsOneWidget);
    expect(find.text('Help Center & AI Support'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/settings_support_integration_test.dart`
Expected: FAIL (HELP & SUPPORT section not found)

- [ ] **Step 3: Update `IngestionSettingsScreen` and `DashboardScreen`**

1. In `ingestion_settings_screen.dart`, add the HELP & SUPPORT card with rows for Replay Guide, Help Center, and Contact Developer.
2. In `dashboard_screen.dart`, add the AppBar Help action button and `showIfFirstTime` trigger in `initState`/postFrameCallback.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/settings_support_integration_test.dart`
Expected: PASS

- [ ] **Step 5: Run full test suite (Flutter + Python)**

Run:
`flutter test`
`.\venv\Scripts\python.exe -m pytest`
Expected: ALL tests pass (0 failures).

- [ ] **Step 6: Commit and Push**

```bash
git add .
git commit -m "feat: complete user guide walkthrough and help & support center integration"
git push origin main
```
