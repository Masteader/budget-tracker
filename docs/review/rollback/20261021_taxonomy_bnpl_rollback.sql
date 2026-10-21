-- ============================================================================
-- Rollback snapshot for 20261021000000_saudi_taxonomy_and_bnpl_schedule.sql
-- Snapshot date: 2026-10-21. Written against a local database rebuilt from the
-- repository up to 20261020900000 (the state live has once 700000 / 750000 /
-- 800000 / 900000 are applied) and the same database after 20261021000000.
--
-- Run ONLY to undo 20261021000000, in the SQL editor as `postgres`, after review.
-- It restores the 20261020900000 pay_installment_plan, drops the schedule
-- trigger, its two functions, the next-due index, the frequency CHECK and the
-- installment_plans.frequency / next_due_at columns, and deletes the 23 system
-- sub-categories and 8 system categories the migration added.
-- Verified locally: 20261021000000 -> this script -> schema and data identical
-- to the pre-migration database (pg_dump diff) -> 20261021000000 re-applied ->
-- DB suite green. It refuses to run twice, before the migration, or while any
-- household data uses the new categories.
--
-- What it cannot undo / data impact:
--   * installment_plans.frequency and next_due_at are dropped: bi-weekly plans
--     lose their frequency (export `SELECT id, frequency FROM installment_plans
--     WHERE frequency <> 'monthly'` first if needed). Payments recorded meanwhile
--     stay recorded (paid_installments / status are not touched).
--   * The new categories are removed only when nothing references them
--     (transactions, budgets, household settings, installment plans); otherwise
--     the script aborts and lists the counts: move those rows to another
--     category first, or keep the taxonomy and roll back nothing.
-- ============================================================================

BEGIN;

-- 0. Guards
DO $$
DECLARE
    v_codes text[] := ARRAY['OPEX-HOUSING', 'OPEX-EDUCATION', 'OPEX-DOMESTIC-HELP', 'OPEX-FAMILY-SUPPORT',
                            'OPEX-CHARITY', 'OPEX-TRANSPORT', 'OPEX-INSURANCE', 'OPEX-REMITTANCE'];
    v_tx int;
    v_budgets int;
    v_settings int;
    v_plans int;
    v_custom int;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'installment_plans'
                     AND column_name = 'frequency') THEN
        RAISE EXCEPTION 'rollback: 20261021000000 does not look applied (installment_plans.frequency missing); nothing to undo';
    END IF;

    SELECT count(*) INTO v_tx FROM public.transactions WHERE category_code = ANY (v_codes);
    SELECT count(*) INTO v_budgets FROM public.budgets WHERE category_code = ANY (v_codes);
    SELECT count(*) INTO v_settings FROM public.household_category_settings WHERE category_code = ANY (v_codes);
    SELECT count(*) INTO v_plans FROM public.installment_plans WHERE category_code = ANY (v_codes);
    SELECT count(*) INTO v_custom FROM public.cost_control_codes
    WHERE household_id IS NOT NULL AND code = ANY (v_codes);
    IF v_tx + v_budgets + v_settings + v_plans + v_custom > 0 THEN
        RAISE EXCEPTION 'rollback: the new categories are in use (transactions %, budgets %, household settings %, installment plans %, household codes %); re-categorise those rows first',
            v_tx, v_budgets, v_settings, v_plans, v_custom;
    END IF;

    RAISE NOTICE 'rollback: % bi-weekly installment plan(s) lose their frequency',
        (SELECT count(*) FROM public.installment_plans WHERE frequency = 'biweekly');
END $$;

-- 1. pay_installment_plan: the 20261020900000 definition (grants and comment are kept by CREATE OR REPLACE)
CREATE OR REPLACE FUNCTION public.pay_installment_plan(
    p_plan_id uuid,
    p_household_id uuid,
    p_actor_user_id uuid
)
RETURNS SETOF public.installment_plans
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_row public.installment_plans;
BEGIN
    IF p_plan_id IS NULL OR p_household_id IS NULL OR p_actor_user_id IS NULL THEN
        RAISE EXCEPTION 'plan, household and actor are required' USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.household_memberships m
        WHERE m.household_id = p_household_id
          AND m.user_id = p_actor_user_id
    ) THEN
        RAISE EXCEPTION 'Only a member of the household can record an installment payment'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.installment_plans AS p
       SET paid_installments = p.paid_installments + 1,
           status = CASE WHEN p.paid_installments + 1 >= p.installment_count THEN 'COMPLETED' ELSE p.status END
     WHERE p.id = p_plan_id
       AND p.household_id = p_household_id
       AND p.status = 'ACTIVE'
       AND p.paid_installments < p.installment_count
    RETURNING p.* INTO v_row;

    IF FOUND THEN
        RETURN NEXT v_row;
        RETURN;
    END IF;

    SELECT p.* INTO v_row
    FROM public.installment_plans AS p
    WHERE p.id = p_plan_id
      AND p.household_id = p_household_id;

    IF NOT FOUND THEN
        RETURN;  -- not in this household: no row
    END IF;

    IF v_row.status NOT IN ('ACTIVE', 'COMPLETED') THEN
        RAISE EXCEPTION 'This installment plan is % and takes no payments', v_row.status
            USING ERRCODE = '22023', HINT = 'plan_not_active';
    END IF;

    RETURN NEXT v_row;  -- already paid up: unchanged
END;
$$;

REVOKE ALL ON FUNCTION public.pay_installment_plan(uuid, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pay_installment_plan(uuid, uuid, uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pay_installment_plan(uuid, uuid, uuid) TO service_role;

-- 2. Schedule trigger, functions, index, constraint, columns
DROP TRIGGER IF EXISTS trg_installment_plans_schedule ON public.installment_plans;
DROP FUNCTION IF EXISTS public.installment_plans_schedule();
DROP FUNCTION IF EXISTS public.installment_next_due_at(date, text, integer, integer, text);
DROP INDEX IF EXISTS public.idx_installment_plans_next_due;
ALTER TABLE public.installment_plans DROP CONSTRAINT IF EXISTS installment_plans_frequency_check;
ALTER TABLE public.installment_plans DROP COLUMN IF EXISTS next_due_at;
ALTER TABLE public.installment_plans DROP COLUMN IF EXISTS frequency;

-- 3. Taxonomy rows added by the migration (exact rows only)
DELETE FROM public.cost_control_sub_categories s
WHERE (s.parent_code, s.sub_code) IN (VALUES
    ('OPEX-HOUSING', 'housing_rent'), ('OPEX-HOUSING', 'annual_rent'), ('OPEX-HOUSING', 'housing_services'),
    ('OPEX-EDUCATION', 'tuition_fees'), ('OPEX-EDUCATION', 'school_transport'),
    ('OPEX-EDUCATION', 'school_uniforms'), ('OPEX-EDUCATION', 'books_supplies'),
    ('OPEX-DOMESTIC-HELP', 'maid_salary'), ('OPEX-DOMESTIC-HELP', 'driver_salary'),
    ('OPEX-DOMESTIC-HELP', 'recruitment_visa'),
    ('OPEX-FAMILY-SUPPORT', 'parents_support'), ('OPEX-FAMILY-SUPPORT', 'relatives_support'),
    ('OPEX-CHARITY', 'sadaqah'), ('OPEX-CHARITY', 'zakat'),
    ('OPEX-TRANSPORT', 'car_installment'), ('OPEX-TRANSPORT', 'ride_hailing'),
    ('OPEX-TRANSPORT', 'public_transport'), ('OPEX-TRANSPORT', 'car_maintenance'),
    ('OPEX-INSURANCE', 'car_insurance'), ('OPEX-INSURANCE', 'health_insurance'),
    ('OPEX-INSURANCE', 'home_insurance'),
    ('OPEX-REMITTANCE', 'family_remittance'), ('OPEX-REMITTANCE', 'transfer_fees'));

DELETE FROM public.cost_control_codes c
WHERE c.household_id IS NULL
  AND c.code IN ('OPEX-HOUSING', 'OPEX-EDUCATION', 'OPEX-DOMESTIC-HELP', 'OPEX-FAMILY-SUPPORT',
                 'OPEX-CHARITY', 'OPEX-TRANSPORT', 'OPEX-INSURANCE', 'OPEX-REMITTANCE');

-- 4. Post-check
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'installment_plans'
                 AND column_name IN ('frequency', 'next_due_at'))
       OR to_regprocedure('public.installment_next_due_at(date, text, integer, integer, text)') IS NOT NULL
       OR to_regprocedure('public.installment_plans_schedule()') IS NOT NULL
       OR EXISTS (SELECT 1 FROM public.cost_control_codes WHERE household_id IS NULL
                  AND code IN ('OPEX-HOUSING', 'OPEX-EDUCATION', 'OPEX-DOMESTIC-HELP', 'OPEX-FAMILY-SUPPORT',
                               'OPEX-CHARITY', 'OPEX-TRANSPORT', 'OPEX-INSURANCE', 'OPEX-REMITTANCE'))
       OR has_function_privilege('authenticated', 'public.pay_installment_plan(uuid, uuid, uuid)', 'EXECUTE')
       OR NOT has_function_privilege('service_role', 'public.pay_installment_plan(uuid, uuid, uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'rollback post-check failed';
    END IF;
    RAISE NOTICE 'rollback: 20261021000000 undone';
END $$;

COMMIT;
