ARCHITECTURAL REFACTORING SPEC: DASHBOARD & BUDGET TAB STATE SYNCHRONIZATION AND OPERATING CASH HARMONIZATION

PROBLEM STATEMENT:
1. Severe Dashboard & Budget Tab Latency (2-5s freeze/load time):
   - On opening dashboard_screen.dart, it executes uncoordinated parallel queries: _fetchCycles, _fetchSetup, _fetchAccountsCount, _fetchCycleIncome.
   - _fetchCycleIncome executes AccountService.instance.getAccounts(hid), while at the exact same moment AccountProvider.refresh() executes AccountService.instance.getAccounts(hid).
   - In budget_management_screen.dart, _loadStaticData() does its own independent waterfall of queries, re-fetching users, categories from API, fallback SQL queries, and calls AccountService.getAccounts(hid) TWICE (before and after reconcileUnlinkedTransactions).
   - Neither screen relies on the preloaded state in AccountProvider and BudgetProvider. Every screen performs duplicate, unbundled network requests to live Supabase and FastAPI.

2. State Race Conditions & Data Desynchronization:
   - _BudgetDashboardState maintains local mutable state variables (_operatingCash, _cycleIncome, _accountsCount) while AccountProvider also maintains (operatingCash, cycleIncomeTotal).
   - As separate network requests finish out of order (0.5s vs 2.5s), values flip back and forth, causing BudgetHeroCard and AccountsSummaryCard to flicker and show desynced numbers.
   - Budget Management Screen shows a different operating cash and budget allocation than the Dashboard Hero Card.

3. Operating Cash Business Logic Formula:
   - Operating Cash must represent TRUE LIQUID OPERATING FUNDS MINUS COMMITTED DEBTS.
   - Liquid Account Balance = Total balance of active, non-archived operating accounts (Bank, E-Wallet, Cash).
   - Pending Commitments = Unpaid recurring bills + active installment dues for the current cycle.
   - True Operating Cash = Liquid Account Balance - Pending Commitments.
   - This exact calculation must be identical across both the Dashboard Hero Card and the Budget Management Screen header.

4. UI/UX Tone & Nomenclature Alignment:
   - All user-facing UI labels must use natural, dignified household terminology.
   - ZERO religious, legalistic, or compliance jargon in the UI (NO "نفقة شرعية", NO "Saudi Fintech Compliance Engine").
   - Backend/database variables remain nafaqah_class, wife_reimbursable, wife_personal.
   - Frontend displays:
     * Husband covers family essentials -> "مصاريف المنزل" / "دفعه الزوج"
     * Wife personal allowance -> "مصروف الزوجة"
     * Wife reimbursable debt owed by husband -> "مستحقات للزوجة"
     * General management -> "إدارة ميزانية الأسرة"

REQUESTED ARCHITECTURAL PLAN:
Provide a surgical, step-by-step TDD implementation plan for Antigravity (Gemini 3.8 Flash High) to:
1. Consolidate account balances, operating cash, and commitments into a single source of truth in AccountProvider.
2. Remove duplicate, waterfall network queries from dashboard_screen.dart and budget_management_screen.dart so the dashboard loads instantly from cached provider state.
3. Align the Operating Cash formula across BudgetHeroCard, PaydayOutlook, and BudgetManagementScreen.
4. Clean up user-facing strings in app_localizations.dart to remove all jargon.
5. Provide exact unit and widget test requirements to verify zero regressions.

