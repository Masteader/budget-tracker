# Design Spec: Family Nafaqah Reimbursement, Multi-Roommate Settlement & Role-Aware Invites

**Date:** 2026-10-15  
**Status:** Approved for Implementation Planning  
**Scope:** `ai_service` (FastAPI backend + Settlement Engine) & `flutter_app` (Mobile UI & Domain Clients)  

---

## 1. Executive Summary

This architecture solves two distinct, real-world household living arrangements in the Saudi and GCC context:
1. **Islamic Family Household (*Nafaqah* & Family Stewardship):**
   - The husband has the legal/religious financial obligation (*Nafaqah*) to cover all household, children, and family expenses, as well as an optional personal allowance (*Masroof* / مصروف الزوجة) for the wife.
   - If the **husband pays**, no debt is generated against the wife or children.
   - If the **wife pays** for household expenses or children out of pocket, **the husband owes her 100% reimbursement**.
   - The husband can settle this in full or partial amounts (auto-recording a reimbursement transaction) or roll it over to increase her personal allowance in the next salary cycle.
2. **Shared Living / Flatmates (Multi-Party Asynchronous Settlement):**
   - A group of flatmates (e.g. single guys or single girls living together) share rent, utilities (SEC, water, internet), and groceries.
   - Supports asynchronous partial and full payments across multiple roommates (e.g., *Omar owes Ahmed 100 SAR, Ibrahim owes Ahmed 200 SAR, Tariq owes Omar 200 SAR*).
   - Includes optional debt simplification to reduce total transactions, and supports receipt line-item tagging so personal items are charged 100% to the specific roommate while shared items are split equally.
3. **Role-Aware Invite & Onboarding Engine:**
   - Household owners generate role-specific invites (Wife, Roommate, Family Member) with explicit role confirmation during onboarding.

---

## 2. Household Financial Personas & Role Architecture

Every member or dependent entity in a household maps to one of four financial profiles:

| Financial Profile | DB Role | Rights & Capabilities | Expense Behavior (Household) | Expense Behavior (Personal) |
|---|---|---|---|---|
| **Primary Provider** | `provider` | Household owner / admin; manages budget & payday. | Obligated to cover 100%; zero debt created for family. | Normal personal budget. |
| **Spouse / Beneficiary** | `spouse` | Registered user or named dependent; can log expenses & view budgets. | **100% reimbursed by Provider** if she covers household/kids expenses. | Tracked against her *Wife Allowance* budget (or personal funds). |
| **Peer Payer (Roommate)** | `peer` | Equal co-payer in flatmate group; logs personal & shared bills. | Split equally among all active peers (or custom ratio). | 100% personal debt if paid by another flatmate. |
| **Dependent** | `dependent` | Children, elderly parents, or domestic workers. | Covered 100% by Provider / Household. | Attribution report only (zero debt). |

---

## 3. Data Schema Extensions

### 3.1 Supabase Database Tables

#### A. `users` Table
```sql
ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS financial_role TEXT DEFAULT 'provider' 
CHECK (financial_role IN ('provider', 'spouse', 'peer'));
```

#### B. `household_invites` Table
```sql
CREATE TABLE IF NOT EXISTS public.household_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    invite_code VARCHAR(8) UNIQUE NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'peer' CHECK (role IN ('spouse', 'peer', 'dependent')),
    created_by UUID REFERENCES public.users(id),
    expires_at TIMESTAMPTZ NOT NULL,
    used_by UUID REFERENCES public.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_invites_code ON public.household_invites(invite_code);
```

#### C. `household_dependents` Table
```sql
ALTER TABLE public.household_dependents
ADD COLUMN IF NOT EXISTS relationship TEXT DEFAULT 'child' 
CHECK (relationship IN ('child', 'wife', 'elderly', 'worker', 'other')),
ADD COLUMN IF NOT EXISTS monthly_allowance NUMERIC(10, 2) DEFAULT 0.0;
```

#### D. `transactions` Table
```sql
ALTER TABLE public.transactions
ADD COLUMN IF NOT EXISTS beneficiary_type TEXT DEFAULT 'household' 
CHECK (beneficiary_type IN ('household', 'all_peers', 'individual')),
ADD COLUMN IF NOT EXISTS beneficiary_id TEXT,
ADD COLUMN IF NOT EXISTS is_settlement BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS settlement_target_id TEXT,
ADD COLUMN IF NOT EXISTS line_items JSONB DEFAULT '[]'::jsonb;
```

---

## 4. Multi-Party Debt Engine & Settlement Mathematics

### 4.1 Pairwise Ledger & Asynchronous Timing
The backend maintains a directed graph of debts $D(i, j)$ representing how much member $i$ owes member $j$:

$$D(i, j) = \sum \text{Expenses paid by } j \text{ benefiting } i - \sum \text{Settlement payments from } i \to j$$

When person $i$ makes a partial payment $P$ to person $j$:
- $D(i, j) \leftarrow D(i, j) - P$
- If $D(i, j) \le 0$, the debt is settled.

### 4.2 Debt Simplification (Minimum Cash Flow)
Given $N$ roommates with net balances $B_k = \sum_{j} D(j, k) - \sum_{j} D(k, j)$:
- Positive $B_k$: Creditors (owed money).
- Negative $B_k$: Debtors (owe money).
- The engine computes the minimum transactions required by repeatedly matching the maximum debtor with the maximum creditor until all balances reach zero.
- *Example*: Tariq owes Omar 200, Omar owes Ahmed 100 &rarr; Tariq pays Ahmed 100, Tariq pays Omar 100. Omar makes 0 transfers!

### 4.3 Wife / Spouse Reimbursement Mathematics
In a Family Household:
- If `paid_by == spouse` and `beneficiary_type IN ('household', 'individual')` where `beneficiary_id != spouse`:
  - `reimbursement_owed = amount`
- If Provider pays reimbursement $R$:
  - A transaction with `is_settlement: true`, `paid_by: provider`, `settlement_target_id: spouse` is recorded.
  - Remaining reimbursement balance decreases by $R$.
- If Provider chooses `allowance_rollover`:
  - The next cycle budget for `OPEX-WIFE-ALLOWANCE` is incremented by $R$.

---

## 5. Line-Item Receipt Splitting

When a user scans a receipt (or manually logs a multi-item purchase):
1. **Total Bill**: e.g., SAR 420.00.
2. **Item Tagging**:
   - `Item 1: Bread & Milk (SAR 20)` &rarr; `beneficiary: all_peers` (shared).
   - `Item 2: Cleaning Supplies (SAR 100)` &rarr; `beneficiary: all_peers` (shared).
   - `Item 3: Omar's Gym Protein (SAR 200)` &rarr; `beneficiary: omar` (personal).
   - `Item 4: Ibrahim's Coffee Beans (SAR 100)` &rarr; `beneficiary: ibrahim` (personal).
3. **Apportionment**:
   - Shared total: SAR 120 / 3 roommates = SAR 40 each.
   - Omar owes: SAR 200 (personal) + SAR 40 (shared) = SAR 240.
   - Ibrahim owes: SAR 100 (personal) + SAR 40 (shared) = SAR 140.
   - Payer (Ahmed) is owed: SAR 240 + SAR 140 = SAR 380.

---

## 6. Mobile UI Components (`flutter_app`)

### 6.1 `FamilyReimbursementCard` (Family Dashboard)
- Displays pending reimbursement to Wife: *"Pending Reimbursement: SAR 350.00 (Panda & Pharmacy)"*.
- Visual status: 🟢 Settled / 🟠 Awaiting Provider Reimbursement.
- **Provider Action Buttons**:
  - **"Reimburse Wife"** dialog:
    - Preset chips: **Pay in Full (SAR 350)**, **Custom Partial Amount**, or **Add to Next Cycle Masroof**.
    - Payment Method: STC Pay, Urpay, IBAN, Cash.
    - 1-tap STC Pay note copy: `"Household Advance Reimbursement - SAR 350"`.

### 6.2 `MultiRoommateSettlementCard` (Roommate Dashboard)
- Summary: Total shared flat spend & your current net balance (*"You are owed SAR 180"* or *"You owe SAR 95"*).
- **Pairwise Breakdown Matrix**:
  - Omar &rarr; Ahmed: SAR 100 [Settle Button]
  - Ibrahim &rarr; Ahmed: SAR 200 [Settle Button]
- **Record Settlement Sheet**:
  - Dropdown: Payer & Recipient.
  - Amount input (prefilled with full debt, editable for partial).
  - Method selector + Instant update.
- Toggle: **"Simplify Debts (Splitwise-style)"**.

### 6.3 `RoleInviteDialog` & `JoinHouseholdRoleSheet`
- When inviting:
  - Radio card selection: 💍 **Wife / Spouse**, 🤝 **Flatmate / Co-Payer**, 👨‍👩‍👦 **Family Dependent**.
  - Generates 8-character code bound to that role.
- When joining:
  - Modal confirms role: *"You are joining as Spouse / Wife (Family Beneficiary)"*.

---

## 7. Multilingual Support
Full Arabic, English, and Urdu localization:
- **Arabic**: نفقة الأسرة، تسوية مصروف الزوجة، السكن المشترك، تبسيط الديون، سداد جزئي، تسوية عبر STC Pay.
- **English**: Family Nafaqah, Wife Reimbursement, Shared Flatmate Living, Debt Simplification, Partial Settle-up.
- **Urdu**: خاندانی نفقہ، اہلیہ کے اخراجات کی واپسی، مشترکہ رہائش، قرض کی آسان تقسیم۔

---

## 8. Verification & Testing Strategy

1. **Backend Tests (`pytest`)**:
   - `test_wife_reimbursement_calculation`: Verify wife paying for household generates debt for husband; husband paying for household generates zero debt for wife.
   - `test_reimbursement_settle_full_and_partial`: Verify recording partial and full reimbursement updates pending balances accurately.
   - `test_roommate_pairwise_settlement`: Verify matrix for 3+ roommates with asynchronous partial payments.
   - `test_debt_simplification`: Verify transitivity simplification algorithm.
2. **Flutter Widget Tests**:
   - `family_reimbursement_card_test.dart`: Test rendering of pending wife advances, full/partial reimburse actions.
   - `multi_roommate_settlement_card_test.dart`: Test pairwise debt display and record settlement modal.
   - `role_invite_dialog_test.dart`: Test generating role-tagged invite codes and join flow role confirmation.
3. **Static Analysis**: Maintain 0 analyzer warnings (`flutter analyze`).
