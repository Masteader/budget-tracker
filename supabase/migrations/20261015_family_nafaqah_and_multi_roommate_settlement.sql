-- Migration: 20261015_family_nafaqah_and_multi_roommate_settlement.sql
-- Description: Extends users, transactions, dependents, and creates household_invites for role-aware settlements.

-- 1. Users financial_role
ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS financial_role TEXT DEFAULT 'provider';

-- 2. Household Invites Table
CREATE TABLE IF NOT EXISTS public.household_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    invite_code VARCHAR(8) UNIQUE NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'peer',
    created_by UUID REFERENCES public.users(id),
    expires_at TIMESTAMPTZ NOT NULL,
    used_by UUID REFERENCES public.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_invites_code ON public.household_invites(invite_code);

-- 3. Household Dependents extensions
ALTER TABLE public.household_dependents
ADD COLUMN IF NOT EXISTS relationship TEXT DEFAULT 'child',
ADD COLUMN IF NOT EXISTS monthly_allowance NUMERIC(10, 2) DEFAULT 0.0;

-- 4. Transactions settlement & line items
ALTER TABLE public.transactions
ADD COLUMN IF NOT EXISTS beneficiary_type TEXT DEFAULT 'household',
ADD COLUMN IF NOT EXISTS beneficiary_id TEXT,
ADD COLUMN IF NOT EXISTS is_settlement BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS settlement_target_id TEXT,
ADD COLUMN IF NOT EXISTS line_items JSONB DEFAULT '[]'::jsonb;

CREATE INDEX IF NOT EXISTS idx_transactions_settlement_flag ON public.transactions(household_id, is_settlement);
