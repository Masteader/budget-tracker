-- ----------------------------------------------------------------------------
-- Migration: 20261020090000_audit_sole_admin_account_deletion.sql
-- Audit DB-12 (Medium): deleting the auth user of a household's sole admin
--   (Supabase Auth admin API / in-app "delete my account") cascades
--   auth.users -> public.users -> household_memberships, where
--   check_last_admin_membership() raises "Cannot remove the sole admin while
--   other household members remain". The account can therefore never be
--   deleted (account-deletion obligations under PDPL / app-store policy).
--   The same cascade would delete every shared-pool account that admin created
--   (accounts.owner_user_id ON DELETE CASCADE), wiping the household's shared
--   funds and nulling account_id on its transactions.
-- Fix: BEFORE DELETE on public.users hands each household over first: if the
--   user is the only admin and other members remain, the longest-standing
--   member is promoted; shared-pool accounts the user owns are re-owned by an
--   admin of that household. Direct demotion/removal of a sole admin stays
--   blocked by check_last_admin_membership() (BUG-03 unchanged).
-- Proof test: supabase/tests/16_audit_account_deletion.sql
-- ----------------------------------------------------------------------------

BEGIN;

CREATE OR REPLACE FUNCTION public.handover_households_on_user_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_hh record;
    v_successor uuid;
    v_new_owner uuid;
BEGIN
    FOR v_hh IN
        SELECT m.household_id, m.role
        FROM public.household_memberships m
        WHERE m.user_id = OLD.id
    LOOP
        IF v_hh.role = 'admin'
           AND NOT EXISTS (
               SELECT 1 FROM public.household_memberships o
               WHERE o.household_id = v_hh.household_id
                 AND o.user_id <> OLD.id
                 AND o.role = 'admin'
           ) THEN
            SELECT o.user_id INTO v_successor
            FROM public.household_memberships o
            WHERE o.household_id = v_hh.household_id
              AND o.user_id <> OLD.id
            ORDER BY o.created_at ASC, o.user_id ASC
            LIMIT 1;

            IF v_successor IS NOT NULL THEN
                UPDATE public.household_memberships
                SET role = 'admin'
                WHERE household_id = v_hh.household_id
                  AND user_id = v_successor;

                UPDATE public.users
                SET role = 'admin'
                WHERE id = v_successor
                  AND household_id = v_hh.household_id;
            END IF;
        END IF;

        SELECT o.user_id INTO v_new_owner
        FROM public.household_memberships o
        WHERE o.household_id = v_hh.household_id
          AND o.user_id <> OLD.id
          AND o.role = 'admin'
        ORDER BY o.created_at ASC, o.user_id ASC
        LIMIT 1;

        IF v_new_owner IS NOT NULL THEN
            UPDATE public.accounts
            SET owner_user_id = v_new_owner,
                updated_at = now()
            WHERE household_id = v_hh.household_id
              AND owner_user_id = OLD.id
              AND is_shared_pool = true;
        END IF;
    END LOOP;

    RETURN OLD;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.handover_households_on_user_delete() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_handover_households_on_user_delete ON public.users;
CREATE TRIGGER trg_handover_households_on_user_delete
BEFORE DELETE ON public.users
FOR EACH ROW EXECUTE FUNCTION public.handover_households_on_user_delete();

COMMIT;
