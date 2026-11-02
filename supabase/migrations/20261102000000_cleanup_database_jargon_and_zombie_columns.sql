-- ============================================================================
-- Migration: 20261102000000_cleanup_database_jargon_and_zombie_columns.sql
-- 1. Remove historical jargon: rename transactions.raw_sms to notes.
-- 2. Drop dead zombie column: users.payday_day (households.payday_day is sole SOT).
-- ============================================================================
BEGIN;

DO $$
BEGIN
    -- Rename raw_sms to notes if raw_sms exists
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'transactions' 
          AND column_name = 'raw_sms'
    ) THEN
        ALTER TABLE public.transactions RENAME COLUMN raw_sms TO notes;
    ELSIF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'transactions' 
          AND column_name = 'notes'
    ) THEN
        ALTER TABLE public.transactions ADD COLUMN notes TEXT;
    END IF;
END $$;

-- Drop dead zombie column payday_day from public.users
ALTER TABLE public.users DROP COLUMN IF EXISTS payday_day;

-- Re-document public.transactions.notes
COMMENT ON COLUMN public.transactions.notes IS 
    'Free-text audit note (chat message text, receipt OCR summary, manual expense tags). The app never reads SMS.';

COMMIT;
