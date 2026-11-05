-- ============================================================================
-- Test 38: account deletion request, cancel, status and preflight RPCs
--
-- Migration: 20261105000200_account_deletion_rpcs.sql
--
-- Verifies:
--   1. Re-auth: refused without session_id, with a stale session, with another
--      user's session, with a malformed session_id. Wrong phrase refused.
--   2. Each locale's phrase is accepted; the date is 30 days out; a repeat keeps it.
--   3. Positions: regular member, sole member, primary admin (transfer and delete),
--      co-admin, and a sole admin who is not the recorded primary.
--   4. Several households: missing, unknown, foreign, duplicate and malformed choices
--      are refused and leave nothing behind. Successor not a member, the caller, or
--      pending is refused.
--   5. Cancel clears only that user's marks, keeps transfers, needs no re-auth and is
--      refused once processing or failed.
--   6. Status and preflight never expose the reason or another user's request.
--   7. Client RPCs act only on auth.uid(); anon can execute none; helpers are internal.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- Runs p_sql as an authenticated user. p_session: a session id, or NULL for no claim.
CREATE FUNCTION pg_temp.call(p_sub uuid, p_session text, p_sql text, p_role text DEFAULT 'authenticated')
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_val text;
    v_hint text;
    v_claims jsonb := jsonb_build_object('role', p_role);
BEGIN
    IF p_sub IS NOT NULL THEN
        v_claims := v_claims || jsonb_build_object('sub', p_sub);
    END IF;
    IF p_session IS NOT NULL THEN
        v_claims := v_claims || jsonb_build_object('session_id', p_session);
    END IF;
    PERFORM set_config('request.jwt.claims', v_claims::text, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    BEGIN
        EXECUTE p_sql INTO v_val;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
        EXECUTE 'RESET ROLE';
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN 'ERR:' || CASE WHEN COALESCE(v_hint, '') <> '' THEN v_hint ELSE SQLSTATE END;
    END;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN COALESCE(v_val, 'ok');
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.call(uuid, text, text, text) TO PUBLIC;

CREATE FUNCTION pg_temp.expect(p_label text, p_got text, p_want text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_got IS DISTINCT FROM p_want THEN
        RAISE EXCEPTION '%: got %, expected %', p_label, p_got, p_want;
    END IF;
END;
$$;

CREATE FUNCTION pg_temp.u(p_n int)
RETURNS uuid
LANGUAGE sql
AS $$ SELECT ('e3800000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.u(int) TO PUBLIC;

CREATE FUNCTION pg_temp.h(p_n int)
RETURNS uuid
LANGUAGE sql
AS $$ SELECT ('e38a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.h(int) TO PUBLIC;

-- A fresh session for this user, as signInWithPassword creates.
CREATE FUNCTION pg_temp.fresh(p_n int)
RETURNS text
LANGUAGE sql
AS $$ INSERT INTO auth.sessions (user_id, created_at) VALUES (pg_temp.u(p_n), now()) RETURNING id::text $$;

CREATE FUNCTION pg_temp.request_sql(p_phrase text, p_choices text DEFAULT '[]', p_reason text DEFAULT NULL, p_locale text DEFAULT 'ar')
RETURNS text
LANGUAGE sql
AS $$ SELECT format('SELECT public.request_account_deletion(%L, %L::jsonb, %L, %L)::text', p_phrase, p_choices, p_reason, p_locale) $$;

CREATE FUNCTION pg_temp.hh(p_n int, p_type text DEFAULT 'roommates')
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO public.households (id, name, invite_code, household_type)
    VALUES (pg_temp.h(p_n), 'T38 H' || p_n, 'T38CODE' || lpad(p_n::text, 9, '0'), p_type);
END;
$$;

CREATE FUNCTION pg_temp.join(p_user int, p_hh int, p_role text DEFAULT 'member')
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role)
    VALUES (pg_temp.h(p_hh), pg_temp.u(p_user), p_role, 'peer');
    UPDATE public.users SET household_id = pg_temp.h(p_hh), role = p_role, financial_role = 'peer'
    WHERE id = pg_temp.u(p_user) AND household_id IS NULL;
END;
$$;

DO $$
BEGIN
    INSERT INTO auth.users (id, email, raw_user_meta_data)
    SELECT pg_temp.u(n), 't38-' || n || '@test.local', jsonb_build_object('display_name', 'T38 User ' || n)
    FROM generate_series(1, 60) AS n;
END $$;

-- 1. Re-auth and phrase -------------------------------------------------------------
DO $$
DECLARE
    v_sess text;
BEGIN
    PERFORM pg_temp.expect('no session_id',
        pg_temp.call(pg_temp.u(1), NULL, pg_temp.request_sql('DELETE')), 'ERR:reauthentication_required');
    PERFORM pg_temp.expect('malformed session_id',
        pg_temp.call(pg_temp.u(1), 'not-a-uuid', pg_temp.request_sql('DELETE')), 'ERR:reauthentication_required');
    PERFORM pg_temp.expect('unknown session',
        pg_temp.call(pg_temp.u(1), gen_random_uuid()::text, pg_temp.request_sql('DELETE')), 'ERR:reauthentication_required');

    INSERT INTO auth.sessions (user_id, created_at) VALUES (pg_temp.u(1), now() - interval '16 minutes')
    RETURNING id::text INTO v_sess;
    PERFORM pg_temp.expect('stale session',
        pg_temp.call(pg_temp.u(1), v_sess, pg_temp.request_sql('DELETE')), 'ERR:reauthentication_required');

    INSERT INTO auth.sessions (user_id, created_at) VALUES (pg_temp.u(2), now())
    RETURNING id::text INTO v_sess;
    PERFORM pg_temp.expect('another user''s session',
        pg_temp.call(pg_temp.u(1), v_sess, pg_temp.request_sql('DELETE')), 'ERR:reauthentication_required');

    v_sess := pg_temp.fresh(1);
    PERFORM pg_temp.expect('wrong phrase',
        pg_temp.call(pg_temp.u(1), v_sess, pg_temp.request_sql('DELET')), 'ERR:confirmation_mismatch');
    PERFORM pg_temp.expect('empty phrase',
        pg_temp.call(pg_temp.u(1), v_sess, pg_temp.request_sql('   ')), 'ERR:confirmation_mismatch');
    PERFORM pg_temp.expect('NULL phrase',
        pg_temp.call(pg_temp.u(1), v_sess, $q$SELECT public.request_account_deletion(NULL)::text$q$), 'ERR:confirmation_mismatch');
    PERFORM pg_temp.expect('no request created by any refusal',
        (SELECT count(*)::text FROM public.account_deletion_requests WHERE user_id = pg_temp.u(1)), '0');

    PERFORM pg_temp.expect('anonymous-style call without sub',
        pg_temp.call(NULL, v_sess, pg_temp.request_sql('DELETE'), 'service_role'), 'ERR:42501');
    RAISE NOTICE 'PASSED: request is refused without a fresh own session or the right phrase.';
END $$;

-- 2. Phrases, the date, repeats -------------------------------------------------------
DO $$
DECLARE
    v_res jsonb;
    v_first timestamptz;
    v_rec record;
    v_n int := 3;
BEGIN
    FOR v_rec IN
        SELECT * FROM (VALUES
            ('DELETE', 'en'), (' delete ', 'en'), ('DeLeTe', 'en'), ('حذف', 'ar'), (' حذف ', 'ar'),
            ('حذف کریں', 'ur'), ('حذف  کریں', 'ur'), (U&'\200Fحذف\200F', 'ar')
        ) AS t(phrase, locale)
    LOOP
        v_res := pg_temp.call(pg_temp.u(v_n), pg_temp.fresh(v_n), pg_temp.request_sql(v_rec.phrase, '[]', NULL, v_rec.locale))::jsonb;
        PERFORM pg_temp.expect('phrase ' || v_rec.phrase || ' status', v_res->>'status', 'scheduled');
        PERFORM pg_temp.expect('phrase ' || v_rec.phrase || ' locale',
            (SELECT locale FROM public.account_deletion_requests WHERE user_id = pg_temp.u(v_n)), v_rec.locale);
        v_n := v_n + 1;
    END LOOP;

    SELECT scheduled_for INTO v_first FROM public.account_deletion_requests WHERE user_id = pg_temp.u(3);
    IF abs(extract(epoch FROM (v_first - (now() + interval '30 days')))) > 60 THEN
        RAISE EXCEPTION 'scheduled_for is not 30 days out: %', v_first;
    END IF;

    -- A repeat returns the existing request and keeps its date.
    UPDATE public.account_deletion_requests SET scheduled_for = scheduled_for - interval '5 days' WHERE user_id = pg_temp.u(3);
    SELECT scheduled_for INTO v_first FROM public.account_deletion_requests WHERE user_id = pg_temp.u(3);
    v_res := pg_temp.call(pg_temp.u(3), pg_temp.fresh(3), pg_temp.request_sql('DELETE'))::jsonb;
    PERFORM pg_temp.expect('repeat flagged', v_res->>'already_requested', 'true');
    PERFORM pg_temp.expect('only one active request',
        (SELECT count(*)::text FROM public.account_deletion_requests WHERE user_id = pg_temp.u(3)), '1');
    PERFORM pg_temp.expect('repeat keeps the date',
        ((SELECT scheduled_for FROM public.account_deletion_requests WHERE user_id = pg_temp.u(3)) = v_first)::text, 'true');

    -- Reason: optional, capped at 500, never NULL-breaking. Unknown locale falls back to ar.
    v_res := pg_temp.call(pg_temp.u(11), pg_temp.fresh(11), pg_temp.request_sql('DELETE', '[]', repeat('x', 800), 'fr'))::jsonb;
    PERFORM pg_temp.expect('reason capped',
        (SELECT char_length(reason)::text FROM public.account_deletion_requests WHERE user_id = pg_temp.u(11)), '500');
    PERFORM pg_temp.expect('unknown locale falls back to ar',
        (SELECT locale FROM public.account_deletion_requests WHERE user_id = pg_temp.u(11)), 'ar');
    RAISE NOTICE 'PASSED: each locale''s phrase is accepted, 30 days out, repeat keeps the original date.';
END $$;

-- 3. Positions -------------------------------------------------------------------------
DO $$
DECLARE
    v_res jsonb;
    v_pre jsonb;
    v_date timestamptz;
BEGIN
    -- Regular member of household 1 (admin 12).
    PERFORM pg_temp.hh(1); PERFORM pg_temp.join(12, 1, 'admin'); PERFORM pg_temp.join(13, 1);
    v_pre := pg_temp.call(pg_temp.u(13), NULL, 'SELECT public.get_account_deletion_preflight()::text')::jsonb;
    PERFORM pg_temp.expect('member position', v_pre #>> '{households,0,position}', 'member');
    PERFORM pg_temp.expect('member needs no choice', v_pre #>> '{households,0,needs_choice}', 'false');
    v_res := pg_temp.call(pg_temp.u(13), pg_temp.fresh(13), pg_temp.request_sql('DELETE'))::jsonb;
    PERFORM pg_temp.expect('member scheduled', v_res->>'status', 'scheduled');
    PERFORM pg_temp.expect('member marks nothing',
        (SELECT deletion_scheduled_for::text FROM public.households WHERE id = pg_temp.h(1)), NULL);

    -- Sole member of household 2: no choice accepted, marked with the same date.
    PERFORM pg_temp.hh(2); PERFORM pg_temp.join(14, 2, 'admin');
    v_pre := pg_temp.call(pg_temp.u(14), NULL, 'SELECT public.get_account_deletion_preflight()::text')::jsonb;
    PERFORM pg_temp.expect('sole member position', v_pre #>> '{households,0,position}', 'sole_member');
    PERFORM pg_temp.expect('sole member needs no choice', v_pre #>> '{households,0,needs_choice}', 'false');
    PERFORM pg_temp.expect('a choice for a household that takes none',
        pg_temp.call(pg_temp.u(14), pg_temp.fresh(14), pg_temp.request_sql('DELETE',
            format('[{"household_id": "%s", "action": "delete"}]', pg_temp.h(2)))), 'ERR:household_choice_invalid');
    v_res := pg_temp.call(pg_temp.u(14), pg_temp.fresh(14), pg_temp.request_sql('DELETE'))::jsonb;
    SELECT scheduled_for INTO v_date FROM public.account_deletion_requests WHERE user_id = pg_temp.u(14);
    PERFORM pg_temp.expect('sole member''s household marked',
        (SELECT (deletion_scheduled_for = v_date AND deletion_requested_by = pg_temp.u(14) AND deletion_requested_at IS NOT NULL)::text
         FROM public.households WHERE id = pg_temp.h(2)), 'true');

    -- Primary admin of household 3 with member 16: must choose. Transfer runs now.
    PERFORM pg_temp.hh(3); PERFORM pg_temp.join(15, 3, 'admin'); PERFORM pg_temp.join(16, 3);
    v_pre := pg_temp.call(pg_temp.u(15), NULL, 'SELECT public.get_account_deletion_preflight()::text')::jsonb;
    PERFORM pg_temp.expect('primary position', v_pre #>> '{households,0,position}', 'primary_admin');
    PERFORM pg_temp.expect('primary needs a choice', v_pre #>> '{households,0,needs_choice}', 'true');
    PERFORM pg_temp.expect('candidates list the member', v_pre #>> '{households,0,candidates,0,user_id}', pg_temp.u(16)::text);
    PERFORM pg_temp.expect('candidate is not pending', v_pre #>> '{households,0,candidates,0,pending_deletion}', 'false');
    PERFORM pg_temp.expect('primary without a choice',
        pg_temp.call(pg_temp.u(15), pg_temp.fresh(15), pg_temp.request_sql('DELETE')), 'ERR:household_choice_missing');
    v_res := pg_temp.call(pg_temp.u(15), pg_temp.fresh(15), pg_temp.request_sql('DELETE',
        format('[{"household_id": "%s", "action": "transfer", "successor_user_id": "%s"}]', pg_temp.h(3), pg_temp.u(16))))::jsonb;
    PERFORM pg_temp.expect('transfer done', (SELECT owner_user_id::text FROM public.households WHERE id = pg_temp.h(3)), pg_temp.u(16)::text);
    PERFORM pg_temp.expect('caller stays a co-admin',
        (SELECT role FROM public.household_memberships WHERE household_id = pg_temp.h(3) AND user_id = pg_temp.u(15)), 'admin');
    PERFORM pg_temp.expect('successor is admin',
        (SELECT role FROM public.household_memberships WHERE household_id = pg_temp.h(3) AND user_id = pg_temp.u(16)), 'admin');
    PERFORM pg_temp.expect('transfer marks nothing',
        (SELECT deletion_scheduled_for::text FROM public.households WHERE id = pg_temp.h(3)), NULL);

    -- Primary admin of household 4 with member 18: delete marks it, others untouched.
    PERFORM pg_temp.hh(4); PERFORM pg_temp.join(17, 4, 'admin'); PERFORM pg_temp.join(18, 4);
    v_res := pg_temp.call(pg_temp.u(17), pg_temp.fresh(17), pg_temp.request_sql('DELETE',
        format('[{"household_id": "%s", "action": "delete"}]', pg_temp.h(4))))::jsonb;
    PERFORM pg_temp.expect('delete marks the household',
        (SELECT deletion_requested_by::text FROM public.households WHERE id = pg_temp.h(4)), pg_temp.u(17)::text);
    PERFORM pg_temp.expect('member keeps belonging until final deletion',
        (SELECT count(*)::text FROM public.household_memberships WHERE household_id = pg_temp.h(4)), '2');

    -- Non-primary co-admin of household 5: no choice, no mark, household kept.
    PERFORM pg_temp.hh(5); PERFORM pg_temp.join(19, 5, 'admin'); PERFORM pg_temp.join(20, 5, 'admin');
    v_pre := pg_temp.call(pg_temp.u(20), NULL, 'SELECT public.get_account_deletion_preflight()::text')::jsonb;
    PERFORM pg_temp.expect('co-admin position', v_pre #>> '{households,0,position}', 'co_admin');
    PERFORM pg_temp.expect('co-admin needs no choice', v_pre #>> '{households,0,needs_choice}', 'false');
    v_res := pg_temp.call(pg_temp.u(20), pg_temp.fresh(20), pg_temp.request_sql('DELETE'))::jsonb;
    PERFORM pg_temp.expect('co-admin scheduled', v_res->>'status', 'scheduled');
    PERFORM pg_temp.expect('co-admin marks nothing',
        (SELECT deletion_scheduled_for::text FROM public.households WHERE id = pg_temp.h(5)), NULL);

    -- Old data: a sole admin with no recorded primary still gets the choice, and transfer works.
    PERFORM pg_temp.hh(10); PERFORM pg_temp.join(40, 10, 'admin'); PERFORM pg_temp.join(41, 10);
    UPDATE public.households SET owner_user_id = NULL WHERE id = pg_temp.h(10);
    v_pre := pg_temp.call(pg_temp.u(40), NULL, 'SELECT public.get_account_deletion_preflight()::text')::jsonb;
    PERFORM pg_temp.expect('sole admin without a recorded primary', v_pre #>> '{households,0,position}', 'primary_admin');
    v_res := pg_temp.call(pg_temp.u(40), pg_temp.fresh(40), pg_temp.request_sql('DELETE',
        format('[{"household_id": "%s", "action": "transfer", "successor_user_id": "%s"}]', pg_temp.h(10), pg_temp.u(41))))::jsonb;
    PERFORM pg_temp.expect('transfer from a sole admin', (SELECT owner_user_id::text FROM public.households WHERE id = pg_temp.h(10)), pg_temp.u(41)::text);
    RAISE NOTICE 'PASSED: regular member, sole member, primary admin (transfer and delete) and co-admin.';
END $$;

-- 4. Several households and bad choices -----------------------------------------------
DO $$
DECLARE
    v_ok_transfer text;
    v_ok_delete text;
    v_res jsonb;
BEGIN
    -- User 21 is primary of 6 (with 22) and of 7 (with 23), and a member of 8 (admin 24).
    PERFORM pg_temp.hh(6); PERFORM pg_temp.join(21, 6, 'admin'); PERFORM pg_temp.join(22, 6);
    PERFORM pg_temp.hh(7); PERFORM pg_temp.join(21, 7, 'admin'); PERFORM pg_temp.join(23, 7);
    PERFORM pg_temp.hh(8); PERFORM pg_temp.join(24, 8, 'admin'); PERFORM pg_temp.join(21, 8);
    -- 25 belongs to 6 but is pending; 26 is in no household of 21's; 27's household is foreign.
    PERFORM pg_temp.join(25, 6);
    INSERT INTO public.account_deletion_requests (user_id, scheduled_for) VALUES (pg_temp.u(25), now() + interval '20 days');
    PERFORM pg_temp.hh(9); PERFORM pg_temp.join(27, 9, 'admin');

    v_ok_transfer := format('{"household_id": "%s", "action": "transfer", "successor_user_id": "%s"}', pg_temp.h(6), pg_temp.u(22));
    v_ok_delete := format('{"household_id": "%s", "action": "delete"}', pg_temp.h(7));

    PERFORM pg_temp.expect('one choice missing',
        pg_temp.call(pg_temp.u(21), pg_temp.fresh(21), pg_temp.request_sql('DELETE', '[' || v_ok_transfer || ']')), 'ERR:household_choice_missing');
    PERFORM pg_temp.expect('unknown household',
        pg_temp.call(pg_temp.u(21), pg_temp.fresh(21), pg_temp.request_sql('DELETE',
            '[' || v_ok_transfer || ',' || v_ok_delete || format(',{"household_id": "%s", "action": "delete"}', gen_random_uuid()) || ']')), 'ERR:household_choice_invalid');
    PERFORM pg_temp.expect('foreign household',
        pg_temp.call(pg_temp.u(21), pg_temp.fresh(21), pg_temp.request_sql('DELETE',
            '[' || v_ok_transfer || ',' || v_ok_delete || format(',{"household_id": "%s", "action": "delete"}', pg_temp.h(9)) || ']')), 'ERR:household_choice_invalid');
    PERFORM pg_temp.expect('household where the caller is a regular member',
        pg_temp.call(pg_temp.u(21), pg_temp.fresh(21), pg_temp.request_sql('DELETE',
            '[' || v_ok_transfer || ',' || v_ok_delete || format(',{"household_id": "%s", "action": "delete"}', pg_temp.h(8)) || ']')), 'ERR:household_choice_invalid');
    PERFORM pg_temp.expect('duplicate household',
        pg_temp.call(pg_temp.u(21), pg_temp.fresh(21), pg_temp.request_sql('DELETE',
            '[' || v_ok_transfer || ',' || v_ok_delete || ',' || v_ok_delete || ']')), 'ERR:household_choice_invalid');
    PERFORM pg_temp.expect('unknown action',
        pg_temp.call(pg_temp.u(21), pg_temp.fresh(21), pg_temp.request_sql('DELETE',
            '[' || v_ok_transfer || format(',{"household_id": "%s", "action": "archive"}', pg_temp.h(7)) || ']')), 'ERR:household_choice_invalid');
    PERFORM pg_temp.expect('choices not an array',
        pg_temp.call(pg_temp.u(21), pg_temp.fresh(21), pg_temp.request_sql('DELETE', v_ok_delete)), 'ERR:household_choice_invalid');
    PERFORM pg_temp.expect('malformed household id',
        pg_temp.call(pg_temp.u(21), pg_temp.fresh(21), pg_temp.request_sql('DELETE',
            '[{"household_id": "nope", "action": "delete"}]')), 'ERR:household_choice_invalid');
    PERFORM pg_temp.expect('delete carrying a successor',
        pg_temp.call(pg_temp.u(21), pg_temp.fresh(21), pg_temp.request_sql('DELETE',
            '[' || v_ok_transfer || format(',{"household_id": "%s", "action": "delete", "successor_user_id": "%s"}', pg_temp.h(7), pg_temp.u(23)) || ']')), 'ERR:household_choice_invalid');

    PERFORM pg_temp.expect('successor not a member',
        pg_temp.call(pg_temp.u(21), pg_temp.fresh(21), pg_temp.request_sql('DELETE',
            format('[{"household_id": "%s", "action": "transfer", "successor_user_id": "%s"},', pg_temp.h(6), pg_temp.u(26)) || v_ok_delete || ']')), 'ERR:successor_invalid');
    PERFORM pg_temp.expect('successor is the caller',
        pg_temp.call(pg_temp.u(21), pg_temp.fresh(21), pg_temp.request_sql('DELETE',
            format('[{"household_id": "%s", "action": "transfer", "successor_user_id": "%s"},', pg_temp.h(6), pg_temp.u(21)) || v_ok_delete || ']')), 'ERR:successor_invalid');
    PERFORM pg_temp.expect('successor missing',
        pg_temp.call(pg_temp.u(21), pg_temp.fresh(21), pg_temp.request_sql('DELETE',
            format('[{"household_id": "%s", "action": "transfer"},', pg_temp.h(6)) || v_ok_delete || ']')), 'ERR:successor_invalid');
    PERFORM pg_temp.expect('successor pending',
        pg_temp.call(pg_temp.u(21), pg_temp.fresh(21), pg_temp.request_sql('DELETE',
            format('[{"household_id": "%s", "action": "transfer", "successor_user_id": "%s"},', pg_temp.h(6), pg_temp.u(25)) || v_ok_delete || ']')), 'ERR:successor_pending_deletion');
    -- A pending member is shown but flagged, so the app can make it unselectable.
    PERFORM pg_temp.expect('preflight flags the pending candidate',
        (SELECT c->>'pending_deletion'
         FROM jsonb_array_elements(pg_temp.call(pg_temp.u(21), NULL, 'SELECT public.get_account_deletion_preflight()::text')::jsonb -> 'households') h,
              jsonb_array_elements(h->'candidates') c
         WHERE c->>'user_id' = pg_temp.u(25)::text), 'true');

    -- Nothing happened in any of those refusals.
    PERFORM pg_temp.expect('no request after refusals',
        (SELECT count(*)::text FROM public.account_deletion_requests WHERE user_id = pg_temp.u(21)), '0');
    PERFORM pg_temp.expect('no transfer after refusals',
        (SELECT owner_user_id::text FROM public.households WHERE id = pg_temp.h(6)), pg_temp.u(21)::text);
    PERFORM pg_temp.expect('no mark after refusals',
        (SELECT deletion_scheduled_for::text FROM public.households WHERE id = pg_temp.h(7)), NULL);

    v_res := pg_temp.call(pg_temp.u(21), pg_temp.fresh(21), pg_temp.request_sql('DELETE', '[' || v_ok_transfer || ',' || v_ok_delete || ']'))::jsonb;
    PERFORM pg_temp.expect('accepted', v_res->>'status', 'scheduled');
    PERFORM pg_temp.expect('household 6 transferred', (SELECT owner_user_id::text FROM public.households WHERE id = pg_temp.h(6)), pg_temp.u(22)::text);
    PERFORM pg_temp.expect('household 7 marked', (SELECT deletion_requested_by::text FROM public.households WHERE id = pg_temp.h(7)), pg_temp.u(21)::text);
    PERFORM pg_temp.expect('household 8 untouched', (SELECT deletion_scheduled_for::text FROM public.households WHERE id = pg_temp.h(8)), NULL);
    RAISE NOTICE 'PASSED: several households; bad choices and bad successors are refused and leave nothing behind.';
END $$;

-- 5. Cancel ---------------------------------------------------------------------------
DO $$
DECLARE
    v_res jsonb;
BEGIN
    -- 21 cancels with no fresh session: their mark clears, their transfer stays,
    -- and user 14's mark on household 2 is not touched.
    v_res := pg_temp.call(pg_temp.u(21), NULL, 'SELECT public.cancel_account_deletion()::text')::jsonb;
    PERFORM pg_temp.expect('cancel result', v_res->>'cancelled', 'true');
    PERFORM pg_temp.expect('status after cancel',
        pg_temp.call(pg_temp.u(21), NULL, 'SELECT public.get_account_deletion_status()::text')::jsonb ->> 'status', 'none');
    PERFORM pg_temp.expect('own mark cleared',
        (SELECT deletion_scheduled_for::text FROM public.households WHERE id = pg_temp.h(7)), NULL);
    PERFORM pg_temp.expect('transfer stays',
        (SELECT owner_user_id::text FROM public.households WHERE id = pg_temp.h(6)), pg_temp.u(22)::text);
    PERFORM pg_temp.expect('other user''s mark stays',
        (SELECT deletion_requested_by::text FROM public.households WHERE id = pg_temp.h(2)), pg_temp.u(14)::text);
    PERFORM pg_temp.expect('other user''s request stays',
        (SELECT status FROM public.account_deletion_requests WHERE user_id = pg_temp.u(14)), 'scheduled');
    PERFORM pg_temp.expect('a pending user no longer',
        public.account_deletion_user_pending(pg_temp.u(21))::text, 'false');

    -- Cancelling twice, or with nothing to cancel, is harmless.
    v_res := pg_temp.call(pg_temp.u(21), NULL, 'SELECT public.cancel_account_deletion()::text')::jsonb;
    PERFORM pg_temp.expect('second cancel', v_res->>'cancelled', 'false');

    -- After cancelling they can request again.
    v_res := pg_temp.call(pg_temp.u(21), pg_temp.fresh(21), pg_temp.request_sql('DELETE',
        format('[{"household_id": "%s", "action": "delete"}]', pg_temp.h(7))))::jsonb;
    PERFORM pg_temp.expect('request again after cancel', v_res->>'status', 'scheduled');
    PERFORM pg_temp.expect('co-admin of 6 is asked nothing, 7 marked again',
        (SELECT deletion_requested_by::text FROM public.households WHERE id = pg_temp.h(7)), pg_temp.u(21)::text);

    -- Once processing or failed the data may be gone.
    UPDATE public.account_deletion_requests SET status = 'processing' WHERE user_id = pg_temp.u(21) AND status = 'scheduled';
    PERFORM pg_temp.expect('cancel while processing',
        pg_temp.call(pg_temp.u(21), NULL, 'SELECT public.cancel_account_deletion()::text'), 'ERR:deletion_in_progress');
    UPDATE public.account_deletion_requests SET status = 'failed' WHERE user_id = pg_temp.u(21) AND status = 'processing';
    PERFORM pg_temp.expect('cancel after failure',
        pg_temp.call(pg_temp.u(21), NULL, 'SELECT public.cancel_account_deletion()::text'), 'ERR:deletion_in_progress');
    PERFORM pg_temp.expect('mark kept while in progress',
        (SELECT deletion_requested_by::text FROM public.households WHERE id = pg_temp.h(7)), pg_temp.u(21)::text);
    RAISE NOTICE 'PASSED: cancel clears only that user''s marks, keeps transfers, refused once processing.';
END $$;

-- 6. Status never exposes the reason or another user's request ---------------------------
DO $$
DECLARE
    v_status text;
    v_preflight text;
BEGIN
    PERFORM pg_temp.call(pg_temp.u(30), pg_temp.fresh(30), pg_temp.request_sql('DELETE', '[]', 'T38 SECRET REASON'));
    v_status := pg_temp.call(pg_temp.u(30), NULL, 'SELECT public.get_account_deletion_status()::text');
    v_preflight := pg_temp.call(pg_temp.u(30), NULL, 'SELECT public.get_account_deletion_preflight()::text');
    PERFORM pg_temp.expect('own status', (v_status::jsonb)->>'status', 'scheduled');
    PERFORM pg_temp.expect('own status can cancel', (v_status::jsonb)->>'can_cancel', 'true');
    IF v_status LIKE '%SECRET%' OR v_preflight LIKE '%SECRET%' THEN
        RAISE EXCEPTION 'VULNERABILITY: status or preflight exposes the reason';
    END IF;
    IF (v_status::jsonb) ? 'reason' THEN
        RAISE EXCEPTION 'VULNERABILITY: status carries a reason key';
    END IF;

    -- Someone else sees nothing of it, and an RPC argument cannot name another user.
    PERFORM pg_temp.expect('another user''s status',
        pg_temp.call(pg_temp.u(31), NULL, 'SELECT public.get_account_deletion_status()::text')::jsonb ->> 'status', 'none');
    PERFORM pg_temp.expect('no request created for the other user',
        (SELECT count(*)::text FROM public.account_deletion_requests WHERE user_id = pg_temp.u(31)), '0');
    IF EXISTS (SELECT 1 FROM pg_proc p
               WHERE p.pronamespace = 'public'::regnamespace
                 AND p.proname IN ('get_account_deletion_preflight', 'get_account_deletion_status', 'cancel_account_deletion')
                 AND p.pronargs <> 0) THEN
        RAISE EXCEPTION 'VULNERABILITY: a client RPC takes an argument that could name a user';
    END IF;
    RAISE NOTICE 'PASSED: status and preflight never expose a reason or another user''s request.';
END $$;

-- 7. Privileges -------------------------------------------------------------------------
DO $$
DECLARE
    v_sig text;
BEGIN
    FOREACH v_sig IN ARRAY ARRAY[
        'public.get_account_deletion_preflight()',
        'public.request_account_deletion(text, jsonb, text, text)',
        'public.cancel_account_deletion()',
        'public.get_account_deletion_status()'
    ] LOOP
        IF has_function_privilege('anon', v_sig, 'EXECUTE') THEN
            RAISE EXCEPTION 'VULNERABILITY: anon can execute %', v_sig;
        END IF;
        IF NOT has_function_privilege('authenticated', v_sig, 'EXECUTE') THEN
            RAISE EXCEPTION 'REGRESSION: authenticated cannot execute %', v_sig;
        END IF;
        PERFORM pg_temp.expect('pinned search_path on ' || v_sig,
            (SELECT (p.prosecdef AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'))::text
             FROM pg_proc p WHERE p.oid = v_sig::regprocedure), 'true');
    END LOOP;

    FOREACH v_sig IN ARRAY ARRAY[
        'public.account_deletion_recent_login_ok()',
        'public.account_deletion_household_positions(uuid)',
        'public.account_deletion_status_json(uuid)',
        'public.account_deletion_user_pending(uuid)'
    ] LOOP
        IF has_function_privilege('anon', v_sig, 'EXECUTE')
           OR has_function_privilege('authenticated', v_sig, 'EXECUTE') THEN
            RAISE EXCEPTION 'VULNERABILITY: internal helper % is client-callable', v_sig;
        END IF;
    END LOOP;

    PERFORM pg_temp.expect('anon calling status',
        pg_temp.call(NULL, NULL, 'SELECT public.get_account_deletion_status()::text', 'anon'), 'ERR:42501');
    PERFORM pg_temp.expect('anon calling request',
        pg_temp.call(NULL, NULL, pg_temp.request_sql('DELETE'), 'anon'), 'ERR:42501');
    PERFORM pg_temp.expect('authenticated without a subject',
        pg_temp.call(NULL, NULL, 'SELECT public.cancel_account_deletion()::text'), 'ERR:42501');
    PERFORM pg_temp.expect('service role has no subject here',
        pg_temp.call(NULL, NULL, 'SELECT public.get_account_deletion_status()::text', 'service_role'), 'ERR:42501');
    RAISE NOTICE 'PASSED: anon can execute none; helpers are internal; each RPC needs a subject.';
END $$;

ROLLBACK;
