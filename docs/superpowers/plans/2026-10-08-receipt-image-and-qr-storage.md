# Scanned Receipt Image Storage & ZATCA QR Retention Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist compressed scanned receipt photos in Supabase Storage, link them to transactions via `receipt_url`, retain ZATCA QR metadata for audit verification, and provide an interactive full-screen image viewer in the Flutter feed.

**Architecture:** Client-side camera photos are compressed on-device upon confirmation and uploaded to Supabase Storage (`receipts/{household_id}/{timestamp}_{uuid}.jpg`). The resulting URL and raw ZATCA QR codes are saved to PostgreSQL via `/agent/scan-receipt` and direct Supabase fallbacks. Transaction cards render a receipt badge, thumbnail, and interactive pinch-to-zoom viewer.

**Tech Stack:** Flutter 3.x, `supabase_flutter`, `image_picker`, FastAPI, Python 3.11, PostgreSQL / Supabase Storage RLS.

**Spec:** `docs/superpowers/specs/2026-10-08-receipt-image-and-qr-storage-design.md`

## Global Constraints

- Storage bucket name: `receipts`
- Storage file path convention: `receipts/{household_id}/{timestamp}_{uuid}.jpg`
- Receipt image format: JPEG, max dimension 1280px, quality 75–80% (target size ~80–140 KB)
- Upload timing: Confirm-only (upload happens when user saves transaction, never on cancel/preview)
- Graceful degradation: If image upload fails, transaction save must succeed with `receipt_url = null`
- Zero regression: Existing manual entry, chat entry, and duplicate candidate flows must remain fully functional

---

### Task 1: Supabase Storage Bucket Migration & Policies

**Files:**
- Create: `supabase/migrations/20261008_create_receipts_bucket_and_policies.sql`

**Interfaces:**
- Produces: Storage bucket `'receipts'` in Supabase with RLS policies restricting read/write to household members.

- [ ] **Step 1: Write the migration SQL file**

Create `supabase/migrations/20261008_create_receipts_bucket_and_policies.sql`:
```sql
-- Migration: Create receipts storage bucket and RLS policies
-- Bucket: receipts

INSERT INTO storage.buckets (id, name, public)
VALUES ('receipts', 'receipts', true)
ON CONFLICT (id) DO NOTHING;

-- Policy: Allow authenticated household members to upload receipts
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'objects' 
      AND schemaname = 'storage' 
      AND policyname = 'Household members can upload receipts'
  ) THEN
    CREATE POLICY "Household members can upload receipts"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
      bucket_id = 'receipts'
      AND EXISTS (
        SELECT 1 FROM public.household_members hm
        WHERE hm.user_id = auth.uid()
          AND hm.household_id::text = (storage.foldername(name))[1]
      )
    );
  END IF;
END $$;

-- Policy: Allow authenticated household members to view their receipts
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'objects' 
      AND schemaname = 'storage' 
      AND policyname = 'Household members can view receipts'
  ) THEN
    CREATE POLICY "Household members can view receipts"
    ON storage.objects FOR SELECT
    TO authenticated
    USING (
      bucket_id = 'receipts'
      AND EXISTS (
        SELECT 1 FROM public.household_members hm
        WHERE hm.user_id = auth.uid()
          AND hm.household_id::text = (storage.foldername(name))[1]
      )
    );
  END IF;
END $$;
```

- [ ] **Step 2: Verify SQL syntax**

Run: `git status` to ensure migration is created cleanly in `supabase/migrations/`.

- [ ] **Step 3: Commit migration**

```bash
git add supabase/migrations/20261008_create_receipts_bucket_and_policies.sql
git commit -m "feat(db): add storage migration for receipts bucket and RLS policies"
```

---

### Task 2: Backend API Receipt URL & ZATCA QR Handling

**Files:**
- Modify: `ai_service/receipt_scanner.py`
- Modify: `ai_service/main.py`
- Modify: `ai_service/tests/test_api_endpoints.py`

**Interfaces:**
- Consumes: `receipt_url: Optional[str]`, `qr_code_raw: Optional[str]` from `/agent/scan-receipt` request body.
- Produces: `receipt_url` persisted in `insert_transaction`, returned in response payload.

- [ ] **Step 1: Write failing test for `receipt_url` forwarding in `test_api_endpoints.py`**

In `ai_service/tests/test_api_endpoints.py`:
```python
def test_scan_receipt_with_receipt_url(client, test_household_id):
    """Verify /agent/scan-receipt accepts receipt_url and returns it."""
    payload = {
        "household_id": test_household_id,
        "qr_code_raw": "AQ5UYW1pbWkgTWFya2V0cwIPMzAwMDAwMDAwMDAwMDAzAxQyMDI2LTEwLTA0VDIyOjE5OjM0WgQHNTAwLjAwBQY2NS4yMg==",
        "receipt_url": "https://example.supabase.co/storage/v1/object/public/receipts/test.jpg",
        "preview_only": True,
    }
    raw = json.dumps(payload).encode("utf-8")
    sig = hmac.new(b"dev_secret_key", raw, hashlib.sha256).hexdigest()
    headers = {"X-Signature": f"sha256={sig}", "Content-Type": "application/json"}
    
    response = client.post("/agent/scan-receipt", content=raw, headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] in ("preview", "success")
    assert data.get("receipt_url") == "https://example.supabase.co/storage/v1/object/public/receipts/test.jpg"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest ai_service/tests/test_api_endpoints.py -k test_scan_receipt_with_receipt_url`
Expected: FAIL (assertion error because `receipt_url` is not yet returned in preview/success response).

- [ ] **Step 3: Update `ai_service/receipt_scanner.py` and `ai_service/main.py`**

In `ai_service/main.py`:
Extract `receipt_url = body.get("receipt_url")` and pass to `process_receipt_scan`:
```python
    result = await asyncio.to_thread(
        process_receipt_scan,
        household_id=household_id,
        images_base64=images_base64,
        qr_code_raw=qr_code_raw,
        user_id=body.get("user_id"),
        allow_duplicate=bool(body.get("allow_duplicate", False)),
        enrich_tx_id=body.get("enrich_tx_id"),
        preview_only=bool(body.get("preview_only", False)),
        override_merchant=body.get("merchant"),
        override_spent_by=body.get("spent_by"),
        receipt_url=body.get("receipt_url"),
    )
```

In `ai_service/receipt_scanner.py`:
Update `process_receipt_scan` signature to include `receipt_url: Optional[str] = None`:
Pass `receipt_url=receipt_url` to `insert_transaction(...)`:
Include `"receipt_url": receipt_url` in both `preview` and `success` returned dictionaries.

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest ai_service/tests/test_api_endpoints.py -k test_scan_receipt_with_receipt_url`
Expected: PASS.

- [ ] **Step 5: Run full test suite for `ai_service`**

Run: `pytest ai_service/tests/ -v`
Expected: All tests PASS.

- [ ] **Step 6: Commit backend changes**

```bash
git add ai_service/main.py ai_service/receipt_scanner.py ai_service/tests/test_api_endpoints.py
git commit -m "feat(api): support receipt_url persistence in receipt scanner"
```

---

### Task 3: Flutter Receipt Storage Service

**Files:**
- Create: `flutter_app/lib/services/receipt_storage_service.dart`
- Create: `flutter_app/test/services/receipt_storage_service_test.dart`

**Interfaces:**
- Produces: `ReceiptStorageService.uploadReceipt({required File imageFile, required String householdId}) -> Future<String?>`

- [ ] **Step 1: Write unit tests in `receipt_storage_service_test.dart`**

Create `flutter_app/test/services/receipt_storage_service_test.dart`:
```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/services/receipt_storage_service.dart';

void main() {
  group('ReceiptStorageService', () {
    test('generateStoragePath creates sanitized path under household partition', () {
      const householdId = 'hh-123-abc';
      final path = ReceiptStorageService.generateStoragePath(householdId, 'test.jpg');
      expect(path.startsWith('hh-123-abc/'), isTrue);
      expect(path.endsWith('.jpg'), isTrue);
    });

    test('uploadReceipt returns null if image file does not exist', () async {
      final service = ReceiptStorageService();
      final nonExistent = File('non_existent_receipt.jpg');
      final result = await service.uploadReceipt(
        imageFile: nonExistent,
        householdId: 'hh-123-abc',
      );
      expect(result, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/receipt_storage_service_test.dart`
Expected: FAIL (file `receipt_storage_service.dart` not found).

- [ ] **Step 3: Implement `ReceiptStorageService`**

Create `flutter_app/lib/services/receipt_storage_service.dart`:
```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ReceiptStorageService {
  final SupabaseClient? _client;
  static const String bucketName = 'receipts';

  ReceiptStorageService({SupabaseClient? client}) : _client = client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  static String generateStoragePath(String householdId, String originalFileName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final uuid = const Uuid().v4().substring(0, 8);
    final ext = originalFileName.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    return '$householdId/${timestamp}_$uuid.$ext';
  }

  /// Uploads a receipt image to Supabase Storage and returns its public URL.
  /// Gracefully catches exceptions and returns null so financial saves are never blocked.
  Future<String?> uploadReceipt({
    required File imageFile,
    required String householdId,
  }) async {
    try {
      if (!await imageFile.exists()) {
        debugPrint('[ReceiptStorageService] Image file does not exist: ${imageFile.path}');
        return null;
      }

      final Uint8List bytes = await imageFile.readAsBytes();
      if (bytes.isEmpty) return null;

      final path = generateStoragePath(householdId, imageFile.path);

      await _supabase.storage.from(bucketName).uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: true,
        ),
      );

      final publicUrl = _supabase.storage.from(bucketName).getPublicUrl(path);
      debugPrint('[ReceiptStorageService] Uploaded receipt to: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('[ReceiptStorageService] Failed to upload receipt image: $e');
      return null;
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/receipt_storage_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit `ReceiptStorageService`**

```bash
git add flutter_app/lib/services/receipt_storage_service.dart flutter_app/test/services/receipt_storage_service_test.dart
git commit -m "feat(mobile): add ReceiptStorageService for Supabase Storage uploads"
```

---

### Task 4: Integrate Upload & ZATCA Retention in `ReceiptScannerSheet`

**Files:**
- Modify: `flutter_app/lib/screens/scanner/receipt_scanner_sheet.dart`
- Modify: `flutter_app/lib/services/api/receipt_api_client.dart` (and `api_service.dart`)

**Interfaces:**
- Consumes: `ReceiptStorageService.uploadReceipt`.
- Produces: `receiptUrl` passed to `ApiService.instance.scanReceipt` and `_fallbackSaveToSupabase`.

- [ ] **Step 1: Update `scanReceipt` in `receipt_api_client.dart` and `api_service.dart` to accept `receiptUrl`**

In `flutter_app/lib/services/api/receipt_api_client.dart`:
Add parameter `String? receiptUrl`:
```dart
    if (receiptUrl != null) 'receipt_url': receiptUrl,
```
Pass it in `ApiService.instance.scanReceipt(...)`.

- [ ] **Step 2: Update `_addPhoto` image quality in `receipt_scanner_sheet.dart`**

Optimize camera capture compression in `_addPhoto`:
```dart
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 78,
        maxWidth: 1280,
        maxHeight: 1280,
      );
```

- [ ] **Step 3: Update `_confirmSave` and `_fallbackSaveToSupabase` in `receipt_scanner_sheet.dart`**

In `_confirmSave`:
1. If `_imageFiles.isNotEmpty`, upload primary photo via `ReceiptStorageService().uploadReceipt(imageFile: _imageFiles.first, householdId: widget.householdId)`.
2. Pass `receiptUrl: uploadedReceiptUrl` into `ApiService.instance.scanReceipt(...)`.
3. In `_fallbackSaveToSupabase`: include `'receipt_url': uploadedReceiptUrl`.
4. Include `_zatcaQrRaw` in `raw_sms` audit text and metadata so tax code is permanently preserved.

- [ ] **Step 4: Run flutter tests to verify no compilation or syntax errors**

Run: `flutter test test/services/base_api_client_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit changes in scanner sheet**

```bash
git add flutter_app/lib/screens/scanner/receipt_scanner_sheet.dart flutter_app/lib/services/api/receipt_api_client.dart flutter_app/lib/services/api_service.dart
git commit -m "feat(mobile): upload receipt image on save confirmation and pass receiptUrl"
```

---

### Task 5: Receipt Photo Viewer & Feed Card Integration

**Files:**
- Create: `flutter_app/lib/widgets/receipt_photo_viewer_dialog.dart`
- Modify: `flutter_app/lib/widgets/transaction_item_breakdown_card.dart`
- Modify: `flutter_app/lib/screens/home/transaction_feed_screen.dart`
- Create: `flutter_app/test/widgets/receipt_viewer_and_card_test.dart`

**Interfaces:**
- Consumes: `tx.receiptUrl` passed from `TransactionFeedScreen` into `TransactionItemBreakdownCard`.
- Produces: `ReceiptPhotoViewerDialog.show(context, receiptUrl: ..., merchant: ...)` with interactive pinch-to-zoom.

- [ ] **Step 1: Write widget test for receipt badge and thumbnail**

Create `flutter_app/test/widgets/receipt_viewer_and_card_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/transaction_item_breakdown_card.dart';

void main() {
  testWidgets('TransactionItemBreakdownCard shows Receipt badge when receiptUrl is present', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TransactionItemBreakdownCard(
            merchant: 'Tamimi Markets',
            amount: 145.50,
            receiptUrl: 'https://example.com/receipt.jpg',
          ),
        ),
      ),
    );

    expect(find.text('Receipt'), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);
  });

  testWidgets('TransactionItemBreakdownCard hides Receipt badge when receiptUrl is null', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TransactionItemBreakdownCard(
            merchant: 'Tamimi Markets',
            amount: 145.50,
            receiptUrl: null,
          ),
        ),
      ),
    );

    expect(find.text('Receipt'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/receipt_viewer_and_card_test.dart`
Expected: FAIL (`receiptUrl` parameter does not exist on `TransactionItemBreakdownCard`).

- [ ] **Step 3: Create `ReceiptPhotoViewerDialog`**

Create `flutter_app/lib/widgets/receipt_photo_viewer_dialog.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ReceiptPhotoViewerDialog extends StatelessWidget {
  final String receiptUrl;
  final String merchant;
  final double? amount;

  const ReceiptPhotoViewerDialog({
    super.key,
    required this.receiptUrl,
    required this.merchant,
    this.amount,
  });

  static Future<void> show(
    BuildContext context, {
    required String receiptUrl,
    required String merchant,
    double? amount,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (_) => ReceiptPhotoViewerDialog(
        receiptUrl: receiptUrl,
        merchant: merchant,
        amount: amount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: [
          // Header Bar
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      merchant,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (amount != null)
                      Text(
                        'SAR ${amount!.toStringAsFixed(2)}',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFF00C896),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Interactive Zoomable Image
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: const Color(0xFF161B22),
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: Center(
                    child: Image.network(
                      receiptUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (ctx, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(color: Color(0xFF00C896)),
                        );
                      },
                      errorBuilder: (ctx, _, __) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.broken_image_outlined, size: 48, color: Color(0xFF8B949E)),
                            const SizedBox(height: 8),
                            Text(
                              'Unable to load receipt image',
                              style: GoogleFonts.outfit(color: const Color(0xFF8B949E)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Update `TransactionItemBreakdownCard` and `TransactionFeedScreen`**

In `flutter_app/lib/widgets/transaction_item_breakdown_card.dart`:
- Add `final String? receiptUrl;` to constructor.
- In subtitle chips row: if `receiptUrl != null && receiptUrl!.isNotEmpty`:
  render `[🧾 Receipt]` badge with `Icon(Icons.receipt_long_rounded, size: 11, color: Color(0xFF58A6FF))`.
- In expanded content section:
  If `receiptUrl != null && receiptUrl!.isNotEmpty`:
  render a `"RECEIPT PHOTO"` card containing a thumbnail with a tap handler calling `ReceiptPhotoViewerDialog.show(context, receiptUrl: receiptUrl!, merchant: merchant, amount: amount)`.

In `flutter_app/lib/screens/home/transaction_feed_screen.dart`:
Pass `receiptUrl: tx.receiptUrl` to `TransactionItemBreakdownCard`.

- [ ] **Step 5: Run widget tests to verify they pass**

Run: `flutter test test/widgets/receipt_viewer_and_card_test.dart`
Expected: All tests PASS.

- [ ] **Step 6: Run full test suite for `flutter_app`**

Run: `flutter test`
Expected: All tests PASS.

- [ ] **Step 7: Commit UI and viewer changes**

```bash
git add flutter_app/lib/widgets/receipt_photo_viewer_dialog.dart flutter_app/lib/widgets/transaction_item_breakdown_card.dart flutter_app/lib/screens/home/transaction_feed_screen.dart flutter_app/test/widgets/receipt_viewer_and_card_test.dart
git commit -m "feat(mobile): add receipt badge, thumbnail, and interactive full-screen viewer"
```

---

### Task 6: End-to-End Verification on Connected Device

**Files:**
- Test target: Realme 8 physical device (`DUGIWSL74PWCJFHA`)

- [ ] **Step 1: Execute Python backend test suite**

Run: `pytest ai_service/tests/ -v`
Expected: 100% tests passing.

- [ ] **Step 2: Execute Flutter test suite**

Run: `flutter test`
Expected: 100% tests passing.

- [ ] **Step 3: Run Flutter build verification**

Run: `flutter build apk --debug`
Expected: Build succeeds with 0 errors.

- [ ] **Step 4: Commit and push branch to origin**

```bash
git push origin main
```
