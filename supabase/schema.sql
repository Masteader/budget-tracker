-- =============================================================================
-- BUDGET TRACKER — SUPABASE SCHEMA
-- Run this entire file in the Supabase SQL Editor (Project → SQL Editor)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- EXTENSIONS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid(), crypt()
CREATE EXTENSION IF NOT EXISTS "unaccent";   -- accent-insensitive merchant search


-- =============================================================================
-- TABLE: households
-- A household groups multiple users sharing a budget.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.households (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    invite_code TEXT UNIQUE NOT NULL DEFAULT substr(md5(random()::text), 1, 8),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.households IS 'A shared budget group (family / flatmates).';
COMMENT ON COLUMN public.households.invite_code IS '8-char code to invite new members.';


-- =============================================================================
-- TABLE: users
-- Extends Supabase auth.users with household membership and role.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.users (
    id           UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    household_id UUID REFERENCES public.households(id) ON DELETE SET NULL,
    display_name TEXT NOT NULL,
    role         TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.users IS 'App-level user profile linked to Supabase Auth.';
COMMENT ON COLUMN public.users.role IS '''admin'' can edit budgets; ''member'' is read-only.';


-- =============================================================================
-- TABLE: cost_control_codes
-- Master list of expense categories + keywords for merchant matching.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.cost_control_codes (
    id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    code        TEXT    UNIQUE NOT NULL,   -- e.g. 'OPEX-GROCERY'
    category    TEXT    NOT NULL,          -- e.g. 'Grocery'
    keywords    TEXT[]  NOT NULL,          -- e.g. ARRAY['tamimi', 'danube', 'panda']
    is_flexible BOOLEAN NOT NULL DEFAULT false,  -- eligible for auto-reallocation
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.cost_control_codes IS 'Category taxonomy + keyword mapping for SMS merchant matching.';
COMMENT ON COLUMN public.cost_control_codes.is_flexible IS 'If true, this budget can be raided during automatic reallocation.';


-- =============================================================================
-- TABLE: budgets
-- Monthly allocation per household per category.
-- remaining_amount is a generated column (always consistent).
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.budgets (
    id               UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id     UUID    NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    month            DATE    NOT NULL,   -- Always the first day of the month, e.g. 2026-09-01
    category_code    TEXT    NOT NULL REFERENCES public.cost_control_codes(code) ON UPDATE CASCADE,
    allocated_amount NUMERIC(12, 2) NOT NULL CHECK (allocated_amount >= 0),
    spent_amount     NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (spent_amount >= 0),
    remaining_amount NUMERIC(12, 2) GENERATED ALWAYS AS (allocated_amount - spent_amount) STORED,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT budgets_unique_month_category UNIQUE (household_id, month, category_code)
);

COMMENT ON TABLE  public.budgets IS 'Monthly budget allocation per category per household.';
COMMENT ON COLUMN public.budgets.month IS 'Always set to the 1st of the month (e.g. 2026-09-01).';
COMMENT ON COLUMN public.budgets.remaining_amount IS 'Computed: allocated_amount - spent_amount.';


-- =============================================================================
-- TABLE: transactions
-- Every parsed SMS expense is stored here.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.transactions (
    id                         UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id               UUID    NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    user_id                    UUID    REFERENCES public.users(id) ON DELETE SET NULL,
    amount                     NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    currency                   TEXT    NOT NULL DEFAULT 'SAR',
    merchant                   TEXT,
    category_code              TEXT    REFERENCES public.cost_control_codes(code) ON UPDATE CASCADE,
    timestamp                  TIMESTAMPTZ NOT NULL,
    raw_sms                    TEXT,
    is_reallocated             BOOLEAN NOT NULL DEFAULT false,
    reallocated_from_budget_id UUID    REFERENCES public.budgets(id) ON DELETE SET NULL,
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.transactions IS 'Every SMS-derived expense transaction.';
COMMENT ON COLUMN public.transactions.raw_sms IS 'Original SMS text for audit trail.';
COMMENT ON COLUMN public.transactions.is_reallocated IS 'True if budget was insufficient and funds were pulled from another category.';


-- =============================================================================
-- INDEXES
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_transactions_household   ON public.transactions (household_id);
CREATE INDEX IF NOT EXISTS idx_transactions_timestamp   ON public.transactions (timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_created_at  ON public.transactions (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_budgets_household_month  ON public.budgets (household_id, month);
CREATE INDEX IF NOT EXISTS idx_users_household          ON public.users (household_id);


-- =============================================================================
-- FUNCTION: handle_new_auth_user
-- Auto-creates a public.users row when someone signs up via Supabase Auth.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.users (id, display_name)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1))
    );
    RETURN NEW;
END;
$$;

-- Trigger: fires after every new Supabase Auth signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();


-- =============================================================================
-- FUNCTION: update_budget_on_transaction
-- Auto-updates budgets.spent_amount when a transaction is inserted.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.update_budget_on_transaction()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Update the primary category budget
    UPDATE public.budgets
    SET spent_amount = spent_amount + NEW.amount
    WHERE household_id  = NEW.household_id
      AND category_code = NEW.category_code
      AND month         = date_trunc('month', NEW.timestamp)::DATE;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_transaction_insert ON public.transactions;
CREATE TRIGGER on_transaction_insert
    AFTER INSERT ON public.transactions
    FOR EACH ROW EXECUTE FUNCTION public.update_budget_on_transaction();


-- =============================================================================
-- FUNCTION: reallocate_budget
-- Atomically shifts allocated amount from a flexible budget to cover a deficit.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.reallocate_budget(
    p_from_id UUID,
    p_to_id UUID,
    p_amount NUMERIC
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.budgets
    SET allocated_amount = allocated_amount - p_amount
    WHERE id = p_from_id;

    UPDATE public.budgets
    SET allocated_amount = allocated_amount + p_amount
    WHERE id = p_to_id;
END;
$$;


-- =============================================================================
-- FUNCTIONS: Household onboarding (bypasses initial RLS chicken-and-egg safely)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.create_household_and_claim(p_name TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_hh public.households%ROWTYPE;
BEGIN
    INSERT INTO public.households (name)
    VALUES (p_name)
    RETURNING * INTO v_hh;

    UPDATE public.users
    SET household_id = v_hh.id,
        role = 'admin'
    WHERE id = auth.uid();

    RETURN to_jsonb(v_hh);
END;
$$;


CREATE OR REPLACE FUNCTION public.join_household_by_code(p_invite_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_hh public.households%ROWTYPE;
BEGIN
    SELECT * INTO v_hh
    FROM public.households
    WHERE lower(invite_code) = lower(trim(p_invite_code));

    IF v_hh.id IS NULL THEN
        RAISE EXCEPTION 'Invalid invite code';
    END IF;

    UPDATE public.users
    SET household_id = v_hh.id,
        role = 'member'
    WHERE id = auth.uid();

    RETURN to_jsonb(v_hh);
END;
$$;


-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

-- ── households ──────────────────────────────────────────────────────────────
ALTER TABLE public.households ENABLE ROW LEVEL SECURITY;

-- Members can view their own household
CREATE POLICY "households_select_own"
    ON public.households FOR SELECT
    USING (
        id = (SELECT household_id FROM public.users WHERE id = auth.uid())
    );

-- Any authenticated user can create a household (during onboarding)
CREATE POLICY "households_insert_authenticated"
    ON public.households FOR INSERT
    WITH CHECK (auth.role() = 'authenticated');

-- Only admins can update household info
CREATE POLICY "households_update_admin"
    ON public.households FOR UPDATE
    USING (
        id = (SELECT household_id FROM public.users WHERE id = auth.uid() AND role = 'admin')
    );


-- ── users ────────────────────────────────────────────────────────────────────
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Users see only household members
CREATE POLICY "users_select_household"
    ON public.users FOR SELECT
    USING (
        household_id = (SELECT household_id FROM public.users WHERE id = auth.uid())
        OR id = auth.uid()  -- always see own row even before joining household
    );

-- User can only insert their own row (handled by trigger — belt-and-suspenders)
CREATE POLICY "users_insert_own"
    ON public.users FOR INSERT
    WITH CHECK (id = auth.uid());

-- User can update their own row; admin can update household members
CREATE POLICY "users_update_own_or_admin"
    ON public.users FOR UPDATE
    USING (
        id = auth.uid()
        OR household_id = (SELECT household_id FROM public.users WHERE id = auth.uid() AND role = 'admin')
    );


-- ── cost_control_codes ───────────────────────────────────────────────────────
ALTER TABLE public.cost_control_codes ENABLE ROW LEVEL SECURITY;

-- All authenticated users can read categories (needed for categorization UI)
CREATE POLICY "cost_control_codes_select_authenticated"
    ON public.cost_control_codes FOR SELECT
    USING (auth.role() = 'authenticated');

-- Write is service-role only (no policy = blocked for all JWT users)


-- ── budgets ──────────────────────────────────────────────────────────────────
ALTER TABLE public.budgets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "budgets_select_household"
    ON public.budgets FOR SELECT
    USING (
        household_id = (SELECT household_id FROM public.users WHERE id = auth.uid())
    );

CREATE POLICY "budgets_insert_admin"
    ON public.budgets FOR INSERT
    WITH CHECK (
        household_id = (SELECT household_id FROM public.users WHERE id = auth.uid() AND role = 'admin')
    );

CREATE POLICY "budgets_update_admin"
    ON public.budgets FOR UPDATE
    USING (
        household_id = (SELECT household_id FROM public.users WHERE id = auth.uid() AND role = 'admin')
    );


-- ── transactions ─────────────────────────────────────────────────────────────
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "transactions_select_household"
    ON public.transactions FOR SELECT
    USING (
        household_id = (SELECT household_id FROM public.users WHERE id = auth.uid())
    );

-- Inserts come from the Python service role key — no JWT insert policy needed


-- =============================================================================
-- REALTIME — Add tables to the supabase_realtime publication
-- Run after enabling Realtime in the Supabase dashboard
-- =============================================================================
-- Note: the publication must already exist (it does by default in Supabase).
-- These commands add our tables to it so clients receive change events.
ALTER PUBLICATION supabase_realtime ADD TABLE public.transactions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.budgets;
