-- ============================================================================
-- Test 15 (audit DB-11): receipts bucket upload limits
--
-- The receipts bucket was created (20261008) and made private (20261019060000)
-- but never given file_size_limit or allowed_mime_types. The storage.objects
-- INSERT policy only checks the file *name* extension, so any household member
-- can store arbitrarily large files of any content type (e.g. HTML/SVG/APK
-- renamed to .jpg) up to the project-wide limit.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    v_bucket storage.buckets%ROWTYPE;
BEGIN
    SELECT * INTO v_bucket FROM storage.buckets WHERE id = 'receipts';
    IF v_bucket.id IS NULL THEN
        RAISE EXCEPTION 'receipts bucket missing';
    END IF;
    IF v_bucket.public IS DISTINCT FROM false THEN
        RAISE EXCEPTION 'VULNERABILITY: receipts bucket is public';
    END IF;
    IF v_bucket.file_size_limit IS NULL OR v_bucket.file_size_limit > 20 * 1024 * 1024 THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-11): receipts bucket file_size_limit is % (expected <= 20 MiB)', v_bucket.file_size_limit;
    END IF;
    IF v_bucket.allowed_mime_types IS NULL
       OR NOT (v_bucket.allowed_mime_types <@ ARRAY['image/jpeg', 'image/png', 'image/webp'])
       OR NOT ('image/jpeg' = ANY (v_bucket.allowed_mime_types)) THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-11): receipts bucket allowed_mime_types is %', v_bucket.allowed_mime_types;
    END IF;
    RAISE NOTICE 'PASSED: receipts bucket is private, size-limited and image-only.';
END $$;

ROLLBACK;
