-- ============================================================================
-- Live pre-flight and post-apply checks for the 20261020 audit batch.
-- Read-only: every statement is a SELECT. Run in the Supabase SQL editor.
-- Context, expected values and the apply plan: docs/review/audit/live_db_preflight.md
-- ============================================================================

-- ----------------------------------------------------------------------------
-- A. PRE-APPLY: aggregate counts only (no row data). Expected values at
--    2026-10-20 are in live_db_preflight.md, section 4. Run right before
--    applying and compare; a difference means data changed since then, so
--    re-read the "Impact" column of that section.
-- ----------------------------------------------------------------------------
select
 (select count(*) from public.households) as households,
 (select count(*) from public.users) as users,
 (select count(*) from auth.users) as auth_users,
 (select count(*) from public.users u where not exists (select 1 from auth.users a where a.id=u.id)) as public_users_without_auth,
 (select count(*) from public.household_memberships) as memberships,
 (select count(*) from public.transactions) as transactions,
 (select count(*) from public.transactions where user_id is null) as tx_user_id_null,
 (select count(*) from public.transactions t where t.user_id is not null and not exists (select 1 from public.household_memberships m where m.household_id=t.household_id and m.user_id=t.user_id)) as tx_creator_not_member,
 (select count(*) from public.transactions where source='sms') as tx_source_sms,
 (select count(*) from public.transactions where source='sms' and raw_sms like 'Chat:%') as sms_to_chat,
 (select count(*) from public.transactions where source='sms' and raw_sms like 'Receipt Scan:%') as sms_to_receipt_scan,
 (select count(*) from public.transactions where source='sms' and (raw_sms is null or (raw_sms not like 'Chat:%' and raw_sms not like 'Receipt Scan:%'))) as sms_to_manual,
 (select count(*) from public.transactions where source is null) as tx_source_null,
 (select count(*) from public.transactions where source is not null and source not in ('sms','chat','receipt_scan','manual')) as tx_source_other,
 (select string_agg(s, ',' order by s) from (select distinct source as s from public.transactions where source is not null) x) as tx_source_labels,
 (select count(*) from public.transactions where spent_by is not null and spent_by not in ('me','partner','both')) as tx_spent_by_invalid,
 (select count(*) from public.transactions where cycle_key is null) as tx_cycle_key_null,
 (select count(*) from (select t.cycle_key, (coalesce(t.timestamp, t.created_at) at time zone 'Asia/Riyadh')::date d, greatest(1, least(31, coalesce(h.payday_day, 27))) pp
     from public.transactions t join public.households h on h.id=t.household_id) x
   where x.cycle_key is distinct from to_char(date_trunc('month', d) + (case when extract(day from d) >= least(pp, extract(day from (date_trunc('month', d) + interval '1 month - 1 day')))
        then case when pp <= 15 then 0 else 1 end else case when pp <= 15 then -1 else 0 end end) * interval '1 month', 'YYYY-MM')) as tx_cycle_key_mismatch,
 (select count(*) from public.transactions t join public.accounts a on a.id=t.account_id
   where a.is_shared_pool=false and (t.user_id is null or a.owner_user_id <> t.user_id)) as tx_personal_account_not_creator,
 (select count(*) from public.transactions t join public.accounts a on a.id=t.account_id where a.household_id<>t.household_id) as tx_account_other_household,
 (select count(*) from public.households h where not exists (select 1 from public.household_memberships m where m.household_id=h.id and m.role='admin')) as hh_without_admin,
 (select count(*) from public.households h where not exists (select 1 from public.household_memberships m where m.household_id=h.id)) as hh_without_members,
 (select count(*) from public.households h where not exists (select 1 from public.household_memberships m where m.household_id=h.id and m.role='admin') and exists (select 1 from public.household_memberships m where m.household_id=h.id)) as hh_members_but_no_admin,
 (select count(*) from (select household_id from public.household_memberships where role='admin' group by 1 having count(*)>1) x) as hh_multi_admin,
 (select count(*) from public.users u where u.household_id is not null and not exists (select 1 from public.household_memberships m where m.user_id=u.id and m.household_id=u.household_id)) as users_active_hh_without_membership,
 (select count(*) from public.users u join public.household_memberships m on m.user_id=u.id and m.household_id=u.household_id where u.role is distinct from m.role) as users_role_ne_membership_role,
 (select count(*) from public.users u join public.household_memberships m on m.user_id=u.id and m.household_id=u.household_id where u.role='admin' and m.role<>'admin') as users_admin_but_member_membership,
 (select count(*) from public.household_invites) as invites,
 (select count(*) from public.household_invites i where i.target_member_id is not null and not exists (select 1 from public.household_dependents d where d.id=i.target_member_id and d.household_id=i.household_id)) as invites_target_other_household,
 (select count(*) from public.household_dependents) as dependents,
 (select count(*) from public.users where financial_role='spouse') as users_spouse,
 (select count(*) from public.users where financial_role='provider') as users_provider,
 (select count(*) from public.accounts) as accounts,
 (select count(*) from public.accounts where is_shared_pool) as shared_pools,
 (select count(*) from public.accounts a where a.is_shared_pool and not exists (select 1 from public.household_memberships m where m.household_id=a.household_id and m.user_id=a.owner_user_id and m.role='admin')) as pools_owner_not_admin,
 (select count(*) from public.income_records) as income_records,
 (select count(*) from public.account_transfers) as account_transfers,
 (select count(*) from public.budgets) as budgets,
 (select count(*) from public.cost_control_codes where household_id is not null) as custom_categories,
 (select count(*) from public.api_quota) as api_quota_rows,
 (select count(*) from public.invite_attempt_log) as invite_attempts,
 (select count(*) from public.budgets_spent_backup_20261019) as backup_rows,
 (select count(*) from storage.objects where bucket_id='receipts') as receipt_objects,
 (select count(*) from storage.objects where bucket_id='receipts' and coalesce((metadata->>'size')::bigint,0) > 20*1024*1024) as receipts_over_20mib,
 (select count(*) from storage.objects where bucket_id='receipts' and coalesce(metadata->>'mimetype','') not in ('image/jpeg','image/png','image/webp')) as receipts_other_mime,
 (select count(*) from information_schema.columns where table_schema='public' and table_name='transactions' and column_name in ('paid_by','beneficiary')) as tx_paid_by_beneficiary_cols,
 (select count(*) from information_schema.columns where table_schema='public' and table_name='transactions' and column_name in ('nafaqah_class','nafaqah_spouse_id')) as tx_nafaqah_cols,
 (select count(*) from information_schema.columns where table_schema='public' and table_name='households' and column_name='owner_user_id') as hh_owner_col,
 (select count(*) from public.households where rollover_rule is not null and rollover_rule not in ('send_to_savings','rollover_to_categories','fresh_start')) as hh_rollover_rule_unrecognised,
 (select string_agg(r, ',' order by r) from (select distinct coalesce(rollover_rule,'<null>') as r from public.households) x) as hh_rollover_rule_values
;

-- Also note these two totals (your own aggregates) before AND after applying;
-- they must not change (no migration in the batch moves money):
SELECT (SELECT sum(spent_amount) FROM public.budgets) AS budgets_spent_total,
       (SELECT sum(balance) FROM public.accounts) AS accounts_balance_total;

-- ----------------------------------------------------------------------------
-- B. POST-APPLY: run after the last file. Expected values are in
--    live_db_preflight.md, section 7 (budgets_spent_total and
--    accounts_balance_total must equal the values noted before applying).
-- ----------------------------------------------------------------------------
select
 (select count(*) from public.transactions) as transactions,
 (select count(*) from public.transactions where source = 'sms') as tx_sms,
 (select count(*) from public.transactions where source = 'chat') as tx_chat,
 (select count(*) from public.transactions where source = 'receipt_scan') as tx_receipt_scan,
 (select count(*) from public.transactions where source = 'manual') as tx_manual,
 (select pg_get_expr(d.adbin, d.adrelid) from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
   where d.adrelid = 'public.transactions'::regclass and a.attname = 'source') as source_default,
 (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.transactions'::regclass and conname = 'transactions_source_check') as source_check,
 (select count(*) from public.transactions where user_id is null) as tx_user_id_null,
 (select sum(spent_amount) from public.budgets) as budgets_spent_total,
 (select sum(balance) from public.accounts) as accounts_balance_total,
 (select count(*) from public.households) as households,
 (select count(*) from public.households where owner_user_id is not null) as hh_with_primary_admin,
 (select count(*) from public.households h where owner_user_id is not null and not exists
   (select 1 from public.household_memberships m where m.household_id = h.id and m.user_id = h.owner_user_id and m.role = 'admin')) as hh_primary_not_admin,
 (select count(*) from public.households h where owner_user_id is null and exists
   (select 1 from public.household_memberships m where m.household_id = h.id and m.role = 'admin')) as hh_admin_but_no_primary,
 (select count(*) from public.household_memberships) as memberships,
 (select relrowsecurity from pg_class where oid = 'public.household_invites'::regclass) as invites_rls,
 (select relrowsecurity from pg_class where oid = to_regclass('public.member_allowances')) as member_allowances_rls,
 (select relrowsecurity from pg_class where oid = to_regclass('public.spouse_reimbursements')) as spouse_reimbursements_rls,
 (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'transactions' and column_name in ('nafaqah_class', 'nafaqah_spouse_id')) as tx_nafaqah_cols,
 (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'households' and column_name in ('owner_user_id', 'rollover_rule')) as hh_new_cols,
 (select file_size_limit from storage.buckets where id = 'receipts') as receipts_size_limit,
 (select allowed_mime_types::text from storage.buckets where id = 'receipts') as receipts_mimes,
 (select public from storage.buckets where id = 'receipts') as receipts_public,
 (select count(*) from pg_policies where schemaname = 'public' and tablename = 'household_memberships' and policyname = 'memberships_admin_manage') as recursive_policy_left,
 (select string_agg(policyname, ',' order by policyname) from pg_policies where schemaname = 'public' and tablename = 'cost_control_codes') as ccc_policies,
 (select string_agg(policyname, ',' order by policyname) from pg_policies where schemaname = 'storage' and tablename = 'objects') as storage_policies,
 (select count(*) from pg_policies where schemaname in ('public', 'storage') and not (roles <@ array['authenticated', 'service_role']::name[])) as policies_to_public_or_anon,
 (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity) as tables_without_rls,
 (select string_agg(p.proname, ',' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'EXECUTE')
     and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')) as anon_executable_app_functions,
 (select string_agg(p.proname, ',' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) cfg where cfg like 'search_path=%')) as definer_without_search_path,
 (select count(*) from unnest(array[
    'reallocate_budget(uuid,uuid,numeric)', 'consume_quota(uuid,text,integer,integer)', 'check_quota_status(uuid,text,integer,integer)',
    'transfer_between_accounts(uuid,uuid,uuid,numeric,numeric,text)', 'record_income(uuid,uuid,text,text,text,numeric,numeric,numeric,numeric,timestamptz,text)',
    'join_household_by_code(text)', 'claim_household_role_invite(text,uuid)', 'create_household_and_claim(text)', 'get_user_households()',
    'switch_active_household(uuid)', 'leave_household()', 'revoke_invite(text)', 'set_member_role(uuid,text)', 'remove_member(uuid)',
    'get_member_allowance_status(uuid,uuid,text,uuid)', 'set_member_allowance(uuid,uuid,numeric,text,uuid)',
    'get_spouse_reimbursement_balance(uuid,uuid,uuid)', 'record_spouse_reimbursement(uuid,uuid,numeric,text,text,uuid)',
    'get_household_members(uuid,uuid)', 'promote_member_to_admin(uuid,uuid,uuid)', 'revoke_admin(uuid,uuid,uuid)',
    'transfer_primary_admin(uuid,uuid,uuid)', 'reconcile_account_balance(uuid,numeric)', 'get_saudi_cycle_for_timestamp(timestamptz,integer)'
  ]) f where to_regprocedure('public.' || f) is null) as expected_functions_missing,
 (select string_agg(tgname, ',' order by tgname) from pg_trigger where tgrelid = 'public.transactions'::regclass and not tgisinternal) as transactions_triggers,
 (select count(*) from pg_trigger where tgrelid = 'public.household_memberships'::regclass and tgname in ('trg_protect_primary_admin', 'trg_maintain_primary_admin')) as membership_role_triggers,
 (select has_function_privilege('anon', 'public.reallocate_budget(uuid,uuid,numeric)', 'EXECUTE')) as anon_can_reallocate,
 (select has_table_privilege('authenticated', 'public.income_records', 'INSERT')) as auth_can_insert_income,
 (select has_column_privilege('authenticated', 'public.households', 'owner_user_id', 'UPDATE')) as auth_can_update_owner
;
