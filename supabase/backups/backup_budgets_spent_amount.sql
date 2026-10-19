-- ============================================================================
-- Pre-Recompute Backup Script: public.budgets
-- Snapshots public.budgets into public.budgets_spent_backup_20261019
-- To be executed before any spent_amount recomputation is run on production.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.budgets_spent_backup_20261019 AS
SELECT 
    b.*,
    now() AS backup_taken_at
FROM public.budgets b;

COMMENT ON TABLE public.budgets_spent_backup_20261019 IS 
'Snapshot of public.budgets table taken on 2026-10-19 prior to spent_amount recomputation.';

-- Verify row count
SELECT 
    count(*) AS backed_up_budget_rows,
    sum(spent_amount) AS total_spent_amount_snapshot,
    min(backup_taken_at) AS backup_timestamp
FROM public.budgets_spent_backup_20261019;
