-- Migration: Fix storage policies, eliminate SELECT warning, and auto-cleanup receipt images on transaction deletion

-- 1. Eliminate Supabase Security Advisor warning:
-- Drop broad / redundant SELECT policies on storage.objects for the public receipts bucket.
-- Public buckets serve image downloads via direct CDN / public URL without needing storage.objects SELECT RLS.
DROP POLICY IF EXISTS "Household members can view receipts" ON storage.objects;
DROP POLICY IF EXISTS "Allow select on receipts" ON storage.objects;
DROP POLICY IF EXISTS "Give users access to own folder" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated select" ON storage.objects;
DROP POLICY IF EXISTS "Allow all users to select" ON storage.objects;

-- 2. Allow authenticated household members to upload receipts (INSERT)
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

-- 3. Allow authenticated household members to delete their receipts (DELETE)
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

-- 4. Trigger: Automatically delete receipt image from storage.objects when transaction is deleted
CREATE OR REPLACE FUNCTION public.clean_up_receipt_storage_on_transaction_delete()
RETURNS TRIGGER AS $$
DECLARE
  v_path TEXT;
BEGIN
  IF OLD.receipt_url IS NOT NULL AND OLD.receipt_url <> '' THEN
    -- Extract relative path after 'receipts/'
    IF OLD.receipt_url ~ 'receipts/' THEN
      v_path := substring(OLD.receipt_url from 'receipts/(.+)$');
      v_path := split_part(v_path, '?', 1);
    ELSE
      v_path := OLD.receipt_url;
    END IF;

    IF v_path IS NOT NULL AND v_path <> '' THEN
      DELETE FROM storage.objects
      WHERE bucket_id = 'receipts'
        AND name = v_path;
    END IF;
  END IF;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_delete_receipt_storage ON public.transactions;
CREATE TRIGGER trg_delete_receipt_storage
AFTER DELETE ON public.transactions
FOR EACH ROW
EXECUTE FUNCTION public.clean_up_receipt_storage_on_transaction_delete();
