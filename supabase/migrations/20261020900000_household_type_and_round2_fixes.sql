-- ============================================================================
-- Migration: 20261020900000_household_type_and_round2_fixes.sql
--
-- Owner decisions of 2026-10-21 (round 3) and the Fable round-2 database report.
--
--   D1  Household type, chosen at creation and stored:
--       households.household_type text NOT NULL DEFAULT 'family'
--       CHECK (household_type IN ('family', 'roommates')).
--       * Backfill: 'roommates' when any membership has financial_role 'peer',
--         else 'family'.
--       * Membership financial roles follow the type: family -> provider, spouse,
--         family_member, dependent; roommates -> peer. Static-code joiners are
--         'peer' (roommates) / 'family_member' (family). A membership inserted
--         with a role that does not fit (e.g. a stale users.financial_role
--         copied by the sync trigger) gets the type's default; an UPDATE to a
--         role that does not fit is refused (23514 financial_role_not_allowed).
--       * Role invites keep their role, but a claim of a spouse / provider /
--         family_member / dependent invite in a roommates household, or of a
--         peer invite in a family household, is refused
--         ({success:false, code:'invite_role_mismatch'}; the invite stays open).
--       * Family features (Nafaqah provider, classified expenses) only when
--         household_type = 'family' (Nafaqah also needs a spouse member).
--       * create_household_and_claim(p_name, p_household_type DEFAULT 'family')
--         (one function: released apps call it with {p_name} only).
--       * set_household_type(): admins; family -> roommates refused while a
--         spouse member or any Nafaqah data exists (22023 type_change_blocked);
--         roommates -> family turns peers into family members (the primary admin
--         becomes 'provider' and the default Nafaqah provider).
--   D2  nafaqah_class / nafaqah_spouse_id are set or changed only by the wife
--       herself, the household's Nafaqah provider or a household admin when the
--       write comes from a client (auth.uid() set); service_role passes (the
--       API enforces the same rule). 42501 HINT nafaqah_class_not_allowed.
--   D3  When the wife's membership in a household ends (leave_household,
--       remove_member, account deletion), her ledger in THAT household is
--       removed: her wife_reimbursable / wife_personal rows there become
--       ordinary expenses (wife_personal amounts enter the category budget),
--       her spouse_reimbursements and member_allowances rows there are deleted.
--       The ledger guard lets exactly this path through (the wife's membership
--       in the row's household no longer exists, or the household itself is
--       being deleted) instead of every pg_trigger_depth() > 1 statement.
--
--   FABLE2-DB-01  The Nafaqah provider is defaulted only when a household is
--                 created (INSERT of the households row naming an owner, or the
--                 first member joining as admin, i.e. create_household_and_claim)
--                 or by an explicit RPC default (transfer_primary_admin when
--                 unset, set_household_type roommates -> family). Owner
--                 succession (account deletion, primary admin leaving) never
--                 re-defaults it: when the provider's membership ends by any
--                 path it stays NULL until an admin chooses one.
--   FABLE2-DB-02  installment_plans: CHECK paid_installments BETWEEN 0 AND
--                 installment_count (added NOT VALID, validated when no row
--                 violates it); clients lose UPDATE of paid_installments /
--                 status (column-level grants; the app never writes this
--                 table, the API uses the service role); pay_installment_plan
--                 counts only ACTIVE plans (a COMPLETED plan is returned
--                 unchanged as before, any other status is refused with 22023
--                 HINT plan_not_active).
--   FABLE2-DB-05  Budget triggers ignore settlement rows (is_settlement), like
--                 recompute_budget_spent.
--   FABLE2-DB-07  set_member_financial_role(): admins set a member's financial
--                 role within the household type (family: spouse,
--                 family_member, dependent; roommates: peer); the Nafaqah
--                 provider is never made a spouse; a wife with ledger data is
--                 not re-roled (22023 spouse_has_ledger).
--
-- Live safety (docs/review/audit/live_db_preflight_round2.md): one transaction,
-- idempotent (re-running changes nothing). On live (4 households, all
-- single-membership, provider x3 / family_member x1, no spouse, no peer, no
-- classified row, no allowance, no repayment) every household becomes
-- 'family', no membership role changes, no provider changes, no transaction or
-- budget changes. Applies after 20261020700000 / 750000 / 800000 (not yet on
-- live: apply 700000, 750000, 800000, 900000 in order).
-- Compatibility with the deployed backend and app (origin/main):
--   * create_household_and_claim keeps working with {p_name} (default 'family',
--     same JSON row returned, plus the new column);
--   * join_household_by_code / claim_household_role_invite keep their return
--     shapes; static-code joiners of a family household were already
--     'family_member' (800000), roommate households now give 'peer';
--   * the deployed backend's service-role writes are unaffected by D2.
--
-- Proof test: supabase/tests/26_household_type_and_round2.sql
-- Rollback: docs/review/rollback/20261020_round3_rollback_snapshot.sql
-- ============================================================================

BEGIN;

-- 0. Guard ---------------------------------------------------------------------------
DO $$
DECLARE
    v_n int;
BEGIN
    SELECT count(*) INTO v_n
    FROM (VALUES ('household_memberships', 'financial_role'), ('households', 'nafaqah_provider_user_id'),
                 ('households', 'owner_user_id'), ('transactions', 'is_settlement'),
                 ('transactions', 'nafaqah_class'), ('transactions', 'nafaqah_spouse_id'),
                 ('installment_plans', 'paid_installments'), ('installment_plans', 'status'),
                 ('installment_plans', 'installment_count')) AS req(t, c)
    WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = req.t AND column_name = req.c);
    IF v_n > 0 THEN
        RAISE EXCEPTION 'guard: % required column(s) missing (apply 20261020800000 first)', v_n;
    END IF;

    IF to_regprocedure('public.household_resolve_actor(uuid)') IS NULL
       OR to_regprocedure('public.household_require_admin(uuid, uuid)') IS NULL
       OR to_regprocedure('public.household_member_role(uuid, uuid)') IS NULL
       OR to_regprocedure('public.household_member_financial_role(uuid, uuid)') IS NULL
       OR to_regprocedure('public.household_apply_role(uuid, uuid, text)') IS NULL
       OR to_regprocedure('public.guard_wife_reimbursable_ledger()') IS NULL
       OR to_regprocedure('public.maintain_household_primary_admin()') IS NULL
       OR to_regprocedure('public.pay_installment_plan(uuid, uuid, uuid)') IS NULL
       OR to_regprocedure('public.create_household_and_claim(text)') IS NULL
          AND to_regprocedure('public.create_household_and_claim(text, text)') IS NULL THEN
        RAISE EXCEPTION 'guard: required functions missing (apply 20261020750000 and 20261020800000 first)';
    END IF;

    -- A household with a peer AND a spouse member or Nafaqah data would be ambiguous.
    SELECT count(*) INTO v_n
    FROM public.households h
    WHERE EXISTS (SELECT 1 FROM public.household_memberships m WHERE m.household_id = h.id AND m.financial_role = 'peer')
      AND (EXISTS (SELECT 1 FROM public.household_memberships m WHERE m.household_id = h.id AND m.financial_role = 'spouse')
           OR EXISTS (SELECT 1 FROM public.transactions t WHERE t.household_id = h.id AND t.nafaqah_class IS NOT NULL));
    IF v_n > 0 THEN
        RAISE EXCEPTION 'guard: % household(s) have peer members AND a spouse member or classified expenses; resolve them before choosing a type', v_n;
    END IF;

    SELECT count(*) INTO v_n FROM public.installment_plans
    WHERE paid_installments < 0 OR paid_installments > installment_count;
    RAISE NOTICE 'guard: % installment plan(s) outside 0..installment_count (CHECK stays NOT VALID if > 0)', v_n;

    SELECT count(*) INTO v_n FROM public.transactions t
    WHERE t.nafaqah_spouse_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.household_memberships m
                      WHERE m.household_id = t.household_id AND m.user_id = t.nafaqah_spouse_id);
    RAISE NOTICE 'guard: % classified row(s) of a wife who is no longer a member (declassified by D3)', v_n;
END;
$$;

-- 1. households.household_type (D1) ------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'households' AND column_name = 'household_type') THEN
        ALTER TABLE public.households ADD COLUMN household_type text NOT NULL DEFAULT 'family';
        ALTER TABLE public.households ADD CONSTRAINT households_household_type_check
            CHECK (household_type IN ('family', 'roommates'));

        -- Backfill (once, so a re-run never undoes an admin's choice).
        UPDATE public.households h
        SET household_type = 'roommates',
            nafaqah_provider_user_id = NULL
        WHERE EXISTS (SELECT 1 FROM public.household_memberships m
                      WHERE m.household_id = h.id AND m.financial_role = 'peer');

        -- Roommate households hold peers only (the guard ruled out spouses there).
        UPDATE public.household_memberships m
        SET financial_role = 'peer'
        FROM public.households h
        WHERE h.id = m.household_id
          AND h.household_type = 'roommates'
          AND m.financial_role <> 'peer';
    END IF;
END $$;

COMMENT ON COLUMN public.households.household_type IS
    'family | roommates, chosen at creation (create_household_and_claim) and changed by an admin (set_household_type). '
    'Decides membership financial roles, settlement mode and whether family (Nafaqah) features apply.';

-- Not client-writable (households UPDATE is a column list since 20261020700000; keep it explicit).
REVOKE UPDATE (household_type) ON public.households FROM PUBLIC, anon, authenticated;

-- 2. Financial roles follow the household type (D1) --------------------------------------
CREATE OR REPLACE FUNCTION public.household_financial_role_allowed(p_household_type text, p_financial_role text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
    SELECT CASE p_household_type
        WHEN 'roommates' THEN p_financial_role = 'peer'
        WHEN 'family' THEN p_financial_role IN ('provider', 'spouse', 'family_member', 'dependent')
        ELSE false
    END;
$$;

-- Role of a user joining without a role-tagged invite (static code, sync trigger).
CREATE OR REPLACE FUNCTION public.household_default_financial_role(p_household_id uuid, p_user_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT CASE WHEN h.household_type = 'roommates' THEN 'peer' ELSE 'family_member' END
    FROM public.households h
    WHERE h.id = p_household_id;
$$;

REVOKE EXECUTE ON FUNCTION public.household_financial_role_allowed(text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.household_default_financial_role(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.membership_financial_role_rules()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_type text;
BEGIN
    SELECT household_type INTO v_type FROM public.households WHERE id = NEW.household_id;

    IF TG_OP = 'INSERT' THEN
        IF NEW.financial_role IS NULL OR NOT public.household_financial_role_allowed(v_type, NEW.financial_role) THEN
            NEW.financial_role := public.household_default_financial_role(NEW.household_id, NEW.user_id);
        END IF;
    ELSIF NOT public.household_financial_role_allowed(v_type, NEW.financial_role) THEN
        RAISE EXCEPTION 'Financial role % does not fit a % household', NEW.financial_role, v_type
            USING ERRCODE = '23514', HINT = 'financial_role_not_allowed';
    END IF;

    IF NEW.financial_role = 'spouse'
       AND (TG_OP = 'INSERT' OR OLD.financial_role IS DISTINCT FROM 'spouse')
       AND EXISTS (SELECT 1 FROM public.households h
                   WHERE h.id = NEW.household_id AND h.nafaqah_provider_user_id = NEW.user_id) THEN
        RAISE EXCEPTION 'The Nafaqah provider of a household cannot be a spouse member'
            USING ERRCODE = '23514', HINT = 'provider_is_spouse';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.membership_financial_role_rules() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_membership_financial_role_rules ON public.household_memberships;
CREATE TRIGGER trg_membership_financial_role_rules
BEFORE INSERT OR UPDATE OF financial_role ON public.household_memberships
FOR EACH ROW EXECUTE FUNCTION public.membership_financial_role_rules();

-- 3. Nafaqah provider: defaulted only at creation (FABLE2-DB-01) ------------------------
CREATE OR REPLACE FUNCTION public.households_nafaqah_provider_rules()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_role text;
BEGIN
    -- Default only when the row is created (an UPDATE, e.g. owner succession after the
    -- provider's account was deleted, never re-defaults it).
    IF TG_OP = 'INSERT'
       AND NEW.nafaqah_provider_user_id IS NULL
       AND NEW.owner_user_id IS NOT NULL
       AND NEW.household_type = 'family' THEN
        v_role := public.household_member_financial_role(NEW.id, NEW.owner_user_id);
        IF v_role IS NOT NULL AND v_role <> 'spouse' THEN
            NEW.nafaqah_provider_user_id := NEW.owner_user_id;
        END IF;
    END IF;

    IF NEW.nafaqah_provider_user_id IS NOT NULL
       AND (TG_OP = 'INSERT'
            OR NEW.nafaqah_provider_user_id IS DISTINCT FROM OLD.nafaqah_provider_user_id
            OR NEW.household_type IS DISTINCT FROM OLD.household_type) THEN
        IF NEW.household_type IS DISTINCT FROM 'family' THEN
            RAISE EXCEPTION 'Only a family household has a Nafaqah provider'
                USING ERRCODE = '23514', HINT = 'not_family_household';
        END IF;
        v_role := public.household_member_financial_role(NEW.id, NEW.nafaqah_provider_user_id);
        IF v_role IS NULL THEN
            RAISE EXCEPTION 'The Nafaqah provider must be a member of the household'
                USING ERRCODE = '23514', HINT = 'provider_not_member';
        END IF;
        IF v_role = 'spouse' THEN
            RAISE EXCEPTION 'A spouse member cannot be the Nafaqah provider'
                USING ERRCODE = '23514', HINT = 'provider_is_spouse';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.households_nafaqah_provider_rules() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_households_nafaqah_provider ON public.households;
CREATE TRIGGER trg_households_nafaqah_provider
BEFORE INSERT OR UPDATE OF owner_user_id, nafaqah_provider_user_id, household_type ON public.households
FOR EACH ROW EXECUTE FUNCTION public.households_nafaqah_provider_rules();

-- The first admin of a household becomes its primary admin; in a family household
-- the creator (first member, joining as admin) is also the default Nafaqah provider.
-- When the primary admin's membership ends, the longest-standing remaining admin
-- takes over as primary admin; the provider is NOT re-defaulted.
CREATE OR REPLACE FUNCTION public.maintain_household_primary_admin()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        UPDATE public.households h
        SET owner_user_id = (
            SELECT m.user_id
            FROM public.household_memberships m
            WHERE m.household_id = OLD.household_id
              AND m.user_id <> OLD.user_id
              AND m.role = 'admin'
            ORDER BY m.created_at ASC, m.user_id ASC
            LIMIT 1
        )
        WHERE h.id = OLD.household_id
          AND (h.owner_user_id IS NULL OR h.owner_user_id = OLD.user_id);
        RETURN OLD;
    END IF;

    IF NEW.role = 'admin' THEN
        UPDATE public.households h
        SET owner_user_id = NEW.user_id,
            nafaqah_provider_user_id = CASE
                WHEN TG_OP = 'INSERT'
                     AND h.nafaqah_provider_user_id IS NULL
                     AND h.household_type = 'family'
                     AND NEW.financial_role IS DISTINCT FROM 'spouse'
                     AND NOT EXISTS (SELECT 1 FROM public.household_memberships o
                                     WHERE o.household_id = NEW.household_id AND o.user_id <> NEW.user_id)
                    THEN NEW.user_id
                ELSE h.nafaqah_provider_user_id
            END
        WHERE h.id = NEW.household_id AND h.owner_user_id IS NULL;
    END IF;
    RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.maintain_household_primary_admin() FROM PUBLIC, anon, authenticated;

-- 4. Nafaqah helpers: family households only; D2 ----------------------------------------
CREATE OR REPLACE FUNCTION public.nafaqah_husband_id(p_household_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT h.nafaqah_provider_user_id
    FROM public.households h
    WHERE h.id = p_household_id
      AND h.household_type = 'family'
      AND EXISTS (SELECT 1 FROM public.household_memberships sm
                  WHERE sm.household_id = h.id AND sm.financial_role = 'spouse')
      AND EXISTS (SELECT 1 FROM public.household_memberships pm
                  WHERE pm.household_id = h.id
                    AND pm.user_id = h.nafaqah_provider_user_id
                    AND pm.financial_role <> 'spouse');
$$;

CREATE OR REPLACE FUNCTION public.validate_transaction_nafaqah_class()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_changed boolean;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_changed := NEW.nafaqah_class IS NOT NULL OR NEW.nafaqah_spouse_id IS NOT NULL;
    ELSE
        v_changed := NEW.nafaqah_class IS DISTINCT FROM OLD.nafaqah_class
                     OR NEW.nafaqah_spouse_id IS DISTINCT FROM OLD.nafaqah_spouse_id;
    END IF;

    -- D2: from a client, only the wife herself, the household's Nafaqah provider or a
    -- household admin sets, changes or clears a classification. Service-role writes
    -- (auth.uid() NULL; the API checks the same rule) and system cascades
    -- (pg_trigger_depth() > 1: account deletion, the D3 ledger removal) pass.
    IF v_changed AND v_uid IS NOT NULL AND pg_trigger_depth() = 1 THEN
        IF NOT COALESCE(
            v_uid = NEW.nafaqah_spouse_id
            OR (TG_OP = 'UPDATE' AND NEW.nafaqah_spouse_id IS NULL AND v_uid = OLD.nafaqah_spouse_id)
            OR v_uid = (SELECT h.nafaqah_provider_user_id FROM public.households h WHERE h.id = NEW.household_id)
            OR public.household_member_role(NEW.household_id, v_uid) = 'admin',
            false
        ) THEN
            RAISE EXCEPTION 'Only the wife, the Nafaqah provider or a household admin can classify a family expense'
                USING ERRCODE = '42501', HINT = 'nafaqah_class_not_allowed';
        END IF;
    END IF;

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

    -- An unchanged classification stays editable (e.g. after the provider left).
    IF TG_OP = 'UPDATE'
       AND NEW.nafaqah_class IS NOT DISTINCT FROM OLD.nafaqah_class
       AND NEW.nafaqah_spouse_id IS NOT DISTINCT FROM OLD.nafaqah_spouse_id
       AND NEW.household_id IS NOT DISTINCT FROM OLD.household_id THEN
        RETURN NEW;
    END IF;

    IF NOT public.nafaqah_is_spouse_member(NEW.household_id, NEW.nafaqah_spouse_id) THEN
        RAISE EXCEPTION 'nafaqah_spouse_id % is not a spouse member of household %', NEW.nafaqah_spouse_id, NEW.household_id
            USING ERRCODE = '23503';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.households h WHERE h.id = NEW.household_id AND h.household_type = 'family') THEN
        RAISE EXCEPTION 'Household % is not a family household: expenses are never Nafaqah-classified there', NEW.household_id
            USING ERRCODE = '23514', HINT = 'not_family_household';
    END IF;

    IF public.nafaqah_husband_id(NEW.household_id) IS NULL THEN
        RAISE EXCEPTION 'Household % has no Nafaqah provider: a household admin must choose one before family expenses are classified', NEW.household_id
            USING ERRCODE = '23514', HINT = 'no_nafaqah_provider';
    END IF;

    RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.validate_transaction_nafaqah_class() FROM PUBLIC, anon, authenticated;

-- 5. D3: the wife's ledger leaves with her membership -----------------------------------
-- Ledger guard (FABLE-LOGIC-02): a change that would leave the advances below the
-- recorded repayments is refused. The only exception is the D3 removal: the wife's
-- membership in the row's household no longer exists (left, removed, account
-- deleted) or the household itself is being deleted; her repayments are removed in
-- the same statement.
CREATE OR REPLACE FUNCTION public.guard_wife_reimbursable_ledger()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_kept numeric(14, 2) := 0;
    v_advanced numeric(14, 2);
    v_repaid numeric(14, 2);
    v_after numeric(14, 2);
BEGIN
    IF OLD.nafaqah_class IS DISTINCT FROM 'wife_reimbursable' OR OLD.nafaqah_spouse_id IS NULL THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.household_memberships m
        JOIN public.households h ON h.id = m.household_id
        JOIN public.users u ON u.id = m.user_id
        WHERE m.household_id = OLD.household_id
          AND m.user_id = OLD.nafaqah_spouse_id
    ) THEN
        RETURN COALESCE(NEW, OLD);  -- D3: her ledger in this household is being removed
    END IF;

    IF TG_OP = 'UPDATE'
       AND NEW.nafaqah_class IS NOT DISTINCT FROM 'wife_reimbursable'
       AND NEW.nafaqah_spouse_id IS NOT DISTINCT FROM OLD.nafaqah_spouse_id
       AND NEW.household_id IS NOT DISTINCT FROM OLD.household_id THEN
        v_kept := COALESCE(NEW.amount, 0);
    END IF;

    IF v_kept >= COALESCE(OLD.amount, 0) THEN
        RETURN COALESCE(NEW, OLD);  -- the advance does not shrink
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(
        'spouse_reimbursement:' || OLD.household_id::text || ':' || OLD.nafaqah_spouse_id::text, 0));

    SELECT COALESCE(sum(t.amount), 0) INTO v_advanced
    FROM public.transactions t
    WHERE t.household_id = OLD.household_id
      AND t.nafaqah_spouse_id = OLD.nafaqah_spouse_id
      AND t.nafaqah_class = 'wife_reimbursable';

    SELECT COALESCE(sum(r.amount), 0) INTO v_repaid
    FROM public.spouse_reimbursements r
    WHERE r.household_id = OLD.household_id AND r.wife_user_id = OLD.nafaqah_spouse_id;

    v_after := v_advanced - COALESCE(OLD.amount, 0) + v_kept;
    IF v_after < v_repaid THEN
        RAISE EXCEPTION 'This change would leave the wife''s reimbursement ledger overpaid: % SAR already repaid, only % SAR of advances would remain', v_repaid, v_after
            USING ERRCODE = '22023',
                  HINT = 'ledger_would_be_overpaid',
                  DETAIL = format('repaid=%s advances_after=%s', v_repaid, v_after);
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.guard_wife_reimbursable_ledger() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.remove_nafaqah_ledger_on_membership_end()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    DELETE FROM public.spouse_reimbursements
    WHERE household_id = OLD.household_id AND wife_user_id = OLD.user_id;

    DELETE FROM public.member_allowances
    WHERE household_id = OLD.household_id AND member_user_id = OLD.user_id;

    -- Her advances and personal purchases become ordinary expenses of the household
    -- (the budget triggers move wife_personal amounts into the category budget).
    UPDATE public.transactions
    SET nafaqah_class = NULL,
        nafaqah_spouse_id = NULL
    WHERE household_id = OLD.household_id
      AND nafaqah_spouse_id = OLD.user_id;
    RETURN OLD;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.remove_nafaqah_ledger_on_membership_end() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_remove_nafaqah_ledger_on_membership_end ON public.household_memberships;
CREATE TRIGGER trg_remove_nafaqah_ledger_on_membership_end
AFTER DELETE ON public.household_memberships
FOR EACH ROW EXECUTE FUNCTION public.remove_nafaqah_ledger_on_membership_end();

-- 6. Budget triggers: wife_personal and settlement rows are not category spending -----
-- (FABLE-LOGIC-06, FABLE2-DB-05; same rule as recompute_budget_spent.)
CREATE OR REPLACE FUNCTION public.update_budget_on_transaction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.nafaqah_class IS NOT DISTINCT FROM 'wife_personal' OR NEW.is_settlement IS TRUE THEN
        RETURN NEW;  -- the wife's allowance only / a transfer between members
    END IF;

    UPDATE public.budgets
    SET spent_amount = spent_amount + NEW.amount
    WHERE household_id  = NEW.household_id
      AND category_code = NEW.category_code
      AND (
          (NEW.cycle_key IS NOT NULL AND cycle_key = NEW.cycle_key)
          OR (NEW.cycle_key IS NULL AND month = date_trunc('month', NEW.timestamp)::DATE)
      );

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_budget_on_transaction_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF OLD.nafaqah_class IS NOT DISTINCT FROM 'wife_personal' OR OLD.is_settlement IS TRUE THEN
        RETURN OLD;
    END IF;

    UPDATE public.budgets
    SET spent_amount = GREATEST(0, spent_amount - OLD.amount)
    WHERE household_id  = OLD.household_id
      AND category_code = OLD.category_code
      AND (
          (OLD.cycle_key IS NOT NULL AND cycle_key = OLD.cycle_key)
          OR (OLD.cycle_key IS NULL AND month = date_trunc('month', OLD.timestamp)::DATE)
      );

    RETURN OLD;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_budget_on_transaction_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_old_counted boolean := OLD.nafaqah_class IS DISTINCT FROM 'wife_personal' AND OLD.is_settlement IS NOT TRUE;
    v_new_counted boolean := NEW.nafaqah_class IS DISTINCT FROM 'wife_personal' AND NEW.is_settlement IS NOT TRUE;
BEGIN
    IF OLD.amount <> NEW.amount
       OR OLD.category_code IS DISTINCT FROM NEW.category_code
       OR OLD.cycle_key IS DISTINCT FROM NEW.cycle_key
       OR date_trunc('month', OLD.timestamp) IS DISTINCT FROM date_trunc('month', NEW.timestamp)
       OR v_old_counted IS DISTINCT FROM v_new_counted THEN

        IF v_old_counted THEN
            UPDATE public.budgets
            SET spent_amount = GREATEST(0, spent_amount - OLD.amount)
            WHERE household_id  = OLD.household_id
              AND category_code = OLD.category_code
              AND (
                  (OLD.cycle_key IS NOT NULL AND cycle_key = OLD.cycle_key)
                  OR (OLD.cycle_key IS NULL AND month = date_trunc('month', OLD.timestamp)::DATE)
              );
        END IF;

        IF v_new_counted THEN
            UPDATE public.budgets
            SET spent_amount = spent_amount + NEW.amount
            WHERE household_id  = NEW.household_id
              AND category_code = NEW.category_code
              AND (
                  (NEW.cycle_key IS NOT NULL AND cycle_key = NEW.cycle_key)
                  OR (NEW.cycle_key IS NULL AND month = date_trunc('month', NEW.timestamp)::DATE)
              );
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_budget_on_transaction() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_budget_on_transaction_delete() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_budget_on_transaction_update() FROM PUBLIC, anon, authenticated;

-- 7. Creation with a type (D1) ---------------------------------------------------------
-- One function with a defaulted parameter: released apps call {p_name} only and an
-- overload would make PostgREST's choice ambiguous (PGRST203).
DROP FUNCTION IF EXISTS public.create_household_and_claim(text);

CREATE OR REPLACE FUNCTION public.create_household_and_claim(
    p_name text,
    p_household_type text DEFAULT 'family'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_type text := COALESCE(lower(trim(p_household_type)), 'family');
    v_hh public.households%ROWTYPE;
    v_count int;
    v_invite_code text;
    v_financial_role text;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF v_type NOT IN ('family', 'roommates') THEN
        RAISE EXCEPTION 'Household type must be ''family'' or ''roommates'''
            USING ERRCODE = '22023', HINT = 'invalid_household_type';
    END IF;

    SELECT count(*) INTO v_count
    FROM public.household_memberships
    WHERE user_id = v_uid AND role = 'admin';

    IF v_count >= 5 THEN
        RAISE EXCEPTION 'Household creation limit reached (maximum 5 households per user)';
    END IF;

    v_invite_code := upper(encode(extensions.gen_random_bytes(8), 'hex'));
    v_financial_role := CASE WHEN v_type = 'roommates' THEN 'peer' ELSE 'provider' END;

    INSERT INTO public.households (name, invite_code, household_type)
    VALUES (trim(p_name), v_invite_code, v_type)
    RETURNING * INTO v_hh;

    -- The creator's membership makes them the primary admin and, in a family
    -- household, the default Nafaqah provider (maintain_household_primary_admin).
    INSERT INTO public.household_memberships (household_id, user_id, role, is_default, financial_role)
    VALUES (v_hh.id, v_uid, 'admin', true, v_financial_role)
    ON CONFLICT (household_id, user_id) DO UPDATE SET role = 'admin';

    UPDATE public.users
    SET household_id = v_hh.id,
        role = 'admin',
        financial_role = v_financial_role
    WHERE id = v_uid;

    SELECT * INTO v_hh FROM public.households WHERE id = v_hh.id;
    RETURN to_jsonb(v_hh);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_household_and_claim(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_household_and_claim(text, text) TO authenticated, service_role;

-- 8. Invite claims respect the household type (D1) --------------------------------------
CREATE OR REPLACE FUNCTION public.join_household_by_code(p_invite_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_clean_code text := upper(trim(p_invite_code));
    v_fail_count int;
    v_invite public.household_invites%ROWTYPE;
    v_hh public.households%ROWTYPE;
    v_claimed_id uuid;
    v_role text;
    v_financial_role text;
    v_is_default boolean;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT count(*) INTO v_fail_count
    FROM public.invite_attempt_log
    WHERE user_id = v_uid
      AND success = false
      AND attempted_at > (now() - interval '15 minutes');

    IF v_fail_count >= 5 THEN
        RAISE EXCEPTION 'Too many failed join attempts. Please try again in 15 minutes.';
    END IF;

    SELECT * INTO v_invite
    FROM public.household_invites
    WHERE upper(trim(invite_code)) = v_clean_code
    FOR UPDATE;

    IF v_invite.id IS NOT NULL THEN
        IF v_invite.expires_at < now() THEN
            INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, false);
            RETURN jsonb_build_object('success', false, 'error', 'Invite code has expired');
        END IF;

        SELECT role, financial_role INTO v_role, v_financial_role
        FROM public.household_memberships
        WHERE household_id = v_invite.household_id AND user_id = v_uid;

        IF v_role IS NOT NULL THEN
            IF v_invite.used_by IS DISTINCT FROM v_uid THEN
                RETURN jsonb_build_object('success', false, 'error', 'You are already a member of this household',
                                          'code', 'already_member');
            END IF;
            SELECT * INTO v_hh FROM public.households WHERE id = v_invite.household_id;
            UPDATE public.users
            SET household_id = v_hh.id, role = v_role, financial_role = v_financial_role
            WHERE id = v_uid;
            INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, true);
            RETURN to_jsonb(v_hh);
        END IF;

        SELECT * INTO v_hh FROM public.households WHERE id = v_invite.household_id;

        -- D1: the invite's role must fit the household type (it may have changed since).
        IF v_invite.role IN ('provider', 'spouse', 'peer', 'family_member', 'dependent')
           AND NOT public.household_financial_role_allowed(v_hh.household_type, v_invite.role) THEN
            RETURN jsonb_build_object('success', false,
                'error', 'This invite does not fit this household type; ask the admin for a new invite',
                'code', 'invite_role_mismatch');
        END IF;

        IF v_invite.used_by = v_uid THEN
            v_claimed_id := v_invite.id;
        ELSIF v_invite.used_by IS NULL THEN
            UPDATE public.household_invites
            SET used_by = v_uid
            WHERE id = v_invite.id AND used_by IS NULL
            RETURNING id INTO v_claimed_id;

            IF v_claimed_id IS NULL THEN
                INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, false);
                RETURN jsonb_build_object('success', false, 'error', 'Invite code has already been used');
            END IF;
        ELSE
            INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, false);
            RETURN jsonb_build_object('success', false, 'error', 'Invite code has already been used');
        END IF;

        IF v_invite.target_member_id IS NOT NULL THEN
            UPDATE public.household_dependents
            SET linked_user_id = v_uid
            WHERE id = v_invite.target_member_id
              AND household_id = v_invite.household_id;
        END IF;

        v_is_default := NOT EXISTS (SELECT 1 FROM public.household_memberships WHERE user_id = v_uid);
        INSERT INTO public.household_memberships (household_id, user_id, role, is_default, financial_role)
        VALUES (
            v_hh.id, v_uid, 'member', v_is_default,
            CASE WHEN v_invite.role IN ('provider', 'spouse', 'peer', 'family_member', 'dependent')
                 THEN v_invite.role
                 ELSE public.household_default_financial_role(v_hh.id, v_uid) END
        )
        ON CONFLICT (household_id, user_id) DO NOTHING;

        SELECT role, financial_role INTO v_role, v_financial_role
        FROM public.household_memberships
        WHERE household_id = v_hh.id AND user_id = v_uid;

        UPDATE public.users
        SET household_id = v_hh.id, role = v_role, financial_role = v_financial_role
        WHERE id = v_uid;

        INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, true);
        RETURN to_jsonb(v_hh);
    END IF;

    -- The household's permanent join code: peer (roommates) / family_member (family).
    SELECT * INTO v_hh
    FROM public.households
    WHERE upper(trim(invite_code)) = v_clean_code;

    IF v_hh.id IS NOT NULL THEN
        v_is_default := NOT EXISTS (SELECT 1 FROM public.household_memberships WHERE user_id = v_uid);
        INSERT INTO public.household_memberships (household_id, user_id, role, is_default, financial_role)
        VALUES (v_hh.id, v_uid, 'member', v_is_default, public.household_default_financial_role(v_hh.id, v_uid))
        ON CONFLICT (household_id, user_id) DO NOTHING;

        SELECT role, financial_role INTO v_role, v_financial_role
        FROM public.household_memberships
        WHERE household_id = v_hh.id AND user_id = v_uid;

        UPDATE public.users
        SET household_id = v_hh.id, role = v_role, financial_role = v_financial_role
        WHERE id = v_uid;

        INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, true);
        RETURN to_jsonb(v_hh);
    END IF;

    INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, false);
    RETURN jsonb_build_object('success', false, 'error', 'Invalid invite code');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.join_household_by_code(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.join_household_by_code(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.claim_household_role_invite(
    p_invite_code text,
    p_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid;
    v_clean_code text := upper(trim(p_invite_code));
    v_fail_count int;
    v_invite public.household_invites%ROWTYPE;
    v_hh public.households%ROWTYPE;
    v_role text;
    v_financial_role text;
    v_is_default boolean;
BEGIN
    IF auth.uid() IS NOT NULL AND p_user_id IS NOT NULL AND p_user_id IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'Forbidden: cannot claim an invite on behalf of another user' USING ERRCODE = '42501';
    END IF;

    v_uid := COALESCE(auth.uid(), p_user_id);

    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    SELECT count(*) INTO v_fail_count
    FROM public.invite_attempt_log
    WHERE user_id = v_uid
      AND success = false
      AND attempted_at > (now() - interval '15 minutes');

    IF v_fail_count >= 5 THEN
        RAISE EXCEPTION 'Too many failed join attempts. Please try again in 15 minutes.';
    END IF;

    SELECT * INTO v_invite
    FROM public.household_invites
    WHERE upper(trim(invite_code)) = v_clean_code
      AND expires_at > now()
    FOR UPDATE;

    IF v_invite.id IS NULL OR (v_invite.used_by IS NOT NULL AND v_invite.used_by IS DISTINCT FROM v_uid) THEN
        INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, false);
        RETURN jsonb_build_object('success', false, 'error', 'Invalid, expired, or already used invite code');
    END IF;

    SELECT * INTO v_hh FROM public.households WHERE id = v_invite.household_id;

    SELECT role, financial_role INTO v_role, v_financial_role
    FROM public.household_memberships
    WHERE household_id = v_invite.household_id AND user_id = v_uid;

    IF v_role IS NOT NULL THEN
        IF v_invite.used_by IS DISTINCT FROM v_uid THEN
            RETURN jsonb_build_object('success', false, 'error', 'You are already a member of this household',
                                      'code', 'already_member');
        END IF;
        RETURN jsonb_build_object(
            'success', true,
            'household_id', v_hh.id,
            'household_name', v_hh.name,
            'role', v_financial_role,
            'target_member_id', v_invite.target_member_id
        );
    END IF;

    IF v_invite.used_by IS NOT NULL THEN
        INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, false);
        RETURN jsonb_build_object('success', false, 'error', 'Invalid, expired, or already used invite code');
    END IF;

    -- D1: a spouse/provider/family invite never lands in a roommates household and a
    -- peer invite never in a family household (the invite stays open).
    IF v_invite.role IN ('provider', 'spouse', 'peer', 'family_member', 'dependent')
       AND NOT public.household_financial_role_allowed(v_hh.household_type, v_invite.role) THEN
        RETURN jsonb_build_object('success', false,
            'error', 'This invite does not fit this household type; ask the admin for a new invite',
            'code', 'invite_role_mismatch');
    END IF;

    UPDATE public.household_invites SET used_by = v_uid WHERE id = v_invite.id;

    IF v_invite.target_member_id IS NOT NULL THEN
        UPDATE public.household_dependents
        SET linked_user_id = v_uid
        WHERE id = v_invite.target_member_id
          AND household_id = v_invite.household_id;
    END IF;

    v_is_default := NOT EXISTS (SELECT 1 FROM public.household_memberships WHERE user_id = v_uid);
    INSERT INTO public.household_memberships (household_id, user_id, role, is_default, financial_role)
    VALUES (
        v_hh.id, v_uid, 'member', v_is_default,
        CASE WHEN v_invite.role IN ('provider', 'spouse', 'peer', 'family_member', 'dependent')
             THEN v_invite.role
             ELSE public.household_default_financial_role(v_hh.id, v_uid) END
    )
    ON CONFLICT (household_id, user_id) DO NOTHING;

    SELECT role, financial_role INTO v_role, v_financial_role
    FROM public.household_memberships
    WHERE household_id = v_hh.id AND user_id = v_uid;

    UPDATE public.users
    SET household_id = v_hh.id, role = v_role, financial_role = v_financial_role
    WHERE id = v_uid;

    INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, true);

    RETURN jsonb_build_object(
        'success', true,
        'household_id', v_hh.id,
        'household_name', v_hh.name,
        'role', v_financial_role,
        'target_member_id', v_invite.target_member_id
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_household_role_invite(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_household_role_invite(text, uuid) TO authenticated, service_role;

-- 9. Provider management: family households only -----------------------------------------
CREATE OR REPLACE FUNCTION public.set_nafaqah_provider(
    p_household_id uuid,
    p_user_id uuid,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.household_resolve_actor(p_actor_user_id);
    v_previous uuid;
    v_type text;
    v_role text;
BEGIN
    PERFORM public.household_require_admin(p_household_id, v_actor);

    SELECT nafaqah_provider_user_id, household_type INTO v_previous, v_type
    FROM public.households
    WHERE id = p_household_id
    FOR UPDATE;

    IF v_type IS DISTINCT FROM 'family' THEN
        RAISE EXCEPTION 'Only a family household has a Nafaqah provider'
            USING ERRCODE = '22023', HINT = 'not_family_household';
    END IF;

    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'Choose a member of this household as the Nafaqah provider' USING ERRCODE = '22023';
    END IF;

    v_role := public.household_member_financial_role(p_household_id, p_user_id);
    IF v_role IS NULL THEN
        RAISE EXCEPTION 'Target user is not a member of this household' USING ERRCODE = 'P0002';
    END IF;
    IF v_role = 'spouse' THEN
        RAISE EXCEPTION 'A spouse member cannot be the Nafaqah provider'
            USING ERRCODE = '22023', HINT = 'provider_is_spouse';
    END IF;

    IF v_previous IS DISTINCT FROM p_user_id THEN
        UPDATE public.households SET nafaqah_provider_user_id = p_user_id WHERE id = p_household_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'household_id', p_household_id,
        'nafaqah_provider_user_id', p_user_id,
        'previous_provider_user_id', v_previous
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_nafaqah_provider(uuid, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_nafaqah_provider(uuid, uuid, uuid) TO authenticated, service_role;

-- Primary admin and provider are separate roles: a transfer keeps the provider; an
-- unset provider of a family household defaults to the new primary admin (non-spouse).
CREATE OR REPLACE FUNCTION public.transfer_primary_admin(
    p_household_id uuid,
    p_new_primary_user_id uuid,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.household_resolve_actor(p_actor_user_id);
    v_owner uuid;
    v_target_role text;
    v_provider uuid;
BEGIN
    PERFORM public.household_require_admin(p_household_id, v_actor);

    SELECT owner_user_id INTO v_owner
    FROM public.households
    WHERE id = p_household_id
    FOR UPDATE;

    IF v_owner IS DISTINCT FROM v_actor THEN
        RAISE EXCEPTION 'Forbidden: only the primary admin can transfer primary admin' USING ERRCODE = '42501';
    END IF;

    IF p_new_primary_user_id IS NULL OR p_new_primary_user_id = v_actor THEN
        RAISE EXCEPTION 'Choose another member of this household' USING ERRCODE = '22023';
    END IF;

    v_target_role := public.household_member_role(p_household_id, p_new_primary_user_id);
    IF v_target_role IS NULL THEN
        RAISE EXCEPTION 'Target user is not a member of this household' USING ERRCODE = 'P0002';
    END IF;

    IF v_target_role <> 'admin' THEN
        PERFORM public.household_apply_role(p_household_id, p_new_primary_user_id, 'admin');
    END IF;

    UPDATE public.households
    SET owner_user_id = p_new_primary_user_id,
        nafaqah_provider_user_id = COALESCE(
            nafaqah_provider_user_id,
            CASE WHEN household_type = 'family'
                      AND public.household_member_financial_role(p_household_id, p_new_primary_user_id) <> 'spouse'
                 THEN p_new_primary_user_id END
        )
    WHERE id = p_household_id
    RETURNING nafaqah_provider_user_id INTO v_provider;

    RETURN jsonb_build_object(
        'success', true,
        'household_id', p_household_id,
        'primary_admin_user_id', p_new_primary_user_id,
        'previous_primary_admin_user_id', v_actor,
        'nafaqah_provider_user_id', v_provider
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.transfer_primary_admin(uuid, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transfer_primary_admin(uuid, uuid, uuid) TO authenticated, service_role;

-- 10. Admin RPCs: household type and member financial role (D1, FABLE2-DB-07) ----------
CREATE OR REPLACE FUNCTION public.set_household_type(
    p_household_id uuid,
    p_household_type text,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.household_resolve_actor(p_actor_user_id);
    v_type text := lower(trim(p_household_type));
    v_previous text;
    v_owner uuid;
    v_provider uuid;
    v_blockers text[] := ARRAY[]::text[];
BEGIN
    PERFORM public.household_require_admin(p_household_id, v_actor);

    IF v_type IS NULL OR v_type NOT IN ('family', 'roommates') THEN
        RAISE EXCEPTION 'Household type must be ''family'' or ''roommates'''
            USING ERRCODE = '22023', HINT = 'invalid_household_type';
    END IF;

    SELECT household_type, owner_user_id, nafaqah_provider_user_id INTO v_previous, v_owner, v_provider
    FROM public.households
    WHERE id = p_household_id
    FOR UPDATE;

    IF v_previous IS DISTINCT FROM v_type THEN
        IF v_type = 'roommates' THEN
            -- Refused while anything of the family ledger exists (no silent conversion).
            IF EXISTS (SELECT 1 FROM public.household_memberships
                       WHERE household_id = p_household_id AND financial_role = 'spouse') THEN
                v_blockers := array_append(v_blockers, 'spouse_member');
            END IF;
            IF EXISTS (SELECT 1 FROM public.transactions
                       WHERE household_id = p_household_id AND nafaqah_class IS NOT NULL) THEN
                v_blockers := array_append(v_blockers, 'nafaqah_expenses');
            END IF;
            IF EXISTS (SELECT 1 FROM public.spouse_reimbursements WHERE household_id = p_household_id) THEN
                v_blockers := array_append(v_blockers, 'reimbursements');
            END IF;
            IF EXISTS (SELECT 1 FROM public.member_allowances WHERE household_id = p_household_id) THEN
                v_blockers := array_append(v_blockers, 'allowances');
            END IF;
            IF cardinality(v_blockers) > 0 THEN
                RAISE EXCEPTION 'A family household with a wife or Nafaqah records cannot become a roommates household'
                    USING ERRCODE = '22023', HINT = 'type_change_blocked',
                          DETAIL = array_to_string(v_blockers, ',');
            END IF;

            UPDATE public.households
            SET household_type = 'roommates',
                nafaqah_provider_user_id = NULL
            WHERE id = p_household_id;

            UPDATE public.household_memberships
            SET financial_role = 'peer'
            WHERE household_id = p_household_id AND financial_role <> 'peer';
        ELSE
            UPDATE public.households SET household_type = 'family' WHERE id = p_household_id;

            UPDATE public.household_memberships
            SET financial_role = CASE WHEN user_id = v_owner THEN 'provider' ELSE 'family_member' END
            WHERE household_id = p_household_id AND financial_role = 'peer';

            -- Explicit default: the primary admin is the Nafaqah provider until an admin changes it.
            IF v_owner IS NOT NULL
               AND public.household_member_financial_role(p_household_id, v_owner) IS DISTINCT FROM 'spouse'
               AND public.household_member_financial_role(p_household_id, v_owner) IS NOT NULL THEN
                UPDATE public.households
                SET nafaqah_provider_user_id = v_owner
                WHERE id = p_household_id AND nafaqah_provider_user_id IS NULL;
            END IF;
        END IF;
    END IF;

    SELECT nafaqah_provider_user_id INTO v_provider FROM public.households WHERE id = p_household_id;

    RETURN jsonb_build_object(
        'success', true,
        'household_id', p_household_id,
        'household_type', v_type,
        'previous_household_type', v_previous,
        'changed', v_previous IS DISTINCT FROM v_type,
        'nafaqah_provider_user_id', v_provider
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_household_type(uuid, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_household_type(uuid, text, uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.set_member_financial_role(
    p_household_id uuid,
    p_user_id uuid,
    p_financial_role text,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.household_resolve_actor(p_actor_user_id);
    v_role text := lower(trim(p_financial_role));
    v_type text;
    v_provider uuid;
    v_previous text;
BEGIN
    PERFORM public.household_require_admin(p_household_id, v_actor);

    SELECT household_type, nafaqah_provider_user_id INTO v_type, v_provider
    FROM public.households
    WHERE id = p_household_id
    FOR UPDATE;

    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'Choose a member of this household' USING ERRCODE = '22023';
    END IF;

    SELECT financial_role INTO v_previous
    FROM public.household_memberships
    WHERE household_id = p_household_id AND user_id = p_user_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Target user is not a member of this household' USING ERRCODE = 'P0002';
    END IF;

    -- The provider label is managed through set_nafaqah_provider, not here.
    IF v_role IS NULL
       OR NOT ((v_type = 'family' AND v_role IN ('spouse', 'family_member', 'dependent'))
               OR (v_type = 'roommates' AND v_role = 'peer')) THEN
        RAISE EXCEPTION 'Financial role % is not available in a % household', COALESCE(v_role, 'NULL'), v_type
            USING ERRCODE = '22023', HINT = 'financial_role_not_allowed';
    END IF;

    IF v_role = 'spouse' AND p_user_id IS NOT DISTINCT FROM v_provider THEN
        RAISE EXCEPTION 'The Nafaqah provider cannot be a spouse member'
            USING ERRCODE = '22023', HINT = 'provider_is_spouse';
    END IF;

    IF v_previous = 'spouse' AND v_role <> 'spouse'
       AND (EXISTS (SELECT 1 FROM public.transactions
                    WHERE household_id = p_household_id AND nafaqah_spouse_id = p_user_id)
            OR EXISTS (SELECT 1 FROM public.spouse_reimbursements
                       WHERE household_id = p_household_id AND wife_user_id = p_user_id)
            OR EXISTS (SELECT 1 FROM public.member_allowances
                       WHERE household_id = p_household_id AND member_user_id = p_user_id)) THEN
        RAISE EXCEPTION 'This wife has Nafaqah records in the household; her role cannot change'
            USING ERRCODE = '22023', HINT = 'spouse_has_ledger';
    END IF;

    IF v_previous IS DISTINCT FROM v_role THEN
        UPDATE public.household_memberships
        SET financial_role = v_role
        WHERE household_id = p_household_id AND user_id = p_user_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'household_id', p_household_id,
        'user_id', p_user_id,
        'financial_role', v_role,
        'previous_financial_role', v_previous
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_member_financial_role(uuid, uuid, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_member_financial_role(uuid, uuid, text, uuid) TO authenticated, service_role;

-- 11. Installment plans (FABLE2-DB-02) ------------------------------------------------
DO $$
DECLARE
    v_bad int;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'installment_plans_paid_installments_range'
                     AND conrelid = 'public.installment_plans'::regclass) THEN
        ALTER TABLE public.installment_plans
            ADD CONSTRAINT installment_plans_paid_installments_range
            CHECK (paid_installments >= 0 AND paid_installments <= installment_count) NOT VALID;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_constraint
               WHERE conname = 'installment_plans_paid_installments_range'
                 AND conrelid = 'public.installment_plans'::regclass
                 AND NOT convalidated) THEN
        SELECT count(*) INTO v_bad FROM public.installment_plans
        WHERE paid_installments < 0 OR paid_installments > installment_count;
        IF v_bad = 0 THEN
            ALTER TABLE public.installment_plans VALIDATE CONSTRAINT installment_plans_paid_installments_range;
        ELSE
            RAISE NOTICE 'installment_plans_paid_installments_range left NOT VALID: % existing row(s) violate it (new writes are checked)', v_bad;
        END IF;
    END IF;
END $$;

-- Clients (the app never writes this table; the API uses the service role) may not
-- move the payment counter or the status.
REVOKE UPDATE ON public.installment_plans FROM PUBLIC, anon, authenticated;
GRANT UPDATE (merchant, provider, total_amount, installment_count, monthly_amount, start_date,
              day_of_month, category_code, original_transaction_id, notes)
    ON public.installment_plans TO authenticated;

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

-- 12. D3 for ledgers orphaned before this migration (a wife who left under 800000) ---
DELETE FROM public.spouse_reimbursements r
WHERE NOT EXISTS (SELECT 1 FROM public.household_memberships m
                  WHERE m.household_id = r.household_id AND m.user_id = r.wife_user_id);
DELETE FROM public.member_allowances a
WHERE NOT EXISTS (SELECT 1 FROM public.household_memberships m
                  WHERE m.household_id = a.household_id AND m.user_id = a.member_user_id);
UPDATE public.transactions t
SET nafaqah_class = NULL, nafaqah_spouse_id = NULL
WHERE t.nafaqah_spouse_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.household_memberships m
                  WHERE m.household_id = t.household_id AND m.user_id = t.nafaqah_spouse_id);

-- 13. Post-checks -----------------------------------------------------------------------
DO $$
DECLARE
    v_n int;
BEGIN
    SELECT count(*) INTO v_n FROM public.households WHERE household_type NOT IN ('family', 'roommates');
    IF v_n > 0 THEN
        RAISE EXCEPTION 'post-check: % household(s) without a valid household_type', v_n;
    END IF;

    SELECT count(*) INTO v_n
    FROM public.household_memberships m JOIN public.households h ON h.id = m.household_id
    WHERE NOT public.household_financial_role_allowed(h.household_type, m.financial_role);
    IF v_n > 0 THEN
        RAISE EXCEPTION 'post-check: % membership(s) whose financial role does not fit the household type', v_n;
    END IF;

    SELECT count(*) INTO v_n FROM public.households
    WHERE household_type <> 'family' AND nafaqah_provider_user_id IS NOT NULL;
    IF v_n > 0 THEN
        RAISE EXCEPTION 'post-check: % roommates household(s) with a Nafaqah provider', v_n;
    END IF;

    SELECT count(*) INTO v_n FROM public.transactions t
    WHERE t.nafaqah_spouse_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.household_memberships m
                      WHERE m.household_id = t.household_id AND m.user_id = t.nafaqah_spouse_id);
    IF v_n > 0 THEN
        RAISE EXCEPTION 'post-check: % classified row(s) of a wife who is not a member', v_n;
    END IF;

    IF has_column_privilege('authenticated', 'public.households', 'household_type', 'UPDATE')
       OR has_column_privilege('anon', 'public.households', 'household_type', 'UPDATE')
       OR has_column_privilege('authenticated', 'public.installment_plans', 'paid_installments', 'UPDATE')
       OR has_column_privilege('authenticated', 'public.installment_plans', 'status', 'UPDATE')
       OR has_column_privilege('anon', 'public.installment_plans', 'paid_installments', 'UPDATE') THEN
        RAISE EXCEPTION 'post-check: clients can write household_type or the installment counter/status';
    END IF;

    IF to_regprocedure('public.create_household_and_claim(text)') IS NOT NULL
       OR NOT has_function_privilege('authenticated', 'public.create_household_and_claim(text, text)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.create_household_and_claim(text, text)', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.set_household_type(uuid, text, uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.set_household_type(uuid, text, uuid)', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.set_member_financial_role(uuid, uuid, text, uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.set_member_financial_role(uuid, uuid, text, uuid)', 'EXECUTE')
       OR has_function_privilege('authenticated', 'public.household_default_financial_role(uuid, uuid)', 'EXECUTE')
       OR has_function_privilege('authenticated', 'public.remove_nafaqah_ledger_on_membership_end()', 'EXECUTE')
       OR has_function_privilege('authenticated', 'public.pay_installment_plan(uuid, uuid, uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'post-check: function privileges are wrong';
    END IF;

    SELECT count(*) INTO v_n FROM public.households WHERE household_type = 'roommates';
    RAISE NOTICE 'post-check: % roommates household(s), % family household(s)',
        v_n, (SELECT count(*) FROM public.households WHERE household_type = 'family');
END;
$$;

COMMIT;
