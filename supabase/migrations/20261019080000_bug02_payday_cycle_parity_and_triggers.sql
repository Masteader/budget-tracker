-- ----------------------------------------------------------------------
-- Migration: 20261019080000_bug02_payday_cycle_parity_and_triggers.sql
-- BUG-02: Payday Cycle Parity, Automatic cycle_key & Budget Sync Triggers
-- ----------------------------------------------------------------------

-- 0. Ensure cycle_key column and index exist on transactions and budgets
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS cycle_key VARCHAR(7);
CREATE INDEX IF NOT EXISTS idx_transactions_cycle ON public.transactions(household_id, cycle_key);

ALTER TABLE public.budgets ADD COLUMN IF NOT EXISTS cycle_key VARCHAR(7);
CREATE INDEX IF NOT EXISTS idx_budgets_cycle ON public.budgets(household_id, cycle_key);

-- 1. Create SQL parity function for Saudi payday salary cycles
CREATE OR REPLACE FUNCTION public.get_saudi_cycle_for_timestamp(
    p_timestamp TIMESTAMPTZ,
    p_payday_day INT DEFAULT 27
)
RETURNS TABLE (
    cycle_key TEXT,
    cycle_start DATE,
    cycle_end DATE
)
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_date DATE;
    v_year INT;
    v_month INT;
    v_day INT;
    v_payday INT;
    v_clamped_today_payday INT;
    v_clamped_next_payday INT;
    v_clamped_prev_payday INT;
    v_next_year INT;
    v_next_month INT;
    v_prev_year INT;
    v_prev_month INT;
    v_max_days INT;
BEGIN
    -- 1. Interpret timestamp in Saudi Arabia timezone (Asia/Riyadh, UTC+3)
    v_date := (p_timestamp AT TIME ZONE 'Asia/Riyadh')::DATE;
    v_year := extract(year from v_date)::INT;
    v_month := extract(month from v_date)::INT;
    v_day := extract(day from v_date)::INT;
    v_payday := GREATEST(1, LEAST(31, COALESCE(p_payday_day, 27)));

    IF v_payday = 1 THEN
        cycle_start := make_date(v_year, v_month, 1);
        cycle_end := (date_trunc('month', cycle_start) + interval '1 month - 1 day')::DATE;
        cycle_key := to_char(cycle_start, 'YYYY-MM');
        RETURN NEXT;
        RETURN;
    END IF;

    -- Calculate max days in current month
    v_max_days := extract(day from (date_trunc('month', make_date(v_year, v_month, 1)) + interval '1 month - 1 day'))::INT;
    v_clamped_today_payday := LEAST(v_payday, v_max_days);

    IF v_day >= v_clamped_today_payday THEN
        cycle_start := make_date(v_year, v_month, v_clamped_today_payday);

        IF v_month = 12 THEN
            v_next_year := v_year + 1;
            v_next_month := 1;
        ELSE
            v_next_year := v_year;
            v_next_month := v_month + 1;
        END IF;

        v_max_days := extract(day from (date_trunc('month', make_date(v_next_year, v_next_month, 1)) + interval '1 month - 1 day'))::INT;
        v_clamped_next_payday := LEAST(v_payday, v_max_days);
        cycle_end := make_date(v_next_year, v_next_month, v_clamped_next_payday) - 1;

        IF v_payday <= 15 THEN
            cycle_key := to_char(make_date(v_year, v_month, 1), 'YYYY-MM');
        ELSE
            cycle_key := to_char(make_date(v_next_year, v_next_month, 1), 'YYYY-MM');
        END IF;
    ELSE
        cycle_end := make_date(v_year, v_month, v_clamped_today_payday) - 1;

        IF v_month = 1 THEN
            v_prev_year := v_year - 1;
            v_prev_month := 12;
        ELSE
            v_prev_year := v_year;
            v_prev_month := v_month - 1;
        END IF;

        v_max_days := extract(day from (date_trunc('month', make_date(v_prev_year, v_prev_month, 1)) + interval '1 month - 1 day'))::INT;
        v_clamped_prev_payday := LEAST(v_payday, v_max_days);
        cycle_start := make_date(v_prev_year, v_prev_month, v_clamped_prev_payday);

        IF v_payday <= 15 THEN
            cycle_key := to_char(make_date(v_prev_year, v_prev_month, 1), 'YYYY-MM');
        ELSE
            cycle_key := to_char(make_date(v_year, v_month, 1), 'YYYY-MM');
        END IF;
    END IF;

    RETURN NEXT;
END;
$$;

-- 2. Populate cycle_key on transactions BEFORE INSERT/UPDATE
CREATE OR REPLACE FUNCTION public.populate_transaction_cycle_key()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_payday INT := 27;
    v_cycle_key TEXT;
BEGIN
    IF NEW.household_id IS NOT NULL THEN
        SELECT COALESCE(payday_day, 27) INTO v_payday
        FROM public.households
        WHERE id = NEW.household_id;
    END IF;

    SELECT cycle_key INTO v_cycle_key
    FROM public.get_saudi_cycle_for_timestamp(COALESCE(NEW.timestamp, now()), v_payday);

    NEW.cycle_key := v_cycle_key;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_populate_transaction_cycle_key ON public.transactions;
CREATE TRIGGER trg_populate_transaction_cycle_key
BEFORE INSERT OR UPDATE OF timestamp, household_id ON public.transactions
FOR EACH ROW
EXECUTE FUNCTION public.populate_transaction_cycle_key();

-- 3. Update budget triggers to match by cycle_key
CREATE OR REPLACE FUNCTION public.update_budget_on_transaction()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE public.budgets
    SET spent_amount = spent_amount + NEW.amount
    WHERE household_id  = NEW.household_id
      AND category_code = NEW.category_code
      AND (
          (NEW.cycle_key IS NOT NULL AND cycle_key = NEW.cycle_key)
          OR (NEW.cycle_key IS NULL AND month = date_trunc('month', NEW.timestamp)::DATE)
      );

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_budget_on_transaction_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE public.budgets
    SET spent_amount = GREATEST(0, spent_amount - OLD.amount)
    WHERE household_id  = OLD.household_id
      AND category_code = OLD.category_code
      AND (
          (OLD.cycle_key IS NOT NULL AND cycle_key = OLD.cycle_key)
          OR (OLD.cycle_key IS NULL AND month = date_trunc('month', OLD.timestamp)::DATE)
      );

    RETURN OLD;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_budget_on_transaction_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF OLD.amount <> NEW.amount 
       OR OLD.category_code <> NEW.category_code 
       OR OLD.cycle_key IS DISTINCT FROM NEW.cycle_key
       OR date_trunc('month', OLD.timestamp) <> date_trunc('month', NEW.timestamp) THEN

        UPDATE public.budgets
        SET spent_amount = GREATEST(0, spent_amount - OLD.amount)
        WHERE household_id  = OLD.household_id
          AND category_code = OLD.category_code
          AND (
              (OLD.cycle_key IS NOT NULL AND cycle_key = OLD.cycle_key)
              OR (OLD.cycle_key IS NULL AND month = date_trunc('month', OLD.timestamp)::DATE)
          );

        UPDATE public.budgets
        SET spent_amount = spent_amount + NEW.amount
        WHERE household_id  = NEW.household_id
          AND category_code = NEW.category_code
          AND (
              (NEW.cycle_key IS NOT NULL AND cycle_key = NEW.cycle_key)
              OR (NEW.cycle_key IS NULL AND month = date_trunc('month', NEW.timestamp)::DATE)
          );
    END IF;

    RETURN NEW;
END;
$$;

-- 4. Backfill cycle_key and synchronize budgets.spent_amount
UPDATE public.transactions t
SET cycle_key = (
    SELECT cycle_key FROM public.get_saudi_cycle_for_timestamp(
        t.timestamp,
        COALESCE((SELECT payday_day FROM public.households h WHERE h.id = t.household_id), 27)
    )
)
WHERE cycle_key IS NULL;

UPDATE public.budgets b
SET spent_amount = COALESCE((
    SELECT SUM(t.amount)
    FROM public.transactions t
    WHERE t.household_id = b.household_id
      AND t.category_code = b.category_code
      AND (
          (b.cycle_key IS NOT NULL AND t.cycle_key = b.cycle_key)
          OR (b.cycle_key IS NULL AND date_trunc('month', t.timestamp)::DATE = b.month)
      )
), 0);
