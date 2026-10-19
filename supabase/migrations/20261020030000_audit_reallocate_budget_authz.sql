-- ----------------------------------------------------------------------------
-- Migration: 20261020030000_audit_reallocate_budget_authz.sql
-- Audit DB-03 (Critical): public.reallocate_budget (schema.sql) is SECURITY
--   DEFINER, performs no caller/household checks, accepts any amount (negative,
--   sub-halala) and kept the default EXECUTE grant to PUBLIC. Anyone holding the
--   public anon key could rewrite any household's budget allocations by UUID.
-- Fix: EXECUTE only for authenticated + service_role; JWT callers must be an
--   admin of the household owning BOTH budget rows; amounts must be positive,
--   at most 2 decimals and covered by the source allocation; rows are locked in
--   deterministic id order. Service-role callers (ai_service auto-reallocation)
--   keep working without a user JWT.
-- Proof test: supabase/tests/10_audit_reallocate_budget_authz.sql
-- ----------------------------------------------------------------------------

BEGIN;

CREATE OR REPLACE FUNCTION public.reallocate_budget(
    p_from_id uuid,
    p_to_id uuid,
    p_amount numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_jwt_role text := auth.role();
    v_from public.budgets%ROWTYPE;
    v_to public.budgets%ROWTYPE;
BEGIN
    IF v_uid IS NULL AND v_jwt_role IS DISTINCT FROM 'service_role' AND v_jwt_role IS NOT NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    IF p_from_id IS NULL OR p_to_id IS NULL OR p_from_id = p_to_id THEN
        RAISE EXCEPTION 'Two distinct budget ids are required' USING ERRCODE = '22023';
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 OR p_amount <> round(p_amount, 2) THEN
        RAISE EXCEPTION 'Reallocation amount must be positive with at most 2 decimals' USING ERRCODE = '22023';
    END IF;

    IF p_from_id < p_to_id THEN
        SELECT * INTO v_from FROM public.budgets WHERE id = p_from_id FOR UPDATE;
        SELECT * INTO v_to FROM public.budgets WHERE id = p_to_id FOR UPDATE;
    ELSE
        SELECT * INTO v_to FROM public.budgets WHERE id = p_to_id FOR UPDATE;
        SELECT * INTO v_from FROM public.budgets WHERE id = p_from_id FOR UPDATE;
    END IF;

    IF v_from.id IS NULL OR v_to.id IS NULL THEN
        RAISE EXCEPTION 'Budget not found' USING ERRCODE = 'P0002';
    END IF;

    IF v_from.household_id IS DISTINCT FROM v_to.household_id THEN
        RAISE EXCEPTION 'Budgets belong to different households' USING ERRCODE = '42501';
    END IF;

    IF v_uid IS NOT NULL THEN
        IF public.get_auth_user_household_id() IS DISTINCT FROM v_from.household_id
           OR public.get_auth_user_role() IS DISTINCT FROM 'admin' THEN
            RAISE EXCEPTION 'Access denied: household admin required' USING ERRCODE = '42501';
        END IF;
    END IF;

    IF v_from.allocated_amount < p_amount THEN
        RAISE EXCEPTION 'Insufficient allocation: % available, % requested', v_from.allocated_amount, p_amount
            USING ERRCODE = '22000';
    END IF;

    UPDATE public.budgets
    SET allocated_amount = allocated_amount - p_amount
    WHERE id = v_from.id;

    UPDATE public.budgets
    SET allocated_amount = allocated_amount + p_amount
    WHERE id = v_to.id;
END;
$$;

REVOKE ALL ON FUNCTION public.reallocate_budget(uuid, uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reallocate_budget(uuid, uuid, numeric) TO authenticated, service_role;

COMMIT;
