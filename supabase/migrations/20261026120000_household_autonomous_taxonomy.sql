-- Migration: 20261026120000_household_autonomous_taxonomy.sql
-- Description: Household Autonomous Taxonomy, Master Templates Catalog,
--              Household Sub-Categories Scoping, and Category Replacement RPC.

BEGIN;

-- 1. Master Template Catalog
CREATE TABLE IF NOT EXISTS public.cost_control_templates (
  code VARCHAR(60) PRIMARY KEY,
  default_name_en VARCHAR(100) NOT NULL,
  default_name_ar VARCHAR(100) NOT NULL,
  icon_key VARCHAR(50) NOT NULL DEFAULT 'category',
  keywords TEXT[] DEFAULT '{}'::TEXT[],
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.cost_control_templates (code, default_name_en, default_name_ar, icon_key, keywords)
VALUES
  ('OPEX-FUEL', 'Fuel & Transportation', 'الوقود والمواصلات', 'car', ARRAY['sasco', 'adrees', 'petrol', 'fuel', 'uber', 'bolt']),
  ('OPEX-GROCERY', 'Groceries & Food', 'البقالة والمقاضي', 'shopping_basket', ARRAY['panda', 'othaim', 'lulu', 'danube', 'tamimi']),
  ('OPEX-UTILITIES', 'Utilities & Bills', 'الفواتير والخدمات', 'bolt', ARRAY['sec', 'electricity', 'stc', 'mobily', 'water']),
  ('OPEX-HOUSING', 'Housing & Rent', 'السكن والإيجار', 'home', ARRAY['rent', 'building', 'maintenance']),
  ('OPEX-DINING', 'Dining & Cafes', 'المطاعم والكافيهات', 'coffee', ARRAY['mcdonalds', 'albaik', 'starbucks', 'barns']),
  ('OPEX-SHOPPING', 'Shopping & Personal', 'التسوق والمستلزمات', 'shopping_bag', ARRAY['jarir', 'noon', 'amazon', 'extra']),
  ('OPEX-HEALTH', 'Healthcare & Pharmacy', 'الصحة والصيدلية', 'health', ARRAY['nahdi', 'dawaa', 'hospital', 'clinic'])
ON CONFLICT (code) DO NOTHING;

ALTER TABLE public.cost_control_templates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cost_control_templates_select ON public.cost_control_templates;
CREATE POLICY cost_control_templates_select ON public.cost_control_templates
  FOR SELECT TO authenticated, anon USING (true);

-- 2. Add household_id to cost_control_sub_categories
ALTER TABLE public.cost_control_sub_categories
  ADD COLUMN IF NOT EXISTS household_id UUID REFERENCES public.households(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_sub_categories_hh_parent 
  ON public.cost_control_sub_categories(household_id, parent_code);

-- Update RLS on cost_control_sub_categories
ALTER TABLE public.cost_control_sub_categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cost_control_sub_categories_select_visible_parent ON public.cost_control_sub_categories;
DROP POLICY IF EXISTS cost_control_sub_categories_select_autonomous ON public.cost_control_sub_categories;
CREATE POLICY cost_control_sub_categories_select_autonomous ON public.cost_control_sub_categories
  FOR SELECT TO authenticated
  USING (
    household_id IS NULL OR household_id = (SELECT public.get_auth_user_household_id())
  );

DROP POLICY IF EXISTS cost_control_sub_categories_insert ON public.cost_control_sub_categories;
CREATE POLICY cost_control_sub_categories_insert ON public.cost_control_sub_categories
  FOR INSERT TO authenticated
  WITH CHECK (
    household_id IS NOT NULL 
    AND household_id = (SELECT public.get_auth_user_household_id())
    AND (SELECT public.get_auth_user_role()) IN ('admin', 'co_admin')
  );

DROP POLICY IF EXISTS cost_control_sub_categories_update ON public.cost_control_sub_categories;
CREATE POLICY cost_control_sub_categories_update ON public.cost_control_sub_categories
  FOR UPDATE TO authenticated
  USING (
    household_id IS NOT NULL 
    AND household_id = (SELECT public.get_auth_user_household_id())
    AND (SELECT public.get_auth_user_role()) IN ('admin', 'co_admin')
  )
  WITH CHECK (
    household_id IS NOT NULL 
    AND household_id = (SELECT public.get_auth_user_household_id())
    AND (SELECT public.get_auth_user_role()) IN ('admin', 'co_admin')
  );

DROP POLICY IF EXISTS cost_control_sub_categories_delete ON public.cost_control_sub_categories;
CREATE POLICY cost_control_sub_categories_delete ON public.cost_control_sub_categories
  FOR DELETE TO authenticated
  USING (
    household_id IS NOT NULL 
    AND household_id = (SELECT public.get_auth_user_household_id())
    AND (SELECT public.get_auth_user_role()) IN ('admin', 'co_admin')
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.cost_control_sub_categories TO authenticated;

-- 3. Category Lifecycle Replacement Stored Procedure / RPC
CREATE OR REPLACE FUNCTION public.replace_household_category(
  p_household_id UUID,
  p_old_code VARCHAR,
  p_new_name VARCHAR,
  p_new_code VARCHAR,
  p_cycle_key VARCHAR
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_role TEXT;
  v_caller_hh UUID;
  v_allocated NUMERIC(12, 2) := 0.0;
  v_month DATE;
  v_generated_code VARCHAR;
BEGIN
  -- Authorization check: caller must be admin or co_admin of p_household_id or service_role
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    v_caller_hh := (SELECT public.get_auth_user_household_id());
    v_caller_role := (SELECT public.get_auth_user_role());
    IF v_caller_hh IS DISTINCT FROM p_household_id OR v_caller_role NOT IN ('admin', 'co_admin') THEN
      RAISE EXCEPTION 'Unauthorized: only household admins can replace categories'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- 1. Determine new category code if not supplied or clean it
  v_generated_code := COALESCE(NULLIF(TRIM(p_new_code), ''), 'CUSTOM-' || upper(regexp_replace(p_new_name, '[^a-zA-Z0-9]+', '_', 'g')));
  IF NOT v_generated_code LIKE 'CUSTOM-%' THEN
    v_generated_code := 'CUSTOM-' || v_generated_code;
  END IF;

  -- 2. Fetch current allocated amount from old budget envelope
  SELECT allocated_amount, month INTO v_allocated, v_month
  FROM public.budgets
  WHERE household_id = p_household_id
    AND category_code = p_old_code
    AND (cycle_key = p_cycle_key OR cycle_key = substring(p_cycle_key from 1 for 7))
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_allocated IS NULL THEN
    v_allocated := 0.0;
  END IF;
  IF v_month IS NULL THEN
    v_month := date_trunc('month', CURRENT_DATE)::DATE;
  END IF;

  -- 3. Deactivate old category in household_category_settings
  INSERT INTO public.household_category_settings (household_id, category_code, is_active, updated_at)
  VALUES (p_household_id, p_old_code, false, now())
  ON CONFLICT (household_id, category_code)
  DO UPDATE SET is_active = false, updated_at = now();

  -- 4. Deactivate old budget envelope
  UPDATE public.budgets
  SET is_active = false
  WHERE household_id = p_household_id
    AND category_code = p_old_code
    AND (cycle_key = p_cycle_key OR cycle_key = substring(p_cycle_key from 1 for 7));

  -- 5. Create new category in cost_control_codes
  INSERT INTO public.cost_control_codes (code, category, is_system, household_id)
  VALUES (v_generated_code, TRIM(p_new_name), false, p_household_id)
  ON CONFLICT (code) DO UPDATE SET category = TRIM(p_new_name);

  -- 6. Activate new category in settings
  INSERT INTO public.household_category_settings (household_id, category_code, is_active, updated_at)
  VALUES (p_household_id, v_generated_code, true, now())
  ON CONFLICT (household_id, category_code)
  DO UPDATE SET is_active = true, updated_at = now();

  -- 7. Provision new budget envelope with transferred allocation
  INSERT INTO public.budgets (household_id, category_code, month, cycle_key, allocated_amount, spent_amount, is_active)
  VALUES (p_household_id, v_generated_code, v_month, p_cycle_key, v_allocated, 0.0, true)
  ON CONFLICT (household_id, month, category_code)
  DO UPDATE SET 
    allocated_amount = EXCLUDED.allocated_amount,
    cycle_key = EXCLUDED.cycle_key,
    is_active = true;

  RETURN jsonb_build_object(
    'status', 'success',
    'old_code', p_old_code,
    'new_code', v_generated_code,
    'new_name', TRIM(p_new_name),
    'allocated_transferred', v_allocated
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.replace_household_category(UUID, VARCHAR, VARCHAR, VARCHAR, VARCHAR) TO authenticated, service_role;

-- 4. Helper to seed default taxonomy for a household
CREATE OR REPLACE FUNCTION public.seed_household_default_taxonomy(p_household_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.household_category_settings (household_id, category_code, is_active)
  SELECT p_household_id, t.code, true
  FROM public.cost_control_templates t
  ON CONFLICT (household_id, category_code) DO NOTHING;
END;
$$;

GRANT EXECUTE ON FUNCTION public.seed_household_default_taxonomy(UUID) TO authenticated, service_role;

COMMIT;
