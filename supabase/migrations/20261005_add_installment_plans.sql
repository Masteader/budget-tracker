-- Migration: Add installment_plans table for BNPL (Tamara, Tabby, Bank installment plans)
CREATE TABLE IF NOT EXISTS public.installment_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    merchant TEXT NOT NULL,
    provider TEXT NOT NULL DEFAULT 'Tamara', -- 'Tamara', 'Tabby', 'Bank', 'Other'
    total_amount NUMERIC(12, 2) NOT NULL,
    installment_count INTEGER NOT NULL DEFAULT 4,
    monthly_amount NUMERIC(12, 2) NOT NULL,
    paid_installments INTEGER NOT NULL DEFAULT 1,
    start_date DATE NOT NULL DEFAULT CURRENT_DATE,
    day_of_month INTEGER NOT NULL DEFAULT 27,
    status TEXT NOT NULL DEFAULT 'ACTIVE', -- 'ACTIVE', 'COMPLETED'
    category_code TEXT DEFAULT 'OPEX-SHOPPING',
    original_transaction_id UUID REFERENCES public.transactions(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Index for fast lookups by household and status
CREATE INDEX IF NOT EXISTS idx_installment_plans_household_status 
ON public.installment_plans(household_id, status);

CREATE INDEX IF NOT EXISTS idx_installment_plans_original_tx 
ON public.installment_plans(original_transaction_id);

-- RLS policies: Allow authenticated users in the household to select and modify
ALTER TABLE public.installment_plans ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow household members full access to installment_plans"
ON public.installment_plans
FOR ALL
TO authenticated
USING (
    household_id IN (
        SELECT household_id FROM public.users WHERE id = auth.uid()
    )
)
WITH CHECK (
    household_id IN (
        SELECT household_id FROM public.users WHERE id = auth.uid()
    )
);
