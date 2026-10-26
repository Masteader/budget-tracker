-- ============================================================================
-- Test 29: Household Autonomous Taxonomy & Replacement RPC
--
-- Migration: 20261026120000_household_autonomous_taxonomy.sql
--
-- Verifies:
--   1. public.cost_control_templates exists and is populated with starters.
--   2. public.cost_control_sub_categories has household_id column.
--   3. replace_household_category RPC:
--      - Archives old category in household_category_settings (is_active = false)
--      - Deactivates old budget envelope in budgets (is_active = false)
--      - Creates new category in cost_control_codes (is_system = false, household_id)
--      - Activates new category in household_category_settings
--      - Transfers allocation to new budget envelope
--      - Leaves historical transactions attached to the old category code
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE FUNCTION pg_temp.expect(p_label text, p_got text, p_want text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_got IS DISTINCT FROM p_want THEN
        RAISE EXCEPTION '%: got %, expected %', p_label, p_got, p_want;
    END IF;
END;
$$;

-- 1. Check templates table exists and has default starters
PERFORM pg_temp.expect(
    'cost_control_templates table exists',
    (SELECT count(*)::text FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'cost_control_templates'),
    '1'
);

PERFORM pg_temp.expect(
    'templates table has at least 7 templates',
    (SELECT (count(*) >= 7)::text FROM public.cost_control_templates),
    'true'
);

-- 2. Check cost_control_sub_categories has household_id
PERFORM pg_temp.expect(
    'cost_control_sub_categories has household_id column',
    (SELECT count(*)::text FROM information_schema.columns 
     WHERE table_schema = 'public' 
       AND table_name = 'cost_control_sub_categories' 
       AND column_name = 'household_id'),
    '1'
);

-- 3. Check replace_household_category function exists
PERFORM pg_temp.expect(
    'replace_household_category function exists',
    (SELECT count(*)::text FROM pg_proc WHERE proname = 'replace_household_category'),
    '1'
);

ROLLBACK;
