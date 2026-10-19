-- Rollback snapshot for SEC-06 (Private Receipts Storage Bucket & Policies)
-- Captured at: 2026-10-19T06:08:00Z

-- 1. Revert bucket public setting
UPDATE storage.buckets SET public = true WHERE id = 'receipts';

-- 2. Revert storage.objects policies
DROP POLICY IF EXISTS "receipts_insert_household" ON storage.objects;
DROP POLICY IF EXISTS "receipts_select_household" ON storage.objects;
DROP POLICY IF EXISTS "receipts_delete_household" ON storage.objects;

CREATE POLICY "Household members can upload receipts" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
    (bucket_id = 'receipts'::text) AND (
        ((storage.foldername(name))[1] = (get_auth_user_household_id())::text) OR
        (EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND (u.household_id)::text = (storage.foldername(objects.name))[1]
        ))
    )
);

CREATE POLICY "hardened_receipt_insert" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
    ((bucket_id = 'receipts'::text) AND (auth.uid() IS NOT NULL) AND (get_auth_user_household_id() IS NOT NULL) AND ((storage.foldername(name))[1] = (get_auth_user_household_id())::text) AND (lower(storage.extension(name)) = ANY (ARRAY['jpg'::text, 'jpeg'::text, 'png'::text, 'webp'::text])) AND (name !~~ '%..%'::text))
);

CREATE POLICY "hardened_receipt_select" ON storage.objects
FOR SELECT TO authenticated
USING (
    ((bucket_id = 'receipts'::text) AND (auth.uid() IS NOT NULL) AND (get_auth_user_household_id() IS NOT NULL) AND ((storage.foldername(name))[1] = (get_auth_user_household_id())::text))
);

CREATE POLICY "hardened_receipt_delete" ON storage.objects
FOR DELETE TO authenticated
USING (
    ((bucket_id = 'receipts'::text) AND (auth.uid() IS NOT NULL) AND (get_auth_user_household_id() IS NOT NULL) AND ((storage.foldername(name))[1] = (get_auth_user_household_id())::text))
);
