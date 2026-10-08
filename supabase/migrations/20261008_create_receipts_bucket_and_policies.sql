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
