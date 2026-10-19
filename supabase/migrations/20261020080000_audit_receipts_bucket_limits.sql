-- ----------------------------------------------------------------------------
-- Migration: 20261020080000_audit_receipts_bucket_limits.sql
-- Audit DB-11 (Low): the private receipts bucket had no file_size_limit and no
--   allowed_mime_types; storage.objects policies only check the name's
--   extension, so members could upload arbitrarily large / non-image content
--   named *.jpg. Storage API enforces these bucket columns on every upload
--   (client JWT and service role).
-- Limits: 20 MiB covers ai_service's stitched multi-shot receipts (request body
--   cap 25 MB base64 ~= 18.75 MB binary); Flutter uploads <= 1600px JPEGs.
--   MIME list matches the extension allow-list in receipts_insert_household.
-- Proof test: supabase/tests/15_audit_receipts_bucket_limits.sql
-- ----------------------------------------------------------------------------

UPDATE storage.buckets
SET file_size_limit = 20 * 1024 * 1024,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp'],
    public = false
WHERE id = 'receipts';
