# Recurring Bill & Subscription Predictor Implementation Plan

> **Goal:** Detect recurring monthly household commitments (STC, Saudi Electricity, Mobily, Netflix, rent, subscriptions) via cadence and merchant pattern clustering, project unpaid reserves for the 27th payday cycle, and adjust daily allowance in mobile dashboard.

---

## Architecture Overview

### 1. Python Predictor Engine (`ai_service/recurring_detector.py`)
- Filters household transactions over the past 90-180 days.
- Groups transactions by normalized merchant / bill category.
- Detects monthly cadence (25-35 day intervals or known recurring providers: STC, SEC, Zain, Mobily, Netflix, Spotify, Prime, Apple).
- Compares against current active salary cycle (Payday 27th) to flag:
  - `PAID_THIS_CYCLE`: Already debited in the current cycle.
  - `UPCOMING`: Not yet debited, expected before payday.
  - `OVERDUE`: Expected date has passed in this cycle without a matching transaction.
- Calculates `reserved_amount` (unpaid recurring bills) and adjusts daily burn allowance.

### 2. FastAPI Endpoint (`GET /budgets/recurring-bills`)
- Route in `ai_service/main.py`.
- Returns list of detected recurring bills, total monthly recurring, amount paid this cycle, and reserved amount.

### 3. Mobile Model & API Client
- Model: `flutter_app/lib/models/recurring_bill.dart`.
- Client: `BudgetApiClient.fetchRecurringBills(...)` and `ApiService.instance.getRecurringBills(...)`.

### 4. Mobile Dashboard Widget
- Display upcoming vs paid recurring bills in the salary cycle widget or a dedicated `RecurringBillsCard`.
- Clearly show reserved funds so users never overspend before their bills clear.

---

## Detailed Task Breakdown

### Task 1: Implement `ai_service/recurring_detector.py` & Pytest
- File: `ai_service/recurring_detector.py`
- Test: `ai_service/tests/test_recurring_detector.py`
- Test-driven development of clustering logic, merchant normalization, cycle status, and reserve calculation.

### Task 2: Expose `GET /budgets/recurring-bills` in `ai_service/main.py`
- Modify: `ai_service/main.py`
- Test: `ai_service/tests/test_recurring_bills_api.py`
- Test endpoint parameters and JSON response format.

### Task 3: Mobile Model & API Client Integration
- Create: `flutter_app/lib/models/recurring_bill.dart`
- Modify: `flutter_app/lib/services/api/budget_api_client.dart`
- Modify: `flutter_app/lib/services/api_service.dart`
- Test: `flutter_app/test/models/recurring_bill_test.dart`

### Task 4: Integrate Recurring Bills Reserve into Mobile Dashboard
- Create: `flutter_app/lib/widgets/dashboard/recurring_bills_card.dart`
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart`
- Test: `flutter test`

### Task 5: Build Debug APK & Verify on Realme 8
- Build debug APK (`flutter build apk --debug`).
- Install on Realme 8 device (`DUGIWSL74PWCJFHA`).
- Capture screenshot verification of recurring bill reserves.
