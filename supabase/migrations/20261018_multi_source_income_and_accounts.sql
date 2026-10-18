-- =============================================================================
-- Migration: 20261018_multi_source_income_and_accounts.sql
-- Description: Adds accounts, account_transfers, and income_records tables;
--              adds account_id to budgets and transactions.
-- =============================================================================

-- 1. Accounts Table (Banks, E-Wallets, Crypto, Cash, Shared Pools)
CREATE TABLE IF NOT EXISTS public.accounts (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id   UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    owner_user_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    name           TEXT NOT NULL,
    account_type   TEXT NOT NULL CHECK (account_type IN ('bank', 'e_wallet', 'crypto', 'cash', 'shared_pool')),
    currency       TEXT NOT NULL DEFAULT 'SAR',
    balance        NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    is_shared_pool BOOLEAN NOT NULL DEFAULT false,
    color_hex      TEXT DEFAULT '#00E5BF',
    icon_name      TEXT DEFAULT 'account_balance_rounded',
    is_archived    BOOLEAN NOT NULL DEFAULT false,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.accounts IS 'Personal bank accounts, e-wallets, crypto exchanges, cash, and shared household pools.';
COMMENT ON COLUMN public.accounts.is_shared_pool IS 'If true, visible to all members of the household for shared bills and flat pooling.';

CREATE INDEX IF NOT EXISTS idx_accounts_household ON public.accounts(household_id);
CREATE INDEX IF NOT EXISTS idx_accounts_owner ON public.accounts(owner_user_id);
CREATE INDEX IF NOT EXISTS idx_accounts_type ON public.accounts(account_type);

-- 2. Inter-Account Transfers Table
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

COMMENT ON TABLE  public.account_transfers IS 'Inter-account fund transfers and fees (e.g. interbank fee or crypto network gas fee).';

CREATE INDEX IF NOT EXISTS idx_account_transfers_household ON public.account_transfers(household_id);
CREATE INDEX IF NOT EXISTS idx_account_transfers_from ON public.account_transfers(from_account_id);
CREATE INDEX IF NOT EXISTS idx_account_transfers_to ON public.account_transfers(to_account_id);

-- 3. Multi-Source Income Records Table
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

COMMENT ON TABLE  public.income_records IS 'Itemized income receipts (Base salary, Overtime, Bonuses, Side gigs, Roommate contributions).';

CREATE INDEX IF NOT EXISTS idx_income_records_household ON public.income_records(household_id);
CREATE INDEX IF NOT EXISTS idx_income_records_cycle ON public.income_records(household_id, cycle_key);
CREATE INDEX IF NOT EXISTS idx_income_records_account ON public.income_records(account_id);

-- 4. Budget & Transaction Linkage
ALTER TABLE public.budgets 
    ADD COLUMN IF NOT EXISTS account_id UUID REFERENCES public.accounts(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_budgets_account ON public.budgets(account_id);

ALTER TABLE public.transactions 
    ADD COLUMN IF NOT EXISTS account_id UUID REFERENCES public.accounts(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_transactions_account ON public.transactions(account_id);

-- 5. Row-Level Security (RLS)
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.income_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users view their accounts or shared pools" ON public.accounts;
CREATE POLICY "Users view their accounts or shared pools" ON public.accounts
    FOR SELECT TO authenticated
    USING (
        owner_user_id = auth.uid() 
        OR (is_shared_pool = true AND household_id IN (SELECT household_id FROM public.users WHERE id = auth.uid()))
    );

DROP POLICY IF EXISTS "Users can manage personal accounts" ON public.accounts;
CREATE POLICY "Users can manage personal accounts" ON public.accounts
    FOR ALL TO authenticated
    USING (owner_user_id = auth.uid());

DROP POLICY IF EXISTS "Household members view and create transfers" ON public.account_transfers;
CREATE POLICY "Household members view and create transfers" ON public.account_transfers
    FOR ALL TO authenticated
    USING (household_id IN (SELECT household_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Household members view and record income" ON public.income_records;
CREATE POLICY "Household members view and record income" ON public.income_records
    FOR ALL TO authenticated
    USING (household_id IN (SELECT household_id FROM public.users WHERE id = auth.uid()));
