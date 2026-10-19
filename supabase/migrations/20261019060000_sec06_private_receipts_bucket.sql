-- ----------------------------------------------------------------------
-- Migration: 20261019060000_sec06_private_receipts_bucket.sql
-- SEC-06: Private Receipts Bucket Hardening & Relative Storage Paths
-- ----------------------------------------------------------------------

-- 1. Flip receipts bucket to private (blocks unauthenticated public access)
UPDATE storage.buckets
SET public = false
WHERE id = 'receipts';

-- 2. Clean up existing legacy public/signed URLs in transactions table to relative storage paths
UPDATE public.transactions
SET receipt_url = regexp_replace(
    receipt_url,
    '^https?://[^/]+/storage/v1/object/(?:public|sign)/receipts/([^?]+).*$',
    '\1'
)
WHERE receipt_url IS NOT NULL 
  AND receipt_url ~* '^https?://[^/]+/storage/v1/object/(?:public|sign)/receipts/';

-- 3. Consolidate and harden storage.objects RLS policies for receipts
DROP POLICY IF EXISTS "Household members can upload receipts" ON storage.objects;
DROP POLICY IF EXISTS "hardened_receipt_insert" ON storage.objects;
DROP POLICY IF EXISTS "hardened_receipt_select" ON storage.objects;
DROP POLICY IF EXISTS "hardened_receipt_delete" ON storage.objects;
DROP POLICY IF EXISTS "receipts_insert_household" ON storage.objects;
DROP POLICY IF EXISTS "receipts_select_household" ON storage.objects;
DROP POLICY IF EXISTS "receipts_delete_household" ON storage.objects;

-- Policy A: INSERT - Authenticated household members can upload receipt images only into their own household folder
CREATE POLICY "receipts_insert_household" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'receipts'
    AND auth.uid() IS NOT NULL
    AND (
        (storage.foldername(name))[1] IN (
            SELECT household_id::text FROM public.household_memberships WHERE user_id = auth.uid()
            UNION
            SELECT household_id::text FROM public.users WHERE id = auth.uid() AND household_id IS NOT NULL
        )
    )
    AND lower(storage.extension(name)) = ANY (ARRAY['jpg', 'jpeg', 'png', 'webp'])
    AND name !~ '\.\.'
);

-- Policy B: SELECT - Authenticated members of the household can download or generate signed URLs for receipts
CREATE POLICY "receipts_select_household" ON storage.objects
FOR SELECT TO authenticated
USING (
    bucket_id = 'receipts'
    AND auth.uid() IS NOT NULL
    AND (
        (storage.foldername(name))[1] IN (
            SELECT household_id::text FROM public.household_memberships WHERE user_id = auth.uid()
            UNION
            SELECT household_id::text FROM public.users WHERE id = auth.uid() AND household_id IS NOT NULL
        )
    )
);

-- Policy C: DELETE - Authenticated members of the household can delete receipts within their household folder
CREATE POLICY "receipts_delete_household" ON storage.objects
FOR DELETE TO authenticated
USING (
    bucket_id = 'receipts'
    AND auth.uid() IS NOT NULL
    AND (
        (storage.foldername(name))[1] IN (
            SELECT household_id::text FROM public.household_memberships WHERE user_id = auth.uid()
            UNION
            SELECT household_id::text FROM public.users WHERE id = auth.uid() AND household_id IS NOT NULL
        )
    )
);
