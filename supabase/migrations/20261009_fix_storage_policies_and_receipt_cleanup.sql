-- Migration: Fix storage policies, eliminate SELECT warning, and enable Storage API deletion

-- 1. Eliminate Supabase Security Advisor warning:
-- Drop broad / redundant SELECT policies on storage.objects for the public receipts bucket.
-- Public buckets serve image downloads via direct CDN / public URL without needing storage.objects SELECT RLS.
DROP POLICY IF EXISTS "Household members can view receipts" ON storage.objects;
DROP POLICY IF EXISTS "Allow select on receipts" ON storage.objects;
DROP POLICY IF EXISTS "Give users access to own folder" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated select" ON storage.objects;
DROP POLICY IF EXISTS "Allow all users to select" ON storage.objects;

-- 2. Allow authenticated household members to upload receipts via Storage API (INSERT)
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
      AND (
        (storage.foldername(name))[1] = public.get_auth_user_household_id()::text
        OR EXISTS (
          SELECT 1 FROM public.users u
          WHERE u.id = auth.uid()
            AND u.household_id::text = (storage.foldername(name))[1]
        )
      )
    );
  END IF;
END $$;

-- 3. Allow authenticated household members to delete their receipts via Storage API (DELETE)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'objects' 
      AND schemaname = 'storage' 
      AND policyname = 'Household members can delete receipts'
  ) THEN
    CREATE POLICY "Household members can delete receipts"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
      bucket_id = 'receipts'
      AND (
        (storage.foldername(name))[1] = public.get_auth_user_household_id()::text
        OR EXISTS (
          SELECT 1 FROM public.users u
          WHERE u.id = auth.uid()
            AND u.household_id::text = (storage.foldername(name))[1]
        )
      )
    );
  END IF;
END $$;

-- 4. Clean up any previous direct-table delete trigger
-- Supabase enforces that deletions from storage must go through the Storage API,
-- which the mobile app handles cleanly via ReceiptStorageService.deleteReceiptByUrl().
DROP TRIGGER IF EXISTS trg_delete_receipt_storage ON public.transactions;
DROP FUNCTION IF EXISTS public.clean_up_receipt_storage_on_transaction_delete();
