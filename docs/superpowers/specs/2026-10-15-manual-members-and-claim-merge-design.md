# Pre-Created Manual Household Members & Automatic Claim-and-Merge Design

## Overview
Allows a household owner or lead payer to create placeholder/manual profiles for wives, partners, roommates, and children *before* they register or join the household with their own accounts. The household can immediately log expenses paid by or for these members, calculate settlements and Islamic *Nafaqah* balances, and assign monthly allowances (*Masroof*). When the person downloads the app and enters their dedicated invite code, their new live account automatically claims their pre-created profile, seamlessly transferring all historical transactions, debt balances, and roles.

---

## 1. Data Model & Database Migration

### 1.1 `household_dependents` Schema Extension
In Supabase / PostgreSQL:
- `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
- `household_id` UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE
- `name` TEXT NOT NULL
- `relationship` VARCHAR(30) NOT NULL DEFAULT 'child' -- `'spouse'`, `'peer'`, `'child'`, `'dependent'`
- `avatar_icon` VARCHAR(50) DEFAULT 'person'
- `monthly_allowance` NUMERIC(10, 2) DEFAULT 0.0
- `linked_user_id` UUID NULL REFERENCES public.users(id) ON DELETE SET NULL
- `created_at` TIMESTAMPTZ DEFAULT NOW()

When `linked_user_id` is NULL, the member is a **pre-account manual profile**. When populated, the member is an **active claimed user**.

### 1.2 `household_invites` Schema Extension
- `target_member_id` UUID NULL REFERENCES public.household_dependents(id) ON DELETE CASCADE
- When an invite is generated for a specific pre-created member (e.g. Fatima), `target_member_id` points to Fatima's dependent record.

---

## 2. Automatic Claim-and-Merge Workflow

1. **Pre-creation**: Household owner taps "Add Member" in Settings &rarr; enters Name ("Fatima"), Role (Wife / Spouse), and Monthly Allowance (1500 SAR).
2. **Immediate Ledgering**:
   - In manual expense log, receipt scan, or AI chat, "Fatima" appears in **Paid by** and **Beneficiary / For whom**.
   - If Fatima spends on groceries, husband owes Fatima reimbursement under *Nafaqah*.
   - If husband spends on Fatima, it tracks against her monthly Masroof.
3. **Targeted Invitation**:
   - The owner taps "Invite" next to Fatima's profile &rarr; an 8-character code bound to `target_member_id = fatima.id` is generated.
4. **Claim on Join**:
   - Fatima signs up and enters the 8-character invite code on the Household Onboarding screen.
   - The app inspects the code &rarr; detects `target_member_id` &rarr; displays: *"Welcome Fatima! You are joining as Wife / Spouse. All prior expenses and settlements are ready for you."*
   - On confirmation:
     - `household_dependents.linked_user_id` is set to Fatima's user ID.
     - `users.financial_role` is set to `'spouse'`.
     - `users.household_id` is set to the household.
     - All prior transactions and settlement ledgers are now active for Fatima.

---

## 3. UI & UX Architecture

### 3.1 Unified "Household & Living Group" Hub
- Replaces disjointed lists with a single unified card in Settings:
  - Header with total members count.
  - Member cards displaying:
    - Name & Icon (💍 Spouse, 🤝 Roommate, 👨‍👩‍👧 Child).
    - Status badge: 🟢 **Active Account** or ⏳ **Pre-Account (Manual)**.
    - Monthly Allowance pill if set (`Masroof: SAR 1,500.00`).
    - Quick Action: **"Share Invite"** button for pre-account members.
  - Primary button: **"Add Household Member"**.

### 3.2 "Add Household Member" Sheet
- Input fields:
  - Full Name (e.g. Fatima or Omar).
  - Role selector chips: 💍 **Wife / Spouse**, 🤝 **Roommate / Partner**, 👶 **Child / Dependent**.
  - Monthly Allowance field (SAR).

### 3.3 Expense Attribution
- Transaction forms dynamically include all manual profiles alongside registered users in:
  - "Who Paid?"
  - "For Whom?" (Beneficiary).

---

## 4. Trilingual Localization
Full support for English, Arabic (`ar`), and Urdu (`ur`) for all member roles, claim states, and dialogs.
