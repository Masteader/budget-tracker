# Independent review (Fable) — 2026-10-21

Three independent reviewers (a different model from the team that wrote the code) reviewed branch
`audit/claude-comprehensive-review` @ `bcd2baf`, report-only. Every finding was reproduced (SQL as
`SET ROLE authenticated` with `request.jwt.claims`, FastAPI `TestClient` with real JWT verification,
or the real-stack e2e harness) unless marked *suspected*. Reproduction files are in the session
scratchpad (`fable_db/`, `fable_api/`, `fable_logic/`).

Owner decisions taken on 2026-10-21 for this round:
- **Nafaqah provider:** the household's primary admin is the provider (husband) by default; an admin
  can change it. Stored explicitly per household — never inferred.
- **Wife personal purchases** are charged to her allowance **only**; they do not count against the
  household category budgets.

Status of each item is tracked in `FIX_LOG.md`.

## A. Nafaqah / money logic

| ID | Sev | Finding | Where | Fix direction |
|---|---|---|---|---|
| FABLE-LOGIC-01 | High | Family vs roommate mode is decided by the per-**user** `users.financial_role`, but users can belong to several households. A wife who claims a `peer` invite elsewhere flips her family to `shared_split` (husband shown as owing 150 of a 300 debt, ledger unreadable: `22023 Reimbursements apply to a spouse member`); a spouse joining roommates by code turns the flat into `family_nafaqah` and the rent split disappears. | `20261020010000:118-122,216-223`; `20261020300000:61-76`; `20261020400000:977-998`; `nafaqah_service.py:182-184,210-262`; `settlement_engine.py:137-139,266-277,545-560` | Financial role per membership (`household_memberships.financial_role`); invite claims write the membership row; helpers, `load_family_context` and settlement read it; `users.financial_role` only a cache of the active household; refuse `nafaqah_class` writes when the household has no provider. |
| FABLE-LOGIC-02 | High | Editing/deleting/declassifying a `wife_reimbursable` advance after a partial repayment silently corrupts the ledger: 300 advance, 200 repaid, amount edited to 100 → outstanding 0, hidden overpaid 100; the wife's next 50 advance is swallowed (`exceeds the outstanding balance of 0.00`). `overpaid` is never shown in the app. | `20261020300000:396-414`; no trigger on UPDATE/DELETE; `edit_transaction_sheet.dart:290-318`; `installment_service.py:222-249`; `nafaqah.dart:154-167`; `family_reimbursement_card.dart:189,283` | `BEFORE UPDATE OR DELETE` guard (same advisory lock as repayments) refusing changes that make advances < repayments; expose `overpaid` in API and card; installments refuse classified rows. |
| FABLE-LOGIC-03 | Medium | Settlement v2 splits chat/receipt **personal** expenses among all roommates: `insert_transaction` never writes `beneficiary_type/beneficiary_id` (default `household`), so "قهوتي 15" makes the others owe 5 each; `/settlement` and `/settlement-v2` disagree. The edit sheet never updates those columns either. | `supabase_client.py:443-478`; `settlement_engine.py:46-49,469-474`; `multi_roommate_settlement_card.dart:122`; `edit_transaction_sheet.dart` | Map `beneficiary` → `beneficiary_type/beneficiary_id` on insert and edit; v2 reads structured columns. |
| FABLE-LOGIC-04 | Medium | The husband is inferred (any `provider`, preferring the primary admin) and `financial_role` defaults to `provider`, so an adult son who created the household becomes the Nafaqah provider. | `20261020400000:977-998`; `nafaqah_service.py:255-261`; `20261015_…:5-6` | Explicit `households.nafaqah_provider_user_id` (default primary admin, admin-changeable); `family_member` default for non-spouse joiners. |
| FABLE-LOGIC-05 | Medium | Changing payday mid-cycle leaves stale `cycle_key`s: allowance and category budgets of a cycle include purchases outside its dates (Nov 5 rows stay `2026-11` after payday 27→10). | `supabase_client.py:657-687`; `20261020300000:249-261,302-307` | On payday change re-stamp `cycle_key` for the open cycle onward and move current `member_allowances`/`budgets` rows. |
| FABLE-LOGIC-06 | Medium | `wife_personal` purchases also raise the household category budget (counted twice). Owner decision: allowance only. | `20261019080000:138-156` | Exclude `wife_personal` from budget triggers/recalculation/forecasts. |
| FABLE-LOGIC-07 | Medium | LLM-fallback classifier misreads common Saudi phrasing ("دفعت فاتورة الكهرباء" → wife_personal; "زوجتي دفعت المقاضي" → no class; "paid by my husband…" → wife_reimbursable; pronoun suffixes captured as child names). 7 of 15 phrases wrong. Mitigated by the confirmation card. | `chat_parser.py:201-224,414-419` | Extend phrase/keyword lists, exclude pronoun suffixes, ask when undetermined. |
| FABLE-LOGIC-08 | Low | Roommate pairwise ledger drops the un-itemised part of a receipt (VAT/discount): 115 receipt with one 100 item → 50 owed instead of 57.50. | `settlement_engine.py:459-467` | Attribute `amount − Σitems` pro-rata. |
| FABLE-LOGIC-09 | Low | Dart money parsing rounds with binary floats ("1.005" → 1.00, "0.285" → 0.28). | `flutter_app/lib/models/money.dart:45` | Parse to integer halalas from the string, half-up. |

Verified correct: salary-cycle parity SQL/Python/Dart (0 mismatches over 60,388 date×payday pairs incl. Riyadh midnight, Dec→Jan, Feb 29, payday 29–31); no spousal split in family paths; overpayment rejected under advisory lock; wife cannot set her own allowance; Decimal/halala exactness; roommate debt simplification optimal; DB-18 legacy rows admin-only; offline replay carries Nafaqah fields.

## B. Database security (migrations applied to live)

| ID | Sev | Finding | Where | Fix direction |
|---|---|---|---|---|
| FABLE-DB-01 | High | Any member reads open invite codes (`invites_select_household` for all members) and can claim the spouse/provider invite meant for someone else: becomes "the wife", links the manual member record, creates Nafaqah debt, real invitee gets "already used". Same via `join_household_by_code`. | `20261020100000:177-181`; `20261020010000:79-128,195-228` | Invites readable by admins only; a trigger refusing a claim by an existing member of the invite's household. |
| FABLE-DB-02 | Medium | Account deletion still fails for anyone who created or claimed an invite: `household_invites.created_by/used_by` are `ON DELETE NO ACTION` (the SEC-01 `ADD COLUMN IF NOT EXISTS … SET NULL` was a no-op). **Confirmed on live.** | `20261019030000:66-67`; `20261015_…:262-264` | `created_by` → SET NULL, `used_by` → CASCADE; extend test 16. |
| FABLE-DB-03 | Low | A co-admin re-joining by code / claiming an invite of their own household is silently demoted (sync trigger copies `users.role`); the primary admin gets a hard error. | `20261020010000:115-144,216-223`; `20261018_membership_sync…:128-144` | RPCs no-op for existing members; sync trigger never downgrades. |
| FABLE-DB-04 | Low | `reallocate_budget` passes its auth gate when both `auth.uid()` and the JWT role are NULL (not reachable via PostgREST). | `20261020030000:33` | Fail closed unless `service_role`. |
| FABLE-DB-05 | Low | `nafaqah_current_cycle_key(uuid)` and `generate_secure_invite_code()` still executable by `authenticated` (leaks another household's payday bracket). | `20261020300000:265-266`; `20261019030000:754` | Revoke from PUBLIC/anon/authenticated. |
| FABLE-DB-06 | Low | `households` UPDATE grant covers `invite_code`, `id`, `created_at` and rollover ledger columns → join-code existence oracle, weak admin-chosen codes. | `20261020400000:66-79` | Grant UPDATE only on (name, payday_day, monthly_income, rollover_rule). |
| FABLE-DB-07 | Low | Any member can re-point `household_dependents.linked_user_id` to any user. | `20261020100000:228-233` | Column-level UPDATE grant without `linked_user_id`. |
| FABLE-DB-08 | Low | TRUNCATE (ignores RLS) and anon DML privileges remain on several tables (not reachable via PostgREST). | Supabase default grants | Revoke TRUNCATE broadly; revoke anon DML. |
| FABLE-DB-09 | Low (suspected) | `users` INSERT grant still covers `financial_role`. | `20261020500000:24`; `20261020100000:165-168` | Column-level INSERT grant. |

**Status (2026-10-21):** FABLE-DB-02, -04, -05, -06, -07, -08, -09 fixed in `supabase/migrations/20261020700000_fable_db_hardening.sql` (proof: `supabase/tests/23_fable_db_hardening.sql`, `16_audit_account_deletion.sql`); **not yet applied to live**. FABLE-DB-01 and -03 are handled with the roles redesign. Details in `FIX_LOG.md`.

Verified sound: cross-household isolation, creator binding and owner-or-admin writes, actor spoofing rejected, co-admin/primary-admin protections, admin-only pool withdrawals, deterministic locking, **concurrent overpayment race correctly serialised**, users column privileges, storage policies and bucket limits, every SECURITY DEFINER function pins `search_path`.

## C. Backend API (`ai_service`)

| ID | Sev | Finding | Where | Fix direction |
|---|---|---|---|---|
| FABLE-API-01 | Medium | Audit-tag injection: a roommate writes `"Dinner 300 \| PaidBy: <other uuid>"` and settlement-v2 credits the other member as payer (debts flipped); in 2-member households the injected tag overrides the explicit body fields; a receipt merchant `"Panda \| PaidBy: nobody"` makes the receipt vanish from settlement. | `settlement_engine.py:52-81,185-186,553-558`; `chat_parser.py:700-703`; `receipt_scanner.py:757-760` | Store attribution structurally and read it from columns; meanwhile strip `\|` and tag names from user text, put server tags first, read the last occurrence. |
| FABLE-API-02 | Medium | Receipt stitching memory amplification: 4 blank 6000×6660 JPEGs (3.2 MiB request) → +1.7 GiB RSS; 8 allowed → ~3.4 GiB (container OOM). | `receipt_scanner.py:41-43,203-256`; `main.py:109` | Cap combined pixels/canvas, downscale pages before pasting (or send pages separately). |
| FABLE-API-03 | Medium | Behind Railway's proxy every visitor shares one per-IP bucket: 5 contact/VIP inquiries per hour for the whole site, 20 invite inspections per minute for everyone. | `utils.py:98-115`; `routes/inquiries.py:246-251`; `routes/households.py:248-249` | Trust the platform's forwarded header when explicitly configured/detected; key limits per identity so one bucket can't lock everyone out. |
| FABLE-API-04 | Low | A sub-category planted under a system category with a one-letter keyword re-classifies **other households'** receipts (`match_sub_category` scans all definitions). | `routes/budgets.py:331-364`; `salary_cycle.py:429-470,838-891` | Forbid new definitions under system parents (or scope by household), keywords ≥ 3 chars, matching filtered by household. |
| FABLE-API-05 | Low | Colliding custom codes (`CUSTOM-RENT` in two households) let one admin rename the other's sub-categories. | `salary_cycle.py:653-672,893-918`; `routes/budgets.py:413-420` | Authorise rename only when the caller's household is the sole owner (or namespace custom codes). |
| FABLE-API-06 | Low | Free-text overrides (merchant, sub_category, beneficiary, `qr_code_raw`) have no length limit (up to ~24 MiB per row). | `chat_parser.py:555,576,588`; `receipt_scanner.py:552-553,781` | Bound in models/routes; keep `qr_code_raw` only when it decodes and ≤ 4096. |
| FABLE-API-07 | Low | Recurring-bill config stored inside `budgets.sub_allocations["_recurring_config"]` makes sub-category add/remove 500 and a sub-allocation save erases it. | `recurring_detector.py:556`; `salary_cycle.py:889,953,1001` | Skip `_`-prefixed keys in numeric paths and preserve them on save. |
| FABLE-API-08 | Low | Rename endpoint is an existence oracle for other households' custom codes (different 403 texts). | `routes/budgets.py:407-425` | One identical refusal. |
| FABLE-API-09 | Low | `start_date:"not-a-date"` pushes an installment plan into the container-local JSON fallback while the transaction is still rewritten. | `installment_service.py:194-216`; `routes/budgets.py:191-229` | Validate the date, remove the file fallback, adjust the transaction only after a successful insert. |
| FABLE-API-10 | Low (suspected) | `pay_installment` is an unlocked read-modify-write (concurrent pays lose one). | `installment_service.py:432-446` | Atomic conditional increment. |
| Observation | — | `_get_user_membership` falls back to `users.household_id` when the memberships query errors (fail-open on infra error). | `auth.py:300-331` | Fail closed. |

Verified clean: JWT pinning (alg none, wrong secret/aud/iss/exp, role anon/service_role, kid on HS256, HS256 signed with a cached ES256 key → 401), firewall, no string-built PostgREST filters, no SSRF, receipt path traversal blocked, inquiry e-mail header handling, idempotency keys per user and endpoint; route-by-route authorization holds.

## Status (2026-10-21, roles and Nafaqah integrity)

Fixed on branch `audit/claude-fable-roles-nafaqah` with migration `20261020800000_household_roles_and_nafaqah_integrity.sql` (applies after `20261020700000`), backend changes and tests (SQL test 25, `ai_service/tests/test_nafaqah_household_roles.py`, e2e `test_08`). Not applied to live yet. Details and verification in `FIX_LOG.md` ("Fable review — household roles and Nafaqah integrity").

| ID | Status |
|---|---|
| FABLE-LOGIC-01 | Fixed: `household_memberships.financial_role`; helpers, RPCs, API and settlement read the role of that household. |
| FABLE-LOGIC-02 | Fixed in DB/API: guard trigger (22023 `ledger_would_be_overpaid`, API 409); `overpaid` exposed. App display/handling: Flutter handoff. Installments refusing classified rows: the DB guard now refuses the amount cut; the swallowed error in `installment_service._adjust_original_transaction` belongs to FABLE-API-09. |
| FABLE-LOGIC-04 | Fixed: explicit `households.nafaqah_provider_user_id`, `set_nafaqah_provider`, `PUT /households/{id}/nafaqah/provider`; family joiners by code are `family_member`. Provider selector in the app: Flutter handoff. |
| FABLE-LOGIC-05 | Fixed: payday change re-keys the open cycle onward and moves its budgets/allowances. |
| FABLE-LOGIC-06 | Fixed: triggers, SQL recompute, Python recalculation and breakdown skip `wife_personal`. |
| FABLE-DB-01 | Fixed: invites admin-readable only; members cannot claim invites of their household. |
| FABLE-DB-03 | Fixed: re-joining never demotes; sync trigger never downgrades an admin. |

## Status — backend API and money-logic items (fix round 2026-10-21)

Branch `audit/claude-comprehensive-review` (worktree commits below). Regression tests reuse the
reviewer's reproductions with the assertions inverted; e2e tests run on the real stack
(`tests/e2e/test_08_fable_api_fixes.py`). Items of section A not listed here (LOGIC-01/02/04/05/06/09)
and section B are owned by the roles/DB and Flutter work streams.

| ID | Status | Fix | Proof tests | Commit |
|---|---|---|---|---|
| FABLE-API-01 | Fixed | Attribution stored structurally on insert (`spent_by` = payer relative to the creator, `beneficiary_type`/`beneficiary_id`); `/settlement` and `/settlement-v2` share `settlement_engine.transaction_attribution`. Legacy rows (`beneficiary_id` NULL) read only the server-authored tag segment (last occurrence before the item summary; chat/receipt payer limited to me/partner); app manual rows read the right-anchored template tail; settlements their `Settlement \| PaidBy:` head. Notes: server tags first, user text without `\|` or tag keywords. | `ai_service/tests/test_fable_attribution.py`; e2e `test_api01_*` | `985c6f4` |
| FABLE-LOGIC-03 | Fixed | Personal chat/receipt expenses carry `individual/<creator>`; 'partner' must name someone (2-member household or the spouse) or the request is 422; both engines agree. | `test_fable_attribution.py::test_personal_chat_expense_*`, `::test_settlement_and_settlement_v2_agree`; e2e `test_logic03_*` | `985c6f4` |
| FABLE-LOGIC-08 | Fixed | Receipt total minus Σ line items attributed pro-rata to the items' beneficiaries (largest remainder, halala exact; discounts too); non-member beneficiaries split instead of dropped. | `test_fable_attribution.py::test_pairwise_line_items_*` | `985c6f4` |
| FABLE-API-02 | Fixed | Header-only checks before decoding: ≤ 40 MP per photo, ≤ 100 MP per receipt, stitched canvas ≤ 20000 px high (413); pages decoded one at a time in JPEG draft mode and downscaled to 1600 px wide. Two 40 MP pages: +0 MiB peak RSS (was +766 MiB); the reviewer's four pages: 413. | `ai_service/tests/test_fable_receipt_limits.py` (subprocess RSS measurement, canvas bounds, route 413) | `996fcdb` |
| FABLE-API-03 | Fixed | `TRUST_PROXY_HEADERS` (auto-on with `RAILWAY_ENVIRONMENT`) + `TRUSTED_PROXY_HOPS` pick the client hop Railway's edge appends; per-IP inquiry limit only for a real client address, per-e-mail and global limits kept; invite inspection limited per verified user (else IP) under a 600/min global ceiling. | `ai_service/tests/test_fable_client_ip_limits.py`; e2e `test_06::test_public_inquiry_per_ip_limit` | `45f37c0` |
| FABLE-API-04 | Fixed | No new definitions under system parents via the API (allocation to the seeded ones only); keywords < 3 chars never stored or matched; `match_sub_category` trusts only seeded system definitions and the transaction household's own custom definitions. | `ai_service/tests/test_fable_sub_categories.py`; e2e `test_api04_*` | `9542307` |
| FABLE-API-05 | Fixed | Definitions/renames under a custom code only when the caller's household is its sole owner (admin). | `test_fable_sub_categories.py::test_colliding_custom_code_*`; e2e `test_api05_api08_*` | `9542307` |
| FABLE-API-08 | Fixed | One identical 403 text for every refused sub-category write. | `test_fable_sub_categories.py::test_rename_is_not_an_existence_oracle` | `9542307` |
| FABLE-API-06 | Fixed | 422 for merchant > 120, sub_category/beneficiary/paid_by > 60 (and other overrides) or non-text; `qr_code_raw` ≤ 4096 and stored only when it decodes; model output bounded too. | `ai_service/tests/test_fable_field_limits.py`; e2e `test_api06_*` | `9aa8921` |
| FABLE-API-07 | Fixed | `_`-prefixed `sub_allocations` keys skipped in totals, ignored in client input, preserved on save. | `ai_service/tests/test_fable_sub_allocations_metadata.py`; e2e `test_api07_*` | `03fbb36` |
| FABLE-API-09 | Fixed | `start_date` must be an ISO date (422); JSON file fallback removed (a failed insert fails the request); the transaction is adjusted only after the plan is stored. | `ai_service/tests/test_fable_installments.py`; e2e `test_api09_*` | `44f5f24` |
| FABLE-API-10 | Fixed | New migration `20261020750000_installment_pay_atomic.sql`: `pay_installment_plan()` conditional increment (never beyond the plan), SECURITY DEFINER, pinned search_path, membership check, service_role-only EXECUTE. | `supabase/tests/24_installment_pay_atomic.sql`; `test_fable_installments.py::test_pay_is_one_atomic_rpc_call`; e2e `test_api10_concurrent_payments_each_count_once` (12 concurrent pays) | `44f5f24` |
| FABLE-LOGIC-07 | Fixed | Fallback classifier: partner-paid cues in both word orders (Arabic/English), bills and grocery items shared, لها/له = partner, pronoun suffixes and ل-words never child names, gifts/relatives outside the household undetermined; preview returns `attribution_needs_confirmation` and no class when undetermined. 15/15 reviewer phrases (was 8/15). | `ai_service/tests/test_fable_classifier.py` | `62e6efa` |
| Observation (auth) | Fixed | `_get_user_membership` fails closed on a query error (no users.household_id fallback). | `ai_service/tests/test_fable_auth_fail_closed.py` | `60814b6` |

Residual (documented, not changed): legacy chat/receipt rows written before this round whose LLM
item names contained `| PaidBy:` text could still shadow the server tag (the heuristic parser cannot
produce such names); no backfill of historical rows was run (live is never written from here).
`installment_service.list_plans` still reconciles plans from notes mentioning Tamara/Tabby.

**App status (2026-10-21, Flutter handoff):** FABLE-LOGIC-04 provider badge/selector and missing-provider prompt, FABLE-LOGIC-02 `overpaid` display and ledger-guard/no-provider explanations, FABLE-LOGIC-01 manual expense roles per household (members API), FABLE-DB-01 join/claim refusal messages: done in the app. FABLE-LOGIC-09: fixed (`money.dart` parses to integer halalas, half-up). Details in `FIX_LOG.md` ("Fable review — app handoff"). FABLE-LOGIC-03 (app writes of `beneficiary_type/beneficiary_id`) left for the follow-up.

## Status — round 2 backend items (fix round 2026-10-21)

| Finding | Status | Fix | Proof | Commit |
|---|---|---|---|---|
| FABLE2-API-01 | Fixed | Constraint/permission refusals of a transaction insert are final (no pruned retries); `no_nafaqah_provider` / `ledger_would_be_overpaid` → 409 `{"detail":{"code":"no_provider"\|"ledger_would_be_overpaid"}}` from chat and receipts; early refusal before budget reallocation when the family needs a provider. | `test_fable_r2_insert_refusals.py`; e2e `test_09::test_api01_*` | `265502e` |
| FABLE2-LOGIC-01 (backend tolerance) | Fixed | `spent_by='both'` → payer from the note tags; manual-tail regex accepts `\| SubCategory: …`. App-side structured edit writes are the Flutter agent's. | `test_fable_r2_legacy_edit_attribution.py`; e2e `test_09::test_logic01_*` | `8460800` |
| FABLE2-API-02 | Fixed | Toggle codes ≤ 60 chars; `sub_code` must be a sub-budget of the category (422). | `test_fable_r2_recurring_toggle_bounds.py`; e2e `test_09::test_api02_*` | `2f9b640` |
| FABLE2-API-03 | Fixed | Full-decode formats capped at 12 MP/page, 24 MP/receipt; 2 concurrent stitches. | `test_fable_r2_receipt_memory.py` | `fb4db86` |
| FABLE2-API-04 | Fixed | Sub-halala roommate settlement → 422; half-up quantisation. | `test_fable_r2_money_rounding.py`; e2e `test_09::test_api04_*` | `b982db3` |
| FABLE2-API-05 | Fixed | Refused adjustment deletes the plan, 409 `ledger_would_be_overpaid`. | `test_fable_r2_installment_consistency.py`; e2e `test_09::test_api05_*` | `bbc8cfe` |
| FABLE2-API-06 | Fixed | Invite target: 400 non-UUID, 404 not a dependent of this household; DB refusals 4xx. | `test_fable_r2_invite_target.py`; e2e `test_09::test_api06_*` | `2523cdc` |
| O2 | Documented | Ingress assumption of proxy-header trust; hop count must be exact. | — | `5e28ae6` |
| O4 | Fixed | v1 roommate 'settled' threshold 0.01; shares sum to the total. | `test_fable_r2_money_rounding.py::test_v1_*` | `b982db3` |
