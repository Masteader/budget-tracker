-- ============================================================================
-- Test Suite 07: Round 6 Hardening Proof Tests (SEC-08)
-- Verifies column-level privilege lock, transaction account authorization,
-- ledger immutability, financial RPC NULL safety, trigger revokes,
-- atomic invite claim, category taxonomy validation, and invite code privacy.
-- ============================================================================

\set ON_ERROR_STOP on

DO $$
DECLARE
    v_victim_hh UUID := '6086befc-0000-0000-0000-000000000001';
    v_attacker_hh UUID := '7086befc-0000-0000-0000-000000000002';
    v_admin_uid UUID := '11111111-0000-0000-0000-000000000001';
    v_member_uid UUID := '22222222-0000-0000-0000-000000000002';
    v_attacker_uid UUID := '33333333-0000-0000-0000-000000000003';
    v_account_victim_personal UUID := 'aaaa0000-0000-0000-0000-000000000001';
    v_account_victim_shared UUID := 'aaaa0000-0000-0000-0000-000000000002';
    v_account_attacker UUID := 'bbbb0000-0000-0000-0000-000000000001';
BEGIN
    -- Setup baseline auth users
    INSERT INTO auth.users (id, email) VALUES
        (v_admin_uid, 'admin@example.com'),
        (v_member_uid, 'member@example.com'),
        (v_attacker_uid, 'attacker@example.com')
    ON CONFLICT (id) DO NOTHING;

    -- Setup households
    INSERT INTO public.households (id, name, invite_code) VALUES
        (v_victim_hh, 'Victim Household', 'VICTIM16CHARCODE'),
        (v_attacker_hh, 'Attacker Household', 'ATTACK16CHARCODE')
    ON CONFLICT (id) DO UPDATE SET invite_code = EXCLUDED.invite_code;

    -- Setup users
    INSERT INTO public.users (id, household_id, role, display_name) VALUES
        (v_admin_uid, v_victim_hh, 'admin', 'Victim Admin'),
        (v_member_uid, v_victim_hh, 'member', 'Victim Member'),
        (v_attacker_uid, v_attacker_hh, 'member', 'Attacker Member')
    ON CONFLICT (id) DO UPDATE SET household_id = EXCLUDED.household_id, role = EXCLUDED.role;

    -- Setup memberships
    INSERT INTO public.household_memberships (household_id, user_id, role, is_default) VALUES
        (v_victim_hh, v_admin_uid, 'admin', true),
        (v_victim_hh, v_member_uid, 'member', false),
        (v_attacker_hh, v_attacker_uid, 'member', true)
    ON CONFLICT (household_id, user_id) DO UPDATE SET role = EXCLUDED.role;

    -- Setup accounts
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool) VALUES
        (v_account_victim_personal, v_victim_hh, v_admin_uid, 'Admin Checking', 'bank', 5000.00, false),
        (v_account_victim_shared, v_victim_hh, v_admin_uid, 'Household Pool', 'shared_pool', 10000.00, true),
        (v_account_attacker, v_attacker_hh, v_attacker_uid, 'Attacker Checking', 'bank', 500.00, false)
    ON CONFLICT (id) DO UPDATE SET balance = EXCLUDED.balance, household_id = EXCLUDED.household_id, is_shared_pool = EXCLUDED.is_shared_pool;

    -- Setup cost control codes
    IF NOT EXISTS (SELECT 1 FROM public.cost_control_codes WHERE code = 'OPEX-GROCERY' AND household_id IS NULL) THEN
        INSERT INTO public.cost_control_codes (code, category, keywords, household_id, is_system) VALUES
            ('OPEX-GROCERY', 'Grocery', '{}', NULL, true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.cost_control_codes WHERE code = 'OPEX-CUSTOM-VICTIM' AND household_id = v_victim_hh) THEN
        INSERT INTO public.cost_control_codes (code, category, keywords, household_id, is_system) VALUES
            ('OPEX-CUSTOM-VICTIM', 'Custom Victim', '{}', v_victim_hh, false);
    END IF;

    RAISE NOTICE 'Round 6 test fixtures initialized successfully.';
END $$;


-- ============================================================================
-- TEST 1: Column-level privilege lock on public.accounts
-- Authenticated users must NOT be able to directly UPDATE balance, household_id,
-- owner_user_id, or is_shared_pool.
-- ============================================================================
DO $$
DECLARE
    v_err text;
BEGIN
    -- Simulate authenticated member attempting direct balance update
    SET LOCAL ROLE authenticated;
    SET LOCAL "request.jwt.claims" = '{"sub": "22222222-0000-0000-0000-000000000002", "role": "authenticated"}';

    BEGIN
        UPDATE public.accounts
        SET balance = 999999.00
        WHERE id = 'aaaa0000-0000-0000-0000-000000000002';
        RAISE EXCEPTION 'VULNERABILITY: Authenticated user was able to directly update accounts.balance!';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASSED: Direct UPDATE on accounts.balance blocked by column privileges.';
    END;
END $$;
\set ON_ERROR_STOP on


-- ============================================================================
-- TEST 2: Account Transfers Ledger Immutability
-- Direct client INSERT on public.account_transfers must be blocked.
-- ============================================================================
DO $$
BEGIN
    SET LOCAL ROLE authenticated;
    SET LOCAL "request.jwt.claims" = '{"sub": "22222222-0000-0000-0000-000000000002", "role": "authenticated"}';

    BEGIN
        INSERT INTO public.account_transfers (
            household_id, user_id, from_account_id, to_account_id, amount
        ) VALUES (
            '6086befc-0000-0000-0000-000000000001',
            '22222222-0000-0000-0000-000000000002',
            'aaaa0000-0000-0000-0000-000000000001',
            'aaaa0000-0000-0000-0000-000000000002',
            500.00
        );
        RAISE EXCEPTION 'VULNERABILITY: Direct INSERT on account_transfers allowed for authenticated user!';
    EXCEPTION WHEN insufficient_privilege OR check_violation THEN
        RAISE NOTICE 'PASSED: Direct INSERT on account_transfers blocked.';
    END;
END $$;
\set ON_ERROR_STOP on


-- ============================================================================
-- TEST 3: Income Records Ledger Immutability
-- Direct client UPDATE and DELETE on public.income_records must be blocked.
-- ============================================================================
DO $$
DECLARE
    v_inc_id UUID;
    v_rows int;
BEGIN
    -- Seed an income record via postgres
    INSERT INTO public.income_records (
        id, household_id, user_id, account_id, cycle_key, source_type, title, base_amount, net_amount
    ) VALUES (
        gen_random_uuid(),
        '6086befc-0000-0000-0000-000000000001',
        '22222222-0000-0000-0000-000000000002',
        'aaaa0000-0000-0000-0000-000000000002',
        '2026-11',
        'salary',
        'Test Salary',
        5000.00,
        5000.00
    ) RETURNING id INTO v_inc_id;

    -- Authenticated user attempts DELETE
    SET LOCAL ROLE authenticated;
    SET LOCAL "request.jwt.claims" = '{"sub": "22222222-0000-0000-0000-000000000002", "role": "authenticated"}';

    -- Since audit DB-07 the privilege itself is revoked (permission denied == 0 rows)
    BEGIN
        DELETE FROM public.income_records WHERE id = v_inc_id;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
    EXCEPTION WHEN insufficient_privilege THEN
        v_rows := 0;
    END;
    IF v_rows > 0 THEN
        RAISE EXCEPTION 'VULNERABILITY: Client was able to DELETE income_record!';
    ELSE
        RAISE NOTICE 'PASSED: Client DELETE on income_records blocked (0 rows affected).';
    END IF;

    BEGIN
        UPDATE public.income_records SET net_amount = 9999.00 WHERE id = v_inc_id;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
    EXCEPTION WHEN insufficient_privilege THEN
        v_rows := 0;
    END;
    IF v_rows > 0 THEN
        RAISE EXCEPTION 'VULNERABILITY: Client was able to UPDATE income_record!';
    ELSE
        RAISE NOTICE 'PASSED: Client UPDATE on income_records blocked (0 rows affected).';
    END IF;
END $$;
\set ON_ERROR_STOP on


-- ============================================================================
-- TEST 4: Transactions RLS & Account Authorization
-- Transactions referencing an account owned by another user (not shared) or
-- belonging to another household must be rejected.
-- ============================================================================
DO $$
DECLARE
    v_vulnerable boolean := false;
BEGIN
    -- Member attempts transaction debiting Admin's personal account
    SET LOCAL ROLE authenticated;
    SET LOCAL "request.jwt.claims" = '{"sub": "22222222-0000-0000-0000-000000000002", "role": "authenticated"}';

    BEGIN
        INSERT INTO public.transactions (
            household_id, category_code, amount, account_id, merchant
        ) VALUES (
            '6086befc-0000-0000-0000-000000000001',
            'OPEX-GROCERY',
            100.00,
            'aaaa0000-0000-0000-0000-000000000001', -- Admin personal account
            'Unauthorized Debit'
        );
        v_vulnerable := true;
    EXCEPTION WHEN insufficient_privilege OR check_violation OR integrity_constraint_violation THEN
        RAISE NOTICE 'PASSED: Member blocked from using another user personal account in transaction.';
    END;

    IF v_vulnerable THEN
        RAISE EXCEPTION 'VULNERABILITY: Member debited personal account owned by admin!';
    END IF;
END $$;
\set ON_ERROR_STOP on


-- ============================================================================
-- TEST 5: NULL Comparison Bug in Financial RPCs
-- transfer_between_accounts & record_income with NULL household_id
-- ============================================================================
DO $$
DECLARE
    v_state text;
BEGIN
    SET LOCAL ROLE authenticated;
    SET LOCAL "request.jwt.claims" = '{"sub": "11111111-0000-0000-0000-000000000001", "role": "authenticated"}';

    v_state := 'accepted';
    BEGIN
        PERFORM public.transfer_between_accounts(
            NULL,
            'aaaa0000-0000-0000-0000-000000000001',
            'aaaa0000-0000-0000-0000-000000000002',
            100.00
        );
    EXCEPTION WHEN OTHERS THEN
        v_state := SQLSTATE;
    END;
    IF v_state IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION 'VULNERABILITY: transfer_between_accounts with NULL household_id was not rejected with 42501 (got %)', v_state;
    END IF;
    RAISE NOTICE 'PASSED: transfer_between_accounts rejected NULL household_id with 42501.';

    v_state := 'accepted';
    BEGIN
        PERFORM public.record_income(
            NULL,
            'aaaa0000-0000-0000-0000-000000000001',
            '2026-11',
            'salary',
            'Test',
            1000.00
        );
    EXCEPTION WHEN OTHERS THEN
        v_state := SQLSTATE;
    END;
    IF v_state IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION 'VULNERABILITY: record_income with NULL household_id was not rejected with 42501 (got %)', v_state;
    END IF;
    RAISE NOTICE 'PASSED: record_income rejected NULL household_id with 42501.';
END $$;
\set ON_ERROR_STOP on


-- ============================================================================
-- TEST 6: Function Privileges & Trigger Function Lockdown
-- consume_quota, check_quota_status, and trigger functions must NOT be callable
-- by authenticated or anon.
-- ============================================================================
DO $$
BEGIN
    SET LOCAL ROLE authenticated;
    SET LOCAL "request.jwt.claims" = '{"sub": "22222222-0000-0000-0000-000000000002", "role": "authenticated"}';

    BEGIN
        PERFORM public.consume_quota('22222222-0000-0000-0000-000000000002', 'chat', 10, 600);
        RAISE EXCEPTION 'VULNERABILITY: Authenticated user was able to execute consume_quota directly!';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASSED: Authenticated execution of consume_quota blocked.';
    END;

    BEGIN
        PERFORM public.populate_transaction_cycle_key();
        RAISE EXCEPTION 'VULNERABILITY: Authenticated user was able to execute populate_transaction_cycle_key directly!';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASSED: Authenticated execution of trigger function blocked.';
    END;
END $$;
\set ON_ERROR_STOP on


-- ============================================================================
-- TEST 7: Category Code Taxonomy Validation Trigger
-- Inserting a transaction or budget with a category code not belonging to the
-- household or global taxonomy must be rejected.
-- ============================================================================
DO $$
DECLARE
    v_vulnerable boolean := false;
BEGIN
    SET LOCAL ROLE authenticated;
    SET LOCAL "request.jwt.claims" = '{"sub": "33333333-0000-0000-0000-000000000003", "role": "authenticated"}';

    BEGIN
        INSERT INTO public.transactions (
            household_id, category_code, amount, merchant
        ) VALUES (
            '7086befc-0000-0000-0000-000000000002', -- Attacker household
            'OPEX-CUSTOM-VICTIM', -- Belongs to Victim household!
            50.00,
            'Cross-Household Category Test'
        );
        v_vulnerable := true;
    EXCEPTION WHEN foreign_key_violation OR integrity_constraint_violation OR check_violation THEN
        RAISE NOTICE 'PASSED: Cross-household custom category code rejected by validation trigger.';
    END;

    IF v_vulnerable THEN
        RAISE EXCEPTION 'VULNERABILITY: Transaction accepted category code belonging to another household!';
    END IF;
END $$;
\set ON_ERROR_STOP on


-- ============================================================================
-- TEST 8: Invite Code Privacy in get_user_households
-- Non-admin members must see NULL for household.invite_code.
-- ============================================================================
DO $$
DECLARE
    v_code text;
BEGIN
    SET LOCAL ROLE authenticated;
    SET LOCAL "request.jwt.claims" = '{"sub": "22222222-0000-0000-0000-000000000002", "role": "authenticated"}';

    SELECT invite_code INTO v_code
    FROM public.get_user_households()
    WHERE household_id = '6086befc-0000-0000-0000-000000000001';

    IF v_code IS NOT NULL THEN
        RAISE EXCEPTION 'VULNERABILITY: Non-admin member can see household invite_code: %', v_code;
    ELSE
        RAISE NOTICE 'PASSED: Non-admin member sees NULL for household invite_code.';
    END IF;
END $$;


-- ============================================================================
-- TEST 9: Account Hijacking Prevention in claim_household_role_invite
-- Authenticated caller passing a different p_user_id must be rejected with 42501.
-- ============================================================================
DO $$
DECLARE
    v_code text := 'HIJACKTESTCODE01';
BEGIN
    INSERT INTO public.household_invites (household_id, invite_code, role, expires_at)
    VALUES ('6086befc-0000-0000-0000-000000000001', v_code, 'peer', now() + interval '1 day')
    ON CONFLICT (invite_code) DO UPDATE SET used_by = NULL, expires_at = now() + interval '1 day';

    -- Attacker attempts to claim invite on behalf of victim
    SET LOCAL ROLE authenticated;
    SET LOCAL "request.jwt.claims" = '{"sub": "33333333-0000-0000-0000-000000000003", "role": "authenticated"}';

    BEGIN
        PERFORM public.claim_household_role_invite(
            p_invite_code := v_code,
            p_user_id := '22222222-0000-0000-0000-000000000002' -- Target victim UID
        );
        RAISE EXCEPTION 'VULNERABILITY: Authenticated user was able to claim invite on behalf of another user!';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASSED: claim_household_role_invite rejected foreign p_user_id with 42501.';
    END;
END $$;
\set ON_ERROR_STOP on


-- ============================================================================
-- TEST 10: Targeted Invite Idempotency & Second-Claim Rejection
-- Calling claim_household_role_invite followed by join_household_by_code as the
-- same user succeeds; a second user calling join_household_by_code is rejected.
-- ============================================================================
DO $$
DECLARE
    v_code text := 'DOUBLECLAIMTEST1';
    v_res jsonb;
    v_user_a uuid := '22222222-0000-0000-0000-000000000002';
    v_user_b uuid := '33333333-0000-0000-0000-000000000003';
BEGIN
    INSERT INTO public.household_invites (household_id, invite_code, role, expires_at)
    VALUES ('6086befc-0000-0000-0000-000000000001', v_code, 'peer', now() + interval '1 day')
    ON CONFLICT (invite_code) DO UPDATE SET used_by = NULL, expires_at = now() + interval '1 day';

    -- 1. User A claims invite via claim_household_role_invite
    SET LOCAL ROLE authenticated;
    SET LOCAL "request.jwt.claims" = '{"sub": "22222222-0000-0000-0000-000000000002", "role": "authenticated"}';

    v_res := public.claim_household_role_invite(v_code);
    IF (v_res->>'success')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'claim_household_role_invite failed for User A: %', v_res;
    END IF;

    -- User A calls join_household_by_code (idempotent double-claim)
    v_res := public.join_household_by_code(v_code);
    IF v_res ? 'error' THEN
        RAISE EXCEPTION 'Idempotent join_household_by_code failed for User A: %', v_res;
    ELSE
        RAISE NOTICE 'PASSED: Idempotent join_household_by_code succeeded for same user.';
    END IF;

    -- 2. User B attempts to call join_household_by_code with User A code
    SET LOCAL "request.jwt.claims" = '{"sub": "33333333-0000-0000-0000-000000000003", "role": "authenticated"}';
    v_res := public.join_household_by_code(v_code);
    IF v_res->>'error' = 'Invite code has already been used' THEN
        RAISE NOTICE 'PASSED: Second user calling join_household_by_code with used code rejected.';
    ELSE
        RAISE EXCEPTION 'VULNERABILITY: User B was able to use already-claimed invite code: %', v_res;
    END IF;
END $$;
\set ON_ERROR_STOP on


-- ============================================================================
-- TEST 11: reconcile_account_balance Authorization
-- Verifies reconcile_account_balance succeeds for authorized owner/admin and
-- rejects unauthorized members with 42501.
-- ============================================================================
DO $$
DECLARE
    v_res jsonb;
    v_victim_personal uuid := 'aaaa0000-0000-0000-0000-000000000001'; -- Admin checking
    v_victim_shared uuid := 'aaaa0000-0000-0000-0000-000000000002'; -- Household Pool
BEGIN
    -- 1. Regular member attempts to reconcile Admin's personal account
    SET LOCAL ROLE authenticated;
    SET LOCAL "request.jwt.claims" = '{"sub": "22222222-0000-0000-0000-000000000002", "role": "authenticated"}';

    BEGIN
        PERFORM public.reconcile_account_balance(v_victim_personal, 12345.00);
        RAISE EXCEPTION 'VULNERABILITY: Non-owner member was able to reconcile another personal account!';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASSED: Non-owner member blocked from reconciling personal account with 42501.';
    END;

    -- 2. Regular member attempts to reconcile shared pool account
    BEGIN
        PERFORM public.reconcile_account_balance(v_victim_shared, 54321.00);
        RAISE EXCEPTION 'VULNERABILITY: Non-admin member was able to reconcile shared pool account!';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASSED: Non-admin member blocked from reconciling shared pool account with 42501.';
    END;

    -- 3. Admin successfully reconciles shared pool account
    SET LOCAL "request.jwt.claims" = '{"sub": "11111111-0000-0000-0000-000000000001", "role": "authenticated"}';
    v_res := public.reconcile_account_balance(v_victim_shared, 15000.00);
    IF (v_res->>'success')::boolean IS TRUE THEN
        RAISE NOTICE 'PASSED: Household admin successfully reconciled shared pool balance.';
    ELSE
        RAISE EXCEPTION 'Household admin failed to reconcile shared balance: %', v_res;
    END IF;

    -- 4. Admin successfully reconciles own personal account
    v_res := public.reconcile_account_balance(v_victim_personal, 6000.00);
    IF (v_res->>'success')::boolean IS TRUE THEN
        RAISE NOTICE 'PASSED: Account owner successfully reconciled personal balance.';
    ELSE
        RAISE EXCEPTION 'Account owner failed to reconcile personal balance: %', v_res;
    END IF;
END $$;
\set ON_ERROR_STOP on

