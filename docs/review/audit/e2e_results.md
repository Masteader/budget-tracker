# End-to-end results: ai_service + real PostgREST + local Postgres

Date: 2026-10-20. Branch `audit/claude-comprehensive-review`, base commit `952098d`.
Suite: `tests/e2e/` (how to run: `tests/e2e/README.md`).

## Environment achieved

| Component | What ran | Real or faked |
|---|---|---|
| Database | PostgreSQL 16.15, database `bt_e2e` rebuilt from `00_local_supabase_stubs.sql` + `schema.sql` + `seed.sql` + all 41 migrations (`run_tests.py --psql --rebuild --no-tests`) | Real |
| REST layer | PostgREST **12.2.3** official static binary (`jwt-secret` = HS256 test secret, `db-anon-role=anon`, `db-schemas=public`, connects as login role `bt_e2e_authenticator` granted `anon`/`authenticated`/`service_role`) | **Real** |
| Supabase URL layout | Python gateway proxying `/rest/v1/*` byte-for-byte to PostgREST (Kong stand-in) | Real traffic, thin proxy |
| Auth (GoTrue) | Not run. Users are rows inserted into `auth.users` (the real `handle_new_auth_user` trigger creates `public.users`); access tokens are GoTrue-shaped HS256 JWTs (`aud=authenticated`, `iss={SUPABASE_URL}/auth/v1`, `role=authenticated`) signed with the test secret. `auth.uid()`/`auth.jwt()` read `request.jwt.claims`, which PostgREST sets from the verified token. | Simulated |
| ai_service | The real FastAPI app (`main.app`) served by uvicorn 0.54 on a loopback port; supabase-py 2.33.0 / postgrest-py 2.33.0 with a locally signed `service_role` JWT as `SUPABASE_SECRET_KEY`; `ENV=development`; no Redis (in-memory limiter + DB quota) | Real |
| LLM | `litellm.completion`/`acompletion` replaced by a queue of canned JSON responses; empty queue raises (exercises the heuristic fallback) | Faked |
| E-mail | `mail_service.RESEND_ENDPOINT` pointed at a local capture endpoint; `RESEND_API_KEY` unset for the "absent" case | Faked provider endpoint only |
| Storage | `/storage/v1` in-memory stub (no scenario uploads; QR receipts need none) | Stubbed |
| Network | Socket guard: any non-loopback connect fails the run. One hit was caught during bring-up (litellm fetching its price map from GitHub at import) and is now disabled with `LITELLM_LOCAL_MODEL_COST_MAP=True`. Final runs: zero outbound attempts. | Enforced |

Not covered: GoTrue itself (signup/refresh/ES256 JWKS path), Supabase storage-api and image
receipts (Gemini vision), Redis-backed limiter/idempotency, Realtime, the Flutter and web clients.
The live Supabase project, Railway and every LLM/e-mail provider were never contacted.

Python 3.13.16, FastAPI 0.156.3, httpx 0.28.1, litellm 1.106.1, python-jose 3.5.0, psycopg 3.3.6,
pytest 9.1.1.

## Results

Full run with rebuild: **30 passed, 8 xfailed (strict), 0 failed** in ~2 min.

| # | Scenario | Tests | Result |
|---|---|---|---|
| 1 | Households: family (husband admin + wife member via spouse invite) and roommates (admin + 2 via peer invites); invite single use; admin-only invites; brute-force lockout → 429 with `Retry-After: 900` (correct code refused while locked; direct `join_household_by_code` RPC also refused); forged / expired / wrong-issuer / service-role tokens → 401 on API and PostgREST | 5 | Pass |
| 2 | Chat commit by every member of both households (creator = JWT subject, 1 LLM call each); heuristic fallback without LLM; ZATCA QR receipt (no LLM) preview + commit with `wife_personal`, fingerprint de-dup on rescan, contradicting class → 422; `cycle_key` for payday 27 and payday 10 at Riyadh 23:59/00:00 boundaries and month boundaries where the UTC date differs, with each cycle's budget charged exactly its own rows; `client_occurred_at` window | 7 + 1 xfail | Pass; **E2E-03** |
| 3 | Nafaqah: wife-paid shared expenses → husband owes 345.50; partial 100.25; overpayment 409 with `outstanding` (API) and refused by `record_spouse_reimbursement` directly; full repayment through `/households/{id}/reimbursements` routed to the ledger; reverse direction 409; allowance 500 → spent 150.75 / remaining 349.25, overspend reported (−50.75); wife cannot set her allowance (API 403, RPC refused); `/settlement` (any `split_ratio`) and `/settlement-v2` equal the ledger outstanding, no 50/50 | 4 + 2 xfail | Pass; **E2E-01, E2E-02** (roommate settlement) |
| 4 | Member edits own tx via PostgREST; other's tx edit/delete/creator change → 403 from the DB; via API: installment linking and chat enrichment of other's tx → 403, own → 200; admin edits/deletes anyone's; shared pool created by admin only; member pool withdrawal → 403, admin → OK (fee booked); co-admin promotion (DB role synced, co-admin edits others' tx via PostgREST); co-admin cannot demote primary (API 403, RPC refused, raw membership PATCH refused) nor transfer primary; primary transfer; former primary demotable; last admin protected | 3 + 2 xfail | Pass; **E2E-06, E2E-07** |
| 5 | IDOR sweep: 55 API calls (every household-scoped route plus B-object ids under A's household) by A's admin and by A's member → all 403/404, no B data in any body, B's rows byte-identical before/after; cross-household enrich/dependent-delete/receipt path → B untouched; PostgREST: 13 tables return `[]` for B, inserts/updates/deletes into B refused, 12 household-scoped RPCs with B's id and spoofed `p_actor_user_id` refused | 4 + 3 xfail | Pass; **E2E-04, E2E-05** |
| 6 | DB quota without Redis: 30 chat calls OK, 31st 429, `api_quota.count` = 31, still 429 after resetting the in-memory limiter (DB authoritative), other user unaffected, `consume_quota` not client-callable; receipt quota 10 → 429; inquiries: no provider → 503 (public and in-app), fake Resend → 200 with correct To/Reply-To/Authorization, honeypot silent, in-app identity from JWT only, provider 500 → 502, per-IP limit 5 → 429 | 5 | Pass |
| 7 | DB-06: transfers of 1.005 / fee 0.001 / 0.001 and income 1.005 or negative parts → 400, balances and transfer table unchanged, 1.01 + 0.25 fee conserves money; chat 10.005 stored = returned amount (2 dp); 3-dp allowance → 422. Mixed multi-step sequence (API budgets, income, transfers, chat, QR receipt, PostgREST inserts with accounts, edits of amount/category/account/timestamp across cycles, admin edit + delete, `/budgets/recalculate`): `budgets.spent_amount == Σ transactions` per (category, cycle) and every account balance == income − debits − transfers out − fees + transfers in after every step | 3 | Pass |

## Bugs found (each is a strict xfail in the suite)

Reproduce any of them with `BT_E2E=1 python -m pytest tests/e2e/<file>::<test> --runxfail`.

### E2E-01 (High): roommate settlements can never be recorded
`POST /households/{id}/reimbursements` in a non-family household always answers 500.
`supabase_client.record_household_reimbursement` inserts `paid_by` and `notes`, which do not exist
on `public.transactions`; PostgREST answers `PGRST204 Could not find the 'notes' column`.
Repro: roommate member A → `POST /households/{hh}/reimbursements {"household_id": hh, "payer_id": A,
"recipient_id": B, "amount": 75}` → 500, no row. Test:
`test_03_nafaqah_and_settlement.py::test_roommate_settlement_reimbursement_is_recorded`.

### E2E-02 (High): multi-roommate settlement never reports any debt
`GET /households/{id}/settlement-v2` (mode `multi_roommate`) selects `transactions.paid_by` (no such
column: `42703`); the error is caught and `txs = []`, so `pairwise_debts`/`simplified_debts` are
always empty. Independently, chat/receipt commits never persist the payer: `insert_transaction`
first sends `paid_by`/`beneficiary` (PGRST204) and retries without them, so even a fixed query
would have no payer to read. Repro: roommate pays 300 shared by chat → settlement-v2 shows nothing
owed (expected 200 owed to the payer). Test:
`test_03_nafaqah_and_settlement.py::test_roommate_multi_party_settlement_reports_debts`.
(Side effect: every chat/receipt commit costs a failed insert and a warning log; `/settlement`
v1 also fails its first query and falls back.)

### E2E-03 (Low): unknown category override → 500
`POST /agent/chat-transaction` with `category_code` not in the taxonomy: the DB trigger's `23503`
propagates through `insert_transaction`'s fallback chain as an unhandled `APIError` → 500 instead
of a 4xx. Test: `test_02_expense_commits_and_cycles.py::test_unknown_category_override_is_a_client_error`.

### E2E-04 (Low): helper RPCs leak another household's admin / husband id
`household_primary_admin_id(uuid)` and `nafaqah_husband_id(uuid)` are SECURITY DEFINER, EXECUTE-able
by `authenticated`, and return the user id for any household id without a membership check;
`nafaqah_is_spouse_member(uuid, uuid)` is a membership oracle. Repro (any signed-in user):
`POST /rest/v1/rpc/household_primary_admin_id {"p_household_id": "<other household>"}` → the
owner's UUID. Test: `test_05_idor_sweep.py::test_postgrest_helper_rpcs_do_not_leak_other_household_members`.

### E2E-05 (Medium): sub-category definitions are global and writable by any member
`cost_control_sub_categories` has no `household_id`. `GET /budgets/sub-categories?parent_code=X`
lists another household's custom sub-categories (custom codes are guessable `CUSTOM-…`), and
`POST /budgets/sub-categories` (membership of the body's household only; no admin, no ownership of
`parent_code`) inserts a definition under any parent — a system category or another household's
custom category — which every household then sees (`GET /budgets/sub-categories`, chat preview
`available_sub_categories`). Repro: member of A posts `{"household_id": A, "parent_code":
"OPEX-DINING", "name_en": "Planted by A"}` → B's `GET /budgets/sub-categories?parent_code=OPEX-DINING`
includes it. Tests: `test_05_idor_sweep.py::test_sub_categories_of_other_household_are_not_listed`,
`::test_sub_category_cannot_be_planted_into_other_households`.

### E2E-06 (Medium): members administer budgets through the API
The database reserves budget writes for admins (`budgets_insert_admin`/`budgets_update_admin`) and
`POST /households/{id}/categories/toggle` requires an admin, but `POST /budgets/categories`,
`DELETE /budgets/categories/{code}`, `POST /budgets/sub-allocations` and
`POST /budgets/sub-categories` use only `verify_household_access` with the service role. Repro: plain
member → `POST /budgets/categories {"household_id", "code": "OPEX-DINING", "allocated_amount": 1}`
→ 200 (allocation 900 → 1) and `DELETE /budgets/categories/OPEX-DINING?household_id=…` → 200
(category deactivated); the same member is refused by RLS when patching `budgets` directly. Test:
`test_04_permissions.py::test_member_cannot_administer_budgets_through_the_api`.

### E2E-07 (High): self-assignable `financial_role` rewrites who owes whom
`authenticated` has UPDATE on `users.financial_role` (`users_update_own_profile`), and that column
alone decides Nafaqah mode, the husband/wife and the debt direction. Repro: roommate →
`PATCH /rest/v1/users?id=eq.<self> {"financial_role": "spouse"}` → 200; the flat becomes
`family_nafaqah` (`/nafaqah` mode, `/settlement` mode), the roommate's next chat expense is stored
`wife_reimbursable` and the primary admin is shown as owing it. A wife can likewise set herself to
`provider` and drop the family out of Nafaqah mode. Test:
`test_04_permissions.py::test_member_cannot_self_assign_financial_role`.

## Observations (not marked as bugs)

- `accounts.balance` is client-settable on INSERT of a personal account and `reconcile_account_balance`
  sets an arbitrary balance; neither leaves a ledger entry, so "balance == ledger" holds only for
  accounts opened at 0 and never reconciled (the money tests do exactly that).
- Chat amounts with a third decimal are rounded by Python `round()` on a float (1.005 → 1.0,
  2.675 → 2.67) while Postgres rounds `numeric` half away from zero (1.005 → 1.01, 2.675 → 2.68, what
  a direct PostgREST insert stores). Stored and returned values agree on each path, so nothing is
  minted, but the API and the app's direct writes can round the same input differently.
- The fixed-window `consume_quota` resets at epoch-aligned 600 s boundaries, so a burst straddling a
  boundary can get up to 2× the limit; the in-memory sliding window still caps a single instance.


## Re-run on the merged branch (2026-10-20)

After merging the final backend review (FR-B-01/02/04/05), the suite was re-run on the fully merged branch: **35 passed, 3 xfailed**. E2E-01, E2E-02, E2E-06, E2E-07 and the planting half of E2E-05 now pass (they were fixed independently by FR-B-01, FR-B-02, FR-B-05 and FR-B-04), so their `xfail` marks were removed. Still open: E2E-03 (Low), E2E-04 (Low), E2E-05 listing (Medium).
