-- ============================================================================
-- Migration: 20261020800000_household_roles_and_nafaqah_integrity.sql
--
-- Independent review (Fable, docs/review/audit/fable_review.md) sections A + B,
-- with the owner decisions of 2026-10-21:
--   * The Nafaqah provider (husband) of a family household is stored
--     explicitly per household. Default: the household's primary admin
--     (households.owner_user_id). An admin can change it to another
--     (non-spouse) member. It is never inferred from user-level roles.
--   * Wife personal purchases (nafaqah_class = 'wife_personal') count against
--     her allowance only, never against the household category budgets.
--
-- Items:
--   FABLE-LOGIC-01  Financial role per membership: household_memberships
--                   .financial_role (same values as users.financial_role),
--                   backfilled from users.financial_role. Every Nafaqah helper
--                   reads the membership of THAT household; users.financial_role
--                   is only a cache of the active household's membership role
--                   (create / join / claim / switch_active_household keep it).
--   FABLE-LOGIC-04  households.nafaqah_provider_user_id (ON DELETE SET NULL),
--                   backfilled = owner_user_id; set_nafaqah_provider() RPC
--                   (admins); cleared when the provider's membership ends; new
--                   classified rows are refused while it is NULL. Non-spouse
--                   joiners of a family household default to 'family_member'.
--   FABLE-DB-01/03  Invites readable by admins only; the claim RPCs never let an
--                   existing member consume an invite of their own household
--                   (no-op switch for idempotent retries / the static code);
--                   the users -> memberships sync trigger never demotes an admin
--                   and never rewrites another household's membership.
--   FABLE-LOGIC-02  BEFORE UPDATE OR DELETE guard on wife_reimbursable rows: a
--                   change that would leave advances below the recorded
--                   repayments is refused (22023, HINT ledger_would_be_overpaid),
--                   under the advisory lock of record_spouse_reimbursement.
--   FABLE-LOGIC-06  Budget triggers ignore wife_personal rows (class changes on
--                   UPDATE move the amount in/out of the category budget).
--   FABLE-LOGIC-05  Changing households.payday_day re-stamps cycle_key from the
--                   open cycle onward and moves the open cycle's budgets and
--                   allowances to the new key (never overwriting a row that
--                   already exists for that key), then recomputes the affected
--                   budgets' spent_amount.
--
-- Live safety: one transaction, idempotent (re-running changes nothing), no row
-- is deleted. Compatible with the deployed backend (origin/main, service role:
-- reads users.financial_role, which stays a correct cache of the active
-- household; sets payday through households.payday_day, now re-keyed by the
-- trigger) and with released app builds (join_household_by_code /
-- create_household_and_claim keep their return shapes; the app never reads
-- household_invites, household_memberships.financial_role or the provider
-- column directly; a direct households.payday_day update is re-keyed too).
-- Applies after 20261020700000 (grants / FK hardening); the provider column is
-- not client-writable whichever households UPDATE column list is in force.
--
-- Proof test: supabase/tests/25_household_roles_and_nafaqah_integrity.sql
-- ============================================================================

BEGIN;

-- 0. Guard: the assumptions this file relies on ------------------------------
DO $$
DECLARE
    v_n int;
BEGIN
    IF to_regclass('public.household_memberships') IS NULL
       OR to_regclass('public.member_allowances') IS NULL
       OR to_regclass('public.spouse_reimbursements') IS NULL
       OR to_regclass('public.household_invites') IS NULL THEN
        RAISE EXCEPTION 'guard: household_memberships / member_allowances / spouse_reimbursements / household_invites missing (apply 20261020300000 first)';
    END IF;

    SELECT count(*) INTO v_n
    FROM (VALUES ('households', 'owner_user_id'), ('households', 'payday_day'),
                 ('transactions', 'nafaqah_class'), ('transactions', 'nafaqah_spouse_id'),
                 ('transactions', 'cycle_key'), ('budgets', 'cycle_key'),
                 ('users', 'financial_role')) AS req(t, c)
    WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = req.t AND column_name = req.c);
    IF v_n > 0 THEN
        RAISE EXCEPTION 'guard: % required column(s) missing (apply 20261020300000 / 20261020400000 first)', v_n;
    END IF;

    IF to_regprocedure('public.get_saudi_cycle_for_timestamp(timestamptz, integer)') IS NULL
       OR to_regprocedure('public.household_resolve_actor(uuid)') IS NULL
       OR to_regprocedure('public.household_require_admin(uuid, uuid)') IS NULL
       OR to_regprocedure('public.household_member_role(uuid, uuid)') IS NULL
       OR to_regprocedure('public.populate_transaction_cycle_key()') IS NULL
       OR to_regprocedure('public.record_spouse_reimbursement(uuid, uuid, numeric, text, text, uuid)') IS NULL THEN
        RAISE EXCEPTION 'guard: required functions missing (apply the 20261020 batch first)';
    END IF;

    SELECT count(*) INTO v_n
    FROM public.users
    WHERE financial_role IS NOT NULL
      AND financial_role NOT IN ('provider', 'spouse', 'peer', 'family_member', 'dependent');
    IF v_n > 0 THEN
        RAISE EXCEPTION 'guard: % users.financial_role value(s) outside the known set', v_n;
    END IF;

    SELECT count(*) INTO v_n FROM (
        SELECT user_id FROM public.household_memberships GROUP BY user_id HAVING count(*) > 1
    ) multi;
    RAISE NOTICE 'guard: % user(s) belong to more than one household (their memberships are backfilled from users.financial_role)', v_n;

    SELECT count(*) INTO v_n FROM public.transactions WHERE nafaqah_class IS NOT NULL;
    RAISE NOTICE 'guard: % classified (Nafaqah) transaction(s)', v_n;
END;
$$;

-- 1. Financial role per membership (FABLE-LOGIC-01) ---------------------------
ALTER TABLE public.household_memberships ADD COLUMN IF NOT EXISTS financial_role text;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'household_memberships_financial_role_check'
          AND conrelid = 'public.household_memberships'::regclass
    ) THEN
        ALTER TABLE public.household_memberships
            ADD CONSTRAINT household_memberships_financial_role_check
            CHECK (financial_role IN ('provider', 'spouse', 'peer', 'family_member', 'dependent'));
    END IF;
END $$;

-- Backfill: the per-user role applied to every household until now (live: one
-- membership per user, so this is exact). Only rows not yet backfilled.
UPDATE public.household_memberships m
SET financial_role = COALESCE(u.financial_role, 'provider')
FROM public.users u
WHERE u.id = m.user_id
  AND m.financial_role IS NULL;

UPDATE public.household_memberships SET financial_role = 'family_member' WHERE financial_role IS NULL;
ALTER TABLE public.household_memberships ALTER COLUMN financial_role SET NOT NULL;

COMMENT ON COLUMN public.household_memberships.financial_role IS
    'Financial role of the user IN THIS household (provider, spouse, peer, family_member, dependent). Decides family '
    '(spouse member) vs roommate mode. Set by the invite RPCs; users.financial_role caches the active household''s value.';

-- Clients never write memberships (20261020020000); keep it explicit for the new column.
REVOKE INSERT, UPDATE ON public.household_memberships FROM anon, authenticated;

-- 2. Explicit Nafaqah provider (FABLE-LOGIC-04) --------------------------------
-- Added and backfilled in one step so a re-run never re-defaults a provider an
-- admin cleared or changed. Backfill = the primary admin of EVERY household
-- whose primary admin is a non-spouse member: in households without a spouse
-- member the provider is inert (nafaqah_husband_id() is NULL there), and a
-- household that later gains a wife works at once with the owner's default.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'households'
                     AND column_name = 'nafaqah_provider_user_id') THEN
        ALTER TABLE public.households
            ADD COLUMN nafaqah_provider_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL;

        UPDATE public.households h
        SET nafaqah_provider_user_id = h.owner_user_id
        WHERE h.owner_user_id IS NOT NULL
          AND EXISTS (
              SELECT 1 FROM public.household_memberships m
              WHERE m.household_id = h.id
                AND m.user_id = h.owner_user_id
                AND m.financial_role <> 'spouse'
          );
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_households_nafaqah_provider
    ON public.households (nafaqah_provider_user_id) WHERE nafaqah_provider_user_id IS NOT NULL;

-- Changed only through set_nafaqah_provider (no column privilege for clients,
-- whatever households UPDATE column list 20261020400000 / 20261020700000 left).
REVOKE UPDATE (nafaqah_provider_user_id) ON public.households FROM PUBLIC, anon, authenticated;

COMMENT ON COLUMN public.households.nafaqah_provider_user_id IS
    'Nafaqah provider (husband) of a family household: a non-spouse member. Defaults to the primary admin; changed by an '
    'admin through set_nafaqah_provider; NULL after the provider leaves (new classified expenses are refused until set).';

-- 3. Helpers -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.household_member_financial_role(p_household_id uuid, p_user_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT m.financial_role
    FROM public.household_memberships m
    WHERE m.household_id = p_household_id AND m.user_id = p_user_id;
$$;

-- Role of a user joining without a role-tagged invite: the owner / first member
-- is the provider; in a family (a spouse member) everyone else is family; in a
-- roommate household (a peer member) a peer; otherwise family. Never 'spouse'.
CREATE OR REPLACE FUNCTION public.household_default_financial_role(p_household_id uuid, p_user_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT CASE
        WHEN (SELECT h.owner_user_id FROM public.households h WHERE h.id = p_household_id) = p_user_id
             OR NOT EXISTS (SELECT 1 FROM public.household_memberships o
                            WHERE o.household_id = p_household_id AND o.user_id <> p_user_id)
            THEN 'provider'
        WHEN EXISTS (SELECT 1 FROM public.household_memberships o
                     WHERE o.household_id = p_household_id AND o.user_id <> p_user_id AND o.financial_role = 'spouse')
            THEN 'family_member'
        WHEN EXISTS (SELECT 1 FROM public.household_memberships o
                     WHERE o.household_id = p_household_id AND o.user_id <> p_user_id AND o.financial_role = 'peer')
            THEN 'peer'
        ELSE 'family_member'
    END;
$$;

REVOKE EXECUTE ON FUNCTION public.household_member_financial_role(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.household_default_financial_role(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- Membership rows: default role on insert; a provider can never become a spouse.
CREATE OR REPLACE FUNCTION public.membership_financial_role_rules()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.financial_role IS NULL THEN
        NEW.financial_role := public.household_default_financial_role(NEW.household_id, NEW.user_id);
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

DROP TRIGGER IF EXISTS trg_membership_financial_role_rules ON public.household_memberships;
CREATE TRIGGER trg_membership_financial_role_rules
BEFORE INSERT OR UPDATE OF financial_role ON public.household_memberships
FOR EACH ROW EXECUTE FUNCTION public.membership_financial_role_rules();

-- users.financial_role caches the active household's membership role.
CREATE OR REPLACE FUNCTION public.membership_financial_role_cache()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE public.users
    SET financial_role = NEW.financial_role
    WHERE id = NEW.user_id
      AND household_id = NEW.household_id
      AND financial_role IS DISTINCT FROM NEW.financial_role;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_membership_financial_role_cache ON public.household_memberships;
CREATE TRIGGER trg_membership_financial_role_cache
AFTER INSERT OR UPDATE OF financial_role ON public.household_memberships
FOR EACH ROW EXECUTE FUNCTION public.membership_financial_role_cache();

-- The provider leaves (or is removed / deletes the account): cleared, never
-- re-inferred. Family features then refuse new classified rows until an admin
-- chooses a provider.
CREATE OR REPLACE FUNCTION public.clear_nafaqah_provider_on_membership_end()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE public.households
    SET nafaqah_provider_user_id = NULL
    WHERE id = OLD.household_id
      AND nafaqah_provider_user_id = OLD.user_id;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_clear_nafaqah_provider ON public.household_memberships;
CREATE TRIGGER trg_clear_nafaqah_provider
AFTER DELETE ON public.household_memberships
FOR EACH ROW EXECUTE FUNCTION public.clear_nafaqah_provider_on_membership_end();

-- households: the first primary admin becomes the default provider; any
-- provider must be a non-spouse member (binds service-role writes too).
CREATE OR REPLACE FUNCTION public.households_nafaqah_provider_rules()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_role text;
BEGIN
    IF NEW.nafaqah_provider_user_id IS NULL
       AND NEW.owner_user_id IS NOT NULL
       AND (TG_OP = 'INSERT' OR OLD.owner_user_id IS NULL) THEN
        v_role := public.household_member_financial_role(NEW.id, NEW.owner_user_id);
        IF v_role IS NOT NULL AND v_role <> 'spouse' THEN
            NEW.nafaqah_provider_user_id := NEW.owner_user_id;
        END IF;
    END IF;

    IF NEW.nafaqah_provider_user_id IS NOT NULL
       AND (TG_OP = 'INSERT' OR NEW.nafaqah_provider_user_id IS DISTINCT FROM OLD.nafaqah_provider_user_id) THEN
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

DROP TRIGGER IF EXISTS trg_households_nafaqah_provider ON public.households;
CREATE TRIGGER trg_households_nafaqah_provider
BEFORE INSERT OR UPDATE OF owner_user_id, nafaqah_provider_user_id ON public.households
FOR EACH ROW EXECUTE FUNCTION public.households_nafaqah_provider_rules();

REVOKE EXECUTE ON FUNCTION public.membership_financial_role_rules() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.membership_financial_role_cache() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.clear_nafaqah_provider_on_membership_end() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.households_nafaqah_provider_rules() FROM PUBLIC, anon, authenticated;

-- 4. Nafaqah helpers read the membership of THAT household --------------------
-- (CREATE OR REPLACE keeps the E2E-04 grants: service_role only.)
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
        WHERE m.household_id = p_household_id
          AND m.user_id = p_user_id
          AND m.financial_role = 'spouse'
    );
$$;

-- The explicit provider, when the household is a family (has a spouse member)
-- and the provider is still a non-spouse member; NULL otherwise.
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
      AND EXISTS (SELECT 1 FROM public.household_memberships sm
                  WHERE sm.household_id = h.id AND sm.financial_role = 'spouse')
      AND EXISTS (SELECT 1 FROM public.household_memberships pm
                  WHERE pm.household_id = h.id
                    AND pm.user_id = h.nafaqah_provider_user_id
                    AND pm.financial_role <> 'spouse');
$$;

COMMENT ON FUNCTION public.nafaqah_husband_id(uuid) IS
    'Internal: households.nafaqah_provider_user_id of a family household (never inferred). Not client-callable (E2E-04).';

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

    IF public.nafaqah_husband_id(NEW.household_id) IS NULL THEN
        RAISE EXCEPTION 'Household % has no Nafaqah provider: a household admin must choose one before family expenses are classified', NEW.household_id
            USING ERRCODE = '23514', HINT = 'no_nafaqah_provider';
    END IF;

    RETURN NEW;
END;
$$;

-- Members with their roles: the financial role is the membership's.
CREATE OR REPLACE FUNCTION public.get_household_members(
    p_household_id uuid,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS TABLE (
    user_id uuid,
    display_name text,
    role text,
    financial_role text,
    is_primary boolean,
    joined_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.household_resolve_actor(p_actor_user_id);
    v_owner uuid;
BEGIN
    IF p_household_id IS NULL OR public.household_member_role(p_household_id, v_actor) IS NULL THEN
        RAISE EXCEPTION 'Forbidden: not a member of this household' USING ERRCODE = '42501';
    END IF;
    v_owner := public.household_primary_admin_id(p_household_id);

    RETURN QUERY
    SELECT m.user_id,
           u.display_name,
           m.role,
           m.financial_role,
           (m.user_id = v_owner) AS is_primary,
           m.created_at AS joined_at
    FROM public.household_memberships m
    JOIN public.users u ON u.id = m.user_id
    WHERE m.household_id = p_household_id
    ORDER BY (m.user_id = v_owner) DESC, (m.role = 'admin') DESC, m.created_at ASC, m.user_id ASC;
END;
$$;

-- 5. users -> memberships sync (FABLE-DB-03) -----------------------------------
-- Creates the active household's membership when missing (copying the role and
-- financial role being written); an existing membership is never demoted from
-- admin and its financial role is never rewritten from the per-user cache.
CREATE OR REPLACE FUNCTION public.sync_user_household_membership()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.household_id IS NOT NULL THEN
        INSERT INTO public.household_memberships (household_id, user_id, role, is_default, financial_role)
        VALUES (
            NEW.household_id,
            NEW.id,
            COALESCE(NEW.role, 'member'),
            NOT EXISTS (SELECT 1 FROM public.household_memberships WHERE user_id = NEW.id),
            NEW.financial_role
        )
        ON CONFLICT (household_id, user_id)
        DO UPDATE SET role = CASE
            WHEN public.household_memberships.role = 'admin' THEN 'admin'
            ELSE COALESCE(EXCLUDED.role, public.household_memberships.role)
        END;
    END IF;
    RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.sync_user_household_membership() FROM PUBLIC, anon, authenticated;

-- 6. Household context RPCs keep the cache in step ---------------------------------
CREATE OR REPLACE FUNCTION public.switch_active_household(p_household_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_role text;
    v_financial_role text;
    v_name text;
BEGIN
    SELECT role, financial_role INTO v_role, v_financial_role
    FROM public.household_memberships
    WHERE household_id = p_household_id AND user_id = auth.uid();

    IF v_role IS NULL THEN
        RAISE EXCEPTION 'Access denied: Not a member of household %', p_household_id;
    END IF;

    SELECT name INTO v_name
    FROM public.households
    WHERE id = p_household_id;

    UPDATE public.users
    SET household_id = p_household_id,
        role = v_role,
        financial_role = v_financial_role
    WHERE id = auth.uid();

    RETURN jsonb_build_object(
        'success', true,
        'household_id', p_household_id,
        'household_name', v_name,
        'role', v_role,
        'financial_role', v_financial_role
    );
END;
$$;

-- The creator is the primary admin and the default Nafaqah provider.
CREATE OR REPLACE FUNCTION public.create_household_and_claim(p_name text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_hh public.households%ROWTYPE;
    v_count int;
    v_invite_code text;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT count(*) INTO v_count
    FROM public.household_memberships
    WHERE user_id = v_uid AND role = 'admin';

    IF v_count >= 5 THEN
        RAISE EXCEPTION 'Household creation limit reached (maximum 5 households per user)';
    END IF;

    v_invite_code := upper(encode(extensions.gen_random_bytes(8), 'hex'));

    INSERT INTO public.households (name, invite_code)
    VALUES (trim(p_name), v_invite_code)
    RETURNING * INTO v_hh;

    -- Membership first: it makes the creator the primary admin, which makes
    -- them the default Nafaqah provider.
    INSERT INTO public.household_memberships (household_id, user_id, role, is_default, financial_role)
    VALUES (v_hh.id, v_uid, 'admin', true, 'provider')
    ON CONFLICT (household_id, user_id) DO UPDATE SET role = 'admin';

    UPDATE public.users
    SET household_id = v_hh.id,
        role = 'admin',
        financial_role = 'provider'
    WHERE id = v_uid;

    SELECT * INTO v_hh FROM public.households WHERE id = v_hh.id;
    RETURN to_jsonb(v_hh);
END;
$$;

-- 7. Invite claims (FABLE-DB-01 / DB-03, FABLE-LOGIC-01) ---------------------------
-- Older app builds call the API claim and then join_household_by_code with the
-- same code: a retry by the user who already used the invite is a no-op switch.
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
                -- An existing member never consumes an invite meant for someone else
                -- (and never re-roles themselves through it).
                RETURN jsonb_build_object('success', false, 'error', 'You are already a member of this household',
                                          'code', 'already_member');
            END IF;
            -- Retry by the claimer: switch to the household, nothing else changes.
            SELECT * INTO v_hh FROM public.households WHERE id = v_invite.household_id;
            UPDATE public.users
            SET household_id = v_hh.id, role = v_role, financial_role = v_financial_role
            WHERE id = v_uid;
            INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, true);
            RETURN to_jsonb(v_hh);
        END IF;

        IF v_invite.used_by = v_uid THEN
            v_claimed_id := v_invite.id;  -- re-joining with the invite this user claimed earlier
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

        SELECT * INTO v_hh FROM public.households WHERE id = v_invite.household_id;

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

    -- The household's permanent join code.
    SELECT * INTO v_hh
    FROM public.households
    WHERE upper(trim(invite_code)) = v_clean_code;

    IF v_hh.id IS NOT NULL THEN
        v_is_default := NOT EXISTS (SELECT 1 FROM public.household_memberships WHERE user_id = v_uid);
        INSERT INTO public.household_memberships (household_id, user_id, role, is_default, financial_role)
        VALUES (v_hh.id, v_uid, 'member', v_is_default, public.household_default_financial_role(v_hh.id, v_uid))
        ON CONFLICT (household_id, user_id) DO NOTHING;

        -- Existing members keep their role and financial role (never demoted).
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
            -- FABLE-DB-01: a member cannot take the spouse/provider invite meant for
            -- someone else; the invite stays open for the real invitee.
            RETURN jsonb_build_object('success', false, 'error', 'You are already a member of this household',
                                      'code', 'already_member');
        END IF;
        -- Idempotent retry by the claimer: nothing changes.
        RETURN jsonb_build_object(
            'success', true,
            'household_id', v_hh.id,
            'household_name', v_hh.name,
            'role', v_financial_role,
            'target_member_id', v_invite.target_member_id
        );
    END IF;

    IF v_invite.used_by IS NOT NULL THEN
        -- Used by this user, who has since left: same answer as any used invite.
        INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, false);
        RETURN jsonb_build_object('success', false, 'error', 'Invalid, expired, or already used invite code');
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

-- Defense in depth (also binds service-role writes): an invite is never marked
-- used by an existing member of its household.
CREATE OR REPLACE FUNCTION public.refuse_invite_claim_by_member()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.used_by IS NOT NULL
       AND OLD.used_by IS NULL
       AND EXISTS (SELECT 1 FROM public.household_memberships m
                   WHERE m.household_id = NEW.household_id AND m.user_id = NEW.used_by) THEN
        RAISE EXCEPTION 'Forbidden: an existing member cannot claim an invite of their own household'
            USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.refuse_invite_claim_by_member() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_refuse_invite_claim_by_member ON public.household_invites;
CREATE TRIGGER trg_refuse_invite_claim_by_member
BEFORE UPDATE OF used_by ON public.household_invites
FOR EACH ROW EXECUTE FUNCTION public.refuse_invite_claim_by_member();

-- Invite codes are readable by admins only (any member could read and claim
-- the spouse invite before). No released app reads this table directly.
DROP POLICY IF EXISTS "invites_select_household" ON public.household_invites;
DROP POLICY IF EXISTS invites_select_admin ON public.household_invites;
CREATE POLICY invites_select_admin ON public.household_invites
    FOR SELECT
    TO authenticated
    USING (
        household_id = (SELECT public.get_auth_user_household_id())
        AND (SELECT public.get_auth_user_role()) = 'admin'
    );

-- 8. Provider management (FABLE-LOGIC-04) --------------------------------------
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
    v_role text;
BEGIN
    PERFORM public.household_require_admin(p_household_id, v_actor);

    SELECT nafaqah_provider_user_id INTO v_previous
    FROM public.households
    WHERE id = p_household_id
    FOR UPDATE;

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

-- Primary admin and provider are separate roles: a transfer keeps the provider,
-- except that an unset provider defaults to the new primary admin (non-spouse).
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
            CASE WHEN public.household_member_financial_role(p_household_id, p_new_primary_user_id) <> 'spouse'
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

-- 9. Reimbursement ledger guard (FABLE-LOGIC-02) ---------------------------------
-- Lowering, declassifying, re-assigning or deleting a wife_reimbursable advance
-- must never leave the advances below what the husband already repaid. Same
-- advisory lock as record_spouse_reimbursement, so the two serialise. System
-- cascades (account / household deletion, pg_trigger_depth() > 1) pass: they
-- remove the repayments too.
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
    IF pg_trigger_depth() > 1 THEN
        RETURN COALESCE(NEW, OLD);
    END IF;
    IF OLD.nafaqah_class IS DISTINCT FROM 'wife_reimbursable' OR OLD.nafaqah_spouse_id IS NULL THEN
        RETURN COALESCE(NEW, OLD);
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

-- Named to run after trg_validate_transaction_nafaqah_class (BEFORE triggers fire alphabetically).
DROP TRIGGER IF EXISTS trg_wife_ledger_guard ON public.transactions;
CREATE TRIGGER trg_wife_ledger_guard
BEFORE UPDATE OR DELETE ON public.transactions
FOR EACH ROW EXECUTE FUNCTION public.guard_wife_reimbursable_ledger();

-- 10. Category budgets ignore wife_personal (FABLE-LOGIC-06) ----------------------
CREATE OR REPLACE FUNCTION public.update_budget_on_transaction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.nafaqah_class IS NOT DISTINCT FROM 'wife_personal' THEN
        RETURN NEW;  -- charged to the wife's allowance only
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
    IF OLD.nafaqah_class IS NOT DISTINCT FROM 'wife_personal' THEN
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
    v_old_counted boolean := OLD.nafaqah_class IS DISTINCT FROM 'wife_personal';
    v_new_counted boolean := NEW.nafaqah_class IS DISTINCT FROM 'wife_personal';
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

-- Spent of one budget row from its transactions (same rules as the triggers;
-- settlements between members are not spending).
CREATE OR REPLACE FUNCTION public.recompute_budget_spent(p_household_id uuid, p_cycle_keys text[])
RETURNS integer
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_n integer;
BEGIN
    UPDATE public.budgets b
    SET spent_amount = GREATEST(0, COALESCE((
        SELECT sum(t.amount)
        FROM public.transactions t
        WHERE t.household_id = b.household_id
          AND t.category_code = b.category_code
          AND t.cycle_key = b.cycle_key
          AND t.nafaqah_class IS DISTINCT FROM 'wife_personal'
          AND t.is_settlement IS NOT TRUE
    ), 0))
    WHERE b.household_id = p_household_id
      AND b.cycle_key = ANY (p_cycle_keys);
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.recompute_budget_spent(uuid, text[]) FROM PUBLIC, anon, authenticated;

-- 11. Payday change re-keys the open cycle (FABLE-LOGIC-05) ------------------------
-- Behaviour (p_as_of = now() from the trigger):
--   * from := the earlier start of the cycle open at p_as_of under the old and
--     under the new payday (Riyadh dates). Rows before it are history and keep
--     their key (moving them would shift spending between closed budgets).
--   * The open cycle's budgets and allowances (old key) move to the new current
--     key when the keys differ. A row that already exists for the new key wins:
--     the old-key row then stays where it is (no duplicate, nothing deleted).
--   * Every transaction dated from `from` onward is re-stamped by the cycle-key
--     trigger with the new payday; the budget rows of every key involved get
--     their spent_amount recomputed from the transactions.
CREATE OR REPLACE FUNCTION public.rekey_household_cycles(
    p_household_id uuid,
    p_old_payday integer,
    p_new_payday integer,
    p_as_of timestamptz DEFAULT now()
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_old record;
    v_new record;
    v_from date;
    v_from_ts timestamptz;
    v_keys text[];
    v_budgets_moved integer := 0;
    v_allowances_moved integer := 0;
    v_rekeyed integer := 0;
    v_new_month date;
BEGIN
    SELECT * INTO v_old FROM public.get_saudi_cycle_for_timestamp(p_as_of, COALESCE(p_old_payday, 27));
    SELECT * INTO v_new FROM public.get_saudi_cycle_for_timestamp(p_as_of, COALESCE(p_new_payday, 27));
    v_from := LEAST(v_old.cycle_start, v_new.cycle_start);
    v_from_ts := v_from::timestamp AT TIME ZONE 'Asia/Riyadh';
    v_new_month := to_date(v_new.cycle_key || '-01', 'YYYY-MM-DD');

    SELECT COALESCE(array_agg(DISTINCT t.cycle_key), ARRAY[]::text[]) INTO v_keys
    FROM public.transactions t
    WHERE t.household_id = p_household_id
      AND t.timestamp >= v_from_ts
      AND t.cycle_key IS NOT NULL;

    IF v_old.cycle_key IS DISTINCT FROM v_new.cycle_key THEN
        UPDATE public.budgets b
        SET cycle_key = v_new.cycle_key,
            month = v_new_month
        WHERE b.household_id = p_household_id
          AND b.cycle_key = v_old.cycle_key
          AND NOT EXISTS (
              SELECT 1 FROM public.budgets t
              WHERE t.household_id = b.household_id
                AND t.category_code = b.category_code
                AND t.id <> b.id
                AND (t.cycle_key = v_new.cycle_key OR t.month = v_new_month)
          );
        GET DIAGNOSTICS v_budgets_moved = ROW_COUNT;

        UPDATE public.member_allowances a
        SET cycle_key = v_new.cycle_key,
            updated_at = now()
        WHERE a.household_id = p_household_id
          AND a.cycle_key = v_old.cycle_key
          AND NOT EXISTS (
              SELECT 1 FROM public.member_allowances t
              WHERE t.household_id = a.household_id
                AND t.member_user_id = a.member_user_id
                AND t.cycle_key = v_new.cycle_key
          );
        GET DIAGNOSTICS v_allowances_moved = ROW_COUNT;
    END IF;

    -- trg_populate_transaction_cycle_key derives the key from households.payday_day.
    UPDATE public.transactions
    SET cycle_key = NULL
    WHERE household_id = p_household_id
      AND timestamp >= v_from_ts;
    GET DIAGNOSTICS v_rekeyed = ROW_COUNT;

    v_keys := v_keys
        || COALESCE((SELECT array_agg(DISTINCT t.cycle_key) FROM public.transactions t
                     WHERE t.household_id = p_household_id AND t.timestamp >= v_from_ts AND t.cycle_key IS NOT NULL),
                    ARRAY[]::text[])
        || ARRAY[v_old.cycle_key, v_new.cycle_key];
    PERFORM public.recompute_budget_spent(p_household_id, v_keys);

    RETURN jsonb_build_object(
        'household_id', p_household_id,
        'from', v_from,
        'old_cycle_key', v_old.cycle_key,
        'new_cycle_key', v_new.cycle_key,
        'transactions_rekeyed', v_rekeyed,
        'budgets_moved', v_budgets_moved,
        'allowances_moved', v_allowances_moved
    );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.rekey_household_cycles(uuid, integer, integer, timestamptz) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.rekey_cycles_on_payday_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM public.rekey_household_cycles(NEW.id, OLD.payday_day, NEW.payday_day, now());
    RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.rekey_cycles_on_payday_change() FROM PUBLIC, anon, authenticated;

-- Fires for the backend (service role, supabase_client.set_household_payday) and
-- for older app builds that update households.payday_day directly.
DROP TRIGGER IF EXISTS trg_rekey_cycles_on_payday_change ON public.households;
CREATE TRIGGER trg_rekey_cycles_on_payday_change
AFTER UPDATE OF payday_day ON public.households
FOR EACH ROW
WHEN (OLD.payday_day IS DISTINCT FROM NEW.payday_day)
EXECUTE FUNCTION public.rekey_cycles_on_payday_change();

-- 12. Post-checks ----------------------------------------------------------------------
DO $$
DECLARE
    v_n int;
BEGIN
    SELECT count(*) INTO v_n FROM public.household_memberships WHERE financial_role IS NULL;
    IF v_n > 0 THEN
        RAISE EXCEPTION 'post-check: % membership(s) without financial_role', v_n;
    END IF;

    SELECT count(*) INTO v_n
    FROM public.households h
    WHERE h.nafaqah_provider_user_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.household_memberships m
                      WHERE m.household_id = h.id AND m.user_id = h.nafaqah_provider_user_id
                        AND m.financial_role <> 'spouse');
    IF v_n > 0 THEN
        RAISE EXCEPTION 'post-check: % household(s) whose provider is not a non-spouse member', v_n;
    END IF;

    IF has_column_privilege('authenticated', 'public.households', 'nafaqah_provider_user_id', 'UPDATE')
       OR has_column_privilege('anon', 'public.households', 'nafaqah_provider_user_id', 'UPDATE')
       OR has_column_privilege('authenticated', 'public.household_memberships', 'financial_role', 'UPDATE')
       OR has_column_privilege('authenticated', 'public.household_memberships', 'financial_role', 'INSERT') THEN
        RAISE EXCEPTION 'post-check: clients can write the provider or a membership financial role';
    END IF;

    IF has_function_privilege('authenticated', 'public.nafaqah_husband_id(uuid)', 'EXECUTE')
       OR has_function_privilege('authenticated', 'public.nafaqah_is_spouse_member(uuid, uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.set_nafaqah_provider(uuid, uuid, uuid)', 'EXECUTE')
       OR has_function_privilege('authenticated', 'public.rekey_household_cycles(uuid, integer, integer, timestamptz)', 'EXECUTE') THEN
        RAISE EXCEPTION 'post-check: internal helpers became client-callable';
    END IF;

    IF EXISTS (SELECT 1 FROM pg_policies
               WHERE schemaname = 'public' AND tablename = 'household_invites' AND policyname = 'invites_select_household') THEN
        RAISE EXCEPTION 'post-check: members can still read invite codes';
    END IF;

    SELECT count(*) INTO v_n FROM public.households WHERE nafaqah_provider_user_id IS NOT NULL;
    RAISE NOTICE 'post-check: % household(s) have a Nafaqah provider', v_n;
END;
$$;

COMMIT;

-- Rollback (owner, SQL editor; only if this file must be undone; no data is lost
-- except the per-membership roles and the chosen providers):
--   BEGIN;
--   DROP TRIGGER IF EXISTS trg_rekey_cycles_on_payday_change ON public.households;
--   DROP TRIGGER IF EXISTS trg_wife_ledger_guard ON public.transactions;
--   DROP TRIGGER IF EXISTS trg_refuse_invite_claim_by_member ON public.household_invites;
--   DROP TRIGGER IF EXISTS trg_households_nafaqah_provider ON public.households;
--   DROP TRIGGER IF EXISTS trg_clear_nafaqah_provider ON public.household_memberships;
--   DROP TRIGGER IF EXISTS trg_membership_financial_role_cache ON public.household_memberships;
--   DROP TRIGGER IF EXISTS trg_membership_financial_role_rules ON public.household_memberships;
--   DROP POLICY IF EXISTS invites_select_admin ON public.household_invites;
--   CREATE POLICY "invites_select_household" ON public.household_invites FOR SELECT TO authenticated
--       USING (household_id = (SELECT public.get_auth_user_household_id()));
--   -- then re-run the function definitions of 20261020010000 (claim RPCs),
--   -- 20261020300000 + 20261020400000 (Nafaqah helpers, transfer_primary_admin,
--   -- get_household_members), 20261019030000 (switch / create), 20261018 +
--   -- 20261020070000 (sync trigger) and 20261019080000 + 20261019100000 (budget
--   -- triggers) before dropping the columns:
--   ALTER TABLE public.households DROP COLUMN IF EXISTS nafaqah_provider_user_id;
--   ALTER TABLE public.household_memberships DROP COLUMN IF EXISTS financial_role;
--   COMMIT;
