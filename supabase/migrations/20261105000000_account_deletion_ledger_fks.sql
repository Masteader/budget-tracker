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
-- 4. void_income_record: with a NULL user_id, `user_id <> caller` is NULL, the IF
--    chain does not raise, and any member could void a departed member's income.
--    Now IS DISTINCT FROM. Nothing else in the function changes.
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

CREATE OR REPLACE FUNCTION public.void_income_record(
    p_income_id UUID
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_uid UUID;
    v_caller_hh UUID;
    v_caller_role TEXT;
    v_income RECORD;
    v_acc RECORD;
    v_new_balance NUMERIC(14, 2);
    v_result jsonb;
BEGIN
    -- 1. Input parameter validation
    IF p_income_id IS NULL THEN
        RAISE EXCEPTION 'Income record ID is required' USING ERRCODE = '22023';
    END IF;

    -- 2. Authentication check
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    -- 3. Row lock on income_records to prevent concurrent voiding
    SELECT * INTO v_income
    FROM public.income_records
    WHERE id = p_income_id
    FOR UPDATE;

    IF v_income.id IS NULL THEN
        RAISE EXCEPTION 'Income record not found' USING ERRCODE = 'P0002';
    END IF;

    -- 4. Multi-tenancy check: caller household must match income record household
    v_caller_hh := public.get_auth_user_household_id();
    IF v_caller_hh IS NULL OR v_caller_hh IS DISTINCT FROM v_income.household_id THEN
        RAISE EXCEPTION 'Access denied: caller does not belong to the household of this income record' USING ERRCODE = '42501';
    END IF;

    -- 5. Row lock on target account
    SELECT * INTO v_acc
    FROM public.accounts
    WHERE id = v_income.account_id
    FOR UPDATE;

    IF v_acc.id IS NULL THEN
        RAISE EXCEPTION 'Target account not found' USING ERRCODE = 'P0002';
    END IF;

    -- Verify account belongs to same household
    IF v_acc.household_id <> v_income.household_id THEN
        RAISE EXCEPTION 'Corrupt ledger: target account belongs to a different household' USING ERRCODE = '42501';
    END IF;

    -- 6. Permission check:
    -- Caller must be:
    --   a) The user who logged the income, OR
    --   b) The account owner, OR
    --   c) A household admin/co-admin.
    -- A NULL creator (deleted member) matches nobody: IS DISTINCT FROM, never <>.
    v_caller_role := public.get_auth_user_role();
    IF v_income.user_id IS DISTINCT FROM v_caller_uid
       AND v_acc.owner_user_id IS DISTINCT FROM v_caller_uid
       AND (v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'co_admin')) THEN
        RAISE EXCEPTION 'Access denied: insufficient permissions to void this income record' USING ERRCODE = '42501';
    END IF;

    -- Non-shared account protection: non-admin cannot debit another user's personal account
    IF v_acc.is_shared_pool = false
       AND v_acc.owner_user_id IS DISTINCT FROM v_caller_uid
       AND (v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'co_admin')) THEN
        RAISE EXCEPTION 'Access denied: cannot void income from a personal account owned by another member' USING ERRCODE = '42501';
    END IF;

    -- 7. Atomically decrement account balance
    UPDATE public.accounts
    SET balance = balance - v_income.net_amount,
        updated_at = now()
    WHERE id = v_acc.id
    RETURNING balance INTO v_new_balance;

    -- 8. Delete the income record
    DELETE FROM public.income_records
    WHERE id = p_income_id;

    -- 9. Construct and return receipt payload
    SELECT jsonb_build_object(
        'success', true,
        'id', v_income.id,
        'income_id', v_income.id,
        'household_id', v_income.household_id,
        'account_id', v_income.account_id,
        'user_id', v_income.user_id,
        'cycle_key', v_income.cycle_key,
        'title', v_income.title,
        'net_amount', v_income.net_amount,
        'reverted_amount', v_income.net_amount,
        'new_balance', v_new_balance,
        'voided_at', now()
    ) INTO v_result;

    RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.void_income_record(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.void_income_record(UUID) TO authenticated, service_role;

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
