# Real-Time Sync, Conversational AI Entry, and Multimodal Receipt Scanner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix real-time UI updates for budgets/transactions in Flutter, and introduce conversational natural-language transaction entry with itemized breakdowns, multimodal camera receipt scanning, and a smart deduplication engine to prevent double-counting across SMS, Chat, and Receipt scans.

**Architecture:** 
1. **Frontend (Flutter):** Replace stale `AnimatedList` with reactive `ListView.separated` connected to Supabase Realtime streams; wrap tabs in `IndexedStack` to preserve stream state; integrate `image_picker` for camera receipt capture; add a conversational Quick Log Chat UI and receipt review sheet.
2. **Backend (Python FastAPI + LangGraph + LiteLLM Gemini):** Add endpoints for natural language text parsing (`/agent/chat-transaction`) and multimodal receipt image parsing (`/agent/scan-receipt`). Both extract merchant, amount, category, and line-item details ("16 ice latte and 3 donut").
3. **Database (Supabase PostgreSQL):** Add `source` (`'sms' | 'chat' | 'receipt_scan' | 'manual'`), `items` JSONB (`[{"name", "qty", "price"}]`), and `receipt_image_url` to `transactions`. Add deduplication query index on `(household_id, amount, timestamp)`. Ensure `supabase_realtime` publication includes all required tables.
4. **Deduplication Engine:** Compares incoming chat/scan entries against existing transactions within a time window (2 hours) on amount and merchant similarity. Offers automatic line-item enrichment rather than duplicate charging.

**Tech Stack:** 
- Mobile: Flutter 3.29+ / Dart 3.7+ (`supabase_flutter`, `image_picker`, `google_fonts`, `intl`)
- AI Microservice: Python 3.12+ (`FastAPI`, `LiteLLM`, `Google Gemini 3.5 Flash Lite`, `Pydantic v2`, `HMAC-SHA256`)
- Cloud / DB: Supabase (PostgreSQL 15+, Supabase Realtime, Row Level Security)
- Hardware: Physical Samsung Galaxy S24/S25 Ultra (`RFGYC0B58DH`) via ADB bridge

---

## Global Constraints
- Target device: Android 16 (API 36) Samsung Galaxy `RFGYC0B58DH`
- API port: FastAPI runs on port 8000 reverse-proxied to device via `adb reverse tcp:8000 tcp:8000`
- Zero real money cost for verification (all tested using mock texts, simulated receipts, and ADB bridge)
- Strict client-side privacy: never store raw sensitive OTPs; HMAC-SHA256 sign all API payloads
- Preserving RLS: client operations use user JWT; backend service uses Supabase service role key

---

## Task Breakdown

### Task 1: Fix Real-Time Sync in Flutter (Transactions, Budgets, and Tab Retention)

**Problem:** 
`TransactionFeedScreen` uses `AnimatedList` with `initialItemCount: transactions.length`. In Flutter, `AnimatedList` only reads item count on widget creation. When a new stream snapshot arrives, `AnimatedList` does NOT re-evaluate count unless `insertItem()` is called manually. Furthermore, switching tabs reconstructs screens because `DashboardScreen` does not use `IndexedStack`. In `BudgetManagementScreen`, `FutureBuilder` is used instead of a real-time stream.

**Files:**
- Modify: `flutter_app/lib/screens/home/transaction_feed_screen.dart`
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart`
- Modify: `flutter_app/lib/screens/home/budget_management_screen.dart`
- Verify DB: `supabase/schema.sql` (Realtime publication checks)

**Interfaces:**
- Consumes: `supabase.from('transactions').stream(...)` and `supabase.from('budgets').stream(...)`
- Produces: Reactive UI that reflects insertions, updates, and reallocations in <500ms without switching tabs.

- [x] **Step 1: Replace AnimatedList with reactive ListView.separated in `transaction_feed_screen.dart`**
Replace `AnimatedList` with a standard `ListView.separated` with `physics: const AlwaysScrollableScrollPhysics()` and wrap in `RefreshIndicator` for manual pull-to-refresh fallback.
```dart
return RefreshIndicator(
  onRefresh: () async => setState(() {}),
  child: ListView.separated(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    itemCount: transactions.length,
    separatorBuilder: (ctx, _) => const SizedBox(height: 8),
    itemBuilder: (ctx, i) => _TransactionTile(tx: transactions[i]),
  ),
);
```

- [x] **Step 2: Wrap tab navigation with IndexedStack in `dashboard_screen.dart`**
Change `body: screens[_selectedIndex]` to:
```dart
body: IndexedStack(
  index: _selectedIndex,
  children: screens,
),
```
This keeps both WebSocket stream connections open and prevents disposing/re-creating states when the user switches between Dashboard, Transactions, and Budgets.

- [x] **Step 3: Convert `BudgetManagementScreen` to listen to live budget streams**
Replace `_loadData()` `FutureBuilder` with a `StreamBuilder<List<Map<String, dynamic>>>` listening to `budgets.stream(primaryKey: ['id']).eq('household_id', hid)`. Rebuilding occurs immediately when any budget allocation or spend changes.

- [x] **Step 4: Verify Supabase Realtime publication in Postgres**
Run verification query to ensure both `transactions` and `budgets` are included in `supabase_realtime`:
```sql
SELECT tablename FROM pg_publication_tables WHERE pubname = 'supabase_realtime';
```

- [x] **Step 5: Test on device**
Run `flutter run` on `RFGYC0B58DH`. While on the Transactions screen, send a simulated bank SMS via `send_simulated_sms.py`. Confirm the new transaction immediately animates/appears at the top of the list without touching or switching tabs.

---

### Task 2: Database Schema & Migration for Line Items, Sources, and Deduplication

**Files:**
- Modify: `supabase/schema.sql`
- Create: `supabase/migrations/20260925_add_line_items_and_sources.sql`

**Interfaces:**
- Columns added to `public.transactions`:
  - `source TEXT NOT NULL DEFAULT 'sms' CHECK (source IN ('sms', 'chat', 'receipt_scan', 'manual'))`
  - `items JSONB DEFAULT '[]'::jsonb` (contains array of `{name: string, quantity: number, price: number, notes?: string}`)
  - `receipt_url TEXT` (optional image URL or storage path)
  - `dedup_fingerprint TEXT` (hash of household_id + amount + rounded date)
- Indexes:
  - `CREATE INDEX idx_transactions_dedup ON public.transactions (household_id, amount, timestamp);`

- [x] **Step 1: Create migration script**
Write `supabase/migrations/20260925_add_line_items_and_sources.sql`:
```sql
ALTER TABLE public.transactions 
  ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'sms' CHECK (source IN ('sms', 'chat', 'receipt_scan', 'manual')),
  ADD COLUMN IF NOT EXISTS items JSONB DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS receipt_url TEXT,
  ADD COLUMN IF NOT EXISTS dedup_fingerprint TEXT;

CREATE INDEX IF NOT EXISTS idx_transactions_dedup 
  ON public.transactions (household_id, amount, timestamp);
```

- [x] **Step 2: Update Supabase Python models and Dart models**
Update `ai_service/models.py`:
Add `source: str = "sms"`, `items: list[dict] = []`, and `receipt_url: Optional[str] = None` to `AgentState` and `SMSWebhookResponse`.
Update `flutter_app/lib/models/models.dart`:
Add `source`, `items`, and `receiptUrl` to the `Transaction` Dart class.

- [x] **Step 3: Execute migration in Supabase and verify schema**
Apply the migration using the Supabase client or SQL runner and verify columns exist.

---

### Task 3: AI Microservice — Natural Language Chat Transaction Parser

**User Requirement:**
"another input of the transactions is that a chat i can enter the transaction message and specifically mention this is merchant dunkin and i spent 19 sar total, 16 ice latte and 3 donut, and it will do the magic"

**Files:**
- Create: `ai_service/chat_parser.py`
- Modify: `ai_service/main.py`
- Modify: `ai_service/supabase_client.py`
- Create test: `ai_service/tests/test_chat_parser.py`

**Interfaces:**
- Input: `ChatTransactionRequest(message: str, household_id: str, user_id: Optional[str], force: bool = False)`
- Output: `ChatTransactionResponse(status: str, transaction_id: Optional[str], merchant: str, amount: float, category_code: str, items: list[TransactionItem], is_duplicate: bool, existing_transaction: Optional[dict])`- [x] **Step 1: Write failing unit test for natural language transaction extraction**
Create `ai_service/tests/test_chat_parser.py`:
```python
def test_parse_chat_transaction_dunkin():
    message = "merchant dunkin and i spent 19 sar total, 16 ice latte and 3 donut"
    result = parse_chat_message(message)
    assert result.merchant.lower() == "dunkin"
    assert result.total_amount == 19.0
    assert len(result.items) == 2
    assert result.items[0]["name"].lower() == "ice latte"
    assert result.items[0]["price"] == 16.0
    assert result.items[1]["name"].lower() == "donut"
    assert result.items[1]["price"] == 3.0
```

- [x] **Step 2: Implement prompt and extraction logic using Gemini 3.5 Flash**
In `ai_service/chat_parser.py`, construct a structured JSON schema extraction prompt.

- [x] **Step 3: Connect to duplicate detection before insertion**
If an existing transaction exists within 2 hours matching amount and merchant:
Return `status="duplicate_warning"` with candidate match ID unless `force=True`.

- [x] **Step 4: Register `POST /agent/chat-transaction` in `main.py`**
Wire endpoint with HMAC-SHA256 signature verification or authenticated user JWT.

- [x] **Step 5: Run tests and verify**
Run: `.\venv\Scripts\pytest ai_service/tests/test_chat_parser.py -v`
Expected: PASS.

---

### Task 4: AI Microservice — Multimodal Receipt & Invoice Scanner

**User Requirement:**
"also a scan for the invoice through the camera phone and it will check what are the spent amounts and types and it will enter all details and do the magic"

**Files:**
- Create: `ai_service/receipt_scanner.py`
- Modify: `ai_service/main.py`
- Create test: `ai_service/tests/test_receipt_scanner.py`

**Interfaces:**
- Input: `ReceiptScanRequest(image_base64: str, household_id: str, user_id: Optional[str], force: bool = False)`
- Output: `ReceiptScanResponse(status: str, merchant: str, total_amount: float, vat_amount: Optional[float], date: Optional[str], items: list[dict], category_code: str, is_duplicate: bool, matched_sms_tx_id: Optional[str])`

- [x] **Step 1: Write test for multimodal receipt parsing**
Create `ai_service/tests/test_receipt_scanner.py` mocking Gemini multimodal image response.

- [x] **Step 2: Implement `parse_receipt_image(image_bytes)` in `ai_service/receipt_scanner.py`**
Use `litellm.completion` with `gemini/gemini-3.5-flash-lite`:
Pass image as base64 data URI to Gemini vision API.

- [x] **Step 3: Expose `POST /agent/scan-receipt` in `ai_service/main.py`**
Ensure robust payload size handling (up to 10MB JPEG/PNG) and background task for budget deduction.

---

### Task 5: Deduplication & Cross-Channel Matching Engine

**User Requirement:**
"the user has to specifically choose which method to choose so no duplicates happens for example if the sms interceptor is active we cant also enter the same amount again via chat message entery or the scan method, note: if some methods can work togather then we can keep them active togather no problem like the invoice camera scan and the manual text input .."

**Files:**
- Create: `ai_service/dedup_engine.py`
- Modify: `ai_service/supabase_client.py`
- Create test: `ai_service/tests/test_dedup.py`

- [x] **Step 1: Write test for duplicate matching and item enrichment**
Verify that an incoming receipt for 19 SAR at Dunkin' matches an existing SMS transaction for 19 SAR at Dunkin' and merges line items into `items` JSONB column.

- [x] **Step 2: Implement `check_duplicate_candidate()` and `enrich_transaction_items()` in `supabase_client.py`**
Query existing rows in Supabase for candidate matches.

- [x] **Step 3: Integrate with Chat and Scan endpoints**
Ensure both endpoints respect duplicate candidate matching and explicit enrichment IDs.

---

### Task 6: Flutter App — Conversational Natural Language Log Screen ("The Magic")

**User Requirement:**
"another input of the transactions is that a chat i can enter the transaction message and specifically mention this is merchant dunkin and i spent 19 sar total, 16 ice latte and 3 donut, and it will do the magic"

**Files:**
- Create: `flutter_app/lib/screens/chat/chat_entry_screen.dart`
- Create: `flutter_app/lib/widgets/transaction_item_breakdown_card.dart`
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart` (Add Floating Action Button or Chat tab)

- [x] **Step 1: Create `ChatEntryScreen` widget**
Build modern chat interface with message history, quick chips, and animated typing indicators.

- [x] **Step 2: Connect to `ApiService.sendChatTransaction(message)`**
Send payload with HMAC signature to `/agent/chat-transaction`.

- [x] **Step 3: Handle duplicate resolution dialog**
If API returns `duplicate_candidate`, show action bar:
- "Enrich Existing SMS"
- "Log as New"

---

### Task 7: Flutter App — Camera Receipt Scanner & Itemized Confirmation

**User Requirement:**
"also a scan for the invoice through the camera phone and it will check what are the spent amounts and types and it will enter all details and do the magic"

**Files:**
- Modify: `flutter_app/pubspec.yaml` (add `image_picker: ^1.1.2`)
- Modify: `flutter_app/android/app/src/main/AndroidManifest.xml` (add camera permissions)
- Create: `flutter_app/lib/screens/scanner/receipt_scanner_sheet.dart`
- Modify: `flutter_app/lib/services/api_service.dart`

- [x] **Step 1: Add `image_picker` to dependencies and rebuild app**
Add `image_picker: ^1.1.2` to `pubspec.yaml`, run `flutter pub get`.
Add `<uses-permission android:name="android.permission.CAMERA" />` to `AndroidManifest.xml`.

- [x] **Step 2: Build `ReceiptScannerSheet` bottom sheet modal**
Options:
- [📷 Take Photo] (opens camera)
- [🖼️ Upload Receipt from Gallery]
Shows image preview with a scanning radar animation while AI parses the receipt.

- [x] **Step 3: Build editable parsed results preview**
Displays:
- Detected Merchant
- Total Amount & VAT
- Extracted Items list with delete/edit controls
- Category code
- [Confirm & Save to Budget] button

---

### Task 8: Ingestion Settings & Channel Preferences

**User Requirement:**
"the user has to specifically choose which method to choose so no duplicates happens for example if the sms interceptor is active we cant also enter the same amount again via chat message entery or the scan method, note: if some methods can work togather then we can keep them active togather no problem like the invoice camera scan and the manual text input .."

**Files:**
- Create: `flutter_app/lib/screens/settings/ingestion_settings_screen.dart`
- Modify: `flutter_app/lib/services/sms_service.dart`
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart`

- [x] **Step 1: Implement `IngestionSettingsScreen`**
Store preferences locally via `shared_preferences` and allow policy selection: Smart Auto-Enrich, Prompt on Conflict, Strict Channel Isolation.

- [x] **Step 2: Integrate toggles with `SmsListenerService`**
If the user turns off SMS Interceptor, cleanly stop the Android foreground service.op the Android foreground service.

---

### Task 9: End-to-End Verification on Samsung Galaxy Device

- [ ] **Step 1: Verify Real-Time Sync**
Add a transaction or edit a budget; verify the Transactions feed and Budget progress bars update instantly without switching tabs.

- [ ] **Step 2: Verify Conversational Chat Entry**
Enter: *"merchant dunkin and i spent 19 sar total, 16 ice latte and 3 donut"*.
Verify:
- Transaction recorded for SAR 19.00
- Category assigned: OPEX-DINING
- Items logged: `Ice Latte (16 SAR)` and `Donut (3 SAR)`
- App displays itemized card

- [ ] **Step 3: Verify Receipt Scanner**
Scan a sample receipt. Verify items and total are extracted and saved.

- [ ] **Step 4: Verify Duplicate Prevention**
1. Simulate SMS: `SAR 50.00 at Starbucks`.
2. Immediately chat: *"Starbucks 50 SAR 2 caramel macchiato"*.
3. Verify deduplication triggers, enriches the existing Starbucks transaction with the 2 caramel macchiatos, and does NOT double-charge the budget.
