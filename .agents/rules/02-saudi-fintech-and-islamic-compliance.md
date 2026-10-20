# Saudi Fintech & Islamic Compliance Rules

## 1. Saudi Salary & Payday Cycle Alignment

- **Payday per household:** salary cycles follow `households.payday_day` (1–31, default **27**, the common Saudi payday). Only a household admin changes it (`PUT /households/{id}/payday`). Never hard-code the 27th in new code.
- **Cycle Identification (`cycle_key`, `YYYY-MM`):**
  - A cycle runs from the payday of one month to the day before the next payday, on the **Asia/Riyadh** calendar date. A payday beyond the month's length is clamped to its last day; payday 1 means the calendar month.
  - With payday > 15 the key names the month the cycle **ends** in (payday 27: 27 Oct → 26 Nov is `2026-11`); with payday ≤ 15 it names the month it starts in.
  - SQL (`get_saudi_cycle_for_timestamp`), Python (`salary_cycle.get_cycle_for_date`) and Dart compute the same key; triggers fill `transactions.cycle_key` and clients cannot forge it.
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
- **Family mode rules (owner decision on audit item UI-24, authoritative).** A household is in family mode when a member has `users.financial_role = 'spouse'`; the husband is a `provider` member (preferring an admin), never a wife because she is an admin.
  1. **Nafaqah is on the husband.** Shared family/household expenses are his responsibility. There is **no 50/50 or any percentage split** between the spouses anywhere in family mode (API, app banners, settlement cards, chat). `split_ratio` and "Shared 50/50" belong to roommate/partner households only.
  2. **Wife pays for something shared** (household, children/dependents, the husband) from her own money → `transactions.nafaqah_class = 'wife_reimbursable'` with `nafaqah_spouse_id` = the wife. It is a debt the husband owes her. The app shows the outstanding balance and history, and records partial or full repayments in the append-only `spouse_reimbursements` ledger (`record_spouse_reimbursement`); paying back more than is outstanding is rejected.
  3. **Wife buys something personal for herself** → `nafaqah_class = 'wife_personal'`. Not a debt: it is charged to her personal allowance ("مصروفها") for the salary cycle (`cycle_key`, household payday to the day before the next). The husband or a household admin (never the wife herself) sets the amount per cycle (`member_allowances`, `set_member_allowance`); the app shows allocated / spent / remaining, and overspend shows a negative remainder (never blocked).
  4. **Husband pays for shared things** (or buys something for his wife) → an ordinary household expense: no class, no debt.
  - A wife's voluntary contribution (Tabarru') is only ever an explicit opt-in flag (`is_tabarru` on a settlement input); it is never assumed or defaulted.
  - Money is `numeric(14,2)` in SQL, `Decimal`/integer halalas in Python. Ledger writes go only through the `SECURITY DEFINER` RPCs with a pinned `search_path` and actor checks; the API passes the verified JWT subject as `p_actor_user_id` and checks the wife belongs to the URL's household (no IDOR).
  - Roommate mode (peers, no spouse) is unaffected: equal splits and multi-roommate debt simplification as below.
- **Shared Living Groups (Roommates / Flatmates):**
  - Flatmates or roommates share joint household living expenses (Rent, Utilities, Internet, Cleaning).
  - Use the Multi-Roommate Settlement Engine with multi-way debt simplification to compute net balances without circular transfers.
  - Support Shared Expense Pools (`is_shared_pool = true`) where roommates contribute their monthly dues and track expenditures against the shared pool.

## 4. Multi-Source Income & Zero-Based Account Balances

- Users maintain real accounts across Banks (Al Rajhi, SNB, Riyad Bank), E-Wallets (STC Pay, Urpay, Tiqmo), Crypto (Binance), and Cash.
- **Zero-Based Budget Invariant:**
  - Total committed budgets for an account must never exceed that account's actual liquid balance.
  - Display dynamic status indicators:
    - `🟢 Zero-Based (100% Allocated)`
    - `🔵 Surplus Buffer (+SAR X.XX)`
    - `🔴 Deficit Shortfall (-SAR X.XX)` with 1-tap `[⚡ Quick Transfer]` shortcut.
