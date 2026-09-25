-- =============================================================================
-- Migration: Add AFTER DELETE and AFTER UPDATE triggers on transactions
-- Keeps budgets.spent_amount strictly synchronized when transactions are edited or removed.
-- =============================================================================

-- 1. Trigger Function for DELETE
CREATE OR REPLACE FUNCTION public.update_budget_on_transaction_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.budgets
    SET spent_amount = GREATEST(0, spent_amount - OLD.amount)
    WHERE household_id  = OLD.household_id
      AND category_code = OLD.category_code
      AND month         = date_trunc('month', OLD.timestamp)::DATE;

    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS on_transaction_delete ON public.transactions;
CREATE TRIGGER on_transaction_delete
    AFTER DELETE ON public.transactions
    FOR EACH ROW EXECUTE FUNCTION public.update_budget_on_transaction_delete();


-- 2. Trigger Function for UPDATE
CREATE OR REPLACE FUNCTION public.update_budget_on_transaction_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Only update budgets if amount, category, or timestamp month changed
    IF OLD.amount <> NEW.amount 
       OR OLD.category_code <> NEW.category_code 
       OR date_trunc('month', OLD.timestamp) <> date_trunc('month', NEW.timestamp) THEN

        -- Deduct from old budget
        UPDATE public.budgets
        SET spent_amount = GREATEST(0, spent_amount - OLD.amount)
        WHERE household_id  = OLD.household_id
          AND category_code = OLD.category_code
          AND month         = date_trunc('month', OLD.timestamp)::DATE;

        -- Add to new budget
        UPDATE public.budgets
        SET spent_amount = spent_amount + NEW.amount
        WHERE household_id  = NEW.household_id
          AND category_code = NEW.category_code
          AND month         = date_trunc('month', NEW.timestamp)::DATE;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_transaction_update ON public.transactions;
CREATE TRIGGER on_transaction_update
    AFTER UPDATE ON public.transactions
    FOR EACH ROW EXECUTE FUNCTION public.update_budget_on_transaction_update();
