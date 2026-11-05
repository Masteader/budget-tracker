-- ============================================================================
-- Test 44: the operator path for someone who cannot sign in
--
-- Migration: 20261105000800_account_deletion_operator_request.sql
--
-- Verifies:
--   1. Service only: anon and authenticated cannot execute any operator function, and
--      each refuses a caller with a JWT subject even under the service role.
--   2. The inquiry must exist and be an account_deletion one; the handle must not be an
--      address; the user must exist.
--   3. Same household rules as request_account_deletion: a primary or sole admin with
--      other members is refused without an explicit choice, the successor rules hold,
--      and a choice for someone else's household is refused, with nothing left behind.
--   4. Regular member, sole member, delete and transfer choices schedule 30 days out and
--      record the operator, the inquiry reference and nothing personal.
--   5. Idempotent: repeating keeps the first date and the first reference; a request the
--      user made themselves is found, not overwritten.
--   6. The status RPC and cancel_account_deletion work on it for the user, and the
--      operator cancel clears the same marks.
--   7. The 90-day inquiry removal leaves the reference on an open job, and the job still
--      runs; completion removes the inquiry and the reference, and keeps no identifiers.
--   8. request_account_deletion still works for the signed-in user, marked 'user'.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE FUNCTION pg_temp.call(p_sub uuid, p_sql text, p_role text DEFAULT 'authenticated', p_session text DEFAULT NULL)
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

CREATE FUNCTION pg_temp.u(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e4400000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.u(int) TO PUBLIC;

CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e44a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.h(int) TO PUBLIC;

CREATE FUNCTION pg_temp.hh(p_n int) RETURNS void LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO public.households (id, name, invite_code, household_type)
    VALUES (pg_temp.h(p_n), 'T44 H' || p_n, 'T44CODE' || lpad(p_n::text, 9, '0'), 'roommates');
END;
$$;

CREATE FUNCTION pg_temp.join(p_user int, p_hh int, p_role text DEFAULT 'member') RETURNS void LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role)
    VALUES (pg_temp.h(p_hh), pg_temp.u(p_user), p_role, 'peer');
    UPDATE public.users SET household_id = pg_temp.h(p_hh), role = p_role, financial_role = 'peer'
    WHERE id = pg_temp.u(p_user) AND household_id IS NULL;
END;
$$;

-- A stored public form request, as POST /public/inquiries writes it.
CREATE FUNCTION pg_temp.inquiry(p_ref text, p_email text, p_type text DEFAULT 'account_deletion') RETURNS void LANGUAGE sql
AS $$
    INSERT INTO public.inquiries (type, email, message, locale, reference)
    VALUES (p_type, p_email, 'please delete my account', 'ur', p_ref)
$$;

CREATE FUNCTION pg_temp.schedule_sql(p_user int, p_ref text DEFAULT 'ref-a', p_by text DEFAULT 'dev_one',
                                     p_choices text DEFAULT '[]', p_locale text DEFAULT NULL)
RETURNS text LANGUAGE sql
AS $$ SELECT format('SELECT public.schedule_account_deletion_by_operator(%L, %L, %L, %L::jsonb, %L)::text',
                    pg_temp.u(p_user), p_ref, p_by, p_choices, p_locale) $$;

CREATE FUNCTION pg_temp.svc(p_sql text) RETURNS text LANGUAGE sql
AS $$ SELECT pg_temp.call(NULL, p_sql, 'service_role') $$;

CREATE FUNCTION pg_temp.field(p_json text, p_key text) RETURNS text LANGUAGE sql
AS $$ SELECT p_json::jsonb ->> p_key $$;

DO $$
BEGIN
    INSERT INTO auth.users (id, email, raw_user_meta_data)
    SELECT pg_temp.u(n), 't44-' || n || '@test.local', jsonb_build_object('display_name', 'T44 User ' || n)
    FROM generate_series(1, 30) AS n;
    PERFORM pg_temp.inquiry('ref-a', 't44-1@test.local');
    PERFORM pg_temp.inquiry('ref-contact', 't44-1@test.local', 'contact');
END $$;

-- 1. Service only ---------------------------------------------------------------------
DO $$
DECLARE
    v_sql text;
    v_role text;
BEGIN
    FOREACH v_sql IN ARRAY ARRAY[
        pg_temp.schedule_sql(1),
        format('SELECT public.cancel_account_deletion_by_operator(%L, %L, %L)::text', pg_temp.u(1), 'ref-a', 'dev_one'),
        format('SELECT public.get_account_deletion_operator_preview(%L, %L)::text', 't44-1@test.local', 'ref-a')
    ] LOOP
        FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
            PERFORM pg_temp.expect('refused for ' || v_role || ': ' || left(v_sql, 60),
                pg_temp.call(CASE WHEN v_role = 'authenticated' THEN pg_temp.u(1) END, v_sql, v_role), 'ERR:42501');
        END LOOP;
        -- A JWT subject under the service role is still a user session.
        PERFORM pg_temp.expect('refused with a subject: ' || left(v_sql, 60),
            pg_temp.call(pg_temp.u(1), v_sql, 'service_role'), 'ERR:42501');
    END LOOP;

    PERFORM pg_temp.expect('internal scheduler is not callable by clients',
        pg_temp.call(pg_temp.u(1),
            format('SELECT public.account_deletion_schedule(%L, ''[]''::jsonb, NULL, ''ar'', ''user'', NULL, NULL)::text', pg_temp.u(1))),
        'ERR:42501');
    PERFORM pg_temp.expect('internal cancel is not callable by clients',
        pg_temp.call(pg_temp.u(1), format('SELECT public.account_deletion_cancel(%L)::text', pg_temp.u(1))),
        'ERR:42501');
    PERFORM pg_temp.expect('nothing scheduled',
        (SELECT count(*)::text FROM public.account_deletion_requests WHERE user_id = pg_temp.u(1)), '0');
    RAISE NOTICE 'PASSED: the operator functions are service only and refuse a JWT subject.';
END $$;

-- 2. Inquiry, handle, user --------------------------------------------------------------
DO $$
BEGIN
    PERFORM pg_temp.expect('unknown inquiry', pg_temp.svc(pg_temp.schedule_sql(1, 'ref-nope')), 'ERR:inquiry_invalid');
    PERFORM pg_temp.expect('wrong inquiry type', pg_temp.svc(pg_temp.schedule_sql(1, 'ref-contact')), 'ERR:inquiry_invalid');
    PERFORM pg_temp.expect('an address is not a handle',
        pg_temp.svc(pg_temp.schedule_sql(1, 'ref-a', 'someone@example.com')), 'ERR:operator_handle_invalid');
    PERFORM pg_temp.expect('empty handle', pg_temp.svc(pg_temp.schedule_sql(1, 'ref-a', '')), 'ERR:operator_handle_invalid');
    PERFORM pg_temp.expect('no handle',
        pg_temp.svc(format('SELECT public.schedule_account_deletion_by_operator(%L, %L, NULL)::text', pg_temp.u(1), 'ref-a')),
        'ERR:operator_handle_invalid');
    PERFORM pg_temp.expect('unknown user',
        pg_temp.svc(format('SELECT public.schedule_account_deletion_by_operator(%L, %L, %L)::text',
                           'e4400000-0000-0000-0000-999999999999', 'ref-a', 'dev_one')),
        'ERR:account_not_found');
    RAISE NOTICE 'PASSED: a valid inquiry, an operator handle and a real user are required.';
END $$;

-- 3. Refuse rather than guess -----------------------------------------------------------
DO $$
BEGIN
    -- Household 1: primary admin 2, members 3 and 4. Household 2 is someone else's.
    PERFORM pg_temp.hh(1);
    PERFORM pg_temp.join(2, 1, 'admin');
    UPDATE public.households SET owner_user_id = pg_temp.u(2) WHERE id = pg_temp.h(1);
    PERFORM pg_temp.join(3, 1);
    PERFORM pg_temp.join(4, 1);
    PERFORM pg_temp.hh(2);
    PERFORM pg_temp.join(5, 2, 'admin');
    UPDATE public.households SET owner_user_id = pg_temp.u(5) WHERE id = pg_temp.h(2);
    PERFORM pg_temp.join(6, 2);

    PERFORM pg_temp.expect('primary admin with members and no choice',
        pg_temp.svc(pg_temp.schedule_sql(2)), 'ERR:household_choice_missing');
    PERFORM pg_temp.expect('a choice for another household',
        pg_temp.svc(pg_temp.schedule_sql(2, 'ref-a', 'dev_one',
            format('[{"household_id":"%s","action":"delete"}]', pg_temp.h(2)))),
        'ERR:household_choice_invalid');
    PERFORM pg_temp.expect('successor not in the household',
        pg_temp.svc(pg_temp.schedule_sql(2, 'ref-a', 'dev_one',
            format('[{"household_id":"%s","action":"transfer","successor_user_id":"%s"}]', pg_temp.h(1), pg_temp.u(6)))),
        'ERR:successor_invalid');
    PERFORM pg_temp.expect('successor is the user',
        pg_temp.svc(pg_temp.schedule_sql(2, 'ref-a', 'dev_one',
            format('[{"household_id":"%s","action":"transfer","successor_user_id":"%s"}]', pg_temp.h(1), pg_temp.u(2)))),
        'ERR:successor_invalid');

    -- A pending successor is refused too.
    PERFORM pg_temp.svc(pg_temp.schedule_sql(4));
    PERFORM pg_temp.expect('successor pending',
        pg_temp.svc(pg_temp.schedule_sql(2, 'ref-a', 'dev_one',
            format('[{"household_id":"%s","action":"transfer","successor_user_id":"%s"}]', pg_temp.h(1), pg_temp.u(4)))),
        'ERR:successor_pending_deletion');

    PERFORM pg_temp.expect('nothing left behind',
        (SELECT count(*)::text FROM public.account_deletion_requests WHERE user_id = pg_temp.u(2)), '0');
    PERFORM pg_temp.expect('household not marked',
        (SELECT (deletion_scheduled_for IS NULL)::text FROM public.households WHERE id = pg_temp.h(1)), 'true');
    PERFORM pg_temp.expect('primary admin unchanged',
        (SELECT owner_user_id::text FROM public.households WHERE id = pg_temp.h(1)), pg_temp.u(2)::text);
    RAISE NOTICE 'PASSED: an admin with members is refused without an explicit choice, with the same successor rules.';
END $$;

-- 4. Positions, and what is recorded ----------------------------------------------------
DO $$
DECLARE
    v_res text;
    v_req public.account_deletion_requests%ROWTYPE;
BEGIN
    -- Regular member (3 in household 1): locale comes from the inquiry.
    v_res := pg_temp.svc(pg_temp.schedule_sql(3));
    PERFORM pg_temp.expect('member scheduled', pg_temp.field(v_res, 'status'), 'scheduled');
    PERFORM pg_temp.expect('member new', pg_temp.field(v_res, 'already_requested'), 'false');
    SELECT * INTO v_req FROM public.account_deletion_requests WHERE user_id = pg_temp.u(3);
    PERFORM pg_temp.expect('thirty days out', (v_req.scheduled_for - v_req.requested_at)::text, '30 days');
    PERFORM pg_temp.expect('marked operator', v_req.initiated_by, 'operator');
    PERFORM pg_temp.expect('reference kept', v_req.operator_inquiry_reference, 'ref-a');
    PERFORM pg_temp.expect('handle kept', v_req.operator_verified_by, 'dev_one');
    PERFORM pg_temp.expect('locale from the inquiry', v_req.locale, 'ur');
    PERFORM pg_temp.expect('no copy of the message', v_req.reason, NULL);

    -- Sole member: no choice, household marked.
    PERFORM pg_temp.hh(3);
    PERFORM pg_temp.join(7, 3, 'admin');
    UPDATE public.households SET owner_user_id = pg_temp.u(7) WHERE id = pg_temp.h(3);
    v_res := pg_temp.svc(pg_temp.schedule_sql(7, 'ref-a', 'dev_one', '[]', 'en'));
    PERFORM pg_temp.expect('sole member marked',
        (SELECT deletion_requested_by::text FROM public.households WHERE id = pg_temp.h(3)), pg_temp.u(7)::text);
    PERFORM pg_temp.expect('an explicit locale wins',
        (SELECT locale FROM public.account_deletion_requests WHERE user_id = pg_temp.u(7)), 'en');

    -- Explicit delete choice.
    v_res := pg_temp.svc(pg_temp.schedule_sql(2, 'ref-a', 'dev_one',
        format('[{"household_id":"%s","action":"delete"}]', pg_temp.h(1))));
    PERFORM pg_temp.expect('delete choice marks',
        (SELECT deletion_requested_by::text FROM public.households WHERE id = pg_temp.h(1)), pg_temp.u(2)::text);

    -- Explicit transfer: runs now, and the user stays a co-admin.
    v_res := pg_temp.svc(pg_temp.schedule_sql(5, 'ref-a', 'dev_one',
        format('[{"household_id":"%s","action":"transfer","successor_user_id":"%s"}]', pg_temp.h(2), pg_temp.u(6))));
    PERFORM pg_temp.expect('transfer ran',
        (SELECT owner_user_id::text FROM public.households WHERE id = pg_temp.h(2)), pg_temp.u(6)::text);
    PERFORM pg_temp.expect('still an admin',
        (SELECT role FROM public.household_memberships WHERE household_id = pg_temp.h(2) AND user_id = pg_temp.u(5)), 'admin');
    RAISE NOTICE 'PASSED: each position schedules 30 days out, and records the operator and the reference only.';
END $$;

-- 5. Idempotent, and never over a user's own request -------------------------------------
DO $$
DECLARE
    v_first text;
    v_again text;
    v_sess text;
BEGIN
    PERFORM pg_temp.inquiry('ref-b', 't44-8@test.local');
    v_first := pg_temp.svc(pg_temp.schedule_sql(8));
    v_again := pg_temp.svc(pg_temp.schedule_sql(8, 'ref-b', 'dev_two'));
    PERFORM pg_temp.expect('repeat found', pg_temp.field(v_again, 'already_requested'), 'true');
    PERFORM pg_temp.expect('same request', pg_temp.field(v_again, 'request_id'), pg_temp.field(v_first, 'request_id'));
    PERFORM pg_temp.expect('same date', pg_temp.field(v_again, 'scheduled_for'), pg_temp.field(v_first, 'scheduled_for'));
    PERFORM pg_temp.expect('first reference stays',
        (SELECT operator_inquiry_reference || '/' || operator_verified_by FROM public.account_deletion_requests
         WHERE user_id = pg_temp.u(8)), 'ref-a/dev_one');

    INSERT INTO auth.sessions (user_id, created_at) VALUES (pg_temp.u(9), now()) RETURNING id::text INTO v_sess;
    v_first := pg_temp.call(pg_temp.u(9), 'SELECT public.request_account_deletion(''delete'', ''[]''::jsonb, ''moving'', ''en'')::text',
                            'authenticated', v_sess);
    PERFORM pg_temp.expect('the user path still works', pg_temp.field(v_first, 'already_requested'), 'false');
    v_again := pg_temp.svc(pg_temp.schedule_sql(9));
    PERFORM pg_temp.expect('operator finds it', pg_temp.field(v_again, 'already_requested'), 'true');
    PERFORM pg_temp.expect('stays the user''s own',
        (SELECT initiated_by || '/' || (operator_inquiry_reference IS NULL)::text || '/' || reason
         FROM public.account_deletion_requests WHERE user_id = pg_temp.u(9)), 'user/true/moving');
    RAISE NOTICE 'PASSED: repeating is a no-op and a user''s own request is not overwritten.';
END $$;

-- 6. Same status and cancel path --------------------------------------------------------
DO $$
DECLARE
    v_res text;
BEGIN
    PERFORM pg_temp.svc(pg_temp.schedule_sql(10));
    v_res := pg_temp.call(pg_temp.u(10), 'SELECT public.get_account_deletion_status()::text');
    PERFORM pg_temp.expect('status shows it', pg_temp.field(v_res, 'status'), 'scheduled');
    PERFORM pg_temp.expect('can cancel', pg_temp.field(v_res, 'can_cancel'), 'true');
    IF v_res LIKE '%ref-a%' OR v_res LIKE '%dev_one%' THEN
        RAISE EXCEPTION 'status exposes the operator record: %', v_res;
    END IF;
    v_res := pg_temp.call(pg_temp.u(10), 'SELECT public.cancel_account_deletion()::text');
    PERFORM pg_temp.expect('the user cancels it', pg_temp.field(v_res, 'cancelled'), 'true');

    -- Operator cancel: marks clear, a transfer stays, the handle is recorded.
    PERFORM pg_temp.hh(4);
    PERFORM pg_temp.join(11, 4, 'admin');
    UPDATE public.households SET owner_user_id = pg_temp.u(11) WHERE id = pg_temp.h(4);
    PERFORM pg_temp.svc(pg_temp.schedule_sql(11));
    PERFORM pg_temp.expect('marked before', (SELECT (deletion_scheduled_for IS NOT NULL)::text FROM public.households WHERE id = pg_temp.h(4)), 'true');
    PERFORM pg_temp.expect('cancel needs a handle',
        pg_temp.svc(format('SELECT public.cancel_account_deletion_by_operator(%L, %L, %L)::text', pg_temp.u(11), 'ref-a', 'a@b.c')),
        'ERR:operator_handle_invalid');
    v_res := pg_temp.svc(format('SELECT public.cancel_account_deletion_by_operator(%L, %L, %L)::text', pg_temp.u(11), 'ref-a', 'dev_two'));
    PERFORM pg_temp.expect('operator cancelled', pg_temp.field(v_res, 'cancelled'), 'true');
    PERFORM pg_temp.expect('marks cleared', (SELECT (deletion_scheduled_for IS NULL)::text FROM public.households WHERE id = pg_temp.h(4)), 'true');
    PERFORM pg_temp.expect('cancel recorded',
        (SELECT status || '/' || operator_cancelled_by FROM public.account_deletion_requests WHERE user_id = pg_temp.u(11)),
        'cancelled/dev_two');

    v_res := pg_temp.svc(format('SELECT public.cancel_account_deletion_by_operator(%L, %L, %L)::text', pg_temp.u(11), 'ref-a', 'dev_two'));
    PERFORM pg_temp.expect('nothing left to cancel', pg_temp.field(v_res, 'cancelled'), 'false');

    -- Refused once processing, like the user's cancel.
    PERFORM pg_temp.svc(pg_temp.schedule_sql(12));
    UPDATE public.account_deletion_requests SET status = 'processing' WHERE user_id = pg_temp.u(12);
    PERFORM pg_temp.expect('too late',
        pg_temp.svc(format('SELECT public.cancel_account_deletion_by_operator(%L, %L, %L)::text', pg_temp.u(12), 'ref-a', 'dev_two')),
        'ERR:deletion_in_progress');
    RAISE NOTICE 'PASSED: the status RPC and both cancels work on an operator request.';
END $$;

-- 7. The 90-day removal and completion ---------------------------------------------------
DO $$
DECLARE
    v_req uuid;
    v_res text;
BEGIN
    -- The typed address differs from the account's, so the purge's own email match misses it.
    PERFORM pg_temp.inquiry('ref-old', 'typed-elsewhere@test.local');
    PERFORM pg_temp.inquiry('ref-live', 'typed-elsewhere@test.local');
    PERFORM pg_temp.svc(pg_temp.schedule_sql(13, 'ref-old'));
    PERFORM pg_temp.svc(pg_temp.schedule_sql(14, 'ref-live'));

    UPDATE public.inquiries SET created_at = now() - interval '91 days' WHERE reference = 'ref-old';
    PERFORM pg_temp.svc('SELECT public.purge_expired_account_deletion_inquiries(90)::text');
    PERFORM pg_temp.expect('the row went at 90 days',
        (SELECT count(*)::text FROM public.inquiries WHERE reference = 'ref-old'), '0');
    PERFORM pg_temp.expect('the reference stays on the open job',
        (SELECT operator_inquiry_reference FROM public.account_deletion_requests WHERE user_id = pg_temp.u(13)), 'ref-old');

    -- That job still runs to the end, with its inquiry gone.
    SELECT id INTO v_req FROM public.account_deletion_requests WHERE user_id = pg_temp.u(13);
    UPDATE public.account_deletion_requests SET status = 'processing', scheduled_for = now() - interval '1 minute' WHERE id = v_req;
    v_res := pg_temp.svc(format('SELECT public.prepare_account_purge(%L)::text', v_req));
    PERFORM pg_temp.expect('prepared', pg_temp.field(v_res, 'prepared'), 'true');
    PERFORM pg_temp.svc(format('SELECT public.mark_account_purge_storage_done(%L)::text', v_req));
    DELETE FROM auth.users WHERE id = pg_temp.u(13);
    PERFORM pg_temp.expect('completed',
        pg_temp.svc(format('SELECT public.complete_account_purge(%L)::text', v_req)), '');
    PERFORM pg_temp.expect('tombstone keeps how it started, and no reference',
        (SELECT status || '/' || initiated_by || '/' || (user_id IS NULL)::text || '/' || (operator_inquiry_reference IS NULL)::text
         FROM public.account_deletion_requests WHERE id = v_req),
        'completed/operator/true/true');

    -- A job whose inquiry is still there removes it: its typed address must not outlive the account.
    SELECT id INTO v_req FROM public.account_deletion_requests WHERE user_id = pg_temp.u(14);
    UPDATE public.account_deletion_requests SET status = 'processing', scheduled_for = now() - interval '1 minute' WHERE id = v_req;
    PERFORM pg_temp.svc(format('SELECT public.prepare_account_purge(%L)::text', v_req));
    PERFORM pg_temp.svc(format('SELECT public.mark_account_purge_storage_done(%L)::text', v_req));
    DELETE FROM auth.users WHERE id = pg_temp.u(14);
    PERFORM pg_temp.svc(format('SELECT public.complete_account_purge(%L)::text', v_req));
    PERFORM pg_temp.expect('the inquiry went with the account',
        (SELECT count(*)::text FROM public.inquiries WHERE reference = 'ref-live'), '0');
    RAISE NOTICE 'PASSED: the 90-day removal does not touch a job, and completion leaves no reference.';
END $$;

-- 8. Preview: only what the operator needs -----------------------------------------------
DO $$
DECLARE
    v_res text;
BEGIN
    v_res := pg_temp.svc(format('SELECT public.get_account_deletion_operator_preview(%L, %L)::text', 'T44-2@test.local', 'ref-a'));
    PERFORM pg_temp.expect('found, any case', pg_temp.field(v_res, 'account_found'), 'true');
    PERFORM pg_temp.expect('inquiry valid', pg_temp.field(v_res, 'inquiry_valid'), 'true');
    PERFORM pg_temp.expect('typed address differs', pg_temp.field(v_res, 'inquiry_email_matches'), 'false');
    PERFORM pg_temp.expect('user id for the next call', pg_temp.field(v_res, 'user_id'), pg_temp.u(2)::text);
    IF v_res LIKE '%T44 User%' OR v_res LIKE '%t44-3%' OR v_res LIKE '%T44 H%' OR v_res LIKE '%' || pg_temp.u(3)::text || '%' THEN
        RAISE EXCEPTION 'preview names other people or households: %', v_res;
    END IF;

    v_res := pg_temp.svc(format('SELECT public.get_account_deletion_operator_preview(%L, %L)::text', 'nobody@test.local', 'ref-a'));
    PERFORM pg_temp.expect('no account', pg_temp.field(v_res, 'account_found'), 'false');
    PERFORM pg_temp.expect('no id', pg_temp.field(v_res, 'user_id'), NULL);
    v_res := pg_temp.svc(format('SELECT public.get_account_deletion_operator_preview(%L, %L)::text', 't44-1@test.local', 'ref-a'));
    PERFORM pg_temp.expect('typed address matches', pg_temp.field(v_res, 'inquiry_email_matches'), 'true');
    RAISE NOTICE 'PASSED: the preview confirms the address and names nobody else.';
END $$;

ROLLBACK;
