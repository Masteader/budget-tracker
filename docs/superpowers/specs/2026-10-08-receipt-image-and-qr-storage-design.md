# Technical Architecture & Design: Scanned Receipt Image Storage & ZATCA QR Persistence

**Date:** 2026-10-08  
**Status:** Approved  

---

## 1. Overview & Goals

When scanning bills or invoices in the Budget Tracker app, users currently capture camera photos and/or scan Saudi ZATCA QR codes to automatically extract line items, merchant, and VAT totals via Gemini vision. However, the captured images are discarded after AI parsing, leaving transactions without persistent visual proof.

### Objectives
1. **Receipt Image Persistence**: Store compressed receipt photos in a secured Supabase Storage bucket (`receipts`) and link the image URL to `transactions.receipt_url`.
2. **Saudi ZATCA QR Retention**: Retain raw ZATCA Base64 payloads and decoded tax fields for audit validation.
3. **Bandwidth & Storage Optimization**: Compress camera captures on-device down to ~80–140 KB before upload to minimize cellular data and fit within free tier quotas (~8,000–10,000 receipts / GB).
4. **Rich Transaction Inspection**: Enable users to view a receipt thumbnail in the transaction feed and open a full-screen pinch-to-zoom viewer.
5. **Zero Waste Upload Lifecycle**: Upload images to storage only when the user confirms saving the transaction, avoiding orphan files from discarded or cancelled previews.

---

## 2. Storage Architecture & Bucket Security

### 2.1 Supabase Storage Bucket Configuration
* **Bucket Name:** `receipts`
* **Visibility:** Authenticated read/write partitioned by household.
* **Storage Path Scheme:**
  ```text
  receipts/{household_id}/{timestamp}_{uuid}.jpg
  ```
* **Directory Partitioning:** Partitioning by `household_id` enables clear tenant boundaries and straightforward Row Level Security (RLS) enforcement.

### 2.2 Row Level Security (RLS) Policies (SQL Migration)
A dedicated migration (`supabase/migrations/20261008_create_receipts_bucket_and_policies.sql`) provisions the bucket and security policies:
```sql
-- Create receipts storage bucket if it does not already exist
INSERT INTO storage.buckets (id, name, public)
VALUES ('receipts', 'receipts', true)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS: Allow authenticated household members to upload receipts
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

-- Storage RLS: Allow household members to view their receipts
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
```

---

## 3. Client-Side Image Compression & Upload Flow

### 3.1 Compression Specifications
High-end smartphone cameras produce 3–8 MB JPEGs. The mobile client compresses the chosen receipt photo before upload:
* **Max Dimension:** 1280px (maintains sharp text readability for small font receipt items).
* **Format:** JPEG.
* **Quality:** 75–80%.
* **Target Size:** 80 KB – 140 KB.

### 3.2 Service Layer (`ReceiptStorageService`)
A new dedicated service in `flutter_app/lib/services/receipt_storage_service.dart`:
```dart
class ReceiptStorageService {
  final SupabaseClient _supabase;
  
  ReceiptStorageService({SupabaseClient? supabaseClient})
      : _supabase = supabaseClient ?? Supabase.instance.client;

  /// Compresses and uploads a receipt image to Supabase Storage.
  /// Returns the public or signed URL, or null if upload fails.
  Future<String?> uploadReceipt({
    required File imageFile,
    required String householdId,
  });
}
```

### 3.3 Upload Lifecycle (Confirm-Only)
1. User captures receipt photo or selects from gallery in `ReceiptScannerSheet`.
2. Local preview is displayed and parsed via Gemini vision (`/agent/scan-receipt` with `preview_only: true`).
3. If user cancels or retries, **no network storage upload occurs**.
4. When user taps **"Save Transaction"** (`_confirmSave`):
   * Status indicator updates to `"Uploading receipt..."`.
   * `ReceiptStorageService.uploadReceipt(...)` sends the compressed JPEG to Supabase Storage.
   * Resulting `receipt_url` is supplied to both the API endpoint `/agent/scan-receipt` and the fallback direct Supabase insert method `_fallbackSaveToSupabase`.

---

## 4. Database & API Data Flow

### 4.1 Schema Usage
* The column `public.transactions.receipt_url TEXT` is already present in PostgreSQL.
* The column `public.transactions.raw_sms TEXT` or `metadata JSONB` stores the raw ZATCA QR string (`AQ5...`) and decoded tax metadata for audit verification.

### 4.2 Backend Endpoints (`ai_service`)
* In `ai_service/receipt_scanner.py`:
  * `process_receipt_scan` accepts optional `receipt_url: Optional[str] = None`.
  * Passes `receipt_url` to `insert_transaction(..., receipt_url=receipt_url)`.
* In `ai_service/main.py`:
  * Route `/agent/scan-receipt` extracts `receipt_url = body.get("receipt_url")` from the request JSON and forwards it to `process_receipt_scan`.

---

## 5. UI & Viewing Experience

### 5.1 Receipt Indicator in Feed
* In `flutter_app/lib/widgets/transaction_item_breakdown_card.dart`:
  * When `receiptUrl != null && receiptUrl.isNotEmpty`, a badge `[🧾 Receipt]` is rendered in the card subtitle chip row.

### 5.2 Receipt Photo Thumbnail & Viewer
* Inside the expanded `TransactionItemBreakdownCard`:
  * A **RECEIPT PHOTO** section shows a high-quality rounded thumbnail with a zoom icon overlay.
  * Tapping the thumbnail launches `ReceiptPhotoViewerDialog` or modal:
    * Built with `InteractiveViewer` supporting two-finger pinch-to-zoom and pan.
    * Full-screen high contrast dark backdrop (`#0D1117`).
    * Merchant name and transaction total in top bar with close button.
    * Loading indicator and error fallback with retry.

### 5.3 ZATCA Verification Badge
* If `tx.dedupFingerprint` or ZATCA metadata exists, displays the official green ZATCA Shield badge with:
  * Verified Seller Name.
  * 15% VAT Breakdown.
  * ZATCA Electronic Invoice QR indication.

---

## 6. Resilience & Error Handling

1. **Storage Network Failure During Save:**
   * If image upload fails (e.g. temporary timeout or offline drop), the transaction save continues with `receipt_url = null` rather than discarding the user's financial entry.
   * A gentle warning toast informs the user: *"Transaction saved (receipt photo upload failed)"*.
2. **Offline Mode:**
   * If user is offline, transaction queues locally; local image path is cached until online sync can upload to Supabase Storage.
3. **Corrupted/Missing Images in Viewer:**
   * Network image load errors display a fallback placeholder with an `Image unavailable` icon and retry button.

---

## 7. Testing Strategy

1. **Unit Tests:**
   * `ReceiptStorageServiceTest`: Test file compression, path generation (`receipts/{householdId}/{timestamp}_{id}.jpg`), and error handling when Supabase Storage returns an exception.
2. **Widget Tests:**
   * `TransactionItemBreakdownCardTest`: Verify `[🧾 Receipt]` badge renders when `receiptUrl` is provided, and does not render when `receiptUrl` is null.
   * Verify tapping receipt thumbnail triggers the interactive photo viewer.
3. **Integration / API Tests:**
   * Test `/agent/scan-receipt` accepting and storing `receipt_url` in `transactions`.
