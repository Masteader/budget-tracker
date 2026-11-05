-- Migration: 20261105001000_inactive_category_budgets.sql
--
-- Owner decision (2026-11-05): an expense recorded in a category that is inactive for the
-- household is filed under that category, never a fallback. It counts in totals and reports,
-- in no budget, and the app offers to activate the category and give it a budget.
--
-- 1. The budget triggers (insert, update, delete of a transaction) and recompute_budget_spent
--    change spent_amount of active budget rows only: is_active IS NOT FALSE. A row turned off
--    (toggle_category_status, archive_category_for_household, replace_household_category)
--    keeps the value it has. NULL counts as active, as the app reads it (Budget.fromMap,
--    `is_active != false`), so rows with NULL behave exactly as before.
--    Nothing else changes: wife_personal rows and settlements still reach no budget, and
--    wife_reimbursable rows still reach the category budget (rule 02).
-- 2. A budget row that becomes active for the household's open cycle (inserted active, or
--    is_active turned from false to true) takes that cycle's spending of its category, by the
--    rule recompute_budget_spent uses (budget_spent_from_transactions). So expenses recorded
--    while the category was inactive or unbudgeted count in the new budget at once. Rows of any
--    other cycle are left as they are, and so are rows that were already active.
--
-- No data is changed by this file: no stored spent_amount is rewritten.
-- Safe to run again (CREATE OR REPLACE, DROP TRIGGER IF EXISTS).
-- Depends on: 20261020800000 (recompute_budget_spent), 20261020900000 (trigger functions),
--             20261020300000 (nafaqah_current_cycle_key).
--
-- Rollback (restores the 20261020800000 / 20261020900000 behaviour):
--   DROP TRIGGER IF EXISTS trg_budget_activation_counts_open_cycle ON public.budgets;
--   DROP FUNCTION IF EXISTS public.budget_activation_counts_open_cycle();
--   then re-run sections 6 of 20261020900000 and the recompute_budget_spent definition of
--   20261020800000, then DROP FUNCTION IF EXISTS public.budget_spent_from_transactions(uuid, text, text);

BEGIN;

-- What a budget row of (household, category, cycle) has spent: the cycle's transactions of
-- that category, less settlements between members and the wife's personal purchases.
CREATE OR REPLACE FUNCTION public.budget_spent_from_transactions(
    p_household_id uuid,
    p_category_code text,
    p_cycle_key text
)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT GREATEST(0, COALESCE(sum(t.amount), 0))
    FROM public.transactions t
    WHERE t.household_id = p_household_id
      AND t.category_code = p_category_code
      AND t.cycle_key = p_cycle_key
      AND t.nafaqah_class IS DISTINCT FROM 'wife_personal'
      AND t.is_settlement IS NOT TRUE;
$$;
REVOKE EXECUTE ON FUNCTION public.budget_spent_from_transactions(uuid, text, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.update_budget_on_transaction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.nafaqah_class IS NOT DISTINCT FROM 'wife_personal' OR NEW.is_settlement IS TRUE THEN
        RETURN NEW;  -- the wife's allowance only / a transfer between members
    END IF;

    UPDATE public.budgets
    SET spent_amount = spent_amount + NEW.amount
    WHERE household_id  = NEW.household_id
      AND category_code = NEW.category_code
      AND is_active IS NOT FALSE
      AND (
          (NEW.cycle_key IS NOT NULL AND cycle_key = NEW.cycle_key)
          OR (NEW.cycle_key IS NULL AND month = date_trunc('month', NEW.timestamp)::DATE)
      );

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_budget_on_transaction_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF OLD.nafaqah_class IS NOT DISTINCT FROM 'wife_personal' OR OLD.is_settlement IS TRUE THEN
        RETURN OLD;
    END IF;

    UPDATE public.budgets
    SET spent_amount = GREATEST(0, spent_amount - OLD.amount)
    WHERE household_id  = OLD.household_id
      AND category_code = OLD.category_code
      AND is_active IS NOT FALSE
      AND (
          (OLD.cycle_key IS NOT NULL AND cycle_key = OLD.cycle_key)
          OR (OLD.cycle_key IS NULL AND month = date_trunc('month', OLD.timestamp)::DATE)
      );

    RETURN OLD;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_budget_on_transaction_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_old_counted boolean := OLD.nafaqah_class IS DISTINCT FROM 'wife_personal' AND OLD.is_settlement IS NOT TRUE;
    v_new_counted boolean := NEW.nafaqah_class IS DISTINCT FROM 'wife_personal' AND NEW.is_settlement IS NOT TRUE;
BEGIN
    IF OLD.amount <> NEW.amount
       OR OLD.category_code IS DISTINCT FROM NEW.category_code
       OR OLD.cycle_key IS DISTINCT FROM NEW.cycle_key
       OR date_trunc('month', OLD.timestamp) IS DISTINCT FROM date_trunc('month', NEW.timestamp)
       OR v_old_counted IS DISTINCT FROM v_new_counted THEN

        IF v_old_counted THEN
            UPDATE public.budgets
            SET spent_amount = GREATEST(0, spent_amount - OLD.amount)
            WHERE household_id  = OLD.household_id
              AND category_code = OLD.category_code
              AND is_active IS NOT FALSE
              AND (
                  (OLD.cycle_key IS NOT NULL AND cycle_key = OLD.cycle_key)
                  OR (OLD.cycle_key IS NULL AND month = date_trunc('month', OLD.timestamp)::DATE)
              );
        END IF;

        IF v_new_counted THEN
            UPDATE public.budgets
            SET spent_amount = spent_amount + NEW.amount
            WHERE household_id  = NEW.household_id
              AND category_code = NEW.category_code
              AND is_active IS NOT FALSE
              AND (
                  (NEW.cycle_key IS NOT NULL AND cycle_key = NEW.cycle_key)
                  OR (NEW.cycle_key IS NULL AND month = date_trunc('month', NEW.timestamp)::DATE)
              );
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_budget_on_transaction() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_budget_on_transaction_delete() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_budget_on_transaction_update() FROM PUBLIC, anon, authenticated;

-- Same rule as the triggers, for active rows only (an inactive row keeps its value).
CREATE OR REPLACE FUNCTION public.recompute_budget_spent(p_household_id uuid, p_cycle_keys text[])
RETURNS integer
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_n integer;
BEGIN
    UPDATE public.budgets b
    SET spent_amount = public.budget_spent_from_transactions(b.household_id, b.category_code, b.cycle_key)
    WHERE b.household_id = p_household_id
      AND b.cycle_key = ANY (p_cycle_keys)
      AND b.is_active IS NOT FALSE;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.recompute_budget_spent(uuid, text[]) FROM PUBLIC, anon, authenticated;

-- A row that starts counting the open cycle counts what that cycle already holds.
CREATE OR REPLACE FUNCTION public.budget_activation_counts_open_cycle()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.is_active IS NOT FALSE
       AND NEW.cycle_key IS NOT NULL
       AND (TG_OP = 'INSERT' OR OLD.is_active IS FALSE)
       AND NEW.cycle_key = public.nafaqah_current_cycle_key(NEW.household_id) THEN
        NEW.spent_amount := public.budget_spent_from_transactions(NEW.household_id, NEW.category_code, NEW.cycle_key);
    END IF;
    RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.budget_activation_counts_open_cycle() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_budget_activation_counts_open_cycle ON public.budgets;
CREATE TRIGGER trg_budget_activation_counts_open_cycle
BEFORE INSERT OR UPDATE OF is_active ON public.budgets
FOR EACH ROW EXECUTE FUNCTION public.budget_activation_counts_open_cycle();

COMMIT;
