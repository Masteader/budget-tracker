-- Migration: Add sub_allocations JSONB to budgets table
-- Allows granular sub-category budget tracking with auto-summing parent

ALTER TABLE budgets 
ADD COLUMN IF NOT EXISTS sub_allocations JSONB NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN budgets.sub_allocations IS 'Dictionary of sub_code to allocated_amount for granular sub-budgets';
