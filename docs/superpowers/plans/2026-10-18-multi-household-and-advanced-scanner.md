# Multi-Household Switching, On-Device OCR Fallback & Sequential Batch Receipt Queue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement multi-household membership and dynamic switching, lightweight on-device OCR fallback for offline receipt scanning, and a sequential batch multi-receipt scanning queue in the Flutter app and Supabase backend.

**Architecture:** 
1. Multi-household tenancy uses a Hybrid Junction Pattern: `public.household_memberships` tracks all user households while preserving `users.household_id` as the active context pointer, keeping 100% of existing RLS policies intact.
2. Offline receipt fallback uses an abstracted `LocalOcrService` and `SaudiReceiptTextParser` to extract store name and SAR totals when disconnected, queuing drafts in `budget_tracker_offline.db` for later Gemini cloud line-item enrichment.
3. Batch scanning uses a continuous shutter capture camera into a thumbnail queue, driving a sequential step-by-step review and save flow (`Receipt X of Y`).

**Tech Stack:** Flutter 3.x, Dart, Supabase PostgreSQL with RLS, SQLite (`sqflite`), Provider state management, Python FastAPI (`ai_service`), Google ML Kit / regex parsing.

**Spec:** [`docs/superpowers/specs/2026-10-18-multi-household-and-advanced-scanner-design.md`](file:///c:/Users/A/OneDrive/Python%20projects/budget-tracker/docs/superpowers/specs/2026-10-18-multi-household-and-advanced-scanner-design.md)

## Global Constraints

- **Branch Isolation:** Work strictly on `feature/multi-source-income-and-accounts`. Do not push or switch to `main`.
- **Zero SMS Interception:** Strict adherence to Rule 4.1. No SMS permissions or background listeners.
- **RLS Invariant:** Tenancy must remain strictly isolated via `household_id IN (SELECT household_id FROM public.users WHERE id = auth.uid())`.
- **Zero Hardcoded Strings:** Every UI label, error, and status must be localized in `AppLocalizations` across `en`, `ar`, and `ur`.
- **Code Quality:** Zero `flutter analyze` warnings, full unit and widget test coverage.

---

### Task 1: Supabase Database Migration for Multi-Household Memberships & Switching RPC

**Files:**
- Create: `supabase/migrations/20261018_household_memberships_and_switching.sql`
- Test: `ai_service/tests/test_multi_household_migration.py`

**Interfaces:**
- Produces: 
  - Table `public.household_memberships(id, household_id, user_id, role, is_default, created_at)`
  - RPC `switch_active_household(p_household_id UUID)`
  - RPC `get_user_households()`

- [ ] **Step 1: Write the failing SQL test script**

```python
# ai_service/tests/test_multi_household_migration.py
import pytest

def test_migration_sql_syntax():
    with open("supabase/migrations/20261018_household_memberships_and_switching.sql", "r", encoding="utf-8") as f:
        sql = f.read()
    assert "CREATE TABLE IF NOT EXISTS public.household_memberships" in sql
    assert "switch_active_household" in sql
    assert "get_user_households" in sql
    assert "INSERT INTO public.household_memberships" in sql # Backfill
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ai_service/.venv/Scripts/pytest -v ai_service/tests/test_multi_household_migration.py`
Expected: FAIL with "FileNotFoundError"

- [ ] **Step 3: Write migration SQL file**

```sql
-- supabase/migrations/20261018_household_memberships_and_switching.sql
-- Description: Creates household_memberships junction table, backfills existing users, and adds switch_active_household RPC.

-- 1. Create household_memberships table
CREATE TABLE IF NOT EXISTS public.household_memberships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    is_default BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_household_user UNIQUE (household_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_memberships_user ON public.household_memberships(user_id);
CREATE INDEX IF NOT EXISTS idx_memberships_household ON public.household_memberships(household_id);

-- 2. Enable RLS
ALTER TABLE public.household_memberships ENABLE ROW LEVEL SECURITY;

-- 3. RLS Policies
DROP POLICY IF EXISTS "memberships_view_own" ON public.household_memberships;
CREATE POLICY "memberships_view_own" ON public.household_memberships
    FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS "memberships_admin_manage" ON public.household_memberships;
CREATE POLICY "memberships_admin_manage" ON public.household_memberships
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.household_memberships m
            WHERE m.household_id = household_memberships.household_id
              AND m.user_id = auth.uid()
              AND m.role = 'admin'
        )
    );

-- 4. Backfill existing user household assignments
INSERT INTO public.household_memberships (household_id, user_id, role, is_default)
SELECT household_id, id, role, true
FROM public.users
WHERE household_id IS NOT NULL
ON CONFLICT (household_id, user_id) DO NOTHING;

-- 5. RPC function to get all households for current user
CREATE OR REPLACE FUNCTION public.get_user_households()
RETURNS TABLE (
    household_id UUID,
    household_name TEXT,
    invite_code TEXT,
    role TEXT,
    is_active BOOLEAN
) LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    RETURN QUERY
    SELECT 
        h.id AS household_id,
        h.name AS household_name,
        h.invite_code,
        m.role,
        (h.id = u.household_id) AS is_active
    FROM public.household_memberships m
    JOIN public.households h ON h.id = m.household_id
    JOIN public.users u ON u.id = m.user_id
    WHERE m.user_id = auth.uid()
    ORDER BY is_active DESC, m.created_at ASC;
END;
$$;

-- 6. RPC function to switch active household context
CREATE OR REPLACE FUNCTION public.switch_active_household(p_household_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_role TEXT;
    v_name TEXT;
BEGIN
    SELECT role INTO v_role
    FROM public.household_memberships
    WHERE household_id = p_household_id AND user_id = auth.uid();

    IF v_role IS NULL THEN
        RAISE EXCEPTION 'Access denied: Not a member of household %', p_household_id;
    END IF;

    SELECT name INTO v_name
    FROM public.households
    WHERE id = p_household_id;

    UPDATE public.users
    SET household_id = p_household_id,
        role = v_role
    WHERE id = auth.uid();

    RETURN jsonb_build_object(
        'success', true,
        'household_id', p_household_id,
        'household_name', v_name,
        'role', v_role
    );
END;
$$;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ai_service/.venv/Scripts/pytest -v ai_service/tests/test_multi_household_migration.py`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20261018_household_memberships_and_switching.sql ai_service/tests/test_multi_household_migration.py
git commit -m "feat(db): add household_memberships table and switch_active_household RPC"
```

---

### Task 2: Flutter Multi-Household Models & API Client Integration

**Files:**
- Create: `flutter_app/lib/models/household_membership.dart`
- Modify: `flutter_app/lib/models/models.dart` (export `household_membership.dart`)
- Modify: `flutter_app/lib/services/api/budget_api_client.dart`
- Modify: `flutter_app/lib/services/api_service.dart`
- Test: `flutter_app/test/services/household_membership_test.dart`

**Interfaces:**
- Produces:
  - `class HouseholdMembership { String householdId, householdName, inviteCode, role; bool isActive; }`
  - `Future<List<HouseholdMembership>> getUserHouseholds()`
  - `Future<bool> switchActiveHousehold(String householdId)`

- [ ] **Step 1: Write the failing unit test**

```dart
// flutter_app/test/services/household_membership_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/household_membership.dart';

void main() {
  group('HouseholdMembership Model Tests', () {
    test('parses from map correctly', () {
      final map = {
        'household_id': 'hh-123',
        'household_name': 'Riyadh Flat',
        'invite_code': 'RF123456',
        'role': 'admin',
        'is_active': true,
      };

      final m = HouseholdMembership.fromMap(map);
      expect(m.householdId, 'hh-123');
      expect(m.householdName, 'Riyadh Flat');
      expect(m.inviteCode, 'RF123456');
      expect(m.role, 'admin');
      expect(m.isAdmin, true);
      expect(m.isActive, true);
    });

    test('serializes to map correctly', () {
      const m = HouseholdMembership(
        householdId: 'hh-456',
        householdName: "Parents' Villa",
        inviteCode: 'PV654321',
        role: 'member',
        isActive: false,
      );

      final map = m.toMap();
      expect(map['household_id'], 'hh-456');
      expect(map['role'], 'member');
      expect(m.isAdmin, false);
      expect(map['is_active'], false);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/household_membership_test.dart`
Expected: FAIL with "Target of URI doesn't exist"

- [ ] **Step 3: Implement `HouseholdMembership` model and API methods**

```dart
// flutter_app/lib/models/household_membership.dart
class HouseholdMembership {
  final String householdId;
  final String householdName;
  final String inviteCode;
  final String role;
  final bool isActive;

  const HouseholdMembership({
    required this.householdId,
    required this.householdName,
    required this.inviteCode,
    this.role = 'member',
    this.isActive = false,
  });

  bool get isAdmin => role.toLowerCase() == 'admin';

  factory HouseholdMembership.fromMap(Map<String, dynamic> map) {
    return HouseholdMembership(
      householdId: map['household_id'] as String? ?? '',
      householdName: map['household_name'] as String? ?? 'Household',
      inviteCode: map['invite_code'] as String? ?? '',
      role: map['role'] as String? ?? 'member',
      isActive: map['is_active'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'household_id': householdId,
      'household_name': householdName,
      'invite_code': inviteCode,
      'role': role,
      'is_active': isActive,
    };
  }
}
```

Add methods in `BudgetApiClient` & `ApiService`:
```dart
Future<List<HouseholdMembership>> getUserHouseholds() async { ... }
Future<bool> switchActiveHousehold(String householdId) async { ... }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/household_membership_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/models/household_membership.dart flutter_app/lib/models/models.dart flutter_app/lib/services/api/budget_api_client.dart flutter_app/lib/services/api_service.dart flutter_app/test/services/household_membership_test.dart
git commit -m "feat: add HouseholdMembership model and switching API endpoints"
```

---

### Task 3: Flutter `HouseholdSwitchSheet` & Global Provider Re-hydration

**Files:**
- Create: `flutter_app/lib/widgets/settings/household_switch_sheet.dart`
- Modify: `flutter_app/lib/screens/settings/ingestion_settings_screen.dart`
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart`
- Modify: `flutter_app/lib/l10n/app_localizations.dart`
- Test: `flutter_app/test/widgets/household_switch_sheet_test.dart`

**Interfaces:**
- Produces: `HouseholdSwitchSheet.show(BuildContext context, {required String currentHouseholdId})`
- Refreshes: `TransactionProvider`, `BudgetProvider`, `AccountService`

- [ ] **Step 1: Write the failing widget test**

```dart
// flutter_app/test/widgets/household_switch_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/household_membership.dart';
import 'package:budget_tracker/widgets/settings/household_switch_sheet.dart';

void main() {
  testWidgets('renders list of households and triggers switch callback', (tester) async {
    final memberships = [
      const HouseholdMembership(
        householdId: 'hh-1',
        householdName: 'Personal Flat',
        inviteCode: 'CODE1',
        role: 'admin',
        isActive: true,
      ),
      const HouseholdMembership(
        householdId: 'hh-2',
        householdName: "Parents' Villa",
        inviteCode: 'CODE2',
        role: 'member',
        isActive: false,
      ),
    ];

    String? switchedId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HouseholdSwitchSheetContent(
            memberships: memberships,
            currentHouseholdId: 'hh-1',
            onSwitch: (id) => switchedId = id,
            onJoinNew: () {},
            onCreateNew: () {},
          ),
        ),
      ),
    );

    expect(find.text('Personal Flat'), findsOneWidget);
    expect(find.text("Parents' Villa"), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);

    await tester.tap(find.text("Parents' Villa"));
    await tester.pumpAndSettle();

    expect(switchedId, 'hh-2');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/household_switch_sheet_test.dart`
Expected: FAIL with "Target of URI doesn't exist"

- [ ] **Step 3: Implement `HouseholdSwitchSheet` and add trilingual strings**

Add strings in `app_localizations.dart` for English, Arabic, and Urdu:
- `switch_household`: 'Switch Household' / 'تبديل المنزل' / 'گھر تبدیل کریں'
- `active_badge`: 'Active' / 'النشط' / 'فعال'
- `join_another_household`: 'Join Another Household' / 'الانضمام لمنزل آخر' / 'کسی دوسرے گھر میں شامل ہوں'
- `create_new_household`: 'Create New Household' / 'إنشاء منزل جديد' / 'نیا گھر بنائیں'

Build `household_switch_sheet.dart`:
Renders styled radio items with role badges (`Admin` / `Member`), active indicator, and action buttons for joining/creating another household.
Connect to `ingestion_settings_screen.dart` via `_showHouseholdSwitchSheet` and to `dashboard_screen.dart` header chip.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/household_switch_sheet_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/settings/household_switch_sheet.dart flutter_app/lib/screens/settings/ingestion_settings_screen.dart flutter_app/lib/screens/home/dashboard_screen.dart flutter_app/lib/l10n/app_localizations.dart flutter_app/test/widgets/household_switch_sheet_test.dart
git commit -m "feat: add HouseholdSwitchSheet for seamless multi-household switching"
```

---

### Task 4: On-Device OCR Offline Text Extraction & Saudi Regex Parser

**Files:**
- Create: `flutter_app/lib/services/ocr/saudi_receipt_text_parser.dart`
- Create: `flutter_app/lib/services/ocr/local_ocr_service.dart`
- Test: `flutter_app/test/services/saudi_receipt_text_parser_test.dart`

**Interfaces:**
- Produces:
  - `class ParsedReceiptDraft { String merchant; double amount; double vatAmount; DateTime? date; double confidence; }`
  - `SaudiReceiptTextParser.parse(String rawText) -> ParsedReceiptDraft`
  - `LocalOcrService.extractFromImage(File imageFile) -> Future<ParsedReceiptDraft>`

- [ ] **Step 1: Write the failing unit test with Saudi receipt text samples**

```dart
// flutter_app/test/services/saudi_receipt_text_parser_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/services/ocr/saudi_receipt_text_parser.dart';

void main() {
  group('SaudiReceiptTextParser Tests', () {
    test('extracts total amount and merchant from Arabic grocery receipt', () {
      const sampleText = '''
أسواق عبدالله العثيم
Al Othaim Markets
الفرع: حي النرجس - الرياض
الرقم الضريبي: 300055555500003
التاريخ: 2026-10-18 14:22
حليب المراعي 2 لتر    14.50
أرز أبو كاس 5 كجم     42.00
دجاج ساديا 1000 جم    18.50
المجموع قبل الضريبة:  65.22
ضريبة القيمة المضافة 15%: 9.78
المجموع الكلي: 75.00 ر.س
شكراً لزيارتكم
''';

      final draft = SaudiReceiptTextParser.parse(sampleText);
      expect(draft.merchant.toLowerCase(), contains('othaim'));
      expect(draft.amount, 75.00);
      expect(draft.vatAmount, 9.78);
    });

    test('extracts total from English dining receipt with SAR currency', () {
      const sampleText = '''
AL BAIK RESTAURANT
Branch: Al Tahlia St, Jeddah
Tax Invoice: 998822
Date: 18/10/2026
Chicken Meal 4 Pcs    21.00
Garlic Sauce           3.00
Soft Drink             4.50
SUBTOTAL:             24.78
VAT 15%:               3.72
TOTAL AMOUNT:      SAR 28.50
THANK YOU
''';

      final draft = SaudiReceiptTextParser.parse(sampleText);
      expect(draft.merchant.toLowerCase(), contains('al baik'));
      expect(draft.amount, 28.50);
      expect(draft.vatAmount, 3.72);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/saudi_receipt_text_parser_test.dart`
Expected: FAIL with "Target of URI doesn't exist"

- [ ] **Step 3: Implement `SaudiReceiptTextParser` and `LocalOcrService`**

```dart
// flutter_app/lib/services/ocr/saudi_receipt_text_parser.dart
class ParsedReceiptDraft {
  final String merchant;
  final double amount;
  final double vatAmount;
  final DateTime? date;
  final double confidence;

  const ParsedReceiptDraft({
    required this.merchant,
    required this.amount,
    this.vatAmount = 0.0,
    this.date,
    this.confidence = 0.5,
  });
}

class SaudiReceiptTextParser {
  static const List<Map<String, String>> knownMerchants = [
    {'key': 'othaim', 'name': 'Al Othaim Markets'},
    {'key': 'عثيم', 'name': 'أسواق عبدالله العثيم'},
    {'key': 'panda', 'name': 'Panda Supermarket'},
    {'key': 'بنده', 'name': 'بنده'},
    {'key': 'danube', 'name': 'Danube'},
    {'key': 'الدانوب', 'name': 'الدانوب'},
    {'key': 'carrefour', 'name': 'Carrefour'},
    {'key': 'كارفور', 'name': 'كارفور'},
    {'key': 'lulu', 'name': 'LuLu Hypermarket'},
    {'key': 'لولو', 'name': 'لولو هايبر ماركت'},
    {'key': 'tamimi', 'name': 'Tamimi Markets'},
    {'key': 'التميمي', 'name': 'أسواق التميمي'},
    {'key': 'al baik', 'name': 'Al Baik'},
    {'key': 'البيك', 'name': 'البيك'},
    {'key': 'barns', 'name': "Barn's Coffee"},
    {'key': 'بارنز', 'name': 'بارنز كافيه'},
    {'key': 'dunkin', 'name': 'Dunkin'},
    {'key': 'starbucks', 'name': 'Starbucks'},
    {'key': 'nahdi', 'name': 'Al Nahdi Pharmacy'},
    {'key': 'النهدي', 'name': 'صيدلية النهدي'},
    {'key': 'sasco', 'name': 'SASCO Fuel'},
    {'key': 'ساسكو', 'name': 'ساسكو'},
    {'key': 'aldrees', 'name': 'Aldrees Petroleum'},
    {'key': 'الدريس', 'name': 'الدريس'},
  ];

  static ParsedReceiptDraft parse(String text) {
    // 1. Identify Merchant
    String merchant = 'Merchant';
    final lower = text.toLowerCase();
    for (final m in knownMerchants) {
      if (lower.contains(m['key']!)) {
        merchant = m['name']!;
        break;
      }
    }

    // 2. Extract Total Amount
    double amount = 0.0;
    final totalPatterns = [
      RegExp(r'(?:المجموع\s*الكلي|المجموع|الإجمالي|صافي\s*القيمة|total\s*amount|total|net\s*amount)[\s:]*([0-9]+(?:\.[0-9]{1,2})?)', caseSensitive: false),
      RegExp(r'(?:sar|ر\.س|sr)[\s:]*([0-9]+(?:\.[0-9]{1,2})?)', caseSensitive: false),
      RegExp(r'([0-9]+(?:\.[0-9]{1,2})?)[\s]*(?:sar|ر\.س|sr)', caseSensitive: false),
    ];
    for (final pattern in totalPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.group(1) != null) {
        final val = double.tryParse(match.group(1)!);
        if (val != null && val > amount) {
          amount = val;
        }
      }
    }

    // 3. Extract VAT Amount
    double vat = 0.0;
    final vatPattern = RegExp(r'(?:vat|ضريبة|15%)[\s\w:]*([0-9]+(?:\.[0-9]{1,2})?)', caseSensitive: false);
    final vatMatch = vatPattern.firstMatch(text);
    if (vatMatch != null && vatMatch.group(1) != null) {
      vat = double.tryParse(vatMatch.group(1)!) ?? 0.0;
    }

    return ParsedReceiptDraft(
      merchant: merchant,
      amount: amount,
      vatAmount: vat,
      date: DateTime.now(),
      confidence: (merchant != 'Merchant' && amount > 0) ? 0.85 : 0.4,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/saudi_receipt_text_parser_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/services/ocr/saudi_receipt_text_parser.dart flutter_app/lib/services/ocr/local_ocr_service.dart flutter_app/test/services/saudi_receipt_text_parser_test.dart
git commit -m "feat: add SaudiReceiptTextParser and LocalOcrService for offline fallback"
```

---

### Task 5: Offline Queue Integration for Receipt Drafts & Sync Worker Enrichment

**Files:**
- Modify: `flutter_app/lib/services/offline_queue_manager.dart`
- Modify: `flutter_app/lib/services/sync_worker.dart`
- Modify: `flutter_app/lib/screens/scanner/receipt_scanner_sheet.dart`
- Test: `flutter_app/test/services/offline_receipt_fallback_test.dart`

**Interfaces:**
- Produces:
  - Enqueue offline receipt draft with `operationType = 'receipt_offline_draft'` and `needs_cloud_enrichment: true`.
  - `SyncWorker.syncReceiptDraft(OfflineQueueItem item)` uploads image and enriches line items via Gemini Vision when internet returns.

- [ ] **Step 1: Write the failing unit test**

```dart
// flutter_app/test/services/offline_receipt_fallback_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:budget_tracker/services/offline_queue_manager.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late OfflineQueueManager queueManager;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    queueManager = OfflineQueueManager(customDb: db);
    await OfflineQueueManager.createSchema(db);
  });

  tearDown(() async => await db.close());

  test('enqueues offline receipt draft with pending cloud enrichment tag', () async {
    final item = await queueManager.enqueue(
      operationType: 'receipt_offline_draft',
      householdId: 'hh-123',
      payload: {
        'merchant': 'Al Othaim Supermarket',
        'amount': 150.0,
        'vat_amount': 22.5,
        'image_path': '/mock/receipt.jpg',
        'needs_cloud_enrichment': true,
      },
    );

    expect(item, isNotNull);
    expect(item!.operationType, 'receipt_offline_draft');
    final pending = await queueManager.getPendingItems();
    expect(pending.length, 1);
    expect(pending.first.payload['needs_cloud_enrichment'], true);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/offline_receipt_fallback_test.dart`
Expected: Verification of `enqueue` contract.

- [ ] **Step 3: Implement offline fallback handling in `receipt_scanner_sheet.dart` and `sync_worker.dart`**

When connectivity is offline and ZATCA QR is not present:
1. Run `LocalOcrService.extractFromImage(file)` to get `ParsedReceiptDraft`.
2. Populate the sheet with an orange `Offline Draft` badge and pre-filled fields.
3. Upon user confirmation, call `OfflineQueueManager.enqueue(operationType: 'receipt_offline_draft', ...)` and display success banner.
4. When `SyncWorker` executes online, it processes `receipt_offline_draft`, sends image bytes to Gemini Vision endpoint, and updates the transaction line items.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/offline_receipt_fallback_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/services/offline_queue_manager.dart flutter_app/lib/services/sync_worker.dart flutter_app/lib/screens/scanner/receipt_scanner_sheet.dart flutter_app/test/services/offline_receipt_fallback_test.dart
git commit -m "feat: integrate offline receipt draft queueing and sync worker enrichment"
```

---

### Task 6: Sequential Batch Multi-Receipt Scanning Queue (`BatchReceiptScannerScreen`)

**Files:**
- Create: `flutter_app/lib/screens/scanner/batch_receipt_scanner_screen.dart`
- Create: `flutter_app/lib/widgets/scanner/batch_item_review_sheet.dart`
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart` (add Batch Scan action to Speed Dial FAB)
- Modify: `flutter_app/lib/l10n/app_localizations.dart`
- Test: `flutter_app/test/screens/batch_receipt_scanner_screen_test.dart`

**Interfaces:**
- Produces:
  - `BatchReceiptScannerScreen(householdId: String)`
  - Continuous shutter capture into queue tray.
  - `BatchItemReviewSheet` for sequential `Receipt X of Y` step-by-step review.

- [ ] **Step 1: Write the failing widget test**

```dart
// flutter_app/test/screens/batch_receipt_scanner_screen_test.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/screens/scanner/batch_receipt_scanner_screen.dart';

void main() {
  testWidgets('renders batch receipt camera screen with empty queue tray', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BatchReceiptScannerScreen(householdId: 'hh-123'),
      ),
    );

    expect(find.byKey(const Key('batch_scanner_app_bar')), findsOneWidget);
    expect(find.byKey(const Key('batch_shutter_button')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/batch_receipt_scanner_screen_test.dart`
Expected: FAIL with "Target of URI doesn't exist"

- [ ] **Step 3: Implement `BatchReceiptScannerScreen` and `BatchItemReviewSheet`**

1. Build `BatchReceiptScannerScreen`:
   - Mobile camera viewfinder with live frame.
   - Shutter button with haptic feedback that adds taken photos to a thumbnail horizontal queue at the bottom.
   - Delete badge on each thumbnail to discard unwanted shots before processing.
   - "Process N Receipts" FAB that launches sequential stepper.
2. Build `BatchItemReviewSheet`:
   - Header: `Receipt ${index + 1} of ${total}` with progress bar.
   - Zoomable photo preview using `ReceiptPhotoViewerDialog`.
   - Extracted fields (Merchant, Amount, Category, Items).
   - `Skip this Receipt` button (advances index).
   - `Save & Next →` button (persists transaction, advances index, or finishes batch).
3. Add trilingual localizations in `app_localizations.dart` (`en`, `ar`, `ur`).
4. Connect to `dashboard_screen.dart` Speed Dial FAB.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/batch_receipt_scanner_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/scanner/batch_receipt_scanner_screen.dart flutter_app/lib/widgets/scanner/batch_item_review_sheet.dart flutter_app/lib/screens/home/dashboard_screen.dart flutter_app/lib/l10n/app_localizations.dart flutter_app/test/screens/batch_receipt_scanner_screen_test.dart
git commit -m "feat: add BatchReceiptScannerScreen with sequential item review queue"
```

---

### Task 7: End-to-End Verification, Analyzer & Quality Checks

**Files:**
- Entire codebase

- [ ] **Step 1: Run Flutter analyzer**

Run: `flutter analyze`
Expected: `No issues found!` (Zero warnings)

- [ ] **Step 2: Run all Flutter unit and widget tests**

Run: `flutter test`
Expected: All tests pass cleanly

- [ ] **Step 3: Run backend Python tests**

Run: `ai_service/.venv/Scripts/pytest -v`
Expected: All tests pass

- [ ] **Step 4: Commit and tag complete feature verification**

```bash
git add -A
git commit -m "chore: verify multi-household switching, on-device OCR, and batch scanning quality gates"
```
