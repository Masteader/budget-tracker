-- ----------------------------------------------------------------------------
-- Migration: 20261020200000_remove_sms_artifacts.sql
-- Audit API-25 / zero-SMS policy: the app never reads SMS. Expenses come only
-- from receipt photos, ZATCA QR codes, chat/voice and manual entry.
--
-- SMS leftovers in the schema (inventory of a full replay of every migration):
--   * transactions.source  DEFAULT 'sms' and CHECK (... 'sms' ...), from
--     20260925_add_line_items_and_sources.sql / 20260930_fix_transactions_rls_and_columns.sql.
--     Because 'sms' was the column DEFAULT, every insert that did not name a
--     source (Flutter manual entries before they sent one, SQL/RPC inserts) was
--     stored as 'sms' although no SMS was ever involved.
--   * comments: transactions ("Every SMS-derived expense transaction"),
--     transactions.raw_sms ("Original SMS text for audit trail") and
--     cost_control_codes ("keyword mapping for SMS merchant matching").
--   No SMS-only table, function, trigger or column exists, so nothing is dropped.
--
-- Changes:
--   1. Historical rows labelled 'sms' are relabelled (no row is deleted, no
--      amount/category/cycle/account column is touched, so no budget or ledger
--      trigger does any work). `source` is a pure display label: no function,
--      trigger, policy or index reads it. The mapping is exactly the one the
--      Flutter client already applies when it displays such rows
--      (Transaction.fromMap): audit note starting 'Chat:' -> 'chat',
--      'Receipt Scan:' -> 'receipt_scan', anything else -> 'manual'. What
--      users see in the app therefore does not change.
--   2. DEFAULT becomes 'manual' and the CHECK no longer allows 'sms', so no
--      code path (old app builds, API, SQL) can create a new SMS-sourced row.
--   3. transactions.raw_sms is KEPT and only re-documented: despite its
--      historical name it is the free-text audit note written by chat,
--      receipt scans, manual entry, installments and settlement tags, and
--      installed app builds write it directly through PostgREST, so renaming
--      or dropping it would break them and lose user notes.
-- Proof test: supabase/tests/18_remove_sms_artifacts.sql
-- ----------------------------------------------------------------------------

BEGIN;

-- Drop every CHECK constraint on transactions that constrains `source`
-- (the inline constraint is auto-named; look it up instead of guessing).
DO $$
DECLARE
    v_con record;
BEGIN
    FOR v_con IN
        SELECT c.conname
        FROM pg_constraint c
        JOIN pg_attribute a
          ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
        WHERE c.conrelid = 'public.transactions'::regclass
          AND c.contype = 'c'
          AND a.attname = 'source'
    LOOP
        EXECUTE format('ALTER TABLE public.transactions DROP CONSTRAINT %I', v_con.conname);
    END LOOP;
END $$;

-- 1. Relabel historical 'sms' rows (label only; see header).
UPDATE public.transactions
SET source = CASE
        WHEN raw_sms LIKE 'Chat:%' THEN 'chat'
        WHEN raw_sms LIKE 'Receipt Scan:%' THEN 'receipt_scan'
        ELSE 'manual'
    END
WHERE source = 'sms';

-- 2. No SMS channel for new rows.
ALTER TABLE public.transactions ALTER COLUMN source SET DEFAULT 'manual';
ALTER TABLE public.transactions
    ADD CONSTRAINT transactions_source_check
    CHECK (source IN ('chat', 'receipt_scan', 'manual'));

COMMENT ON COLUMN public.transactions.source IS
    'Ingestion channel: chat (chat/voice), receipt_scan (receipt photo or ZATCA QR), or manual. The app never reads SMS.';

-- 3. Re-document the audit note column (name kept for installed clients) and
--    the tables whose comments described an SMS pipeline.
COMMENT ON COLUMN public.transactions.raw_sms IS
    'Free-text audit note (chat text, receipt summary, manual/installment/settlement tags). Historical column name; the app never reads SMS.';
COMMENT ON TABLE public.transactions IS
    'Every household expense transaction (chat/voice, receipt or QR scan, manual entry).';
COMMENT ON TABLE public.cost_control_codes IS
    'Category taxonomy + keyword mapping for merchant matching (chat, receipt and manual entries).';

COMMIT;
