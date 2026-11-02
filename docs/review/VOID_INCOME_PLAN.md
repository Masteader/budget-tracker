# IMPLEMENTATION PLAN: Void / Delete Income Record (`void_income_record` RPC + Flutter UI Action)

**Sensitive:** yes, because it mutates accounts.balance, deletes ledger rows from public.income_records, and adds a database security definer RPC.

**Review Pipeline Mandate:**
- **Round 1:** Opus 5.5 high (`reviewer-spec`)
- **Round 2:** Opus 5.5 high (`reviewer-break`)
- **Round 3:** Fable high (`reviewer-fable`) (mandated by [docs/sensitive.md](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/docs/sensitive.md))

---

## 1. Architectural & Operational Context

### 1.1 Background & Problem Statement
In the multi-source income architecture (`20261018_multi_source_income_and_accounts.sql` and `20261020050000_audit_ledger_precision_and_income_append_only.sql`), income is recorded via the atomic security definer RPC `public.record_income`. This function credits the target account balance (`accounts.balance = balance + v_net_amount`) and appends an itemized receipt row to `public.income_records`.

To protect financial ledger integrity and prevent rogue modifications, migration `20261020050000` enforced append-only ledgers:
```sql
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.income_records FROM anon, authenticated;
```
However, no compensating reversal or void RPC was introduced. Consequently, when a user enters an income record mistakenly (e.g. logging 700 SAR to a Cash account instead of Bank Checking, or misentering a bonus amount), there is **no database RPC or user interface action** to void or delete the record. The user is trapped with an inflated account balance and an incorrect cycle income ledger.

### 1.2 Core Architectural Invariants & Compliance Rules
1. **Ledger Immutability & Safe Reversals (Rule 01 & Rule 04):**
   - Direct client `DELETE` operations on `public.income_records` must remain strictly revoked from `anon` and `authenticated`.
   - The deletion must only occur via a strictly audited, single-purpose `SECURITY DEFINER` RPC (`public.void_income_record(p_income_id UUID)`).
2. **Atomic Balance Reversal (Rule 01):**
   - The deduction from `accounts.balance` (`balance = balance - v_net_amount`) and the deletion of the `income_records` row must execute within the exact same database transaction.
   - Row-level locks (`FOR UPDATE`) must be acquired on both `income_records` and `accounts` in consistent order to prevent race conditions or concurrent modifications.
3. **Multi-Tenancy & IDOR Defense (Rule 04):**
   - Strict verification of `auth.uid()`.
   - The caller's household (`public.get_auth_user_household_id()`) must strictly match the income record's `household_id`.
4. **Islamic Financial Isolation & Spousal Permissions (Rule 02):**
   - Under Saudi / Islamic financial principles, personal accounts belonging to a spouse or individual member are strictly isolated.
   - A regular member may void an income record **only if** they were the creator (`income_records.user_id = auth.uid()`) OR the account owner (`accounts.owner_user_id = auth.uid()`).
   - Household admins and co-admins (`admin`, `co_admin`) retain administrative authority across household shared pools and household transactions, but cannot execute arbitrary voids across non-shared spousal personal accounts without administrative entitlement.
5. **UI & Localization Completeness (Rule 03):**
   - Trilingual localizations (English, Arabic, Urdu) must be added with correct RTL typography.
   - Confirmation dialog must explicitly disclose the exact deduction amount and target account name before committing.

### 1.3 Affected Component Inventory
- **Database & Migrations:**
  - `supabase/migrations/20261102010000_void_income_record_rpc.sql` (NEW)
  - `supabase/tests/35_void_income_record.sql` (NEW)
  - [supabase/schema.sql](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/supabase/schema.sql) (Baseline schema consolidation)
- **Frontend Services & State Providers:**
  - [flutter_app/lib/services/account_service.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/services/account_service.dart) (`voidIncomeRecord`)
  - [flutter_app/lib/providers/account_provider.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/providers/account_provider.dart) (`voidIncomeRecord`)
- **Frontend UI & Localization:**
  - [flutter_app/lib/screens/accounts/accounts_overview_screen.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/screens/accounts/accounts_overview_screen.dart) (Delete action button on `_buildIncomeRow`, confirmation modal)
  - [flutter_app/lib/l10n/app_localizations.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/l10n/app_localizations.dart) (Trilingual dictionaries: EN, AR, UR)
- **Test Suites (TDD):**
  - `flutter_app/test/services/account_service_void_income_test.dart` (NEW)
  - `flutter_app/test/screens/accounts_overview_void_income_test.dart` (NEW)

---

## 2. Test-Driven Development (TDD) Strategy & Verification Gates

Per **Rule 05 (TDD)**, tests are created and asserted to fail **before** any production implementation code is merged:

```
[Phase 1: DB Red]   Write supabase/tests/35_void_income_record.sql
[Phase 1: DB Green] Apply supabase/migrations/20261102010000_void_income_record_rpc.sql
[Phase 2: Svc Red]  Write flutter_app/test/services/account_service_void_income_test.dart
[Phase 2: Svc Green]Implement AccountService.voidIncomeRecord & AccountProvider.voidIncomeRecord
[Phase 3: UI Red]   Write flutter_app/test/screens/accounts_overview_void_income_test.dart
[Phase 3: UI Green] Implement UI Delete Action, Modal & Localizations
[Phase 4: Gate]     Run flutter analyze (0 issues), flutter test (100% pass), pytest (100% pass)
```

---

## 3. Step-by-Step Implementation Instructions

### Step 1: Write Database Regression Test `35_void_income_record.sql`
- **File:** `supabase/tests/35_void_income_record.sql`
- **Action:** CREATE
- **TDD Test Cases Specified (write first):**
  1. **Success Reversal & Row Deletion:**
     - Provision `test_hh1`, admin user `u1`, checking account `acc1` with balance `1000.00`.
     - Record income: 500 SAR (`base_amount: 500.00`) -> balance becomes `1500.00`.
     - Execute `SELECT public.void_income_record(v_income_id)` as user `u1`.
     - Assert JSON returned contains `'success': true`, `'id': v_income_id`, `'net_amount': 500.00`.
     - Assert `accounts.balance` decremented back to `1000.00`.
     - Assert `SELECT COUNT(*) FROM public.income_records WHERE id = v_income_id` equals `0`.
  2. **Net Amount Ledger Precision Math:**
     - Record income with base `1000.00`, overtime `250.00`, bonus `150.00`, deductions `100.00` (`net_amount = 1300.00`).
     - Balance becomes `2300.00`.
     - Void income record.
     - Assert balance decremented by exactly `1300.00` (net amount), returning to `1000.00`.
  3. **Multi-Tenant IDOR Attack Rejection:**
     - Provision `test_hh2` with user `u2`.
     - Attempt to execute `SELECT public.void_income_record(v_income_id)` as user `u2` against `test_hh1`'s income record.
     - Assert call fails with error code `42501` (`Access denied: caller does not belong to the household of this income record`).
     - Assert `test_hh1`'s income record still exists and `acc1` balance remains intact.
  4. **Non-Existent & Invalid IDs:**
     - Call `void_income_record('00000000-0000-0000-0000-000000000000'::uuid)` -> assert raises `P0002` (`Income record not found`).
     - Call `void_income_record(NULL)` -> assert raises `22023` (`Income record ID is required`).
  5. **Direct Client DELETE Blocked:**
     - Authenticated user executes `DELETE FROM public.income_records WHERE id = v_income_id;`.
     - Assert 0 rows affected or permission denied due to append-only policy. Only the RPC may delete.
  6. **Role & Account Ownership Boundary:**
     - Regular member `m1` in `test_hh1` attempts to void an income record logged by admin `u1` into `u1`'s private account.
     - Assert call fails with error code `42501`.

---

### Step 2: Implement Migration `20261102010000_void_income_record_rpc.sql`
- **File:** `supabase/migrations/20261102010000_void_income_record_rpc.sql`
- **Action:** CREATE
- **Function Specification:**
  ```sql
  CREATE OR REPLACE FUNCTION public.void_income_record(
      p_income_id UUID
  )
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
  AS $$
  DECLARE
      v_caller_uid UUID;
      v_caller_hh UUID;
      v_caller_role TEXT;
      v_income RECORD;
      v_acc RECORD;
      v_new_balance NUMERIC(14, 2);
      v_result jsonb;
  BEGIN
      -- 1. Input parameter validation
      IF p_income_id IS NULL THEN
          RAISE EXCEPTION 'Income record ID is required' USING ERRCODE = '22023';
      END IF;

      -- 2. Authentication check
      v_caller_uid := auth.uid();
      IF v_caller_uid IS NULL THEN
          RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
      END IF;

      -- 3. Row lock on income_records to prevent concurrent voiding
      SELECT * INTO v_income
      FROM public.income_records
      WHERE id = p_income_id
      FOR UPDATE;

      IF v_income.id IS NULL THEN
          RAISE EXCEPTION 'Income record not found' USING ERRCODE = 'P0002';
      END IF;

      -- 4. Multi-tenancy check: caller household must match income record household
      v_caller_hh := public.get_auth_user_household_id();
      IF v_caller_hh IS NULL OR v_caller_hh IS DISTINCT FROM v_income.household_id THEN
          RAISE EXCEPTION 'Access denied: caller does not belong to the household of this income record' USING ERRCODE = '42501';
      END IF;

      -- 5. Row lock on target account
      SELECT * INTO v_acc
      FROM public.accounts
      WHERE id = v_income.account_id
      FOR UPDATE;

      IF v_acc.id IS NULL THEN
          RAISE EXCEPTION 'Target account not found' USING ERRCODE = 'P0002';
      END IF;

      -- Verify account belongs to same household
      IF v_acc.household_id <> v_income.household_id THEN
          RAISE EXCEPTION 'Corrupt ledger: target account belongs to a different household' USING ERRCODE = '42501';
      END IF;

      -- 6. Permission check:
      -- Caller must be:
      --   a) The user who logged the income, OR
      --   b) The account owner, OR
      --   c) A household admin/co-admin.
      v_caller_role := public.get_auth_user_role();
      IF v_income.user_id <> v_caller_uid
         AND v_acc.owner_user_id <> v_caller_uid
         AND (v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'co_admin')) THEN
          RAISE EXCEPTION 'Access denied: insufficient permissions to void this income record' USING ERRCODE = '42501';
      END IF;

      -- Non-shared account protection: non-admin cannot debit another user's personal account
      IF v_acc.is_shared_pool = false
         AND v_acc.owner_user_id <> v_caller_uid
         AND (v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'co_admin')) THEN
          RAISE EXCEPTION 'Access denied: cannot void income from a personal account owned by another member' USING ERRCODE = '42501';
      END IF;

      -- 7. Atomically decrement account balance
      UPDATE public.accounts
      SET balance = balance - v_income.net_amount,
          updated_at = now()
      WHERE id = v_acc.id
      RETURNING balance INTO v_new_balance;

      -- 8. Delete the income record
      DELETE FROM public.income_records
      WHERE id = p_income_id;

      -- 9. Construct and return receipt payload
      SELECT jsonb_build_object(
          'id', v_income.id,
          'household_id', v_income.household_id,
          'account_id', v_income.account_id,
          'user_id', v_income.user_id,
          'cycle_key', v_income.cycle_key,
          'title', v_income.title,
          'net_amount', v_income.net_amount,
          'new_balance', v_new_balance,
          'voided_at', now(),
          'success', true
      ) INTO v_result;

      RETURN v_result;
  END;
  $$;

  -- Security grant restrictions
  REVOKE ALL ON FUNCTION public.void_income_record(UUID) FROM PUBLIC, anon;
  GRANT EXECUTE ON FUNCTION public.void_income_record(UUID) TO authenticated, service_role;
  ```

---

### Step 3: Synchronize Baseline Schema `supabase/schema.sql`
- **File:** [supabase/schema.sql](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/supabase/schema.sql)
- **Action:** UPDATE
- **Details:**
  - Add `public.void_income_record(UUID)` definition under the financial functions section.
  - Add associated `REVOKE` and `GRANT` permission statements at the bottom of the schema file to ensure new local rebuilds have complete baseline fidelity.

---

### Step 4: Write Flutter Service & Provider Unit Tests
- **File:** `flutter_app/test/services/account_service_void_income_test.dart`
- **Action:** CREATE
- **TDD Test Cases Specified (write first):**
  1. `AccountService.voidIncomeRecord` invokes `_client.rpc('void_income_record', params: {'p_income_id': ...})` and returns the deserialized map.
  2. `AccountService.voidIncomeRecord` propagates RPC exceptions (e.g. `PostgrestException`) when backend returns an error.
  3. `AccountProvider.voidIncomeRecord` calls `AccountService.voidIncomeRecord` with the provided ID.
  4. `AccountProvider.voidIncomeRecord` triggers a forced refresh (`refresh(force: true)`), updating `_cycleIncomeRecords`, account balances, and recomputing `_snapshot`.
  5. In case of service failure, `AccountProvider.voidIncomeRecord` bubbles the exception and leaves previous valid state intact.

---

### Step 5: Implement `AccountService` and `AccountProvider` Void Methods
- **Files:**
  - [flutter_app/lib/services/account_service.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/services/account_service.dart)
  - [flutter_app/lib/providers/account_provider.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/providers/account_provider.dart)
- **Action:** UPDATE
- **Details:**
  1. In `AccountService`:
     ```dart
     /// Void an income record and atomically decrement the credited account balance.
     Future<Map<String, dynamic>> voidIncomeRecord(String incomeId) async {
       final res = await _client.rpc('void_income_record', params: {
         'p_income_id': incomeId,
       });
       return Map<String, dynamic>.from(res as Map);
     }
     ```
  2. In `AccountProvider`:
     ```dart
     /// Voids an income record, reverses the credited account balance, and forces a refresh of snapshot and accounts.
     Future<void> voidIncomeRecord(String incomeId) async {
       await _accountsService.voidIncomeRecord(incomeId);
       await refresh(force: true);
     }
     ```

---

### Step 6: Add Trilingual Localizations in `app_localizations.dart`
- **File:** [flutter_app/lib/l10n/app_localizations.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/l10n/app_localizations.dart)
- **Action:** UPDATE
- **Keys and Translations to add across all 3 language blocks:**
  - **English (`en`):**
    ```dart
    'void_income_title': 'Void Income Record',
    'void_income_confirmation': 'Are you sure you want to void this income record? {amount} will be deducted from {account}.',
    'void_income_action': 'Void Income',
    'income_voided_success': 'Income record voided and balance deducted successfully.',
    'void_income_error': 'Failed to void income record.',
    ```
  - **Arabic (`ar`):**
    ```dart
    'void_income_title': 'إلغاء تسجيل الدخل',
    'void_income_confirmation': 'هل أنت متأكد من رغبتك في إلغاء تسجيل هذا الدخل؟ سيتم خصم {amount} من {account}.',
    'void_income_action': 'إلغاء الدخل',
    'income_voided_success': 'تم إلغاء تسجيل الدخل وخصم الرصيد بنجاح.',
    'void_income_error': 'تعذر إلغاء تسجيل الدخل.',
    ```
  - **Urdu (`ur`):**
    ```dart
    'void_income_title': 'آمدنی کا ریکارڈ منسوخ کریں',
    'void_income_confirmation': 'کیا آپ واقعی اس آمدنی کے ریکارڈ کو منسوخ کرنا چاہتے ہیں؟ {account} سے {amount} منہا کر دیا جائے گا۔',
    'void_income_action': 'آمدنی منسوخ کریں',
    'income_voided_success': 'آمدنی کا ریکارڈ منسوخ کر دیا گیا اور رقم کامیابی سے منہا ہو گئی۔',
    'void_income_error': 'آمدنی کا ریکارڈ منسوخ کرنے میں ناکامی۔',
    ```

---

### Step 7: Write Widget Test for Income Voiding Action
- **File:** `flutter_app/test/screens/accounts_overview_void_income_test.dart`
- **Action:** CREATE
- **TDD Test Cases Specified (write first):**
  1. Render `AccountsOverviewScreen` with an active `AccountProvider` containing accounts and cycle income records.
  2. Verify each income row in `_buildIncomeRow` displays a delete / void icon button (`Icons.delete_outline` or similar).
  3. Tap the delete icon on an income row:
     - Verify a confirmation dialog pops up titled `Void Income Record`.
     - Verify dialog body contains the formatted amount (e.g., `500.00 SAR`) and destination account name.
  4. Tap `Cancel` on the dialog:
     - Verify dialog dismisses.
     - Verify `AccountProvider.voidIncomeRecord` was NOT called.
  5. Tap `Void Income` on the dialog:
     - Verify `AccountProvider.voidIncomeRecord` was called with the specific income record ID.
     - Verify confirmation dialog dismisses.
     - Verify a success `SnackBar` is displayed.
  6. Arabic / RTL render verification:
     - Render in Arabic locale (`Locale('ar')`).
     - Verify dialog renders Arabic title `إلغاء تسجيل الدخل` and action button `إلغاء الدخل` in RTL layout.

---

### Step 8: Implement UI Action in `AccountsOverviewScreen`
- **File:** [flutter_app/lib/screens/accounts/accounts_overview_screen.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/screens/accounts/accounts_overview_screen.dart)
- **Action:** UPDATE
- **Details:**
  1. Update `_buildIncomeRow(BuildContext context, IncomeRecord rec, String accountName)`:
     - Wrap trailing amount and delete icon into a compact `Row(mainAxisSize: MainAxisSize.min, children: [...])`.
     - Add `IconButton`:
       ```dart
       IconButton(
         icon: Icon(Icons.delete_outline, size: 18, color: context.textSecondary),
         visualDensity: VisualDensity.compact,
         padding: EdgeInsets.zero,
         constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
         tooltip: context.tr('void_income_title'),
         onPressed: () => _confirmVoidIncome(context, rec, accountName),
       )
       ```
  2. Implement `_confirmVoidIncome(BuildContext context, IncomeRecord rec, String accountName)`:
     - Present styled dialog:
       ```dart
       Future<void> _confirmVoidIncome(BuildContext context, IncomeRecord rec, String accountName) async {
         final confirmed = await showDialog<bool>(
           context: context,
           builder: (ctx) => AlertDialog(
             backgroundColor: ctx.surfaceColor,
             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
             title: Row(
               children: [
                 Icon(Icons.warning_amber_rounded, color: ctx.dangerColor, size: 22),
                 const SizedBox(width: 8),
                 Expanded(
                   child: Text(
                     ctx.tr('void_income_title'),
                     style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: ctx.textPrimary),
                   ),
                 ),
               ],
             ),
             content: Text(
               ctx.trArgs('void_income_confirmation', {
                 'amount': ctx.sar(rec.netAmount),
                 'account': accountName.isNotEmpty ? accountName : ctx.tr('account'),
               }),
               style: TextStyle(fontSize: 13.5, color: ctx.textSecondary),
             ),
             actions: [
               TextButton(
                 onPressed: () => Navigator.of(ctx).pop(false),
                 child: Text(ctx.tr('cancel'), style: TextStyle(color: ctx.textSecondary)),
               ),
               ElevatedButton(
                 style: ElevatedButton.styleFrom(
                   backgroundColor: ctx.dangerColor,
                   foregroundColor: Colors.white,
                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                 ),
                 onPressed: () => Navigator.of(ctx).pop(true),
                 child: Text(ctx.tr('void_income_action')),
               ),
             ],
           ),
         );

         if (confirmed == true && mounted) {
           try {
             await context.read<AccountProvider>().voidIncomeRecord(rec.id);
             if (!mounted) return;
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(
                 content: Text(context.tr('income_voided_success')),
                 backgroundColor: context.forestGreen,
               ),
             );
           } catch (e) {
             if (!mounted) return;
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(
                 content: Text(context.tr('void_income_error')),
                 backgroundColor: context.dangerColor,
               ),
             );
           }
         }
       }
       ```

---

### Step 9: Full Quality Gates & Verification
Execute all automated test suites and linters:
1. `flutter analyze` in `flutter_app/` (Must output: `No issues found!`).
2. `flutter test` in `flutter_app/` (Must pass 100% of tests, including new unit and widget tests).
3. `pytest` for backend test suite (Must pass 100% of tests).

---

## 4. Edge Cases, Attack Vectors & Invariant Audits

| Attack Vector / Edge Case | Threat / Risk | Mitigation & Defense |
|---|---|---|
| **Multi-Tenant Cross-Household IDOR** | Malicious user passes UUID of another household's income record to `void_income_record`. | Function verifies `v_caller_hh IS DISTINCT FROM v_income.household_id` and raises SQLSTATE `42501`. |
| **Concurrent Void Execution** | Two requests attempt to void the same income record simultaneously to double-deduct balance. | PostgreSQL row lock: `SELECT * FROM public.income_records WHERE id = p_income_id FOR UPDATE;`. Second request blocks until first completes and fails with `P0002` (row deleted). |
| **Deadlock on Account & Record Locking** | Two transactions lock `accounts` and `income_records` in inverted order. | Invariant lock order: Always lock `income_records` FOR UPDATE first, then target `accounts` FOR UPDATE. |
| **Client Direct DELETE Bypass** | Attacker bypasses the UI and attempts `DELETE FROM income_records` directly via Supabase client. | Ledger remains append-only: `REVOKE DELETE ON public.income_records FROM anon, authenticated;` is preserved. Client DELETE yields 0 rows or permission error. |
| **Spousal Personal Account Depletion** | Admin or roommate attempts to void income in another member's private account without entitlement. | Explicit checks enforce that if `is_shared_pool = false`, caller must be account owner or record creator or admin. |
| **Negative / Overdraft Balance** | Account balance becomes negative after deducting mistakenly recorded income. | Permitted in database: Accounts represent real-world state; if money was mistakenly credited and already spent, deducting the mistaken income reflects the true negative/overdraft liability. The UI handles negative balances seamlessly. |
| **Stale Provider Cache / HUD Inconsistency** | UI shows old cycle income or stale cash after voiding. | `AccountProvider.voidIncomeRecord` explicitly forces full refresh (`refresh(force: true)`), recomputing `OperatingCashSnapshot` immediately. |

---

## 5. Multi-Round Review Pipeline Execution Checklist

This feature touches balances, financial ledger rows, and security definer RPCs, making it **SENSITIVE** under [docs/sensitive.md](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/docs/sensitive.md). It mandates full 3-round review:

- [ ] **Round 1: Opus 5.5 High (`reviewer-spec`)**
  - Verify signature: `public.void_income_record(p_income_id UUID) RETURNS jsonb`.
  - Verify Flutter signatures: `AccountService.voidIncomeRecord(String incomeId)`, `AccountProvider.voidIncomeRecord(String incomeId)`.
  - Verify adherence to Zero SMS, Zero Jargon, Saudi Fintech salary cycle rules.
  - Verify trilingual localization strings exist for EN, AR, UR.
- [ ] **Round 2: Opus 5.5 High (`reviewer-break`)**
  - Verify deadlock prevention (lock acquisition ordering).
  - Verify race condition resistance (`FOR UPDATE` on income and account rows).
  - Verify error handling when network drops or backend throws RPC exception.
  - Verify widget testing covers dialog dismiss on Cancel vs Void.
- [ ] **Round 3: Fable High (`reviewer-fable`)**
  - Verify strict security definer hygiene (`search_path = public, pg_temp`).
  - Verify RLS and permissions: `REVOKE FROM PUBLIC, anon; GRANT TO authenticated, service_role`.
  - Verify cross-tenant isolation and IDOR rejection.
  - Verify Islamic financial compliance regarding spousal private account isolation.
