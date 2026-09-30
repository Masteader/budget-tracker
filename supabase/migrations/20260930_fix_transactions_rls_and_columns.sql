-- =============================================================================
-- Migration: Add Missing Columns and Fix RLS Insert Policy on Transactions
-- Run in Supabase SQL Editor: https://supabase.com/dashboard/project/qnhyiszgiymsypcwnntu/sql/new
-- =============================================================================

-- 1. Add missing columns to transactions table
ALTER TABLE public.transactions 
  ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'sms' 
    CHECK (source IN ('sms', 'chat', 'receipt_scan', 'manual')),
  ADD COLUMN IF NOT EXISTS items JSONB DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS spent_by TEXT NOT NULL DEFAULT 'me'
    CHECK (spent_by IN ('me', 'partner', 'both')),
  ADD COLUMN IF NOT EXISTS receipt_url TEXT,
  ADD COLUMN IF NOT EXISTS dedup_fingerprint TEXT;

-- 2. Allow authenticated users to INSERT transactions for their household
-- Fixes: "new row violates row-level security policy for table transactions (code: 42501)"
DROP POLICY IF EXISTS "transactions_insert_household" ON public.transactions;
CREATE POLICY "transactions_insert_household"
  ON public.transactions FOR INSERT
  WITH CHECK (
    household_id = public.get_auth_user_household_id()
  );

-- 3. Also allow authenticated users to UPDATE/DELETE transactions in their household
DROP POLICY IF EXISTS "transactions_update_household" ON public.transactions;
CREATE POLICY "transactions_update_household"
  ON public.transactions FOR UPDATE
  USING (
    household_id = public.get_auth_user_household_id()
  );

DROP POLICY IF EXISTS "transactions_delete_household" ON public.transactions;
CREATE POLICY "transactions_delete_household"
  ON public.transactions FOR DELETE
  USING (
    household_id = public.get_auth_user_household_id()
  );

-- 4. Fast deduplication index
CREATE INDEX IF NOT EXISTS idx_transactions_dedup 
  ON public.transactions (household_id, amount, timestamp);
