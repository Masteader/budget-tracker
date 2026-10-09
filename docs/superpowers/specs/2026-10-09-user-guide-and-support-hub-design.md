# User Guide Walkthrough & Help/Support Center Design

## 1. Overview & Objectives

Provide a seamless onboarding and support experience for new and existing users of the Budget Tracker application.
The system consists of two primary layers:
1. **First-Run Onboarding Walkthrough (`UserGuideModal`)**: A high-impact, 5-step swipeable visual guide that automatically introduces core features to new users after household setup, and remains replayable anytime from Settings.
2. **Dedicated Help & Support Center (`HelpSupportScreen`)**: An interactive self-service hub accessible from Settings and the Dashboard AppBar, featuring searchable FAQs, an AI Support Assistant powered by Gemini 2.0 Flash, and 1-tap direct developer email escalation (`fmscoinfo@fmsco.com.sa`).

---

## 2. Onboarding Walkthrough (5 Core Visuals)

### 2.1 The 5 Feature Steps
1. **AI Invoice & ZATCA Scanner** 🧾
   - Multi-page camera captures & gallery selection.
   - Real-time Saudi ZATCA QR code (TLV) scanning and tax invoice validation.
   - Automatic line-item extraction with unit pricing and discount parsing.
2. **Voice & Dialect Chat** 🎙️
   - Natural Saudi colloquial dialect expense entry (`قهوة 16 ريال وحلا 12`, `دجاج وخضار بـ 75`).
   - Natural language affordability check & budget simulations (`أقدر أشتري آيباد بـ 1200 ريال؟`).
3. **Salary Cycles & Payday Alignment** 📅
   - Automatic 27th-of-month Saudi payday cycles.
   - Real-time burn-rate forecasting, cycle rollover, and daily discretionary allowance.
4. **Recurring Bills & Installments (BNPL)** 💳
   - Dedicated reserves for fixed obligations (Housing Rent, SEC Electricity, Fiber, Iqama fees).
   - 1-tap payment logging directly from the dashboard card.
   - Installment plan tracking (Tabby / Tamara / Bank installments) with payoff progress.
5. **Household & 2D Partner Split** 👥
   - Two-dimensional attribution: tracks who paid (`paid_by`) vs who benefited (`beneficiary`).
   - Zero-friction monthly net settlements with partner balance cards.

### 2.2 Walkthrough Trigger & Persistence
- Stored in `SharedPreferences` under key: `has_seen_user_guide_v1`.
- When a user lands on `DashboardScreen` after creating or joining a household:
  - If `has_seen_user_guide_v1` is `false` or null, show `UserGuideModal` as a modal dialog with smooth fade/scale animation.
  - Setting `has_seen_user_guide_v1 = true` upon tapping "Get Started" or "Skip".
- Can be manually reopened anytime via Settings or Help Center.

---

## 3. Help & Support Center Architecture

### 3.1 Screen Structure (`HelpSupportScreen`)
- **AppBar**: Title "Help & Support", quick action to "Replay Guide".
- **Tab 1: FAQs & Knowledge Base**:
  - Search bar to filter FAQs dynamically.
  - Categorized expandable accordion cards:
    - *Getting Started*: How household codes work, switching households, payday dates.
    - *Scanning & Invoices*: Best lighting, QR vs photo OCR, duplicate resolution.
    - *Budgeting & Bills*: How reserves work, adding recurring bills, Iqama fees.
    - *Voice & Chat*: Dialect examples, simulation vs logging.
    - *Partner Attribution*: How net settlement is calculated.
- **Tab 2: AI Support Assistant**:
  - Conversational chat powered by the backend `/support/chat` endpoint.
  - Quick question prompt chips (`How does salary cycle work?`, `How to add Iqama fee?`, `What is 2D attribution?`).
  - Contextual markdown message rendering.
  - **Auto-Escalation Engine**:
    - When the AI detects a bug report, system error, billing query, or request to contact the developer:
      - Renders an interactive `DeveloperContactCard` directly in the chat stream.
      - 1-tap button to launch the device email client to `fmscoinfo@fmsco.com.sa`.
      - Email subject: `[Budget Tracker Support] <Issue Summary>`.
      - Email body pre-populated with: App version, OS platform, User ID / Household ID, and the user's specific problem description.

### 3.2 Settings Integration (`IngestionSettingsScreen`)
- Add a dedicated **HELP & SUPPORT** section containing:
  - 📖 **App Guide & Tutorial**: Replays the 5-step visual walkthrough.
  - 💬 **Help Center & AI Support**: Navigates to `HelpSupportScreen`.
  - ✉️ **Contact Developer**: Directly launches email to `fmscoinfo@fmsco.com.sa`.

---

## 4. Backend Support Service (`ai_service`)

### 4.1 Endpoint Specification
- `POST /support/chat`
  - **Request Body**:
    ```json
    {
      "message": "string",
      "household_id": "optional-uuid",
      "user_id": "optional-uuid",
      "history": [
        {"role": "user", "content": "..."},
        {"role": "assistant", "content": "..."}
      ]
    }
    ```
  - **Response Body**:
    ```json
    {
      "reply": "string",
      "escalate_to_developer": true,
      "summary": "User reported camera freeze on ZATCA scan",
      "support_email": "fmscoinfo@fmsco.com.sa"
    }
    ```

### 4.2 Support Agent Prompt & Grounding (`support_agent.py`)
- System prompt incorporates:
  - Detailed app taxonomy (10 standard categories).
  - Receipt scan workflow (ZATCA QR TLV + Vision OCR).
  - 27th-to-26th salary cycle rules and rollover mechanics.
  - 2D partner settlement logic (`paid_by` vs `beneficiary`).
  - Reassurance: Zero SMS background processes or SMS permissions.
  - Tone: Helpful, concise, bilingual (Saudi Arabic and English).
  - Auto-detection trigger: flags `escalate_to_developer = true` whenever unhandled issues, errors, crash reports, or user requests for developer contact appear.

---

## 5. Testing & Verification Plan

1. **Unit Tests (Backend `ai_service`)**:
   - `tests/test_support_agent.py`:
     - Test standard FAQ question answering in Arabic & English.
     - Test bug detection triggering `escalate_to_developer = true`.
     - Test endpoint contract `/support/chat`.
2. **Widget Tests (Flutter `flutter_app`)**:
   - `test/widgets/user_guide_walkthrough_test.dart`:
     - Test 5-step carousel pagination, skip, and get started actions.
     - Verify preference persistence (`has_seen_user_guide_v1`).
   - `test/screens/help_support_screen_test.dart`:
     - Test FAQ accordion expansion and search filtering.
     - Test AI chat message bubble rendering and escalation button.
     - Test settings navigation to Help Center.
