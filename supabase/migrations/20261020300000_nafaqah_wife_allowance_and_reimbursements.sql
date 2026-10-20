-- ============================================================================
-- Migration: 20261020300000_nafaqah_wife_allowance_and_reimbursements.sql
--
-- Owner decision on audit item UI-24 (family mode = married couple, Islamic
-- marriage rules; see .agents/rules/02-saudi-fintech-and-islamic-compliance.md):
--   1. Nafaqah is on the husband: shared family/household expenses are his
--      responsibility. There is no 50/50 (or any percentage) spousal split.
--   2. The wife paying from her own money for something shared (household,
--      children, dependents) is a debt the husband owes her. She collects it
--      back through recorded reimbursements (partial or full).
--   3. A personal purchase for the wife is not a debt: it is charged to her
--      personal allowance ("مصروفها") for the salary cycle (cycle_key).
--   4. Husband-paid shared expenses are ordinary household expenses.
--
-- Schema:
--   * transactions.nafaqah_class ('wife_reimbursable' | 'wife_personal') and
--     transactions.nafaqah_spouse_id (the wife concerned). NULL = ordinary
--     expense (rule 4). Validated by trigger: the spouse must be a member of the
--     transaction's household with financial_role = 'spouse' (so roommate
--     households can never carry a Nafaqah class).
--   * member_allowances: per-wife allowance per (household, cycle_key). Written
--     only by set_member_allowance (husband or a household admin other than the
--     wife). "Spent" is derived from wife_personal transactions of the cycle.
--   * spouse_reimbursements: append-only repayments from the husband to the
--     wife. Written only by record_spouse_reimbursement, which locks the
--     (household, wife) pair and rejects overpayment.
--
-- RPCs follow the claim_household_role_invite pattern: authenticated callers
-- act as auth.uid(); the ai_service (service_role, no JWT subject) must pass
-- the verified caller as p_actor_user_id. Money is numeric(14,2).
-- Proof test: supabase/tests/19_nafaqah_allowance_and_reimbursements.sql
-- ============================================================================

BEGIN;

-- 1. Transaction classification ---------------------------------------------
ALTER TABLE public.transactions
    ADD COLUMN IF NOT EXISTS nafaqah_class text,
    ADD COLUMN IF NOT EXISTS nafaqah_spouse_id uuid REFERENCES public.users(id) ON DELETE SET NULL;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'transactions_nafaqah_class_check') THEN
        ALTER TABLE public.transactions
            ADD CONSTRAINT transactions_nafaqah_class_check
            CHECK (nafaqah_class IS NULL OR nafaqah_class IN ('wife_reimbursable', 'wife_personal'));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_transactions_nafaqah_spouse
    ON public.transactions (nafaqah_spouse_id, household_id, nafaqah_class, cycle_key)
    WHERE nafaqah_spouse_id IS NOT NULL;

COMMENT ON COLUMN public.transactions.nafaqah_class IS
    'Family (Nafaqah) classification: wife_reimbursable = wife paid for something shared, husband owes her; '
    'wife_personal = personal purchase for the wife, charged to her allowance. NULL = ordinary household expense.';
COMMENT ON COLUMN public.transactions.nafaqah_spouse_id IS
    'The wife (users.financial_role = spouse, member of the household) the Nafaqah class refers to.';

-- Is p_user_id a spouse member of p_household_id?
CREATE OR REPLACE FUNCTION public.nafaqah_is_spouse_member(p_household_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.household_memberships m
        JOIN public.users u ON u.id = m.user_id
        WHERE m.household_id = p_household_id
          AND m.user_id = p_user_id
          AND u.financial_role = 'spouse'
    );
$$;

-- The husband (Nafaqah provider) of a family household: a provider member,
-- preferring a household admin, then the longest-standing membership.
-- NULL when the household has no spouse member (not a family household).
CREATE OR REPLACE FUNCTION public.nafaqah_husband_id(p_household_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT m.user_id
    FROM public.household_memberships m
    JOIN public.users u ON u.id = m.user_id
    WHERE m.household_id = p_household_id
      AND COALESCE(u.financial_role, 'provider') = 'provider'
      AND EXISTS (
          SELECT 1
          FROM public.household_memberships sm
          JOIN public.users su ON su.id = sm.user_id
          WHERE sm.household_id = p_household_id AND su.financial_role = 'spouse'
      )
    ORDER BY (m.role = 'admin') DESC, m.created_at, m.user_id
    LIMIT 1;
$$;

REVOKE EXECUTE ON FUNCTION public.nafaqah_is_spouse_member(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.nafaqah_husband_id(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.nafaqah_is_spouse_member(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.nafaqah_husband_id(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.validate_transaction_nafaqah_class()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- ON DELETE SET NULL of the spouse's account: keep the expense, drop the class.
    IF TG_OP = 'UPDATE' AND NEW.nafaqah_spouse_id IS NULL AND OLD.nafaqah_spouse_id IS NOT NULL
       AND NEW.nafaqah_class IS NOT DISTINCT FROM OLD.nafaqah_class THEN
        NEW.nafaqah_class := NULL;
        RETURN NEW;
    END IF;

    IF NEW.nafaqah_class IS NULL AND NEW.nafaqah_spouse_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.nafaqah_class IS NULL OR NEW.nafaqah_spouse_id IS NULL THEN
        RAISE EXCEPTION 'nafaqah_class and nafaqah_spouse_id must be set together'
            USING ERRCODE = '23514';
    END IF;

    IF NOT public.nafaqah_is_spouse_member(NEW.household_id, NEW.nafaqah_spouse_id) THEN
        RAISE EXCEPTION 'nafaqah_spouse_id % is not a spouse member of household %', NEW.nafaqah_spouse_id, NEW.household_id
            USING ERRCODE = '23503';
    END IF;

    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.validate_transaction_nafaqah_class() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_validate_transaction_nafaqah_class ON public.transactions;
CREATE TRIGGER trg_validate_transaction_nafaqah_class
BEFORE INSERT OR UPDATE OF nafaqah_class, nafaqah_spouse_id, household_id ON public.transactions
FOR EACH ROW EXECUTE FUNCTION public.validate_transaction_nafaqah_class();

-- 2. Personal allowance per wife per salary cycle -----------------------------
CREATE TABLE IF NOT EXISTS public.member_allowances (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    member_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    cycle_key varchar(7) NOT NULL CHECK (cycle_key ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
    amount numeric(14, 2) NOT NULL CHECK (amount >= 0),
    set_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_member_allowance_cycle UNIQUE (household_id, member_user_id, cycle_key)
);

CREATE INDEX IF NOT EXISTS idx_member_allowances_member ON public.member_allowances (member_user_id);
CREATE INDEX IF NOT EXISTS idx_member_allowances_set_by ON public.member_allowances (set_by);

ALTER TABLE public.member_allowances ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.member_allowances FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.member_allowances TO authenticated;
GRANT ALL ON public.member_allowances TO service_role;

DROP POLICY IF EXISTS member_allowances_select_household ON public.member_allowances;
CREATE POLICY member_allowances_select_household ON public.member_allowances
    FOR SELECT TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id()));

COMMENT ON TABLE public.member_allowances IS
    'Wife personal allowance (مصروفها) per salary cycle, set by the husband/admin. Spent = wife_personal transactions of the cycle.';

-- 3. Husband -> wife reimbursements (append-only) -----------------------------
CREATE TABLE IF NOT EXISTS public.spouse_reimbursements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    wife_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    paid_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
    amount numeric(14, 2) NOT NULL CHECK (amount > 0),
    payment_method text NOT NULL DEFAULT 'cash'
        CHECK (payment_method IN ('stc_pay', 'urpay', 'bank_transfer', 'iban', 'cash', 'other')),
    notes text CHECK (notes IS NULL OR char_length(notes) <= 500),
    recorded_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_spouse_reimbursements_household_wife
    ON public.spouse_reimbursements (household_id, wife_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_spouse_reimbursements_wife ON public.spouse_reimbursements (wife_user_id);
CREATE INDEX IF NOT EXISTS idx_spouse_reimbursements_paid_by ON public.spouse_reimbursements (paid_by_user_id);
CREATE INDEX IF NOT EXISTS idx_spouse_reimbursements_recorded_by ON public.spouse_reimbursements (recorded_by);

ALTER TABLE public.spouse_reimbursements ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.spouse_reimbursements FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.spouse_reimbursements TO authenticated;
GRANT ALL ON public.spouse_reimbursements TO service_role;

DROP POLICY IF EXISTS spouse_reimbursements_select_household ON public.spouse_reimbursements;
CREATE POLICY spouse_reimbursements_select_household ON public.spouse_reimbursements
    FOR SELECT TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id()));

COMMENT ON TABLE public.spouse_reimbursements IS
    'Repayments by the husband of the wife''s Nafaqah advances (wife_reimbursable transactions). Append-only; via record_spouse_reimbursement.';

-- 4. Internal helpers -----------------------------------------------------------
-- Resolve the acting user: the JWT subject, or (service_role only) p_actor_user_id.
CREATE OR REPLACE FUNCTION public.nafaqah_resolve_actor(p_actor_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
BEGIN
    IF v_uid IS NOT NULL AND p_actor_user_id IS NOT NULL AND p_actor_user_id IS DISTINCT FROM v_uid THEN
        RAISE EXCEPTION 'Forbidden: cannot act on behalf of another user' USING ERRCODE = '42501';
    END IF;
    v_uid := COALESCE(v_uid, p_actor_user_id);
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;
    RETURN v_uid;
END;
$$;

CREATE OR REPLACE FUNCTION public.nafaqah_require_member(p_household_id uuid, p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_household_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.household_memberships m
        WHERE m.household_id = p_household_id AND m.user_id = p_user_id
    ) THEN
        RAISE EXCEPTION 'Forbidden: not a member of this household' USING ERRCODE = '42501';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.nafaqah_current_cycle_key(p_household_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT c.cycle_key
    FROM public.get_saudi_cycle_for_timestamp(
        now(),
        COALESCE((SELECT h.payday_day FROM public.households h WHERE h.id = p_household_id), 27)
    ) c;
$$;

REVOKE EXECUTE ON FUNCTION public.nafaqah_resolve_actor(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.nafaqah_require_member(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.nafaqah_current_cycle_key(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.nafaqah_current_cycle_key(uuid) TO authenticated, service_role;

-- 5. Allowance RPCs -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_member_allowance_status(
    p_household_id uuid,
    p_member_user_id uuid,
    p_cycle_key text DEFAULT NULL,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
    v_cycle text;
    v_allocated numeric(14, 2);
    v_spent numeric(14, 2);
    v_count int;
BEGIN
    PERFORM public.nafaqah_require_member(p_household_id, v_actor);
    IF NOT public.nafaqah_is_spouse_member(p_household_id, p_member_user_id) THEN
        RAISE EXCEPTION 'Allowances apply to a spouse member of this household' USING ERRCODE = '22023';
    END IF;

    v_cycle := COALESCE(NULLIF(trim(p_cycle_key), ''), public.nafaqah_current_cycle_key(p_household_id));
    IF v_cycle !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
        RAISE EXCEPTION 'Invalid cycle_key %', v_cycle USING ERRCODE = '22023';
    END IF;

    SELECT a.amount INTO v_allocated
    FROM public.member_allowances a
    WHERE a.household_id = p_household_id AND a.member_user_id = p_member_user_id AND a.cycle_key = v_cycle;

    SELECT COALESCE(sum(t.amount), 0), count(*) INTO v_spent, v_count
    FROM public.transactions t
    WHERE t.household_id = p_household_id
      AND t.nafaqah_spouse_id = p_member_user_id
      AND t.nafaqah_class = 'wife_personal'
      AND t.cycle_key = v_cycle;

    RETURN jsonb_build_object(
        'household_id', p_household_id,
        'member_user_id', p_member_user_id,
        'cycle_key', v_cycle,
        'is_set', v_allocated IS NOT NULL,
        'allocated', COALESCE(v_allocated, 0),
        'spent', v_spent,
        'remaining', COALESCE(v_allocated, 0) - v_spent,
        'transaction_count', v_count
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.set_member_allowance(
    p_household_id uuid,
    p_member_user_id uuid,
    p_amount numeric,
    p_cycle_key text DEFAULT NULL,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
    v_cycle text;
    v_is_admin boolean;
BEGIN
    PERFORM public.nafaqah_require_member(p_household_id, v_actor);
    IF NOT public.nafaqah_is_spouse_member(p_household_id, p_member_user_id) THEN
        RAISE EXCEPTION 'Allowances apply to a spouse member of this household' USING ERRCODE = '22023';
    END IF;
    IF v_actor = p_member_user_id THEN
        RAISE EXCEPTION 'Forbidden: the allowance is set by the husband or a household admin' USING ERRCODE = '42501';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.household_memberships m
        WHERE m.household_id = p_household_id AND m.user_id = v_actor AND m.role = 'admin'
    ) INTO v_is_admin;
    IF NOT v_is_admin AND v_actor IS DISTINCT FROM public.nafaqah_husband_id(p_household_id) THEN
        RAISE EXCEPTION 'Forbidden: the allowance is set by the husband or a household admin' USING ERRCODE = '42501';
    END IF;

    IF p_amount IS NULL OR p_amount < 0 OR p_amount <> round(p_amount, 2) OR p_amount > 999999999999.99 THEN
        RAISE EXCEPTION 'Allowance must be a non-negative SAR amount with at most 2 decimals' USING ERRCODE = '22023';
    END IF;

    v_cycle := COALESCE(NULLIF(trim(p_cycle_key), ''), public.nafaqah_current_cycle_key(p_household_id));
    IF v_cycle !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
        RAISE EXCEPTION 'Invalid cycle_key %', v_cycle USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.member_allowances (household_id, member_user_id, cycle_key, amount, set_by)
    VALUES (p_household_id, p_member_user_id, v_cycle, p_amount, v_actor)
    ON CONFLICT (household_id, member_user_id, cycle_key)
    DO UPDATE SET amount = EXCLUDED.amount, set_by = EXCLUDED.set_by, updated_at = now();

    RETURN public.get_member_allowance_status(p_household_id, p_member_user_id, v_cycle, v_actor);
END;
$$;

-- 6. Reimbursement RPCs ----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_spouse_reimbursement_balance(
    p_household_id uuid,
    p_wife_user_id uuid,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
    v_gross numeric(14, 2);
    v_paid numeric(14, 2);
BEGIN
    PERFORM public.nafaqah_require_member(p_household_id, v_actor);
    IF NOT public.nafaqah_is_spouse_member(p_household_id, p_wife_user_id) THEN
        RAISE EXCEPTION 'Reimbursements apply to a spouse member of this household' USING ERRCODE = '22023';
    END IF;

    SELECT COALESCE(sum(t.amount), 0) INTO v_gross
    FROM public.transactions t
    WHERE t.household_id = p_household_id
      AND t.nafaqah_spouse_id = p_wife_user_id
      AND t.nafaqah_class = 'wife_reimbursable';

    SELECT COALESCE(sum(r.amount), 0) INTO v_paid
    FROM public.spouse_reimbursements r
    WHERE r.household_id = p_household_id AND r.wife_user_id = p_wife_user_id;

    RETURN jsonb_build_object(
        'household_id', p_household_id,
        'wife_user_id', p_wife_user_id,
        'husband_user_id', public.nafaqah_husband_id(p_household_id),
        'gross_advanced', v_gross,
        'reimbursed', v_paid,
        'outstanding', GREATEST(v_gross - v_paid, 0),
        'overpaid', GREATEST(v_paid - v_gross, 0)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.record_spouse_reimbursement(
    p_household_id uuid,
    p_wife_user_id uuid,
    p_amount numeric,
    p_payment_method text DEFAULT 'cash',
    p_notes text DEFAULT NULL,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
    v_husband uuid;
    v_is_admin boolean;
    v_balance jsonb;
    v_outstanding numeric(14, 2);
    v_id uuid;
    v_method text := lower(COALESCE(NULLIF(trim(p_payment_method), ''), 'cash'));
BEGIN
    PERFORM public.nafaqah_require_member(p_household_id, v_actor);
    IF NOT public.nafaqah_is_spouse_member(p_household_id, p_wife_user_id) THEN
        RAISE EXCEPTION 'Reimbursements apply to a spouse member of this household' USING ERRCODE = '22023';
    END IF;

    v_husband := public.nafaqah_husband_id(p_household_id);
    SELECT EXISTS (
        SELECT 1 FROM public.household_memberships m
        WHERE m.household_id = p_household_id AND m.user_id = v_actor AND m.role = 'admin'
    ) INTO v_is_admin;
    IF v_actor <> p_wife_user_id AND v_actor IS DISTINCT FROM v_husband AND NOT v_is_admin THEN
        RAISE EXCEPTION 'Forbidden: only the husband, the wife or a household admin can record a reimbursement'
            USING ERRCODE = '42501';
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 OR p_amount <> round(p_amount, 2) OR p_amount > 999999999999.99 THEN
        RAISE EXCEPTION 'Reimbursement must be a positive SAR amount with at most 2 decimals' USING ERRCODE = '22023';
    END IF;
    IF v_method NOT IN ('stc_pay', 'urpay', 'bank_transfer', 'iban', 'cash', 'other') THEN
        RAISE EXCEPTION 'Unsupported payment method %', v_method USING ERRCODE = '22023';
    END IF;

    -- Serialise repayments of one wife's debt so two concurrent calls cannot both pass the check.
    PERFORM pg_advisory_xact_lock(hashtextextended('spouse_reimbursement:' || p_household_id::text || ':' || p_wife_user_id::text, 0));

    v_balance := public.get_spouse_reimbursement_balance(p_household_id, p_wife_user_id, v_actor);
    v_outstanding := (v_balance->>'outstanding')::numeric;
    IF p_amount > v_outstanding THEN
        RAISE EXCEPTION 'Reimbursement of % exceeds the outstanding balance of %', p_amount, v_outstanding
            USING ERRCODE = '22023', HINT = 'overpayment';
    END IF;

    INSERT INTO public.spouse_reimbursements (household_id, wife_user_id, paid_by_user_id, amount, payment_method, notes, recorded_by)
    VALUES (p_household_id, p_wife_user_id, v_husband, p_amount, v_method, NULLIF(left(trim(p_notes), 500), ''), v_actor)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object(
        'success', true,
        'reimbursement_id', v_id,
        'household_id', p_household_id,
        'wife_user_id', p_wife_user_id,
        'paid_by_user_id', v_husband,
        'amount', p_amount,
        'payment_method', v_method,
        'outstanding_before', v_outstanding,
        'outstanding_after', v_outstanding - p_amount
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_member_allowance_status(uuid, uuid, text, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.set_member_allowance(uuid, uuid, numeric, text, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_spouse_reimbursement_balance(uuid, uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.record_spouse_reimbursement(uuid, uuid, numeric, text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_member_allowance_status(uuid, uuid, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_member_allowance(uuid, uuid, numeric, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_spouse_reimbursement_balance(uuid, uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_spouse_reimbursement(uuid, uuid, numeric, text, text, uuid) TO authenticated, service_role;

COMMIT;
