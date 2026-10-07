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
