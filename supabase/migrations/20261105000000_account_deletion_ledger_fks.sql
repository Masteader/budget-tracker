-- ============================================================================
-- Migration: 20261105000000_account_deletion_ledger_fks.sql
-- Plan: docs/superpowers/plans/2026-11-05-account-deletion-corrected.md, Task 1
--
-- Deleting a member must not move money that belongs to the people who stay.
--
-- 1. income_records.user_id was ON DELETE CASCADE, and
--    trg_adjust_account_balance_on_income_change subtracts net_amount on delete,
--    so deleting anyone who recorded income into a shared pool lowered that pool.
--    Now nullable, ON DELETE SET NULL. The row and the balance both stay.
-- 2. account_transfers.user_id (CASCADE) and from_account_id / to_account_id
--    (RESTRICT) lost history or blocked the delete, depending on which RI trigger
--    fired first. All three are now nullable, ON DELETE SET NULL. Nothing derives a
--    balance from this table, so a NULL side moves nothing.
-- 3. handover_households_on_user_delete: income_records.account_id stays RESTRICT,
--    so income into an account about to cascade goes first; a transfer with both
--    sides on such accounts has nothing left to say and goes too; and a pool owned
--    by someone who already left the household is re-owned instead of cascading.
--
-- This file does not define void_income_record. Item 1 makes user_id nullable, and with a
-- NULL user_id the `user_id <> caller` of 20261102010000 is NULL, so the IF chain does not
-- raise and any member could void a departed member's income. The fix, IS DISTINCT FROM,
-- ships in 20261105000500, which also stops the double subtraction. That file goes to
-- production as a hotfix before this one, and production has no migration history, so a
-- definition here would bring the double subtraction back. Run 000500 first. Test 46 runs
-- the suite in that order.
--
-- Constraints are matched by column, so this does not depend on constraint names.
-- Out-of-band deletion of auth.users keeps today's handover and never deletes a
-- household.
-- ============================================================================

BEGIN;

DO $$
DECLARE
    v_target record;
    v_fk record;
BEGIN
    FOR v_target IN
        SELECT * FROM (VALUES
            ('public.income_records'::regclass,    'user_id'),
            ('public.account_transfers'::regclass, 'user_id'),
            ('public.account_transfers'::regclass, 'from_account_id'),
            ('public.account_transfers'::regclass, 'to_account_id')
        ) AS t(rel, col)
    LOOP
        FOR v_fk IN
            SELECT c.conname
            FROM pg_constraint c
            JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
            WHERE c.contype = 'f'
              AND c.conrelid = v_target.rel
              AND array_length(c.conkey, 1) = 1
              AND a.attname = v_target.col
        LOOP
            EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', v_target.rel, v_fk.conname);
        END LOOP;
        EXECUTE format('ALTER TABLE %s ALTER COLUMN %I DROP NOT NULL', v_target.rel, v_target.col);
    END LOOP;
END $$;

ALTER TABLE public.income_records
    ADD CONSTRAINT income_records_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.account_transfers
    ADD CONSTRAINT account_transfers_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.account_transfers
    ADD CONSTRAINT account_transfers_from_account_id_fkey
    FOREIGN KEY (from_account_id) REFERENCES public.accounts(id) ON DELETE SET NULL;
ALTER TABLE public.account_transfers
    ADD CONSTRAINT account_transfers_to_account_id_fkey
    FOREIGN KEY (to_account_id) REFERENCES public.accounts(id) ON DELETE SET NULL;

-- Same handover as before, then the ledger cleanup described in the header.
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

    -- A pool owned by someone who has already left: leave_household and remove_member
    -- do not re-own, so the loop above never sees it. Hand it to the household's admin.
    UPDATE public.accounts a
    SET owner_user_id = n.user_id,
        updated_at = now()
    FROM (
        SELECT DISTINCT ON (o.household_id) o.household_id, o.user_id
        FROM public.household_memberships o
        WHERE o.user_id <> OLD.id AND o.role = 'admin'
        ORDER BY o.household_id, o.created_at ASC, o.user_id ASC
    ) n
    WHERE a.household_id = n.household_id
      AND a.owner_user_id = OLD.id
      AND a.is_shared_pool = true;

    -- Whatever this user still owns now cascades. income_records.account_id is RESTRICT.
    DELETE FROM public.income_records i
    USING public.accounts a
    WHERE i.account_id = a.id
      AND a.owner_user_id = OLD.id;

    DELETE FROM public.account_transfers t
    USING public.accounts f, public.accounts d
    WHERE t.from_account_id = f.id
      AND t.to_account_id = d.id
      AND f.owner_user_id = OLD.id
      AND d.owner_user_id = OLD.id;

    RETURN OLD;
END;
$$;

-- Abort rather than continue on a database whose FKs ended up different.
DO $$
DECLARE
    v_got text;
BEGIN
    SELECT string_agg(c.conrelid::regclass::text || '.' || a.attname || ':' || c.confdeltype::text,
                      ',' ORDER BY c.conrelid::regclass::text, a.attname) INTO v_got
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
    WHERE c.contype = 'f'
      AND c.conrelid IN ('public.income_records'::regclass, 'public.account_transfers'::regclass)
      AND a.attname IN ('user_id', 'from_account_id', 'to_account_id');
    IF v_got IS DISTINCT FROM 'account_transfers.from_account_id:n,account_transfers.to_account_id:n,account_transfers.user_id:n,income_records.user_id:n' THEN
        RAISE EXCEPTION 'account deletion ledger FKs are not as required: %', v_got;
    END IF;
END $$;

COMMIT;
