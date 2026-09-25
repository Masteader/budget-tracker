-- =============================================================================
-- Migration: Add Line Items, Source Channel, Receipt URL & Deduplication Index
-- Run in Supabase SQL Editor: https://supabase.com/dashboard/project/qnhyiszgiymsypcwnntu/sql/new
-- =============================================================================

ALTER TABLE public.transactions 
  ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'sms' 
    CHECK (source IN ('sms', 'chat', 'receipt_scan', 'manual')),
  ADD COLUMN IF NOT EXISTS items JSONB DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS receipt_url TEXT,
  ADD COLUMN IF NOT EXISTS dedup_fingerprint TEXT;

COMMENT ON COLUMN public.transactions.source IS 'Ingestion channel: sms, chat, receipt_scan, or manual.';
COMMENT ON COLUMN public.transactions.items IS 'Itemized breakdown JSON: [{"name": string, "quantity": number, "price": number}].';
COMMENT ON COLUMN public.transactions.receipt_url IS 'Optional image URL or storage reference for scanned receipt.';

-- Composite index for fast deduplication lookup (within time window)
CREATE INDEX IF NOT EXISTS idx_transactions_dedup 
  ON public.transactions (household_id, amount, timestamp);

-- Ensure Realtime publication includes transactions and budgets
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'transactions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.transactions;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'budgets'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.budgets;
  END IF;
END $$;
