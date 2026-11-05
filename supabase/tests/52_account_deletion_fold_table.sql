-- ============================================================================
-- Test 52: the typed confirmation word, one table for the server, the app and the web page
--
-- Migrations: 20261105000800_account_deletion_operator_request.sql
--
-- The table between the $fold_cases$ markers below is the one source of these cases. It is read
-- as well, unchanged, by:
--   flutter_app/test/models/account_deletion_fold_table_test.dart
--       foldConfirmationWord and confirmationWordMatches (flutter_app/lib/models/account_deletion.dart)
--   ai_service/tests/test_account_deletion_web_logic.py
--       foldConfirmation and isAcceptedConfirmation (web_app/src/lib/accountDeletion.ts), run with Node
-- so the three cannot drift apart without one of the three suites failing.
--
-- Each row:
--   input         what was typed (JSON escapes keep every invisible character visible here)
--   fold          public.account_deletion_fold_confirmation(input) in a UTF-8 ctype database
--   match         whether request_account_deletion accepts it
--   fold_differs  implementations whose folded TEXT differs from fold, for a known reason; their
--                 match never differs, and each must really differ (a stale entry fails):
--                   dart         the app has no NFC normalizer; only inputs NFC changes can differ
--                   ts           JavaScript lowercases with full Unicode mappings (U+0130 -> i U+0307)
--                   sql_c_ctype  a database with LC_CTYPE C or POSIX lowercases ASCII only
--
-- Verifies:
--   1. At least 30 rows, unique ids, both outcomes present.
--   2. The server's fold of each input is the row's fold (or, under sql_c_ctype, differs).
--   3. The real RPC, with a fresh session, accepts exactly the rows marked match and refuses the
--      rest with confirmation_mismatch.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE FUNCTION pg_temp.call(p_sub uuid, p_session text, p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_val text;
    v_hint text;
BEGIN
    PERFORM set_config('request.jwt.claims',
        jsonb_build_object('role', 'authenticated', 'sub', p_sub, 'session_id', p_session)::text, true);
    SET LOCAL ROLE authenticated;
    BEGIN
        EXECUTE p_sql INTO v_val;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
        RESET ROLE;
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN 'ERR:' || CASE WHEN COALESCE(v_hint, '') <> '' THEN v_hint ELSE SQLSTATE END;
    END;
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN COALESCE(v_val, 'ok');
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.call(uuid, text, text) TO PUBLIC;

CREATE TEMP TABLE fold_cases ON COMMIT DROP AS
SELECT (c ->> 'id') AS id,
       (c ->> 'input') AS input,
       (c ->> 'fold') AS fold,
       (c ->> 'match')::boolean AS match,
       ARRAY(SELECT jsonb_array_elements_text(c -> 'fold_differs')) AS fold_differs,
       n
FROM jsonb_array_elements($fold_cases$
[
  {"id": "en", "input": "delete", "fold": "delete", "match": true, "fold_differs": [], "note": "the English word"},
  {"id": "ar", "input": "\u062d\u0630\u0641", "fold": "\u062d\u0630\u0641", "match": true, "fold_differs": [], "note": "the Arabic word"},
  {"id": "ur", "input": "\u062d\u0630\u0641 \u06a9\u0631\u06cc\u06ba", "fold": "\u062d\u0630\u0641 \u0643\u0631\u064a\u0646", "match": true, "fold_differs": [], "note": "the Urdu words as the app shows them: keheh, Farsi yeh, noon ghunna"},
  {"id": "en-upper", "input": "DELETE", "fold": "delete", "match": true, "fold_differs": [], "note": "uppercase"},
  {"id": "en-mixed-case", "input": "DeLeTe", "fold": "delete", "match": true, "fold_differs": [], "note": "mixed case"},
  {"id": "en-padded", "input": "  delete  ", "fold": "delete", "match": true, "fold_differs": [], "note": "spaces around"},
  {"id": "en-tab-crlf", "input": "\tdelete\r\n", "fold": "delete", "match": true, "fold_differs": [], "note": "tab, carriage return and newline around"},
  {"id": "en-vt-ff", "input": "\u000bdelete\f", "fold": "delete", "match": true, "fold_differs": [], "note": "vertical tab and form feed around"},
  {"id": "ur-arabic-keyboard", "input": "\u062d\u0630\u0641 \u0643\u0631\u064a\u0646", "fold": "\u062d\u0630\u0641 \u0643\u0631\u064a\u0646", "match": true, "fold_differs": [], "note": "Urdu typed on an Arabic keyboard: kaf, yeh, noon"},
  {"id": "ur-alef-maksura", "input": "\u062d\u0630\u0641 \u0643\u0631\u0649\u0646", "fold": "\u062d\u0630\u0641 \u0643\u0631\u064a\u0646", "match": true, "fold_differs": [], "note": "alef maksura for the yeh"},
  {"id": "ur-mixed-letters", "input": "\u062d\u0630\u0641 \u06a9\u0631\u064a\u0646", "fold": "\u062d\u0630\u0641 \u0643\u0631\u064a\u0646", "match": true, "fold_differs": [], "note": "keheh with Arabic yeh and noon"},
  {"id": "lrm-inside-word", "input": "de\u200elete", "fold": "de lete", "match": false, "fold_differs": [], "note": "a direction mark inside a word becomes a space: no match"},
  {"id": "rlm-inside-arabic-word", "input": "\u062d\u0630\u200f\u0641", "fold": "\u062d\u0630 \u0641", "match": false, "fold_differs": [], "note": "RLM inside the Arabic word becomes a space: no match"},
  {"id": "rlm-between-words", "input": "\u062d\u0630\u0641\u200f\u06a9\u0631\u06cc\u06ba", "fold": "\u062d\u0630\u0641 \u0643\u0631\u064a\u0646", "match": true, "fold_differs": [], "note": "RLM between the Urdu words is a space"},
  {"id": "marks-around", "input": "\u200f\u062d\u0630\u0641\u200e", "fold": "\u062d\u0630\u0641", "match": true, "fold_differs": [], "note": "RLM and LRM around the word"},
  {"id": "alm-inside-word", "input": "\u062d\u0630\u061c\u0641", "fold": "\u062d\u0630\u061c\u0641", "match": false, "fold_differs": [], "note": "ARABIC LETTER MARK is neither dropped nor a space: no match"},
  {"id": "alm-between-words", "input": "\u062d\u0630\u0641\u061c\u06a9\u0631\u06cc\u06ba", "fold": "\u062d\u0630\u0641\u061c\u0643\u0631\u064a\u0646", "match": false, "fold_differs": [], "note": "ARABIC LETTER MARK between the words: no match"},
  {"id": "zwnj-between-words", "input": "\u062d\u0630\u0641\u200c\u06a9\u0631\u06cc\u06ba", "fold": "\u062d\u0630\u0641\u0643\u0631\u064a\u0646", "match": false, "fold_differs": [], "note": "ZWNJ between the words is dropped and joins them: no match"},
  {"id": "zwnj-inside-arabic-word", "input": "\u062d\u200c\u0630\u0641", "fold": "\u062d\u0630\u0641", "match": true, "fold_differs": [], "note": "ZWNJ inside the Arabic word is dropped"},
  {"id": "zwnj-inside-urdu-word", "input": "\u062d\u0630\u0641 \u06a9\u0631\u200c\u06cc\u06ba", "fold": "\u062d\u0630\u0641 \u0643\u0631\u064a\u0646", "match": true, "fold_differs": [], "note": "ZWNJ inside the second Urdu word is dropped"},
  {"id": "zwnj-inside-latin-word", "input": "del\u200cete", "fold": "delete", "match": true, "fold_differs": [], "note": "ZWNJ inside the English word is dropped"},
  {"id": "zwj-inside-word", "input": "del\u200dete", "fold": "delete", "match": true, "fold_differs": [], "note": "ZWJ is dropped"},
  {"id": "zwsp-between-words", "input": "\u062d\u0630\u0641\u200b\u06a9\u0631\u06cc\u06ba", "fold": "\u062d\u0630\u0641\u0643\u0631\u064a\u0646", "match": false, "fold_differs": [], "note": "a zero-width space is dropped, not a space: no match"},
  {"id": "zwsp-only", "input": "\u200b", "fold": "", "match": false, "fold_differs": [], "note": "nothing left after the fold: no match"},
  {"id": "bom", "input": "\ufeffdelete", "fold": "delete", "match": true, "fold_differs": [], "note": "a byte order mark is dropped"},
  {"id": "embedding", "input": "\u202b\u062d\u0630\u0641\u202c", "fold": "\u062d\u0630\u0641", "match": true, "fold_differs": [], "note": "RLE and PDF are dropped"},
  {"id": "override-inside-word", "input": "de\u202elete", "fold": "delete", "match": true, "fold_differs": [], "note": "RLO inside a word is dropped"},
  {"id": "isolates", "input": "\u2067\u062d\u0630\u0641 \u06a9\u0631\u06cc\u06ba\u2069", "fold": "\u062d\u0630\u0641 \u0643\u0631\u064a\u0646", "match": true, "fold_differs": [], "note": "RLI and PDI are dropped"},
  {"id": "nbsp-between-words", "input": "\u062d\u0630\u0641\u00a0\u06a9\u0631\u06cc\u06ba", "fold": "\u062d\u0630\u0641 \u0643\u0631\u064a\u0646", "match": true, "fold_differs": [], "note": "NBSP between the words"},
  {"id": "nbsp-around", "input": "\u00a0delete\u00a0", "fold": "delete", "match": true, "fold_differs": [], "note": "NBSP around the word"},
  {"id": "narrow-nbsp", "input": "\u062d\u0630\u0641\u202f\u06a9\u0631\u06cc\u06ba", "fold": "\u062d\u0630\u0641 \u0643\u0631\u064a\u0646", "match": true, "fold_differs": [], "note": "narrow NBSP"},
  {"id": "em-and-ideographic-space", "input": "\u062d\u0630\u0641\u2003\u3000\u0643\u0631\u064a\u0646", "fold": "\u062d\u0630\u0641 \u0643\u0631\u064a\u0646", "match": true, "fold_differs": [], "note": "em space and ideographic space make one space"},
  {"id": "nel", "input": "\u062d\u0630\u0641\u0085\u06a9\u0631\u06cc\u06ba", "fold": "\u062d\u0630\u0641 \u0643\u0631\u064a\u0646", "match": true, "fold_differs": [], "note": "NEXT LINE"},
  {"id": "line-separator", "input": "delete\u2028", "fold": "delete", "match": true, "fold_differs": [], "note": "LINE SEPARATOR"},
  {"id": "paragraph-separator", "input": "\u062d\u0630\u0641\u2029\u06a9\u0631\u06cc\u06ba", "fold": "\u062d\u0630\u0641 \u0643\u0631\u064a\u0646", "match": true, "fold_differs": [], "note": "PARAGRAPH SEPARATOR"},
  {"id": "ogham-space", "input": "\u1680delete", "fold": "delete", "match": true, "fold_differs": [], "note": "OGHAM SPACE MARK"},
  {"id": "math-space", "input": "\u062d\u0630\u0641\u205f\u06a9\u0631\u06cc\u06ba", "fold": "\u062d\u0630\u0641 \u0643\u0631\u064a\u0646", "match": true, "fold_differs": [], "note": "MEDIUM MATHEMATICAL SPACE"},
  {"id": "figure-space", "input": "\u062d\u0630\u0641\u2007\u06a9\u0631\u06cc\u06ba", "fold": "\u062d\u0630\u0641 \u0643\u0631\u064a\u0646", "match": true, "fold_differs": [], "note": "FIGURE SPACE"},
  {"id": "space-run", "input": "\u062d\u0630\u0641   \u06a9\u0631\u06cc\u06ba", "fold": "\u062d\u0630\u0641 \u0643\u0631\u064a\u0646", "match": true, "fold_differs": [], "note": "a run of spaces is one"},
  {"id": "no-space", "input": "\u062d\u0630\u0641\u0643\u0631\u064a\u0646", "fold": "\u062d\u0630\u0641\u0643\u0631\u064a\u0646", "match": false, "fold_differs": [], "note": "the Urdu words run together: no match"},
  {"id": "upper-nbsp-rlm", "input": "DELETE\u00a0\u200f", "fold": "delete", "match": true, "fold_differs": [], "note": "uppercase with NBSP and RLM after"},
  {"id": "combining-acute-decomposed", "input": "delete\u0301", "fold": "delet\u00e9", "match": false, "fold_differs": ["dart"], "note": "a combining acute composes under NFC: no match"},
  {"id": "combining-acute-upper-inside", "input": "DELE\u0301TE", "fold": "del\u00e9te", "match": false, "fold_differs": ["dart", "sql_c_ctype"], "note": "a combining mark inside an uppercase word: no match"},
  {"id": "precomposed-e-acute", "input": "delet\u00e9", "fold": "delet\u00e9", "match": false, "fold_differs": [], "note": "a precomposed accented letter: no match"},
  {"id": "fatha", "input": "\u062d\u064e\u0630\u0641", "fold": "\u062d\u064e\u0630\u0641", "match": false, "fold_differs": [], "note": "a harakah (fatha) is not dropped: no match"},
  {"id": "yeh-hamza-decomposed", "input": "\u062d\u0630\u0641 \u0643\u0631\u064a\u0654\u0646", "fold": "\u062d\u0630\u0641 \u0643\u0631\u0626\u0646", "match": false, "fold_differs": ["dart"], "note": "yeh and combining hamza compose to U+0626 under NFC: no match"},
  {"id": "farsi-yeh-hamza", "input": "\u062d\u0630\u0641 \u0643\u0631\u06cc\u0654\u0646", "fold": "\u062d\u0630\u0641 \u0643\u0631\u064a\u0654\u0646", "match": false, "fold_differs": [], "note": "Farsi yeh and combining hamza do not compose: no match"},
  {"id": "tatweel", "input": "\u062d\u0640\u0630\u0641", "fold": "\u062d\u0640\u0630\u0641", "match": false, "fold_differs": [], "note": "a tatweel is not dropped: no match"},
  {"id": "presentation-forms", "input": "\ufea3\ufeac\ufed2", "fold": "\ufea3\ufeac\ufed2", "match": false, "fold_differs": [], "note": "Arabic presentation forms are not folded (NFC, not NFKC): no match"},
  {"id": "soft-hyphen", "input": "del\u00adete", "fold": "del\u00adete", "match": false, "fold_differs": [], "note": "a soft hyphen is not dropped: no match"},
  {"id": "word-joiner", "input": "de\u2060lete", "fold": "de\u2060lete", "match": false, "fold_differs": [], "note": "WORD JOINER is not dropped: no match"},
  {"id": "mongolian-vowel-separator", "input": "de\u180elete", "fold": "de\u180elete", "match": false, "fold_differs": [], "note": "U+180E is no longer a space: no match"},
  {"id": "unit-separator", "input": "de\u001flete", "fold": "de\u001flete", "match": false, "fold_differs": [], "note": "U+001F is not a space: no match"},
  {"id": "fullwidth-upper", "input": "\uff24\uff25\uff2c\uff25\uff34\uff25", "fold": "\uff44\uff45\uff4c\uff45\uff54\uff45", "match": false, "fold_differs": ["sql_c_ctype"], "note": "fullwidth letters are not folded to ASCII: no match"},
  {"id": "dotted-capital-i", "input": "DELET\u0130", "fold": "deleti", "match": false, "fold_differs": ["ts", "sql_c_ctype"], "note": "U+0130 lowercases differently per implementation: no match anywhere"},
  {"id": "kelvin-sign", "input": "\u212aelvin", "fold": "kelvin", "match": false, "fold_differs": [], "note": "U+212A becomes K under NFC"},
  {"id": "empty", "input": "", "fold": "", "match": false, "fold_differs": [], "note": "empty: no match"},
  {"id": "spaces-only", "input": "   ", "fold": "", "match": false, "fold_differs": [], "note": "only spaces: no match"},
  {"id": "en-twice", "input": "delete delete", "fold": "delete delete", "match": false, "fold_differs": [], "note": "the word twice: no match"},
  {"id": "en-other-word", "input": "remove", "fold": "remove", "match": false, "fold_differs": [], "note": "another word: no match"},
  {"id": "en-short", "input": "delet", "fold": "delet", "match": false, "fold_differs": [], "note": "a letter short: no match"},
  {"id": "ar-short", "input": "\u062d\u0630", "fold": "\u062d\u0630", "match": false, "fold_differs": [], "note": "a letter short: no match"},
  {"id": "ur-extra-word", "input": "\u062d\u0630\u0641 \u0643\u0631\u064a\u0646 x", "fold": "\u062d\u0630\u0641 \u0643\u0631\u064a\u0646 x", "match": false, "fold_differs": [], "note": "an extra word: no match"}
]
$fold_cases$::jsonb) WITH ORDINALITY AS t(c, n);
GRANT SELECT ON fold_cases TO PUBLIC;

-- 1. The table itself ----------------------------------------------------------------------------
DO $$
BEGIN
    IF (SELECT count(*) FROM fold_cases) < 30 THEN
        RAISE EXCEPTION 'the fold table needs at least 30 rows, has %', (SELECT count(*) FROM fold_cases);
    END IF;
    IF (SELECT count(DISTINCT id) FROM fold_cases) <> (SELECT count(*) FROM fold_cases) THEN
        RAISE EXCEPTION 'fold table ids repeat';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM fold_cases WHERE match) OR NOT EXISTS (SELECT 1 FROM fold_cases WHERE NOT match) THEN
        RAISE EXCEPTION 'the fold table needs rows that match and rows that do not';
    END IF;
    IF EXISTS (SELECT 1 FROM fold_cases WHERE NOT fold_differs <@ ARRAY['dart', 'ts', 'sql_c_ctype']) THEN
        RAISE EXCEPTION 'unknown fold_differs entry';
    END IF;
    -- The app differs only where NFC changes the input (not always there: its lowercasing turns
    -- U+212A into k, as NFC and lower() do).
    IF EXISTS (SELECT 1 FROM fold_cases WHERE 'dart' = ANY (fold_differs) AND normalize(input, NFC) = input) THEN
        RAISE EXCEPTION 'dart is marked on inputs NFC leaves alone: %',
            (SELECT string_agg(id, ', ') FROM fold_cases WHERE 'dart' = ANY (fold_differs) AND normalize(input, NFC) = input);
    END IF;
END $$;

-- 2. The server's fold ---------------------------------------------------------------------------
DO $$
DECLARE
    v_ctype text := (SELECT datctype FROM pg_database WHERE datname = current_database());
    v_c_ctype boolean := v_ctype IN ('C', 'POSIX');
    v_row record;
    v_got text;
BEGIN
    FOR v_row IN SELECT * FROM fold_cases ORDER BY n LOOP
        v_got := public.account_deletion_fold_confirmation(v_row.input);
        IF v_c_ctype AND 'sql_c_ctype' = ANY (v_row.fold_differs) THEN
            IF v_got = v_row.fold THEN
                RAISE EXCEPTION '%: marked sql_c_ctype but folds the same here', v_row.id;
            END IF;
        ELSIF v_got IS DISTINCT FROM v_row.fold THEN
            RAISE EXCEPTION '%: folded to %, the table says %', v_row.id, to_json(v_got), to_json(v_row.fold);
        END IF;
    END LOOP;
    RAISE NOTICE 'PASSED: the server folds all % rows as the table says (lc_ctype %).',
        (SELECT count(*) FROM fold_cases), v_ctype;
END $$;

-- 3. The real RPC --------------------------------------------------------------------------------
INSERT INTO auth.users (id, email) VALUES ('e5200000-0000-0000-0000-000000000001', 't52-1@test.local');

CREATE FUNCTION pg_temp.try_request(p_word text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_uid uuid := 'e5200000-0000-0000-0000-000000000001';
    v_session text;
BEGIN
    INSERT INTO auth.sessions (user_id, created_at) VALUES (v_uid, now()) RETURNING id::text INTO v_session;
    RETURN pg_temp.call(v_uid, v_session,
        format('SELECT public.request_account_deletion(%L, %L::jsonb, NULL, %L)::text', p_word, '[]', 'en'));
END;
$$;

DO $$
DECLARE
    v_uid uuid := 'e5200000-0000-0000-0000-000000000001';
    v_row record;
    v_res text;
    v_accepted int := 0;
BEGIN
    FOR v_row IN SELECT * FROM fold_cases ORDER BY n LOOP
        v_res := pg_temp.try_request(v_row.input);
        IF v_row.match THEN
            IF v_res LIKE 'ERR:%' OR (v_res::jsonb ->> 'success') IS DISTINCT FROM 'true'
               OR (v_res::jsonb ->> 'already_requested') = 'true' THEN
                RAISE EXCEPTION '%: should be accepted, got %', v_row.id, v_res;
            END IF;
            v_accepted := v_accepted + 1;
            IF pg_temp.call(v_uid, NULL, 'SELECT (public.cancel_account_deletion()->>''cancelled'')') <> 'true' THEN
                RAISE EXCEPTION '%: the request could not be cancelled', v_row.id;
            END IF;
        ELSIF v_res IS DISTINCT FROM 'ERR:confirmation_mismatch' THEN
            RAISE EXCEPTION '%: should be refused as confirmation_mismatch, got %', v_row.id, v_res;
        END IF;
    END LOOP;
    RAISE NOTICE 'PASSED: request_account_deletion accepts the % matching rows and refuses the other %.',
        v_accepted, (SELECT count(*) FROM fold_cases) - v_accepted;
END $$;

ROLLBACK;
