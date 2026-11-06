# Sensitive Paths and Operations

This document defines the strict sensitivity boundary for the **Budget Tracker** repository.

Any plan or pull request that touches these paths or performs these operations is classified as **SENSITIVE** automatically.

---

## 1. Automatic Sensitive Paths

The following paths in the repository are classified as sensitive by default:

### Database & Migrations
- `supabase/migrations/**` (All schema, constraints, triggers, and functions)
- `supabase/tests/**` (Database security and regression tests)

### Authentication, Security & Permissions
- `ai_service/household_permissions.py` (Access control, admin/co-admin checks, account debit guards)
- `flutter_app/lib/providers/household_role_provider.dart` (Client-side role and permission state)
- `flutter_app/lib/screens/auth/**` (Login, OTP, password updates, account creation)
- `flutter_app/lib/services/api/` (Preview tokens, token authentication)

### Balances, Money & Ledger Operations
- `ai_service/supabase_client.py` (Account balance mutations, debit assertions, default debitable account resolution)
- `ai_service/chat_parser.py` (Transaction commit payloads, expense ledger recording)
- `ai_service/receipt_scanner.py` (OCR expense commit payloads, ledger recording)
- `ai_service/salary_cycle.py` (Saudi salary cycle calculation, payday bounds)
- `flutter_app/lib/models/operating_cash.dart` (Operating cash & liquid balance calculations)
- `flutter_app/lib/models/payday_outlook.dart` (Payday outlook, safe daily spend, afterCommitments math)
- `flutter_app/lib/services/account_service.dart` (Balance ledger queries, reconciliation)
- `flutter_app/lib/services/commitments_service.dart` (Pending recurring bills & installment obligations)
- `flutter_app/lib/services/salary_cycle_service.dart` (Saudi payday calendar cycle calculation)
- `flutter_app/lib/providers/account_provider.dart` (Central account balances and commitments state)
- `flutter_app/lib/widgets/dashboard/budget_hero_card.dart` (Primary financial HUD)
- `flutter_app/lib/screens/home/budget_management_screen.dart` (Budget allocations, funding, and prior spend)

### Islamic Compliance & Nafaqah
- `ai_service/nafaqah_service.py` (Wife allowance, personal spend, reimbursement ledger, a deleted wife's outstanding record; who sees and settles a wife's ledger: she, her husband, an admin who is not a wife once he is gone; who sees her allowance and her personal purchases: she, her husband, an admin who is not a wife; who sets it: the husband or an admin, never a wife; `can_view_personal_purchase` / `visible_transactions`, the filter every service-role answer built from transactions applies; `can_view_installment_plan`, the plan of her personal purchase)
- `ai_service/settlement_engine.py` (Settlement totals, including the Nafaqah totals of only the wives whose ledger the caller sees, and personal totals of only the personal purchases the caller reads)
- `ai_service/installment_service.py` and the installment routes of `ai_service/routes/budgets.py` (Service-role reads of installment plans answered to a member: only the plans the caller reads, never the plan of a co-wife's personal purchase; a payment, an edit or a new linked plan only on a plan or purchase the caller reads)
- `ai_service/dedup_engine.py`, `ai_service/price_tracker.py`, `ai_service/pdf_statement_generator.py`, `ai_service/recurring_detector.py` and the cycle list in `ai_service/salary_cycle.py` (Service-role reads of the household's transactions answered to a member: only the rows the caller reads, never a co-wife's personal purchase)
- `flutter_app/lib/widgets/nafaqah/former_member_debt_panel.dart` (Payments and waiver of what a deleted wife was owed)
- `flutter_app/lib/widgets/nafaqah/repayment_account_picker.dart` and `flutter_app/lib/widgets/dashboard/family_reimbursement_card.dart` (Which account a repayment to the wife is paid from, her requests and their approval, and reversals; every one of them moves balances; which wife's ledger and allowance the card shows to whom, and to whom it offers setting her allowance)
- `flutter_app/lib/models/nafaqah.dart` (Who the app shows a wife's ledger, her allowance, a former member's record and the dues lines to)
- `flutter_app/lib/widgets/nafaqah/unconfirmed_payments.dart` (Keeps the request key and what was sent of a repayment, her request, an approval or a former member's payment whose answer was lost, so a reopened sheet never sends it under a second key)
- `supabase/migrations/20261105001300_wife_repayment_debit.sql` (Tracked repayments, the wife's requests and reversals: debits and credits accounts, changes what is owed, closes requests at the purge; the read policies of her ledger and of her allowance, and who reads and sets her allowance; the read policy of `transactions` (her personal purchases) and of receipt photos in storage; the read policies of `account_transfers` (her accounts' transfers, through `personal_owner_ids` and its triggers) and of `installment_plans` (the plans of her personal purchases); refuses a client's delete of an account a repayment used)
- `flutter_app/lib/models/nafaqah_account.dart` (Wife account debiting isolation)
- `flutter_app/lib/widgets/settlement/` (Spousal reimbursement & roommate settlement)

### Account Deletion
- `ai_service/account_deletion_worker.py` (Permanently deletes accounts with the service-role key)
- `ai_service/account_deletion_notices.py` (Deletion emails to account holders and household members)
- `ai_service/scripts/account_deletion_operator.py` (Schedules a deletion for someone who cannot sign in)
- `supabase/migrations/20261105000000_account_deletion_ledger_fks.sql`, `20261105000100_account_deletion_schema.sql`, `20261105000200_account_deletion_rpcs.sql`, `20261105000300_account_deletion_purge.sql`, `20261105000400_account_deletion_worker_support.sql`, `20261105000800_account_deletion_operator_request.sql`, `20261105000900_account_deletion_notice_windows.sql`, `20261105001200_account_deletion_former_member_debt.sql` (Also covered by `supabase/migrations/**`)
- `flutter_app/lib/services/account_deletion_service.dart` (Request, cancel and status RPC calls)
- `flutter_app/lib/services/local_account_data_cleaner.dart` (Wipes a deleted user's data from the device)
- `web_app/src/components/AccountDeletionPage.tsx` (Authenticated deletion path and public request form)

### Secrets & Deployment
- `.env*` (Environment files and configuration templates)
- `ai_service/Dockerfile`, deploy scripts
- Railway settings and variables (This repository has no `railway.json`: Railway, including the account deletion Cron service, is configured in its dashboard)

---

## 2. Sensitive Operational Actions

Regardless of file path, an action is **SENSITIVE** if it:
1. **Moves money or alters balances:** Modifies accounts, budgets, commitments, debt simplification, or expense ledger math.
2. **Changes permissions:** Alters user roles, admin privileges, co-admin grants, or membership states.
3. **Touches security policies:** Modifies PostgreSQL Row Level Security (RLS) policies, JWT validation, or API signatures.
4. **Deletes data:** Performs destructive operations, drops columns/tables, or archives active accounts.
5. **Touches secrets:** Deals with API credentials, service-role keys, tokens, or encryption keys.

---

## 3. Governance Invariants

- **Unidirectional Escalation:** The orchestrator or reviewer may raise a task to sensitive, but **never lower it**. When in doubt, it is sensitive.
- **Plan Requirement:** Every implementation plan must state upfront:
  > **Sensitive:** yes or no, because [exact justification].
- **Audit Mandate:** Sensitive tasks mandate an additional **Round 3 review by Fable (effort high)** following Rounds 1 & 2 by Opus 5.5 high.

