-- Migration: 20261011_hybrid_category_lifecycle.sql
-- Description: Adds system flag and household_id to cost_control_codes,
--              creates household_category_settings for active/inactive state.

-- 1. Alter cost_control_codes
ALTER TABLE public.cost_control_codes
  ADD COLUMN IF NOT EXISTS household_id UUID REFERENCES public.households(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS is_system BOOLEAN NOT NULL DEFAULT false;

-- 2. Mark existing standard seeded codes as system
UPDATE public.cost_control_codes
SET is_system = true, household_id = NULL
WHERE code LIKE 'OPEX-%' OR code LIKE 'CAPEX-%';

-- 3. Create household_category_settings table
CREATE TABLE IF NOT EXISTS public.household_category_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
  category_code VARCHAR(60) NOT NULL REFERENCES public.cost_control_codes(code) ON UPDATE CASCADE ON DELETE CASCADE,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_household_category UNIQUE (household_id, category_code)
);

CREATE INDEX IF NOT EXISTS idx_hh_cat_settings_active 
  ON public.household_category_settings(household_id, is_active);

-- 4. Enable RLS
ALTER TABLE public.cost_control_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.household_category_settings ENABLE ROW LEVEL SECURITY;

-- 5. RLS Policies for cost_control_codes
DROP POLICY IF EXISTS "cost_control_codes_select" ON public.cost_control_codes;
CREATE POLICY "cost_control_codes_select" ON public.cost_control_codes
  FOR SELECT USING (household_id IS NULL OR household_id = auth.uid());

DROP POLICY IF EXISTS "cost_control_codes_insert" ON public.cost_control_codes;
CREATE POLICY "cost_control_codes_insert" ON public.cost_control_codes
  FOR INSERT WITH CHECK (household_id IS NOT NULL AND is_system = false);

DROP POLICY IF EXISTS "cost_control_codes_update" ON public.cost_control_codes;
CREATE POLICY "cost_control_codes_update" ON public.cost_control_codes
  FOR UPDATE USING (household_id IS NOT NULL AND is_system = false);

-- Disallow deletion by end users: categories are permanent taxonomy items
-- that can only be toggled active or inactive via household_category_settings.
DROP POLICY IF EXISTS "cost_control_codes_delete" ON public.cost_control_codes;
CREATE POLICY "cost_control_codes_delete" ON public.cost_control_codes
  FOR DELETE USING (auth.role() = 'service_role');

-- 6. RLS Policies for household_category_settings
DROP POLICY IF EXISTS "household_category_settings_all" ON public.household_category_settings;
CREATE POLICY "household_category_settings_all" ON public.household_category_settings
  FOR ALL USING (household_id = auth.uid());
