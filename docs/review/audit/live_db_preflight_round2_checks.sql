-- ============================================================================
-- Live pre-flight (part A) and post-apply (part B) checks for the round-2 pair
--   20261020700000_fable_db_hardening.sql
--   20261020800000_household_roles_and_nafaqah_integrity.sql
-- Read-only: every statement is a SELECT (aggregate counts and catalog reads,
-- no row data). Run in the Supabase SQL editor, or with any read-only role.
-- Context, expected values and the apply plan:
--   docs/review/audit/live_db_preflight_round2.md (part A: section 4, part B: section 7)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- A. PRE-APPLY (run right before file 1). Expected values at 2026-10-21 are in
--    section 4 of the report. A difference means data changed since then:
--    re-read the "Impact" column there before applying. Note the three totals
--    (budgets_spent_total, budgets_allocated_total, accounts_balance_total);
--    part B must print the same values.
-- ----------------------------------------------------------------------------
select
 (select count(*) from public.households) as households,
 (select count(*) from public.users) as users,
 (select count(*) from auth.users) as auth_users,
 (select count(*) from public.household_memberships) as memberships,
 (select count(*) from public.household_memberships where role = 'admin') as memberships_admin,
 (select count(*) from public.household_memberships where role = 'member') as memberships_member,
 (select count(*) from (select user_id from public.household_memberships group by 1 having count(*) > 1) x) as users_multi_membership,
 (select count(*) from public.household_memberships m left join public.users u on u.id = m.user_id where u.financial_role is null) as memberships_user_fr_null,
 (select count(*) from public.users where financial_role is not null and financial_role not in ('provider','spouse','peer','family_member','dependent')) as users_fr_unknown,
 (select count(*) from public.household_memberships m join public.users u on u.id = m.user_id where u.household_id is distinct from m.household_id) as memberships_not_active_hh,
 (select count(*) from public.users u where u.household_id is not null and not exists (select 1 from public.household_memberships m where m.user_id = u.id and m.household_id = u.household_id)) as users_active_hh_without_membership,
 (select count(*) from public.users u join public.household_memberships m on m.user_id = u.id and m.household_id = u.household_id where u.role is distinct from m.role) as users_role_ne_membership_role,
 (select count(*) from public.households where owner_user_id is null) as hh_owner_null,
 (select count(*) from public.households h where owner_user_id is null and exists (select 1 from public.household_memberships m where m.household_id = h.id)) as hh_owner_null_with_members,
 (select count(*) from public.households h where not exists (select 1 from public.household_memberships m where m.household_id = h.id)) as hh_without_members,
 (select count(*) from public.households h where h.owner_user_id is not null and not exists (select 1 from public.household_memberships m where m.household_id = h.id and m.user_id = h.owner_user_id and m.role = 'admin')) as hh_owner_not_admin_member,
 (select count(*) from public.households h join public.users u on u.id = h.owner_user_id where u.financial_role = 'spouse') as hh_owner_is_spouse,
 (select count(*) from public.households h join public.household_memberships m on m.household_id = h.id and m.user_id = h.owner_user_id join public.users u on u.id = m.user_id where coalesce(u.financial_role, 'provider') <> 'spouse') as expected_hh_with_provider,
 (select count(*) from public.households h join public.users u on u.id = h.owner_user_id where u.financial_role is null) as hh_owner_fr_null,
 (select count(*) from (select household_id from public.household_memberships where role = 'admin' group by 1 having count(*) > 1) x) as hh_multi_admin,
 (select count(*) from public.households h where exists (select 1 from public.household_memberships m join public.users u on u.id = m.user_id where m.household_id = h.id and u.financial_role = 'spouse')) as hh_with_spouse_member,
 (select count(*) from public.households h where exists (select 1 from public.household_memberships m join public.users u on u.id = m.user_id where m.household_id = h.id and u.financial_role = 'peer')) as hh_with_peer_member,
 (select count(*) from public.household_invites) as invites,
 (select count(*) from public.household_invites where used_by is null and expires_at >= now()) as invites_open,
 (select count(*) from public.household_invites where used_by is not null) as invites_used,
 (select count(*) from public.household_invites where used_by is null and expires_at < now()) as invites_expired,
 (select count(*) from public.household_invites i where i.used_by is not null and exists (select 1 from public.household_memberships m where m.household_id = i.household_id and m.user_id = i.used_by)) as invites_used_by_current_member,
 (select count(*) from public.household_invites i where i.created_by is not null and not exists (select 1 from public.users u where u.id = i.created_by)) as invites_creator_dangling,
 (select count(*) from public.household_invites i where i.used_by is not null and not exists (select 1 from public.users u where u.id = i.used_by)) as invites_claimer_dangling,
 (select count(*) from public.household_invites where created_by is null) as invites_creator_null,
 (select count(*) from public.household_dependents) as dependents,
 (select count(*) from public.household_dependents where linked_user_id is not null) as dependents_linked,
 (select count(*) from public.transactions) as transactions,
 (select count(*) from public.transactions where user_id is null) as tx_user_id_null,
 (select count(*) from public.transactions where nafaqah_class is not null) as tx_classified,
 (select count(*) from public.transactions where nafaqah_class = 'wife_personal') as tx_wife_personal,
 (select count(*) from public.transactions where nafaqah_class = 'wife_reimbursable') as tx_wife_reimbursable,
 (select count(*) from public.transactions where cycle_key is null) as tx_cycle_key_null,
 (select count(*) from (select t.cycle_key, (coalesce(t.timestamp, t.created_at) at time zone 'Asia/Riyadh')::date d, greatest(1, least(31, coalesce(h.payday_day, 27))) pp
     from public.transactions t join public.households h on h.id = t.household_id) x
   where x.cycle_key is distinct from to_char(date_trunc('month', d) + (case when extract(day from d) >= least(pp, extract(day from (date_trunc('month', d) + interval '1 month - 1 day')))
        then case when pp <= 15 then 0 else 1 end else case when pp <= 15 then -1 else 0 end end) * interval '1 month', 'YYYY-MM')) as tx_cycle_key_mismatch,
 (select count(*) from public.member_allowances) as member_allowances,
 (select count(*) from public.spouse_reimbursements) as spouse_reimbursements,
 (select count(*) from public.budgets) as budgets,
 (select coalesce(sum(spent_amount), 0) from public.budgets) as budgets_spent_total,
 (select coalesce(sum(allocated_amount), 0) from public.budgets) as budgets_allocated_total,
 (select count(*) from public.budgets b where b.spent_amount <> greatest(0, coalesce((select sum(t.amount) from public.transactions t
    where t.household_id = b.household_id and t.category_code = b.category_code and t.cycle_key = b.cycle_key
      and t.nafaqah_class is distinct from 'wife_personal' and t.is_settlement is not true), 0))) as budgets_spent_drift,
 (select count(*) from public.accounts) as accounts,
 (select coalesce(sum(balance), 0) from public.accounts) as accounts_balance_total,
 (select count(*) from public.cost_control_sub_categories) as sub_categories,
 (select count(*) from public.cost_control_codes where household_id is not null) as custom_categories,
 (select count(*) from public.households where payday_day is null) as hh_payday_null,
 (select string_agg(p || ':' || n, ',' order by p) from (select coalesce(payday_day::text, 'null') p, count(*) n from public.households group by 1) x) as payday_distribution,
 (select string_agg(r || '/' || f || ':' || n, ',' order by r, f) from (select m.role r, coalesce(u.financial_role, '<null>') f, count(*) n from public.household_memberships m join public.users u on u.id = m.user_id group by 1, 2) x) as membership_role_x_user_fr,
 (select string_agg(f || ':' || n, ',' order by f) from (select coalesce(financial_role, '<null>') f, count(*) n from public.users group by 1) x) as users_fr_distribution,
 (select count(*) from information_schema.columns where table_schema = 'public' and ((table_name = 'household_memberships' and column_name = 'financial_role') or (table_name = 'households' and column_name = 'nafaqah_provider_user_id'))) as new_cols_present,
 (select string_agg(a.attname || ':' || c.confdeltype::text, ',' order by a.attname) from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.conrelid = 'public.household_invites'::regclass and c.contype = 'f' and a.attname in ('created_by', 'used_by')) as invite_fk_actions,
 (select string_agg(policyname, ',' order by policyname) from pg_policies where schemaname = 'public' and tablename = 'household_invites') as invite_policies,
 (select string_agg(a.attname, ',' order by a.attname) from pg_attribute a where a.attrelid = 'public.households'::regclass and a.attnum > 0 and not a.attisdropped
    and has_column_privilege('authenticated', a.attrelid, a.attnum, 'UPDATE')) as hh_auth_update_cols,
 (select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','p')
    and (has_table_privilege('anon', c.oid, 'TRUNCATE') or has_table_privilege('authenticated', c.oid, 'TRUNCATE')
         or has_table_privilege('anon', c.oid, 'TRIGGER') or has_table_privilege('authenticated', c.oid, 'TRIGGER')
         or has_table_privilege('anon', c.oid, 'REFERENCES') or has_table_privilege('authenticated', c.oid, 'REFERENCES')
         or has_any_column_privilege('anon', c.oid, 'INSERT') or has_any_column_privilege('anon', c.oid, 'UPDATE') or has_table_privilege('anon', c.oid, 'DELETE'))) as tables_with_unneeded_client_privs,
 case when current_setting('server_version_num')::int >= 170000 then (select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','p')
    and (has_table_privilege('anon', c.oid, 'MAINTAIN') or has_table_privilege('authenticated', c.oid, 'MAINTAIN'))) end as tables_client_maintain_pg17,
 has_function_privilege('authenticated', 'public.nafaqah_current_cycle_key(uuid)', 'EXECUTE') as auth_x_nafaqah_cycle_key,
 has_function_privilege('authenticated', 'public.generate_secure_invite_code()', 'EXECUTE') as auth_x_gen_invite_code,
 (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.oid in (
    to_regprocedure('public.get_saudi_cycle_for_timestamp(timestamptz, integer)'), to_regprocedure('public.household_resolve_actor(uuid)'),
    to_regprocedure('public.household_require_admin(uuid, uuid)'), to_regprocedure('public.household_member_role(uuid, uuid)'),
    to_regprocedure('public.populate_transaction_cycle_key()'), to_regprocedure('public.record_spouse_reimbursement(uuid, uuid, numeric, text, text, uuid)'),
    to_regprocedure('public.household_primary_admin_id(uuid)'), to_regprocedure('public.household_apply_role(uuid, uuid, text)'))) as guard_functions_present,
 (select count(*) from supabase_migrations.schema_migrations) as migrations_recorded,
 (select max(version) from supabase_migrations.schema_migrations) as last_migration;

-- ----------------------------------------------------------------------------
-- B. POST-APPLY (run after file 2). Fails before the pair is applied (it reads
--    the new columns and functions). Expected values: section 7 of the report.
--    tables_client_maintain_pg17 is NULL on PostgreSQL 16 (local replica) and
--    0 on live (PostgreSQL 17).
-- ----------------------------------------------------------------------------
select
 (select count(*) from public.households) as households,
 (select count(*) from public.household_memberships) as memberships,
 (select count(*) from public.household_memberships where financial_role is null) as memberships_fr_null,
 (select string_agg(r || '/' || f || ':' || n, ',' order by r, f) from (select role r, financial_role f, count(*) n from public.household_memberships group by 1, 2) x) as membership_role_x_fr,
 (select count(*) from public.household_memberships m join public.users u on u.id = m.user_id and u.household_id = m.household_id where u.financial_role is distinct from m.financial_role) as users_fr_cache_mismatch,
 (select attnotnull from pg_attribute where attrelid = 'public.household_memberships'::regclass and attname = 'financial_role') as membership_fr_not_null,
 (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.household_memberships'::regclass and conname = 'household_memberships_financial_role_check') as membership_fr_check,
 (select count(*) from public.households where nafaqah_provider_user_id is not null) as hh_with_provider,
 (select count(*) from public.households where nafaqah_provider_user_id is not null and nafaqah_provider_user_id = owner_user_id) as hh_provider_is_primary_admin,
 (select count(*) from public.households where nafaqah_provider_user_id is not null and nafaqah_provider_user_id is distinct from owner_user_id) as hh_provider_not_primary_admin,
 (select count(*) from public.households where owner_user_id is not null and nafaqah_provider_user_id is null) as hh_owner_but_no_provider,
 (select count(*) from public.households where owner_user_id is null and nafaqah_provider_user_id is null) as hh_no_owner_no_provider,
 (select count(*) from public.households h where h.nafaqah_provider_user_id is not null and not exists (select 1 from public.household_memberships m where m.household_id = h.id and m.user_id = h.nafaqah_provider_user_id and m.financial_role <> 'spouse')) as hh_provider_invalid,
 (select pg_get_constraintdef(c.oid) from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1] where c.conrelid = 'public.households'::regclass and c.contype = 'f' and a.attname = 'nafaqah_provider_user_id') as provider_fk,
 (select string_agg(a.attname || ':' || c.confdeltype::text, ',' order by a.attname) from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.conrelid = 'public.household_invites'::regclass and c.contype = 'f' and a.attname in ('created_by', 'used_by')) as invite_fk_actions,
 (select string_agg(policyname || '=' || cmd, ',' order by policyname) from pg_policies where schemaname = 'public' and tablename = 'household_invites') as invite_policies,
 (select qual from pg_policies where schemaname = 'public' and tablename = 'household_invites' and policyname = 'invites_select_admin') as invites_select_qual,
 (select string_agg(a.attname, ',' order by a.attname) from pg_attribute a where a.attrelid = 'public.households'::regclass and a.attnum > 0 and not a.attisdropped
    and has_column_privilege('authenticated', a.attrelid, a.attnum, 'UPDATE')) as hh_auth_update_cols,
 (select string_agg(a.attname, ',' order by a.attname) from pg_attribute a where a.attrelid = 'public.household_dependents'::regclass and a.attnum > 0 and not a.attisdropped
    and has_column_privilege('authenticated', a.attrelid, a.attnum, 'UPDATE')) as dependents_auth_update_cols,
 (select string_agg(a.attname, ',' order by a.attname) from pg_attribute a where a.attrelid = 'public.household_dependents'::regclass and a.attnum > 0 and not a.attisdropped
    and has_column_privilege('authenticated', a.attrelid, a.attnum, 'INSERT')) as dependents_auth_insert_cols,
 (select string_agg(a.attname, ',' order by a.attname) from pg_attribute a where a.attrelid = 'public.users'::regclass and a.attnum > 0 and not a.attisdropped
    and has_column_privilege('authenticated', a.attrelid, a.attnum, 'INSERT')) as users_auth_insert_cols,
 (select string_agg(a.attname, ',' order by a.attname) from pg_attribute a where a.attrelid = 'public.users'::regclass and a.attnum > 0 and not a.attisdropped
    and has_column_privilege('authenticated', a.attrelid, a.attnum, 'UPDATE')) as users_auth_update_cols,
 has_column_privilege('authenticated', 'public.households', 'nafaqah_provider_user_id', 'UPDATE') as auth_can_update_provider,
 has_any_column_privilege('authenticated', 'public.household_memberships', 'INSERT') or has_any_column_privilege('authenticated', 'public.household_memberships', 'UPDATE') as auth_can_write_memberships,
 (select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','p')
    and (has_table_privilege('anon', c.oid, 'TRUNCATE') or has_table_privilege('authenticated', c.oid, 'TRUNCATE')
         or has_table_privilege('anon', c.oid, 'TRIGGER') or has_table_privilege('authenticated', c.oid, 'TRIGGER')
         or has_table_privilege('anon', c.oid, 'REFERENCES') or has_table_privilege('authenticated', c.oid, 'REFERENCES')
         or has_any_column_privilege('anon', c.oid, 'INSERT') or has_any_column_privilege('anon', c.oid, 'UPDATE') or has_table_privilege('anon', c.oid, 'DELETE'))) as tables_with_unneeded_client_privs,
 (select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','p') and has_table_privilege('service_role', c.oid, 'TRUNCATE')) as tables_service_role_truncate,
 case when current_setting('server_version_num')::int >= 170000 then (select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','p')
    and (has_table_privilege('anon', c.oid, 'MAINTAIN') or has_table_privilege('authenticated', c.oid, 'MAINTAIN'))) end as tables_client_maintain_pg17,
 has_function_privilege('authenticated', 'public.nafaqah_current_cycle_key(uuid)', 'EXECUTE') as auth_x_nafaqah_cycle_key,
 has_function_privilege('authenticated', 'public.generate_secure_invite_code()', 'EXECUTE') as auth_x_gen_invite_code,
 has_function_privilege('service_role', 'public.nafaqah_current_cycle_key(uuid)', 'EXECUTE') as svc_x_nafaqah_cycle_key,
 has_function_privilege('anon', 'public.reallocate_budget(uuid, uuid, numeric)', 'EXECUTE') as anon_x_reallocate,
 has_function_privilege('authenticated', 'public.set_nafaqah_provider(uuid, uuid, uuid)', 'EXECUTE') as auth_x_set_provider,
 has_function_privilege('anon', 'public.set_nafaqah_provider(uuid, uuid, uuid)', 'EXECUTE') as anon_x_set_provider,
 has_function_privilege('authenticated', 'public.rekey_household_cycles(uuid, integer, integer, timestamptz)', 'EXECUTE') as auth_x_rekey,
 has_function_privilege('authenticated', 'public.nafaqah_husband_id(uuid)', 'EXECUTE') as auth_x_husband_id,
 (select count(*) from (values ('set_nafaqah_provider'), ('household_member_financial_role'), ('household_default_financial_role'), ('membership_financial_role_rules'),
    ('membership_financial_role_cache'), ('clear_nafaqah_provider_on_membership_end'), ('households_nafaqah_provider_rules'), ('refuse_invite_claim_by_member'),
    ('guard_wife_reimbursable_ledger'), ('recompute_budget_spent'), ('rekey_household_cycles'), ('rekey_cycles_on_payday_change')) f(n)
    where not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = f.n)) as new_functions_missing,
 (select string_agg(tgname, ',' order by tgname) from pg_trigger where not tgisinternal and tgrelid = 'public.household_memberships'::regclass) as membership_triggers,
 (select string_agg(tgname, ',' order by tgname) from pg_trigger where not tgisinternal and tgrelid = 'public.households'::regclass) as households_triggers,
 (select string_agg(tgname, ',' order by tgname) from pg_trigger where not tgisinternal and tgrelid = 'public.household_invites'::regclass) as invites_triggers,
 (select string_agg(tgname, ',' order by tgname) from pg_trigger where not tgisinternal and tgrelid = 'public.transactions'::regclass) as transactions_triggers,
 (select count(*) from pg_policies where schemaname in ('public', 'storage') and (roles::text ~ '(public|anon)')) as policies_to_public_or_anon,
 (select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and not c.relrowsecurity) as tables_without_rls,
 (select string_agg(p || ':' || n, ',' order by p) from (select coalesce(payday_day::text, 'null') p, count(*) n from public.households group by 1) x) as payday_distribution,
 (select count(*) from public.transactions) as transactions,
 (select count(*) from public.transactions where cycle_key is null) as tx_cycle_key_null,
 (select string_agg(k || ':' || n, ',' order by k) from (select cycle_key k, count(*) n from public.transactions group by 1) x) as tx_cycle_keys,
 (select string_agg(k || ':' || n, ',' order by k) from (select cycle_key k, count(*) n from public.budgets group by 1) x) as budget_cycle_keys,
 (select count(*) from public.budgets) as budgets,
 (select coalesce(sum(spent_amount), 0) from public.budgets) as budgets_spent_total,
 (select coalesce(sum(allocated_amount), 0) from public.budgets) as budgets_allocated_total,
 (select coalesce(sum(balance), 0) from public.accounts) as accounts_balance_total,
 (select count(*) from public.household_invites) as invites,
 (select count(*) from public.household_dependents) as dependents,
 (select count(*) from public.users) as users;
