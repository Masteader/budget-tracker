-- =============================================================================
-- BUDGET TRACKER — CONSOLIDATED SUPABASE SCHEMA BASELINE
-- Complete 15-Table Architecture, RLS Policies, Functions & Triggers
-- Saudi Fintech & Islamic Law Invariants Enforced (Rule 02, Rule 04, Rule 05)
-- Run this entire file in Supabase SQL Editor (Project → SQL Editor)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- EXTENSIONS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid(), crypt()
CREATE EXTENSION IF NOT EXISTS "unaccent";   -- accent-insensitive merchant search

-- =============================================================================
-- 1. TABLE: households
-- Single source of truth for salary cycle (payday_day) & shared budgeting.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.households (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                TEXT NOT NULL,
    invite_code         TEXT UNIQUE NOT NULL DEFAULT substr(md5(random()::text), 1, 8),
    payday_day          INTEGER NOT NULL DEFAULT 27 CHECK (payday_day >= 1 AND payday_day <= 31),
    monthly_income      NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (monthly_income >= 0),
    rollover_rule       TEXT NOT NULL DEFAULT 'accumulate' CHECK (rollover_rule IN ('accumulate', 'reset', 'send_to_savings')),
    owner_user_id       UUID, -- Forward reference to users(id), constrained below
    household_type      TEXT NOT NULL DEFAULT 'family' CHECK (household_type IN ('family', 'flatmates', 'individual')),
    accumulated_savings NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    last_rollover_date  DATE,
    last_rollover_amount NUMERIC(12, 2) DEFAULT 0.00,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.households IS 'A shared budget group (family / flatmates / individual).';
COMMENT ON COLUMN public.households.invite_code IS '8-char code to invite new members.';
COMMENT ON COLUMN public.households.payday_day IS 'Configured monthly salary day (1-31). Sole Single Source of Truth.';

-- =============================================================================
-- 2. TABLE: users
-- Extends Supabase auth.users with household profile.
-- Historical payday_day is restored here for migration replay chain compatibility
-- and dropped in migration 20261102000000_cleanup_database_jargon_and_zombie_columns.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.users (
    id             UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    household_id   UUID REFERENCES public.households(id) ON DELETE SET NULL,
    display_name   TEXT NOT NULL,
    role           TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    payday_day     INT DEFAULT 27 CHECK (payday_day >= 1 AND payday_day <= 31),
    financial_role TEXT DEFAULT 'provider',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.users IS 'App-level user profile linked to Supabase Auth.';
COMMENT ON COLUMN public.users.role IS '''admin'' can edit budgets; ''member'' is read-only.';
COMMENT ON COLUMN public.users.financial_role IS 'Islamic role (provider, wife, dependent, co_earner, peer).';

-- Add circular FK for households.owner_user_id
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'households_owner_user_id_fkey'
    ) THEN
        ALTER TABLE public.households
        ADD CONSTRAINT households_owner_user_id_fkey
        FOREIGN KEY (owner_user_id) REFERENCES public.users(id) ON DELETE SET NULL;
    END IF;
END $$;

-- =============================================================================
-- 3. TABLE: cost_control_codes
-- Master list of expense categories + keywords for merchant matching.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.cost_control_codes (
    id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    code        TEXT    UNIQUE NOT NULL,
    category    TEXT    NOT NULL,
    keywords    TEXT[]  NOT NULL DEFAULT '{}'::TEXT[],
    is_flexible BOOLEAN NOT NULL DEFAULT false,
    household_id UUID   REFERENCES public.households(id) ON DELETE CASCADE,
    is_system   BOOLEAN NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.cost_control_codes IS 'Category taxonomy + keyword mapping for merchant matching.';
COMMENT ON COLUMN public.cost_control_codes.is_flexible IS 'If true, this budget can be raided during automatic reallocation.';

-- =============================================================================
-- 4. TABLE: cost_control_sub_categories
-- Sub-category line items under main category codes.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.cost_control_sub_categories (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID REFERENCES public.households(id) ON DELETE CASCADE,
    parent_code  TEXT NOT NULL REFERENCES public.cost_control_codes(code) ON UPDATE CASCADE ON DELETE CASCADE,
    sub_code     TEXT NOT NULL,
    name_en      TEXT NOT NULL,
    name_ar      TEXT NOT NULL,
    keywords     TEXT[] NOT NULL DEFAULT '{}'::TEXT[],
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_sub_category UNIQUE (household_id, parent_code, sub_code)
);

CREATE INDEX IF NOT EXISTS idx_sub_categories_hh_parent 
    ON public.cost_control_sub_categories(household_id, parent_code);

-- =============================================================================
-- 5. TABLE: cost_control_templates
-- Master catalog templates for autonomous category provisioning.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.cost_control_templates (
    code            VARCHAR(60) PRIMARY KEY,
    default_name_en VARCHAR(100) NOT NULL,
    default_name_ar VARCHAR(100) NOT NULL,
    icon_key        VARCHAR(50) NOT NULL DEFAULT 'category',
    keywords        TEXT[] DEFAULT '{}'::TEXT[],
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- 6. TABLE: household_category_settings
-- Active/inactive toggles for categories per household.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.household_category_settings (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id  UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    category_code VARCHAR(60) NOT NULL REFERENCES public.cost_control_codes(code) ON UPDATE CASCADE ON DELETE CASCADE,
    is_active     BOOLEAN NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_household_category UNIQUE (household_id, category_code)
);

CREATE INDEX IF NOT EXISTS idx_hh_cat_settings_active 
    ON public.household_category_settings(household_id, is_active);

-- =============================================================================
-- 7. TABLE: budgets
-- Monthly budget allocation per category per household.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.budgets (
    id               UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id     UUID    NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    month            DATE    NOT NULL,
    category_code    TEXT    NOT NULL REFERENCES public.cost_control_codes(code) ON UPDATE CASCADE,
    allocated_amount NUMERIC(12, 2) NOT NULL CHECK (allocated_amount >= 0),
    spent_amount     NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (spent_amount >= 0),
    remaining_amount NUMERIC(12, 2) GENERATED ALWAYS AS (allocated_amount - spent_amount) STORED,
    cycle_key        VARCHAR(7),
    sub_allocations  JSONB   NOT NULL DEFAULT '{}'::jsonb,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT budgets_unique_month_category UNIQUE (household_id, month, category_code)
);

CREATE INDEX IF NOT EXISTS idx_budgets_household_month ON public.budgets (household_id, month);
CREATE INDEX IF NOT EXISTS idx_budgets_cycle_key ON public.budgets (household_id, cycle_key);

-- =============================================================================
-- 8. TABLE: accounts
-- Personal bank accounts, e-wallets, crypto, cash, and shared pools.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.accounts (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id   UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    owner_user_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    name           TEXT NOT NULL,
    account_type   TEXT NOT NULL CHECK (account_type IN ('bank', 'e_wallet', 'crypto', 'cash', 'shared_pool', 'savings')),
    currency       TEXT NOT NULL DEFAULT 'SAR',
    balance        NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    is_shared_pool BOOLEAN NOT NULL DEFAULT false,
    color_hex      TEXT DEFAULT '#00E5BF',
    icon_name      TEXT DEFAULT 'account_balance_rounded',
    is_archived    BOOLEAN NOT NULL DEFAULT false,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_accounts_household ON public.accounts(household_id);
CREATE INDEX IF NOT EXISTS idx_accounts_owner ON public.accounts(owner_user_id);

-- =============================================================================
-- 9. TABLE: transactions
-- Every expense transaction (chat/voice, receipt OCR, manual entry).
-- Modern notes TEXT column (historical raw_sms jargon eliminated).
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
    notes                      TEXT,
    source                     TEXT    NOT NULL DEFAULT 'manual' CHECK (source IN ('chat', 'receipt_scan', 'manual')),
    is_reallocated             BOOLEAN NOT NULL DEFAULT false,
    reallocated_from_budget_id UUID    REFERENCES public.budgets(id) ON DELETE SET NULL,
    items                      JSONB   DEFAULT '[]'::jsonb,
    receipt_url                TEXT,
    spent_by                   TEXT    NOT NULL DEFAULT 'me',
    beneficiary_type           TEXT    DEFAULT 'household',
    beneficiary_id             TEXT,
    account_id                 UUID    REFERENCES public.accounts(id) ON DELETE SET NULL,
    cycle_key                  VARCHAR(7),
    dedup_fingerprint          TEXT,
    qr_code_raw                TEXT,
    nafaqah_class              TEXT,
    nafaqah_spouse_id          UUID    REFERENCES public.users(id) ON DELETE SET NULL,
    is_settlement              BOOLEAN DEFAULT false,
    settlement_target_id       TEXT,
    line_items                 JSONB   DEFAULT '[]'::jsonb,
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.transactions IS 'Every household expense transaction (chat/voice, receipt OCR, manual entry).';
COMMENT ON COLUMN public.transactions.notes IS 'Free-text audit note (chat message text, receipt OCR summary, manual expense tags). The app never reads SMS.';
COMMENT ON COLUMN public.transactions.source IS 'Ingestion channel: chat (chat/voice), receipt_scan (receipt photo or ZATCA QR), or manual. The app never reads SMS.';

CREATE INDEX IF NOT EXISTS idx_transactions_household   ON public.transactions (household_id);
CREATE INDEX IF NOT EXISTS idx_transactions_timestamp   ON public.transactions (timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_created_at  ON public.transactions (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_cycle_key   ON public.transactions (household_id, cycle_key);

-- =============================================================================
-- 10. TABLE: account_transfers
-- Inter-account transfers and transfer fees.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.account_transfers (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id    UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    from_account_id UUID NOT NULL REFERENCES public.accounts(id) ON DELETE RESTRICT,
    to_account_id   UUID NOT NULL REFERENCES public.accounts(id) ON DELETE RESTRICT,
    amount          NUMERIC(14, 2) NOT NULL CHECK (amount > 0),
    fee             NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (fee >= 0),
    timestamp       TIMESTAMPTZ NOT NULL DEFAULT now(),
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- 11. TABLE: income_records
-- Itemized income receipts (Base salary, Overtime, Bonuses, Side gigs).
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.income_records (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id  UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    user_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    account_id    UUID NOT NULL REFERENCES public.accounts(id) ON DELETE RESTRICT,
    cycle_key     TEXT NOT NULL,
    source_type   TEXT NOT NULL CHECK (source_type IN ('salary', 'overtime', 'bonus', 'side_gig', 'roommate_share', 'other')),
    title         TEXT NOT NULL,
    base_amount   NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    overtime      NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    bonus         NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    deductions    NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    net_amount    NUMERIC(14, 2) NOT NULL,
    received_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    notes         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- 12. TABLE: installment_plans
-- BNPL and recurring installment plans (Tamara, Tabby, etc.).
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.installment_plans (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id            UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    merchant                TEXT NOT NULL,
    provider                TEXT NOT NULL DEFAULT 'Tamara',
    total_amount            NUMERIC(12, 2) NOT NULL,
    installment_count       INTEGER NOT NULL DEFAULT 4,
    monthly_amount          NUMERIC(12, 2) NOT NULL,
    paid_installments       INTEGER NOT NULL DEFAULT 1,
    start_date              DATE NOT NULL DEFAULT CURRENT_DATE,
    day_of_month            INTEGER NOT NULL DEFAULT 27,
    status                  TEXT NOT NULL DEFAULT 'ACTIVE',
    category_code           TEXT DEFAULT 'OPEX-SHOPPING',
    original_transaction_id UUID REFERENCES public.transactions(id) ON DELETE SET NULL,
    frequency               TEXT NOT NULL DEFAULT 'monthly',
    next_due_at             DATE,
    notes                   TEXT,
    created_at              TIMESTAMPTZ DEFAULT now()
);

-- =============================================================================
-- 13. TABLE: household_dependents
-- Manual family members and dependents.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.household_dependents (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id      UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    name              TEXT NOT NULL,
    avatar_icon       TEXT DEFAULT 'child',
    relationship      TEXT DEFAULT 'child',
    monthly_allowance NUMERIC(10, 2) DEFAULT 0.0,
    linked_user_id    UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- 14. TABLE: household_invites
-- Secure join invitations for households.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.household_invites (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id     UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    invite_code      VARCHAR(8) UNIQUE NOT NULL,
    role             VARCHAR(20) NOT NULL DEFAULT 'peer',
    created_by       UUID REFERENCES public.users(id) ON DELETE SET NULL,
    target_member_id UUID REFERENCES public.household_dependents(id) ON DELETE CASCADE,
    expires_at       TIMESTAMPTZ NOT NULL,
    used_by          UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at       TIMESTAMPTZ DEFAULT now()
);

-- =============================================================================
-- 15. TABLE: household_memberships
-- Multi-household membership junction with permissions and roles.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.household_memberships (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id   UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    user_id        UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    role           TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'co_admin', 'member')),
    financial_role TEXT DEFAULT 'provider',
    is_default     BOOLEAN NOT NULL DEFAULT false,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_household_user UNIQUE (household_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_memberships_user ON public.household_memberships(user_id);
CREATE INDEX IF NOT EXISTS idx_memberships_household ON public.household_memberships(household_id);

-- =============================================================================
-- SECONDARY TABLES
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.member_allowances (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    user_id      UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    amount       NUMERIC(10, 2) NOT NULL CHECK (amount >= 0),
    cycle_key    TEXT NOT NULL,
    status       TEXT NOT NULL DEFAULT 'pending',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.spouse_reimbursements (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    claimant_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    amount       NUMERIC(10, 2) NOT NULL CHECK (amount > 0),
    status       TEXT NOT NULL DEFAULT 'pending',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.api_quota (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    request_type TEXT NOT NULL,
    period_start TIMESTAMPTZ NOT NULL,
    call_count   INTEGER NOT NULL DEFAULT 1,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.invite_attempt_log (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    ip_address INET,
    attempted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    success    BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.inquiries (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID REFERENCES public.users(id) ON DELETE SET NULL,
    household_id UUID REFERENCES public.households(id) ON DELETE SET NULL,
    message      TEXT NOT NULL,
    status       TEXT NOT NULL DEFAULT 'open',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- CORE SECURITY DEFINER FUNCTIONS & HELPERS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_auth_user_household_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT household_id FROM public.users WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.get_auth_user_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT role FROM public.users WHERE id = auth.uid();
$$;

-- Trigger: auto-create public.users row on auth.users signup
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

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();

-- Trigger: update spent_amount in budgets on transaction insert
CREATE OR REPLACE FUNCTION public.update_budget_on_transaction()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.budgets
    SET spent_amount = spent_amount + NEW.amount
    WHERE household_id  = NEW.household_id
      AND category_code = NEW.category_code
      AND (
          (cycle_key IS NOT NULL AND cycle_key = NEW.cycle_key)
          OR (cycle_key IS NULL AND month = date_trunc('month', NEW.timestamp)::DATE)
      );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_transaction_insert ON public.transactions;
CREATE TRIGGER on_transaction_insert
    AFTER INSERT ON public.transactions
    FOR EACH ROW EXECUTE FUNCTION public.update_budget_on_transaction();

-- Function: reallocate_budget with authorization
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
DECLARE
    v_from_hh UUID;
    v_to_hh UUID;
    v_user_hh UUID;
    v_user_role TEXT;
BEGIN
    SELECT household_id INTO v_from_hh FROM public.budgets WHERE id = p_from_id;
    SELECT household_id INTO v_to_hh FROM public.budgets WHERE id = p_to_id;

    IF v_from_hh IS NULL OR v_to_hh IS NULL OR v_from_hh <> v_to_hh THEN
        RAISE EXCEPTION 'Invalid budget accounts for reallocation';
    END IF;

    SELECT household_id, role INTO v_user_hh, v_user_role FROM public.users WHERE id = auth.uid();
    IF auth.role() <> 'service_role' AND (v_user_hh <> v_from_hh OR v_user_role NOT IN ('admin', 'co_admin')) THEN
        RAISE EXCEPTION 'Unauthorized to reallocate budget';
    END IF;

    UPDATE public.budgets
    SET allocated_amount = allocated_amount - p_amount
    WHERE id = p_from_id AND allocated_amount >= p_amount;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Insufficient allocated amount for transfer';
    END IF;

    UPDATE public.budgets
    SET allocated_amount = allocated_amount + p_amount
    WHERE id = p_to_id;
END;
$$;

-- =============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- =============================================================================

ALTER TABLE public.households ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cost_control_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cost_control_sub_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cost_control_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.household_category_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.income_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.installment_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.household_dependents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.household_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.household_memberships ENABLE ROW LEVEL SECURITY;

-- Realtime Publications
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'transactions'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.transactions;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'budgets'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.budgets;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'accounts'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.accounts;
    END IF;
END $$;
