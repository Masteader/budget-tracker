# Technical Architecture & Design: Mobile Modularization, Offline SQLite Sync & Recurring Bill Predictor

**Date:** 2026-10-05  
**Branch:** `refactor/mobile-architecture-and-technical-fixes`  
**Status:** Approved  

---

## 1. Executive Summary

This architecture document specifies the technical design for three sequential enhancements in the Budget Tracker platform:
1. **Sub-Project 1: Mobile Modularization Part 2** — Split the monolithic `ApiService` into domain-specific clients and de-bloat `DashboardScreen` into focused, reusable presentation widgets.
2. **Sub-Project 2: Offline SQLite Queue & Sync Engine** — Implement local SQLite persistence for instant optimistic writes, offline resilience, and automatic background replay upon network reconnection.
3. **Sub-Project 3: Recurring Bill & Subscription Predictor** — Deploy cadence-based heuristic and statistical prediction in FastAPI to detect recurring Saudi household expenses (electricity, fiber internet, rent, subscriptions) and automatically reserve funds in the salary cycle.

---

## 2. Sub-Project 1: Mobile Modularization Part 2

### 2.1 Domain API Client Layer (`lib/services/api/`)
Currently, `lib/services/api_service.dart` (650 lines) mixes HMAC-SHA256 signing, HTTP retries, fallback parsing, chat endpoints, receipt scanning, and budget queries into one file.

#### Design:
1. **`BaseApiClient`** (`base_api_client.dart`):
   - Centralizes HMAC-SHA256 signing (`X-Signature`), authentication headers (`X-App-Token`), HTTP timeouts, and error response handling.
   - Provides protected helper methods `get(path, params)` and `post(path, body, sign)`.
2. **`BudgetApiClient`** (`budget_api_client.dart`):
   - Handles salary cycle queries (`/budgets/salary-cycle-forecast`, `/budgets/cycles`), household settlement (`/households/{id}/settlement`), and sub-allocation breakdowns (`/budgets/breakdown`).
3. **`TransactionApiClient`** (`transaction_api_client.dart`):
   - Handles SMS ingestion webhook (`/webhook/sms`) and transaction queries.
   - Designed with an interceptor hook for offline queueing (Sub-Project 2).
4. **`ReceiptApiClient`** (`receipt_api_client.dart`):
   - Handles multi-page receipt image uploads and ZATCA QR code analysis (`/agent/scan-receipt`).
5. **`ChatApiClient`** (`chat_api_client.dart`):
   - Handles natural language expense logging (`/agent/chat-transaction`), purchase simulations (`/agent/simulate-purchase`), and offline regex fallback parsing.
6. **Backward-Compatible Facade (`ApiService`)**:
   - `ApiService.instance` acts as a unified facade delegating calls to `budgetApi`, `transactionApi`, `receiptApi`, and `chatApi`. Existing consumers experience zero breaking changes.

### 2.2 Dashboard Screen De-Bloat (`lib/widgets/dashboard/`)
`lib/screens/home/dashboard_screen.dart` (911 lines) contains tight coupling between UI styling, state listeners, and dialog flows.

#### Design:
Extract modular widgets into `lib/widgets/dashboard/`:
- **`SalaryCycleCard`**: Displays days remaining to payday (27th), burn rate per day, circular progress indicator, and budget pace status.
- **`BudgetHeroCard`**: Displays total allocated budget, total spent, remaining balance, and over-budget projection warning banner.
- **`PartnerSettlementCard`**: Displays 50/50 balance settlement status between partners with "Partner Owes You" visual badges.
- **`SubAllocationsSection`**: Renders category budgets and sub-allocations with progress bars.
- **`DashboardActionSheet`**: Bottom modal containing AI Chat, VAT Receipt Scanner, and Quick Expense creation actions.

---

## 3. Sub-Project 2: Offline SQLite Queue & Sync Engine

### 3.1 Motivation & Requirements
When a user records an expense (via SMS auto-ingest, quick entry, or offline receipt scan) while on poor cellular network or without internet connectivity:
- The app must immediately record the transaction locally with zero latency.
- The UI must optimistically update local budget calculations and state.
- When network connectivity is restored, a background queue worker must replay pending operations against the backend with idempotency keys.

### 3.2 Database Schema (`sqflite`)
```sql
CREATE TABLE offline_sync_queue (
    id TEXT PRIMARY KEY,
    operation_type TEXT NOT NULL, -- 'INSERT_TRANSACTION', 'ENRICH_TRANSACTION'
    payload TEXT NOT NULL,        -- JSON serialized request body
    idempotency_key TEXT UNIQUE,  -- SHA-256 fingerprint
    status TEXT NOT NULL,         -- 'PENDING', 'SYNCING', 'FAILED'
    retry_count INTEGER DEFAULT 0,
    created_at TEXT NOT NULL,
    last_error TEXT
);
```

### 3.3 Sync Engine Architecture
- **`OfflineQueueManager`**: Manages SQLite CRUD for pending sync items.
- **`SyncWorker`**: Listens to connectivity changes (`connectivity_plus`) and app resume lifecycle events to trigger drain operations sequentially with exponential backoff.
- **Idempotency Guarantee**: Submits deterministic client-generated transaction IDs so repeated network replays never create duplicate database rows.

---

## 4. Sub-Project 3: Recurring Bill & Subscription Predictor

### 4.1 Concept
Many Saudi household expenses occur on a predictable monthly cadence:
- **Telecom:** STC, Mobily, Zain (typically between 25th and 1st).
- **Utilities:** Saudi Electricity Company (SEC), National Water Company (NWC).
- **Housing:** Rent installment (monthly, quarterly, or bi-annually).
- **Digital Subscriptions:** Netflix, Spotify, iCloud, YouTube Premium.

### 4.2 Backend Predictor Engine (`ai_service/recurring_detector.py`)
- Analyzes historic transaction clusters for a household:
  - Amount variance <= 5% (fixed bills) or seasonal variance (electricity).
  - Interval consistency (every 28-32 days).
  - Merchant pattern matching (`STC`, `Saudi Electricity`, `Mobily`, `Netflix`).
- Endpoint: `GET /budgets/recurring-bills?household_id={id}`
  - Returns list of detected recurring bills: `merchant`, `expected_day`, `average_amount`, `status` (`PAID_THIS_CYCLE`, `UPCOMING`, `OVERDUE`).
  - Calculates `reserved_amount`: Total sum of upcoming unpaid bills for the active cycle.

### 4.3 Mobile UI Integration
- The `SalaryCycleCard` in the dashboard integrates the "Reserved for Recurring Bills" indicator, automatically adjusting the allowable daily burn rate:
  $$\text{Effective Daily Allowance} = \frac{\text{Remaining Budget} - \text{Unpaid Recurring Reserves}}{\text{Days Remaining to Payday}}$$

---

## 5. Testing & Verification Strategy

1. **Unit Tests:**
   - Flutter tests for each domain API client (`budget_api_client_test.dart`, `transaction_api_client_test.dart`, `receipt_api_client_test.dart`, `chat_api_client_test.dart`).
   - Flutter tests for dashboard modular widgets.
   - Flutter tests for `OfflineQueueManager` and replay worker.
   - Pytest tests for `recurring_detector.py` and `/budgets/recurring-bills` API.
2. **Integration & Physical Device Verification:**
   - Run full test suites (`flutter test`, `pytest`).
   - Build debug APK and install on physical Realme 8 (`DUGIWSL74PWCJFHA`).
   - Verify dashboard navigation, offline queueing, and recurring bill indicators.

---

## 6. Branch & Policy Adherence
- All changes are strictly made on `refactor/mobile-architecture-and-technical-fixes`.
- **Zero pushes or merges to `origin/main`** until explicitly instructed by the user.
