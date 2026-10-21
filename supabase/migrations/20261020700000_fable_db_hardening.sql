-- ----------------------------------------------------------------------------
-- Migration: 20261020700000_fable_db_hardening.sql
-- Independent (Fable) review, docs/review/audit/fable_review.md section B:
-- FABLE-DB-02, -04, -05, -06, -07, -08, -09. (DB-01 and DB-03 are fixed
-- separately, together with the invite-claim / roles redesign.)
--
-- FABLE-DB-02 (Medium, confirmed on live): household_invites.created_by and
--   .used_by reference public.users with ON DELETE NO ACTION (the SEC-01
--   "ADD COLUMN IF NOT EXISTS ... ON DELETE SET NULL" was a no-op because the
--   columns already existed), so deleting the account of anyone who ever
--   created or claimed an invite fails with a FK violation.
--   Fix:
--     created_by -> ON DELETE SET NULL: the invite (open or used) belongs to the
--       household, not to the admin who issued it; the household survives the
--       admin's departure (primary-admin handover), so its invites stay.
--     used_by    -> ON DELETE CASCADE: a used invite is deleted with its
--       claimer. SET NULL is deliberately NOT used: used_by IS NULL is what
--       makes an invite claimable (claim_household_role_invite,
--       join_household_by_code, ai_service inspect_household_role_invite), so
--       SET NULL would silently re-open a spent spouse/provider invite for
--       anyone holding the code. Nothing references household_invites (no FK
--       points at it) and nothing reads a used invite afterwards: the claimer's
--       membership and the manual-member link (household_dependents
--       .linked_user_id, already ON DELETE SET NULL) are separate rows, and an
--       admin can issue a fresh invite for the unlinked manual member.
--   The constraints are matched by column (any name) so this is idempotent and
--   independent of the constraint names on the target database.
--
-- FABLE-DB-04 (Low): reallocate_budget accepted callers with neither a JWT
--   subject nor a JWT role (auth.uid() and auth.role() both NULL). It now fails
--   closed unless the caller is the service role (ai_service) or an
--   authenticated user with a subject (who must still be an admin of the
--   household owning both rows). Body otherwise unchanged from 20261020030000.
--
-- FABLE-DB-05 (Low): nafaqah_current_cycle_key(uuid) (any household's payday
--   bracket) and generate_secure_invite_code() stay EXECUTE-able by
--   authenticated. Revoked from PUBLIC, anon, authenticated; service_role keeps
--   them. Internal callers are SECURITY DEFINER functions owned by the same
--   owner (get_member_allowance_status, set_member_allowance) and keep working;
--   generate_secure_invite_code has no caller. No RLS policy, view, column
--   default or client (.rpc in ai_service / flutter_app / web_app, this branch
--   and origin/main) references either; the guard in section 7 re-checks.
--
-- FABLE-DB-06 (Low): the households UPDATE grant (built in 20261020400000
--   from every column but owner_user_id) covers id, created_at, invite_code
--   (join-code existence oracle via the UNIQUE violation, weak admin-chosen
--   codes) and the rollover ledger (accumulated_savings, last_rollover_*).
--   Now: UPDATE (name, payday_day, monthly_income, rollover_rule) only. RLS
--   (households_update_admin) still restricts the rows to admins of their own
--   active household.
--   Client writes to public.households (user JWT), all within the new list:
--     deployed app, origin/main flutter_app/lib/screens/settings/ingestion_settings_screen.dart
--       :225 update({'payday_day'}), :250 update({'monthly_income'}),
--       :275 update({'rollover_rule'})
--     this branch, flutter_app/lib/screens/settings/ingestion_settings_screen.dart
--       :235 _confirmAndMirror(... update(column)) with column = {'payday_day'} (:253),
--       {'monthly_income'} (:279), {'rollover_rule'} (:304)
--     name: no client write today; kept per the review's fix direction.
--   invite_code / rollover ledger / owner_user_id are written only by SECURITY
--   DEFINER RPCs and ai_service (service role), which are unaffected. No client
--   inserts into households (create_household RPC).
--
-- FABLE-DB-07 (Low): any member could re-point household_dependents
--   .linked_user_id (the manual member <-> real user link that the targeted
--   invite claim sets) to any user. Client privileges become:
--     INSERT (id, household_id, name, avatar_icon, relationship, monthly_allowance, created_at)
--     UPDATE (name, avatar_icon, relationship, monthly_allowance)
--   i.e. never linked_user_id (set only by claim_household_role_invite, a
--   SECURITY DEFINER RPC), and no re-keying of id/household_id/created_at.
--   Client writes to household_dependents: none, in either app version
--   (git grep of flutter_app/lib and web_app/src on this branch and
--   origin/main: no from('household_dependents') write; manual members are
--   managed through ai_service with the service role).
--
-- FABLE-DB-08 (Low): Supabase's default grants left TRUNCATE (ignores RLS),
--   TRIGGER and REFERENCES on public tables to anon/authenticated, and
--   INSERT/UPDATE/DELETE to anon. None is reachable through PostgREST (it never
--   issues TRUNCATE/CREATE TRIGGER, and no RLS policy targets anon or PUBLIC),
--   so nothing that works today stops working. Revoked on every table of the
--   public schema (including tables that exist only on live, e.g.
--   budgets_spent_backup_20261019), plus MAINTAIN (LOCK TABLE / VACUUM) on
--   PostgreSQL 17+. service_role is not touched. anon keeps SELECT where it
--   has it (RLS returns nothing without a policy).
--
-- FABLE-DB-09 (Low, suspected -> confirmed): the users INSERT privilege was
--   table-wide, so it covered financial_role (FR-B-04 only revoked UPDATE).
--   The users_insert_own policy pins id = auth.uid(), household_id IS NULL and
--   role = 'member', but not financial_role. Now column-level:
--     INSERT (id, household_id, display_name, role, payday_day, created_at)
--   (household_id/role stay listed so a client sending the policy's own safe
--   values explicitly keeps working.) Rows are normally created by
--   handle_new_auth_user() (SECURITY DEFINER trigger on auth.users); no client
--   inserts into public.users in either app version (git grep, as above: only
--   selects of users in flutter_app/lib). anon loses INSERT/DELETE (section 6).
--
-- RLS: policies run as the invoking role, so a revoked EXECUTE would break a
--   policy that calls the function; none of the revoked functions appears in
--   any policy (checked by the guard in section 7).
--
-- Live safety: idempotent (DROP/ADD constraint by column, CREATE OR REPLACE,
--   REVOKE/GRANT), one transaction, no row is changed or deleted (adding the FKs
--   re-validates the existing rows, which already satisfy the same reference).
--   The final guard verifies the resulting privileges/FKs and aborts (rolling
--   everything back) if anything differs, e.g. a grant made by another grantor.
-- Proof tests: supabase/tests/23_fable_db_hardening.sql,
--   supabase/tests/16_audit_account_deletion.sql (invite creator / claimer).
-- ----------------------------------------------------------------------------

BEGIN;

-- 1. FABLE-DB-02: invite creator / claimer FKs ------------------------------------
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT c.conname
        FROM pg_constraint c
        WHERE c.conrelid = 'public.household_invites'::regclass
          AND c.contype = 'f'
          AND array_length(c.conkey, 1) = 1
          AND (SELECT a.attname FROM pg_attribute a
               WHERE a.attrelid = c.conrelid AND a.attnum = c.conkey[1]) IN ('created_by', 'used_by')
    LOOP
        EXECUTE format('ALTER TABLE public.household_invites DROP CONSTRAINT %I', r.conname);
    END LOOP;
END $$;

ALTER TABLE public.household_invites
    ADD CONSTRAINT household_invites_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.household_invites
    ADD CONSTRAINT household_invites_used_by_fkey
    FOREIGN KEY (used_by) REFERENCES public.users(id) ON DELETE CASCADE;

-- 2. FABLE-DB-04: reallocate_budget fails closed -----------------------------------
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
    -- Only the service role (ai_service) or an authenticated user with a JWT
    -- subject; no claims at all (or any other role without a subject) is refused.
    IF v_uid IS NULL AND v_jwt_role IS DISTINCT FROM 'service_role' THEN
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

-- 3. FABLE-DB-05: internal helpers are not client RPCs -----------------------------
DO $$
DECLARE
    v_fn text;
BEGIN
    FOREACH v_fn IN ARRAY ARRAY[
        'public.nafaqah_current_cycle_key(uuid)',
        'public.generate_secure_invite_code()'
    ]
    LOOP
        IF to_regprocedure(v_fn) IS NOT NULL THEN
            EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', v_fn);
            EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', v_fn);
        END IF;
    END LOOP;
END $$;

-- 4. FABLE-DB-06: households client-updatable columns ------------------------------
-- (REVOKE of the table privilege also revokes every column privilege.)
REVOKE UPDATE ON public.households FROM PUBLIC, anon, authenticated;
GRANT UPDATE (name, payday_day, monthly_income, rollover_rule) ON public.households TO authenticated;

-- 5. FABLE-DB-07 / FABLE-DB-09: column-level INSERT/UPDATE --------------------------
REVOKE INSERT, UPDATE ON public.household_dependents FROM PUBLIC, anon, authenticated;
GRANT INSERT (id, household_id, name, avatar_icon, relationship, monthly_allowance, created_at)
    ON public.household_dependents TO authenticated;
GRANT UPDATE (name, avatar_icon, relationship, monthly_allowance)
    ON public.household_dependents TO authenticated;

REVOKE INSERT ON public.users FROM PUBLIC, anon, authenticated;
GRANT INSERT (id, household_id, display_name, role, payday_day, created_at)
    ON public.users TO authenticated;

-- 6. FABLE-DB-08: privileges PostgREST never needs ---------------------------------
DO $$
DECLARE
    r record;
    v_pg17 boolean := current_setting('server_version_num')::int >= 170000;
BEGIN
    FOR r IN
        SELECT c.oid::regclass AS tbl
        FROM pg_class c
        WHERE c.relnamespace = 'public'::regnamespace
          AND c.relkind IN ('r', 'p')
          AND NOT EXISTS (SELECT 1 FROM pg_depend d
                          WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype = 'e')
    LOOP
        EXECUTE format('REVOKE TRUNCATE, TRIGGER, REFERENCES ON TABLE %s FROM PUBLIC, anon, authenticated', r.tbl);
        EXECUTE format('REVOKE INSERT, UPDATE, DELETE ON TABLE %s FROM PUBLIC, anon', r.tbl);
        IF v_pg17 THEN
            EXECUTE format('REVOKE MAINTAIN ON TABLE %s FROM PUBLIC, anon, authenticated', r.tbl);
        END IF;
    END LOOP;
END $$;

-- 7. Guard: verify the result on the target database; abort otherwise ---------------
DO $$
DECLARE
    v_bad text;
    v_cols text;
BEGIN
    -- DB-02
    IF (SELECT string_agg(a.attname || ':' || c.confdeltype::text, ',' ORDER BY a.attname)
        FROM pg_constraint c
        JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
        WHERE c.conrelid = 'public.household_invites'::regclass AND c.contype = 'f'
          AND a.attname IN ('created_by', 'used_by')) IS DISTINCT FROM 'created_by:n,used_by:c' THEN
        RAISE EXCEPTION 'fable_db_hardening guard: household_invites created_by/used_by FKs not as expected';
    END IF;

    -- DB-05: no client EXECUTE, and no policy relies on the helpers
    IF has_function_privilege('authenticated', 'public.nafaqah_current_cycle_key(uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.nafaqah_current_cycle_key(uuid)', 'EXECUTE')
       OR (to_regprocedure('public.generate_secure_invite_code()') IS NOT NULL
           AND (has_function_privilege('authenticated', 'public.generate_secure_invite_code()', 'EXECUTE')
                OR has_function_privilege('anon', 'public.generate_secure_invite_code()', 'EXECUTE'))) THEN
        RAISE EXCEPTION 'fable_db_hardening guard: helper still client-executable';
    END IF;
    SELECT string_agg(schemaname || '.' || tablename || '.' || policyname, ', ') INTO v_bad
    FROM pg_policies
    WHERE coalesce(qual, '') || coalesce(with_check, '') ~* '(nafaqah_current_cycle_key|generate_secure_invite_code)';
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'fable_db_hardening guard: policies call a revoked helper: %', v_bad;
    END IF;

    -- DB-06 / DB-07 / DB-09: exact client column lists
    SELECT string_agg(a.attname, ',' ORDER BY a.attname) INTO v_cols
    FROM pg_attribute a
    WHERE a.attrelid = 'public.households'::regclass AND a.attnum > 0 AND NOT a.attisdropped
      AND has_column_privilege('authenticated', a.attrelid, a.attnum, 'UPDATE');
    IF v_cols IS DISTINCT FROM 'monthly_income,name,payday_day,rollover_rule' THEN
        RAISE EXCEPTION 'fable_db_hardening guard: households UPDATE columns are %', v_cols;
    END IF;
    SELECT string_agg(a.attname, ',' ORDER BY a.attname) INTO v_cols
    FROM pg_attribute a
    WHERE a.attrelid = 'public.household_dependents'::regclass AND a.attnum > 0 AND NOT a.attisdropped
      AND has_column_privilege('authenticated', a.attrelid, a.attnum, 'UPDATE');
    IF v_cols IS DISTINCT FROM 'avatar_icon,monthly_allowance,name,relationship' THEN
        RAISE EXCEPTION 'fable_db_hardening guard: household_dependents UPDATE columns are %', v_cols;
    END IF;
    IF has_column_privilege('authenticated', 'public.household_dependents', 'linked_user_id', 'INSERT')
       OR has_column_privilege('authenticated', 'public.users', 'financial_role', 'INSERT')
       OR has_column_privilege('authenticated', 'public.users', 'financial_role', 'UPDATE') THEN
        RAISE EXCEPTION 'fable_db_hardening guard: linked_user_id / financial_role still client-writable';
    END IF;

    -- DB-08 (tables this role can manage)
    SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_bad
    FROM pg_class c
    WHERE c.relnamespace = 'public'::regnamespace
      AND c.relkind IN ('r', 'p')
      AND pg_has_role(current_user, c.relowner, 'MEMBER')
      AND (has_table_privilege('anon', c.oid, 'TRUNCATE')
           OR has_table_privilege('authenticated', c.oid, 'TRUNCATE')
           OR has_any_column_privilege('anon', c.oid, 'INSERT')
           OR has_any_column_privilege('anon', c.oid, 'UPDATE')
           OR has_table_privilege('anon', c.oid, 'DELETE')
           OR has_table_privilege('authenticated', c.oid, 'TRIGGER'));
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'fable_db_hardening guard: TRUNCATE/TRIGGER/anon DML still granted on %', v_bad;
    END IF;
END $$;

COMMIT;
