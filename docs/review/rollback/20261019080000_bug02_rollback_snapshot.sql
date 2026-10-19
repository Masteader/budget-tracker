-- ----------------------------------------------------------------------
-- Rollback snapshot for BUG-02 (Payday cycle parity and triggers)
-- Captured at: 2026-10-19T06:32:00Z
-- ----------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_populate_transaction_cycle_key ON public.transactions;
DROP FUNCTION IF EXISTS public.populate_transaction_cycle_key();
DROP FUNCTION IF EXISTS public.get_saudi_cycle_for_timestamp(TIMESTAMPTZ, INT);

CREATE OR REPLACE FUNCTION public.update_budget_on_transaction()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.budgets
    SET spent_amount = spent_amount + NEW.amount
    WHERE household_id  = NEW.household_id
      AND category_code = NEW.category_code
      AND month         = date_trunc('month', NEW.timestamp)::DATE;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_budget_on_transaction_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
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

CREATE OR REPLACE FUNCTION public.update_budget_on_transaction_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.amount <> NEW.amount 
       OR OLD.category_code <> NEW.category_code 
       OR date_trunc('month', OLD.timestamp) <> date_trunc('month', NEW.timestamp) THEN

        UPDATE public.budgets
        SET spent_amount = GREATEST(0, spent_amount - OLD.amount)
        WHERE household_id  = OLD.household_id
          AND category_code = OLD.category_code
          AND month         = date_trunc('month', OLD.timestamp)::DATE;

        UPDATE public.budgets
        SET spent_amount = spent_amount + NEW.amount
        WHERE household_id  = NEW.household_id
          AND category_code = NEW.category_code
          AND month         = date_trunc('month', NEW.timestamp)::DATE;
    END IF;

    RETURN NEW;
END;
$$;
