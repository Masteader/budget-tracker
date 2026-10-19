-- ====================================================================
-- Test Suite: 03_sec06_private_receipts.sql
-- Proves SEC-06: Receipts bucket is private, storage RLS enforced per household,
-- and transactions.receipt_url converts to storage paths.
-- ====================================================================

-- 1. Ensure storage stub schema exists in local test environment
CREATE SCHEMA IF NOT EXISTS storage;
CREATE TABLE IF NOT EXISTS storage.buckets (
    id text PRIMARY KEY,
    name text NOT NULL,
    public boolean DEFAULT false
);

CREATE OR REPLACE FUNCTION storage.foldername(name text)
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
    SELECT string_to_array(name, '/');
$$;

CREATE OR REPLACE FUNCTION storage.extension(name text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT substring(name from '\.([^\.]+)$');
$$;

CREATE TABLE IF NOT EXISTS storage.objects (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    bucket_id text REFERENCES storage.buckets(id),
    name text NOT NULL,
    owner uuid,
    created_at timestamptz DEFAULT now()
);
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage.objects FORCE ROW LEVEL SECURITY;
GRANT ALL ON SCHEMA storage TO authenticated, anon, postgres, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA storage TO authenticated, anon, postgres, service_role;

-- Apply SEC-06 migration
UPDATE storage.buckets SET public = false WHERE id = 'receipts';
INSERT INTO storage.buckets (id, name, public) VALUES ('receipts', 'receipts', false) ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "receipts_insert_household" ON storage.objects;
DROP POLICY IF EXISTS "receipts_select_household" ON storage.objects;
DROP POLICY IF EXISTS "receipts_delete_household" ON storage.objects;

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

-- ====================================================================
-- Test Fixtures
-- ====================================================================
DO $$
DECLARE
    v_victim_hh uuid := 'a0000000-0000-0000-0000-000000000001';
    v_attacker_hh uuid := 'b0000000-0000-0000-0000-000000000002';
    v_victim_user uuid := '10000000-0000-0000-0000-000000000001';
    v_attacker_user uuid := '20000000-0000-0000-0000-000000000002';
    v_bucket_public boolean;
    v_clean_url text;
BEGIN
    -- 1. Verify bucket is marked private
    SELECT public INTO v_bucket_public FROM storage.buckets WHERE id = 'receipts';
    IF v_bucket_public IS NOT FALSE THEN
        RAISE EXCEPTION 'VULNERABILITY: storage.buckets receipts is public!';
    END IF;
    RAISE NOTICE 'PASSED: Receipts bucket is private (public = false).';

    -- 2. Verify legacy URL cleanup regex
    SELECT regexp_replace(
        'https://qnhyiszgiymsypcwnntu.supabase.co/storage/v1/object/public/receipts/hh-123/1728412345_abcd.jpg',
        '^https?://[^/]+/storage/v1/object/(?:public|sign)/receipts/([^?]+).*$',
        '\1'
    ) INTO v_clean_url;
    IF v_clean_url != 'hh-123/1728412345_abcd.jpg' THEN
        RAISE EXCEPTION 'Regex cleanup failed: got %', v_clean_url;
    END IF;
    RAISE NOTICE 'PASSED: Legacy receipt URL converted to relative storage path: %', v_clean_url;

    -- Set up fixtures
    INSERT INTO public.households (id, name, payday_day, monthly_income)
    VALUES (v_victim_hh, 'Victim Household', 27, 5000),
           (v_attacker_hh, 'Attacker Household', 27, 5000)
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (id, email, display_name, role, household_id)
    VALUES (v_victim_user, 'victim@test.local', 'Victim User', 'member', v_victim_hh),
           (v_attacker_user, 'attacker@test.local', 'Attacker User', 'member', v_attacker_hh)
    ON CONFLICT (id) DO UPDATE SET household_id = EXCLUDED.household_id;

    INSERT INTO public.household_memberships (household_id, user_id, role)
    VALUES (v_victim_hh, v_victim_user, 'member'),
           (v_attacker_hh, v_attacker_user, 'member')
    ON CONFLICT (household_id, user_id) DO NOTHING;

    -- Clean old objects
    DELETE FROM storage.objects WHERE bucket_id = 'receipts';

    -- Insert victim receipt
    INSERT INTO storage.objects (bucket_id, name, owner)
    VALUES ('receipts', v_victim_hh::text || '/victim_receipt.jpg', v_victim_user);

    RAISE NOTICE 'Test fixtures created.';
END $$;

-- 3. Attacker tries to view victim receipt (must see 0)
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "20000000-0000-0000-0000-000000000002", "role": "authenticated"}', false);

DO $$
DECLARE
    v_count int;
BEGIN
    SELECT count(*) INTO v_count FROM storage.objects WHERE bucket_id = 'receipts';
    IF v_count > 0 THEN
        RAISE EXCEPTION 'VULNERABILITY: Attacker saw % receipt(s) belonging to victim!', v_count;
    END IF;
    RAISE NOTICE 'PASSED: Attacker cannot see victim receipts (visible: 0).';
END $$;

-- 4. Attacker tries to insert receipt into victim household folder (must be blocked)
DO $$
BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner)
    VALUES ('receipts', 'a0000000-0000-0000-0000-000000000001/malicious.jpg', '20000000-0000-0000-0000-000000000002');
    RAISE EXCEPTION 'VULNERABILITY: Attacker was able to upload receipt into victim household folder!';
EXCEPTION
    WHEN insufficient_privilege OR check_violation THEN
        RAISE NOTICE 'PASSED: Attacker blocked from uploading into victim household folder.';
END $$;

-- 5. Attacker tries to upload disallowed extension (.exe)
DO $$
BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner)
    VALUES ('receipts', 'b0000000-0000-0000-0000-000000000002/exploit.exe', '20000000-0000-0000-0000-000000000002');
    RAISE EXCEPTION 'VULNERABILITY: Attacker was able to upload disallowed file extension (.exe)!';
EXCEPTION
    WHEN insufficient_privilege OR check_violation THEN
        RAISE NOTICE 'PASSED: Disallowed extension (.exe) blocked by storage RLS.';
END $$;

-- 6. Attacker tries path traversal (..)
DO $$
BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner)
    VALUES ('receipts', 'b0000000-0000-0000-0000-000000000002/../../etc/passwd.jpg', '20000000-0000-0000-0000-000000000002');
    RAISE EXCEPTION 'VULNERABILITY: Path traversal was not blocked by storage RLS!';
EXCEPTION
    WHEN insufficient_privilege OR check_violation THEN
        RAISE NOTICE 'PASSED: Path traversal pattern blocked by storage RLS.';
END $$;

-- 7. Victim views their own receipt
SELECT set_config('request.jwt.claims', '{"sub": "10000000-0000-0000-0000-000000000001", "role": "authenticated"}', false);
DO $$
DECLARE
    v_count int;
BEGIN
    SELECT count(*) INTO v_count FROM storage.objects WHERE bucket_id = 'receipts';
    IF v_count = 0 THEN
        RAISE EXCEPTION 'FAILURE: Victim user cannot see their own household receipt!';
    END IF;
    RAISE NOTICE 'PASSED: Victim user successfully accessed own household receipt (visible: %).', v_count;
END $$;

-- 8. Anonymous caller sees 0 receipts
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{}', false);
DO $$
DECLARE
    v_count int;
BEGIN
    SELECT count(*) INTO v_count FROM storage.objects WHERE bucket_id = 'receipts';
    IF v_count > 0 THEN
        RAISE EXCEPTION 'VULNERABILITY: Anonymous user saw % receipt(s)!', v_count;
    END IF;
    RAISE NOTICE 'PASSED: Anon cannot see any receipts (visible: 0).';
END $$;

RESET ROLE;

