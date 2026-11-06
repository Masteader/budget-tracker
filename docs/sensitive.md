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
- `ai_service/nafaqah_service.py` (Wife allowance, personal spend, reimbursement ledger, a deleted wife's outstanding record)
- `flutter_app/lib/widgets/nafaqah/former_member_debt_panel.dart` (Payments and waiver of what a deleted wife was owed)
- `flutter_app/lib/widgets/nafaqah/repayment_account_picker.dart` and `flutter_app/lib/widgets/dashboard/family_reimbursement_card.dart` (Which account a repayment to the wife is paid from; it moves balances)
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

