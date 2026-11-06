# Saudi Fintech & Islamic Compliance Rules

## 1. Saudi Salary & Payday Cycle Alignment

- **Payday per household:** salary cycles follow `households.payday_day` (1–31, default **27**, the common Saudi payday). Only a household admin changes it (`PUT /households/{id}/payday`). Never hard-code the 27th in new code.
- **Cycle Identification (`cycle_key`, `YYYY-MM`):**
  - A cycle runs from the payday of one month to the day before the next payday, on the **Asia/Riyadh** calendar date. A payday beyond the month's length is clamped to its last day; payday 1 means the calendar month.
  - With payday > 15 the key names the month the cycle **ends** in (payday 27: 27 Oct → 26 Nov is `2026-11`); with payday ≤ 15 it names the month it starts in.
  - SQL (`get_saudi_cycle_for_timestamp`), Python (`salary_cycle.get_cycle_for_date`) and Dart compute the same key; database triggers fill `transactions.cycle_key` and clients cannot forge it.
- **Client & API Callers Prohibition:**
  - Clients and API callers MUST NOT forge, compute, or send `cycle_key` or `payday_day` query overrides; the database trigger `trg_populate_transaction_cycle_key` and household configuration are the sole authoritative sources of truth.
- **Payday Check-In:**
  - When the household payday arrives, prompt the user with the Payday Check-in Sheet to record their salary, overtime, bonus, and deductions.
  - Offer the 1-tap Salary Distribution Assistant to fund secondary wallets and bank accounts.
- **Cycle Rollover Handling:** the household chooses its rule (`households.rollover_rule`, `GET|PUT /households/{id}/rollover-rule`, admin to change):
  - `send_to_savings` (default): leftover funds are swept into the savings reserve; categories start fresh.
  - `rollover_to_categories`: leftover funds increase each category in the new cycle (`previous_cycle_delta`).
  - `fresh_start`: allocations reset to baseline with no carryover.

## 2. ZATCA Phase 2 E-Invoicing Compliance

- All Saudi electronic receipts must comply with the Zakat, Tax and Customs Authority (ZATCA) Phase 2 e-invoicing standard.
- The app scanner decodes the Base64 TLV (Tag-Length-Value) barcode:
  - **Tag 1:** Seller Name
  - **Tag 2:** VAT Registration Number (15 digits, starting and ending with 3)
  - **Tag 3:** Timestamp (ISO 8601)
  - **Tag 4:** Invoice Total (including VAT)
  - **Tag 5:** VAT Amount (standard 15% VAT calculation)
- Never reject valid ZATCA QR codes; store `qr_code_raw` and extracted structured line items.

## 3. Islamic Family Finance (Nafaqah vs. Roommate Living Groups)

- **Islamic Sharia Nafaqah Principle:**
  - In Islamic jurisprudence, the husband bears complete legal financial responsibility (*Nafaqah*) for housing, food, clothing, and essential family maintenance.
  - **Strict Prohibition:** NEVER impose automatic 50/50 expense splits between husband and wife.
  - If a wife pays for household groceries or expenses out of her personal funds, track it as **Reimbursable Debt** owed by the husband.
- **Family mode rules (owner decision on audit item UI-24, authoritative).** A household is in family mode when its `households.household_type` is `'family'`, chosen at creation; a `'roommates'` household never is. A family with no wife member stays in family mode, so nothing is ever split between the people in it; with no wife there is nothing to classify and no allowance or reimbursement to record. The wives are its members with `household_memberships.financial_role = 'spouse'` (roles are per household; `users.financial_role` only caches the active household's). The husband is the household's explicit Nafaqah provider, `households.nafaqah_provider_user_id` (owner decision 2026-10-21): by default the primary admin, changed by any admin to another non-spouse member (`set_nafaqah_provider`, `PUT /households/{id}/nafaqah/provider`); never inferred from roles or admin rights. Without a provider, new classified expenses are refused. `wife_personal` purchases count against her allowance only, never the category budgets; edits that would leave the reimbursement ledger overpaid are refused (`ledger_would_be_overpaid`).
  1. **Nafaqah is on the husband.** Shared family/household expenses are his responsibility. There is **no 50/50 or any percentage split** between the spouses anywhere in family mode (API, app banners, settlement cards, chat). `split_ratio` and "Shared 50/50" belong to roommate/partner households only.
  2. **Wife pays for something shared** (household, children/dependents, the husband) from her own money → `transactions.nafaqah_class = 'wife_reimbursable'` with `nafaqah_spouse_id` = the wife. It is a debt the husband owes her. The app shows the outstanding balance and history, and records partial or full repayments in the append-only `spouse_reimbursements` ledger (`record_spouse_reimbursement`); paying back more than is outstanding is rejected.
     - **How a repayment moves money (owner decisions 2026-11-06, migration `20261105001300`):**
       - *Who sees and who acts (owner decisions 2026-11-06, reviews R1-01 and R3-01).* **Her husband** is the household's Nafaqah provider while he is a current member who is not a wife; **he is gone** when there is no such member (he left, his account was deleted, or nobody was named). One definition: `nafaqah_ledger_husband_id` in SQL, `FamilyContext.ledger_husband_id` / `husband_gone` in the API.
         - *Seeing.* A wife's ledger (what is owed, the advances behind it, repayments, reversals, her requests and their outcomes, decline reasons and notes) is read by her and by her husband only. A co-wife, an ordinary member and an admin who is not a wife read nothing of it: no rows, no totals, no entry for her in any summary (`wives[]`), settlement or notice; a wife sees only her own entry. When the husband is gone, an admin of the household who is not a wife reads it too.
         - *Acting.* Only her husband records a repayment, approves or declines her request, and reverses; she only makes and cancels her own requests. When he is gone, an admin who is not a wife does what he did. A wife never sees or acts for a co-wife, even as an admin. The account rules are unchanged: a personal account only by its owner, a shared pool only by an admin who is not a wife, so the husband pays from a pool only if he is an admin.
         - *A deleted wife's record* follows the same rule: seen and closed (paid or waived) by the husband it is owed by; by an admin who is not a wife only when he is gone; never by a co-wife or an ordinary member. Her deletion notices and emails go to the same people.
         - The database enforces it (`nafaqah_may_manage_ledgers`, the read policies on the ledger, requests, outcomes and former member tables through `nafaqah_caller_manages_ledgers`, `get_spouse_reimbursement_balance`, `nafaqah_may_repay`, `former_member_debt_require_manager`, the account helper); the API checks the caller on every route (`require_ledger_reader`, `can_view_wife_ledger`, `can_manage_wife_ledgers`, `resolve_wife_id`: a wife resolves herself only) and the settlement totals; the app hides what the caller cannot use. Her allowance is not her ledger: the husband or any admin still sets it (rule 3), and an admin who reads no ledger gets each wife's allowance alone (`allowance_wives`).
       - *Every repayment is tracked.* The payer picks the account it leaves: his own personal account, or a shared pool when he is an admin (in the household, not archived, in SAR, holding the amount; a cash payment leaves his Cash account). That account goes down by the amount as one `account_transfers` row to no account (`to_account_id` NULL, `purpose` naming it, so the account's own history shows "Repayment to wife"), linked from the ledger row (`transfer_id`). The ledger row records who actually paid (`paid_by_user_id`) and what was owed before and after it. Her account is never credited. No budget or transaction moves: her expense already counted when she recorded it. A call without an account (the old signatures, or an API request without `account_id`) is refused with `app_update_required` (HTTP 426) and records nothing. A request key makes a retry record once and answer as the first time, also after the account it left was deleted (the ledger keeps `account_id`); the same key with another amount, account, kind or person is refused (`request_key_reused`). A key names one operation in its household, whatever the path (review R2-01): every call that takes one (a repayment, an approval, a reversal, her request, a former member's payment, waiver or reversal) claims it in `nafaqah_request_keys` in the same transaction, so a key used on another path, for another wife or on another record is `request_key_reused` and moves nothing, also when two calls race. In the app, a sheet whose answer was lost (no answer, a server failure, or any failure that is not one of the API's definite answers) keeps its key and what it sent, also after it is closed and reopened, until a definite answer (review R2-02).
       - *She asks, he approves.* The wife never records a repayment (`wife_must_request`). She marks "I received X": a pending request (`spouse_reimbursement_requests`) that moves no money and does not lower what is owed; she can cancel it. The husband or an admin who is not a wife approves it from an account (the normal repayment of exactly that amount, re-checked against what is owed at that moment) or declines it with an optional reason (at most 200 Unicode code points). Pending requests together never exceed what is owed: a new one is refused beyond it, and whatever lowers what is owed (a direct repayment, an approval, a smaller advance) closes in the same transaction the pending requests that no longer fit, as `already_repaid`, with nothing moved, keeping them in the order she made them while they fit (so the most recent close first). Each outcome is a row of its own (`spouse_reimbursement_request_outcomes`).
       - *Corrections are reversals.* Nothing is deleted, edited or voided. A reversal (`kind = 'reversal'`, at most one per repayment) returns the full amount to the account the repayment left (a transfer from no account, "Repayment reversed" in that account's history) and adds it back to what is owed; the repayment stays, marked reversed. Refused for a row from before tracking (no transfer) and for an archived or deleted account. Who reverses follows the account: a personal account's owner, while he is a member and not a wife, even if he is no longer an admin or the husband (review R1-07); a pool's repayment, the husband if he is an admin, or an admin who is not a wife when he is gone (review R3-01). A client cannot delete an account a repayment or a reversal used (`account_has_repayments`, review R3-05): it is archived instead, so the correction stays possible; the purge still deletes the accounts of the person it deletes.
       - *What is owed* = her advances − repayments + reversals; pending requests never count.
       - *A deleted wife's record* (`former_member_debts`) is paid from an account the same way, with nothing credited ("Paid on a former member's record" in the account's history, with no name); a payment is reversed the same way (a settled record opens again, never after her waiver); her waiver moves nothing; there are no requests. While a record is open the household cannot switch from family to roommates (`set_household_type` names `former_member_debt`; the API answers `former_member_debt_open`, review R2-04 owner decision): it is closed first, by a payment of what remains or her waiver.
  3. **Wife buys something personal for herself** → `nafaqah_class = 'wife_personal'`. Not a debt: it is charged to her personal allowance ("مصروفها") for the salary cycle (`cycle_key`, household payday to the day before the next). The husband or a household admin (never the wife herself) sets the amount per cycle (`member_allowances`, `set_member_allowance`); the app shows allocated / spent / remaining, and overspend shows a negative remainder (never blocked).
  4. **Husband pays for shared things** (or buys something for his wife) → an ordinary household expense: no class, no debt.
  - **Wife Expense Account Isolation (`trg_enforce_wife_class_account`):**
    - Under migration `20261101000100`, wife-class transactions (`wife_personal`, `wife_reimbursable`) CANNOT debit a shared pool or husband's account.
    - They must link exclusively to a personal, non-shared, non-archived account owned by the designated wife (`owner_user_id = nafaqah_spouse_id`) or remain unlinked (`account_id IS NULL`).
  - A wife's voluntary contribution (Tabarru') is only ever an explicit opt-in flag (`is_tabarru` on a settlement input); it is never assumed or defaulted.
  - Money is `numeric(14,2)` in SQL, `Decimal`/integer halalas in Python. Ledger writes go only through the `SECURITY DEFINER` RPCs with a pinned `search_path` and actor checks; the API passes the verified JWT subject as `p_actor_user_id` and checks the wife belongs to the URL's household (no IDOR).
  - Roommate mode (peers, no spouse) is unaffected: equal splits and multi-roommate debt simplification as below.
- **Shared Living Groups (Roommates / Flatmates):**
  - Flatmates or roommates share joint household living expenses (Rent, Utilities, Internet, Cleaning).
  - Use the Multi-Roommate Settlement Engine with multi-way debt simplification to compute net balances without circular transfers.
  - Support Shared Expense Pools (`is_shared_pool = true`) where roommates contribute their monthly dues and track expenditures against the shared pool.

## 4. Multi-Source Income & Zero-Based Account Balances

- Users maintain real accounts across Banks (Al Rajhi, SNB, Riyad Bank), E-Wallets (STC Pay, Urpay, Tiqmo), Crypto (Binance), and Cash.
- **Operating Cash Single Source of Truth:**
  $$\text{Operating Cash} = \text{Liquid Balance} - \text{Pending Commitments}$$
  - `Liquid Balance` is the exact sum of balances across non-archived, SAR-denominated operating pool accounts.
  - `Pending Commitments` is the sum of unpaid recurring bills and active cycle installment plan obligations.
  - Category *Spent Amount* is strictly EXCLUDED from the operating cash subtraction because the database trigger `trg_update_account_balance_on_transaction` already decrements `accounts.balance` at write time. Python and Flutter must NEVER manually decrement or clamp balances.
- **Zero-Based Budget Invariant:**
  - Total committed budgets for an account must never exceed that account's actual liquid balance.
  - Display dynamic status indicators:
    - `🟢 Zero-Based (100% Allocated)`
    - `🔵 Surplus Buffer (+SAR X.XX)`
    - `🔴 Deficit Shortfall (-SAR X.XX)` with 1-tap `[⚡ Quick Transfer]` shortcut.
