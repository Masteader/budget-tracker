-- ----------------------------------------------------------------------------
-- Migration: 20261020750000_installment_pay_atomic.sql
-- Independent review FABLE-API-10 (Low, suspected; docs/review/audit/fable_review.md):
--   POST /budgets/installments/{id}/pay read the plan, added one in Python and
--   wrote paid_installments back. Two concurrent payments both read the same
--   value, so one payment was lost (and nothing stopped a paid-up plan from
--   being "paid" again through a stale read).
-- Fix: pay_installment_plan() performs one conditional increment
--     UPDATE ... SET paid_installments = paid_installments + 1
--      WHERE id = $plan AND household_id = $household AND paid_installments < installment_count
--   (row lock taken by the UPDATE, so concurrent calls serialise and each one
--   counts exactly once, never beyond installment_count). A plan that is
--   already complete is returned unchanged; a plan outside the household
--   returns no row.
-- Security: SECURITY DEFINER with a pinned search_path; the verified caller
--   (p_actor_user_id, from the API's JWT check) must be a member of the
--   household (household_memberships). EXECUTE for service_role only (the
--   ai_service); anon/authenticated cannot call it.
-- Live safety: adds one function, changes no table, no data. Idempotent
--   (CREATE OR REPLACE, REVOKE/GRANT). Deploy before the ai_service build that
--   calls it (README deployment order: migrations -> ai_service -> app).
-- Proof test: supabase/tests/24_installment_pay_atomic.sql
-- ----------------------------------------------------------------------------

BEGIN;

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
       AND p.paid_installments < p.installment_count
    RETURNING p.* INTO v_row;

    IF FOUND THEN
        RETURN NEXT v_row;
        RETURN;
    END IF;

    -- Already paid up (or not in this household): the current row, unchanged, if any.
    RETURN QUERY
        SELECT p.*
        FROM public.installment_plans AS p
        WHERE p.id = p_plan_id
          AND p.household_id = p_household_id;
END;
$$;

REVOKE ALL ON FUNCTION public.pay_installment_plan(uuid, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pay_installment_plan(uuid, uuid, uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pay_installment_plan(uuid, uuid, uuid) TO service_role;

COMMENT ON FUNCTION public.pay_installment_plan(uuid, uuid, uuid) IS
    'Records one installment payment atomically (conditional increment, never beyond installment_count). service_role only; p_actor_user_id must be a household member.';

COMMIT;
