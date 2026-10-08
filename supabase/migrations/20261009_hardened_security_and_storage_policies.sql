-- =============================================================================
-- Migration: Hardened Multi-Tenant Security Policies for Storage & Transactions
-- =============================================================================

-- ── 1. HARDEN STORAGE POLICIES (storage.objects) ──────────────────────────────
-- Bucket: receipts

-- Drop all old / loose policies on storage.objects for receipts
DROP POLICY IF EXISTS "Household members can view receipts" ON storage.objects;
DROP POLICY IF EXISTS "Household members can upload receipts" ON storage.objects;
DROP POLICY IF EXISTS "Household members can delete receipts" ON storage.objects;
DROP POLICY IF EXISTS "Allow select on receipts" ON storage.objects;
DROP POLICY IF EXISTS "Give users access to own folder" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated select" ON storage.objects;
DROP POLICY IF EXISTS "Allow all users to select" ON storage.objects;

-- Policy A: HARDENED INSERT (Uploads)
-- 1. Must be an authenticated user with a valid JWT
-- 2. Must belong to an active household
-- 3. File MUST be placed strictly inside user's household folder ({household_id}/...)
-- 4. ONLY allow valid image file extensions (jpg, jpeg, png, webp)
-- 5. Disallow path traversal attacks (..)
CREATE POLICY "hardened_receipt_insert"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'receipts'
  AND auth.uid() IS NOT NULL
  AND public.get_auth_user_household_id() IS NOT NULL
  AND (storage.foldername(name))[1] = public.get_auth_user_household_id()::text
  AND lower(storage.extension(name)) IN ('jpg', 'jpeg', 'png', 'webp')
  AND name NOT LIKE '%..%'
);

-- Policy B: HARDENED SELECT (Viewing & Listing)
-- Strictly partitioned per-household:
-- An authenticated user can ONLY access or list files residing in their own household folder.
-- Cross-household file access is strictly blocked.
CREATE POLICY "hardened_receipt_select"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'receipts'
  AND auth.uid() IS NOT NULL
  AND public.get_auth_user_household_id() IS NOT NULL
  AND (storage.foldername(name))[1] = public.get_auth_user_household_id()::text
);

-- Policy C: HARDENED DELETE
-- Strictly restricted to household members targeting files in their own folder.
CREATE POLICY "hardened_receipt_delete"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'receipts'
  AND auth.uid() IS NOT NULL
  AND public.get_auth_user_household_id() IS NOT NULL
  AND (storage.foldername(name))[1] = public.get_auth_user_household_id()::text
);

-- Policy D: IMMUTABLE AUDIT - BLOCK UPDATES
-- Receipt images are financial audit evidence and must NEVER be overwritten or mutated.
DROP POLICY IF EXISTS "hardened_receipt_update" ON storage.objects;
-- (No UPDATE policy = updates are completely rejected by RLS)


-- ── 2. HARDEN TRANSACTION POLICIES (public.transactions) ─────────────────────

-- Drop existing transaction policies
DROP POLICY IF EXISTS "transactions_select_household" ON public.transactions;
DROP POLICY IF EXISTS "transactions_insert_household" ON public.transactions;
DROP POLICY IF EXISTS "transactions_update_household" ON public.transactions;
DROP POLICY IF EXISTS "transactions_delete_household" ON public.transactions;

-- Transaction SELECT: Strict authenticated household isolation
CREATE POLICY "transactions_select_household"
ON public.transactions FOR SELECT
TO authenticated
USING (
  auth.uid() IS NOT NULL
  AND household_id = public.get_auth_user_household_id()
);

-- Transaction INSERT: Require authenticated caller, valid household match & positive amount
CREATE POLICY "transactions_insert_household"
ON public.transactions FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() IS NOT NULL
  AND household_id = public.get_auth_user_household_id()
  AND amount >= 0
);

-- Transaction UPDATE: Strict household match
CREATE POLICY "transactions_update_household"
ON public.transactions FOR UPDATE
TO authenticated
USING (
  auth.uid() IS NOT NULL
  AND household_id = public.get_auth_user_household_id()
)
WITH CHECK (
  auth.uid() IS NOT NULL
  AND household_id = public.get_auth_user_household_id()
);

-- Transaction DELETE: Strict household match
CREATE POLICY "transactions_delete_household"
ON public.transactions FOR DELETE
TO authenticated
USING (
  auth.uid() IS NOT NULL
  AND household_id = public.get_auth_user_household_id()
);
