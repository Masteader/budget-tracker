-- =============================================================================
-- Migration: 20261005_query_performance_and_indexes.sql
-- Description: Adds high-performance composite indexes, covering indexes,
--              GIN index on items JSONB, and foreign key indexes for transactions
--              and budgets to maximize query throughput and minimize latency.
-- =============================================================================

-- 1. Covering Index for Mobile Transaction Feed
-- Accelerates `SELECT * FROM transactions WHERE household_id = $1 ORDER BY timestamp DESC`
CREATE INDEX IF NOT EXISTS idx_transactions_feed_covering 
  ON public.transactions (household_id, timestamp DESC, category_code, spent_by);

-- 2. Composite Index for Category Spending Rollups & Budget Tracking
CREATE INDEX IF NOT EXISTS idx_transactions_category_spent 
  ON public.transactions (household_id, category_code, amount);

-- 3. Partial Index for Sub-Category Breakdown & Allocations
CREATE INDEX IF NOT EXISTS idx_transactions_sub_category 
  ON public.transactions (household_id, cycle_key, sub_category)
  WHERE sub_category IS NOT NULL;

-- 4. GIN Index on items JSONB for Grocery Price Tracker & Receipt Item Queries
CREATE INDEX IF NOT EXISTS idx_transactions_items_gin 
  ON public.transactions USING gin (items jsonb_path_ops);

-- 5. Covering Index for Budget Category Lookups
CREATE INDEX IF NOT EXISTS idx_budgets_lookup_covering 
  ON public.budgets (household_id, cycle_key, category_code)
  INCLUDE (allocated_amount, spent_amount, is_active);

-- 6. Settlement Index for Partner Reimbursements
CREATE INDEX IF NOT EXISTS idx_transactions_settlement 
  ON public.transactions (household_id, spent_by, amount)
  WHERE spent_by IN ('me', 'partner', 'both');

-- 7. Foreign Key Index on user_id to prevent table lock during user updates/deletes
CREATE INDEX IF NOT EXISTS idx_transactions_user_id 
  ON public.transactions (user_id);

-- 8. Sub-categories Parent Code Lookup Index
CREATE INDEX IF NOT EXISTS idx_sub_categories_parent 
  ON public.cost_control_sub_categories (parent_code);

-- Verification:
-- Run in Supabase SQL Editor:
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT * FROM transactions 
-- WHERE household_id = '00000000-0000-0000-0000-000000000000' 
-- ORDER BY timestamp DESC 
-- LIMIT 50;
