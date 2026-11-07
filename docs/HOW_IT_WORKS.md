# How the App Works

A plain guide for the owner and for new developers to how the whole of Qawam Money (قوام المال)
behaves today: signing in and setting up a household, the people and their roles, accounts,
budgets and salary cycles, income, the ways to record an expense, the family and roommate rules,
bills and installments, the dashboard and reports, reminders, settings, help, the website, who sees
what, and what happens when someone deletes their account. It describes behaviour, not code. Where
you need the exact rule, the database objects or the review history, follow the links to the
project rules:

- [Rule 02, Saudi fintech and Islamic compliance](../.agents/rules/02-saudi-fintech-and-islamic-compliance.md):
  payday cycles, family mode rules 1 to 4, the wife ledger and the wife account.
- [Rule 03, UI/UX and design system](../.agents/rules/03-ui-ux-and-design-system.md): themes and
  the three languages.
- [Rule 04, security and privacy](../.agents/rules/04-security-and-privacy.md): roles, row level
  security, who reads what, account deletion.

The database enforces every rule below. The API re-checks them for the signed-in user, and the app
only hides what the server would refuse anyway. Button and screen names are the English ones the
app shows; the app also runs in Arabic and Urdu.

Last checked against the code: 2026-11-07 (`main` at `f6e57fb`; the setup tutor, the Help FAQ and
the duplicate card in §1, §6 and §14 on `feat/onboarding-guide-update`).

## Contents

1. [Getting started](#1-getting-started)
2. [Households and roles](#2-households-and-roles)
3. [Accounts](#3-accounts)
4. [Budgets and salary cycles](#4-budgets-and-salary-cycles)
5. [Income](#5-income)
6. [Recording an expense](#6-recording-an-expense)
7. [Expense kinds](#7-expense-kinds)
8. [Paying her back: repayments, requests and reversals](#8-paying-her-back-repayments-requests-and-reversals)
9. [Roommate settlements](#9-roommate-settlements)
10. [Bills, installments and commitments](#10-bills-installments-and-commitments)
11. [Dashboard, reports and exports](#11-dashboard-reports-and-exports)
12. [Reminders and notifications](#12-reminders-and-notifications)
13. [Settings](#13-settings)
14. [Help, support and the in-app guide](#14-help-support-and-the-in-app-guide)
15. [The website](#15-the-website)
16. [Who sees what](#16-who-sees-what)
17. [Privacy basics](#17-privacy-basics)
18. [Account deletion](#18-account-deletion)
19. [Accepted limits and follow-ups](#19-accepted-limits-and-follow-ups)

---

## 1. Getting started

### Signing in

- The app signs in with **email and password**. There is no Google or Apple sign-in, and the sign-in
  screen offers no email link. (Only when the password reset email cannot be sent does **Forgot
  password?** fall back to a one-time sign-in email; its code is entered the same way as below.)
- **Create Account** asks for a display name, an email and a password of at least 6 characters.
  The app then asks them to confirm the email from the link it sends.
- **Forgot password?** → **Send Reset Code** sends an email and goes straight to **Enter
  Verification Code**, which takes the code and the new password together. Tapping the reset link
  in the email instead opens the app on **Set New Password**. A new code can be asked for after 60
  seconds.
- The app only accepts sign-in links meant for it. A link that carries sign-in tokens is refused,
  so nobody can sign someone into another account by sending them a link.
- The sign-in is kept in the phone's secure storage, so the app opens signed in next time.

### The first run

- A person with no household sees **Your Household**: create one (a name, then **Family** or
  **Roommates**) or join one with an invite code. See [section 2](#2-households-and-roles).
- The household's admin then sees **Set up your household in two minutes** on the dashboard. While
  the cycle has no budgets it takes the place of the hero card; once budgets exist it sits below the
  hero card, the over-budget alerts and **Quick Access**. Each step opens the right editor:

| Step | What it does | Done when |
|---|---|---|
| Payday | Confirms or changes the payday | Confirmed, or a payday other than the 27th was chosen |
| Monthly income | Opens **Record Income** | Income is recorded for this cycle, or the household has a monthly income figure |
| Starter budgets | **Suggested budgets**: one amount per category, filled in from the income; 0 skips a category | The cycle has budgets |
| Invite your wife / Invite your roommates | Opens the role invite | The household has a second member |
| Choose household provider (family only) | Opens **Members & Admins** | A provider is named |

- A member who is not an admin sees **Budgets not set up yet** instead, and can already record
  expenses.
- The checklist stays on the dashboard while steps are open. **Hide** appears once the cycle has
  budgets and removes it for this household on this phone; Settings → **Household Setup
  Checklist** → **Restore to Dashboard** brings it back.
- The first time the dashboard has loaded the household on a phone, the **Interactive Setup Tutor**
  also appears once, with the steps for the person's role (see
  [section 14](#14-help-support-and-the-in-app-guide)).

### Finding your way

- The bottom bar has **Dashboard**, **Transactions**, a centre button for the AI chat, **Budgets**
  and **Settings**.
- On Dashboard and Transactions, the **Add Expense** button opens **Scan Receipt**, **Voice & AI
  Assistant** and **Manual Log** ([section 6](#6-recording-an-expense)).
- On the dashboard header, the grid icon opens **Tools**, the arrows icon switches household, and
  the bell icon opens **Help & Support**.
- **Tools** holds the planning and extra capture tools: **Can I Afford This?**, **Accounts &
  Balances**, **Income & Cash Flow Report**, **Record Income**, **Transfer Funds**, **Batch Scan
  Receipts**, **Price Tracker** and **Smart Basket Optimizer**.

---

## 2. Households and roles

### Households

- A **household** is the space people share. It is created as one of two types:
  - **Family**: a husband, one or more wives, and other family members.
  - **Roommates**: people sharing a flat, with equal splits and settle-ups.
- An admin can switch the type later. A family cannot become a roommates household while it has a
  wife member or any family ledger records (her expenses, allowances, repayments, or an open
  record of what a former wife is owed).
- People **join by invite code**. Only admins see the codes. The household's own join code stays
  the same; a role invite is single use and expires after 7 days (see "Joining, invites and
  switching" below). After 5 wrong codes in 15 minutes, joining is refused for 15 minutes. An
  existing member cannot claim an invite of their own household.
- A person can belong to **several households** and switches the active one in Settings. Creating a
  household is refused once the person is admin of 5.
- Every money account belongs to **exactly one household**.
- Each household has its own **payday** (`households.payday_day`, 1 to 31, default the 27th).
  Budgets and allowances run from payday to the day before the next payday, on the Riyadh calendar
  date. A payday past the end of a short month falls on its last day. Only an admin changes it.
- **Payday check-in.** From the household's payday, the dashboard shows a prompt to log the
  salary. It stays for up to 8 days (it closes 7 days after payday, counted on a 31-day month: payday
  27 closes on the 3rd, payday 15 on the 22nd). It does not show when a salary was logged in the last
  20 days, and it can be dismissed.

### Roles

| Role | Who | What they can do |
|---|---|---|
| **Primary admin** (owner) | `households.owner_user_id`: the person who created or inherited the household | Everything an admin can do. Only they hand the primary admin role to someone else. Co-admins cannot demote or remove them. |
| **Co-admin** | Any other admin | The same rights as the primary admin, except over the primary admin. |
| **Member** | Everyone else | Records, edits and deletes their own expenses; sees what the household shares. |

- When the primary admin's membership ends, the role passes to the longest-standing remaining admin.
- The last admin can never be demoted, and a sole admin cannot leave while other members remain.
- An admin edits or deletes any household expense **that they can read**. Rows hidden from them (see
  [section 16](#16-who-sees-what)) are out of their reach too.

### People in a family household

- **Husband (Nafaqah provider)**: `households.nafaqah_provider_user_id`. By default he is the
  primary admin. Any admin may name another member who is not a wife. Without a provider, the app
  refuses new wife expenses (advances and personal purchases).
- **Wife**: a member whose financial role in that household is `spouse`. There can be several.
  Each wife's private records are hidden from her co-wives, even a co-wife who is an admin.
- **Her husband is "gone"** when the household has no provider who is a current member and not a
  wife (he left, his account was deleted, or nobody was named). Then an admin who is not a wife
  takes over his part in her ledger and her wife account. The rest of this guide says "her husband"
  for that person.

### Joining, invites and switching

- **The household's join code.** Settings → **HOUSEHOLD & MEMBERSHIP** shows it to admins, with
  **Copy Code** and **Share invite**. It stays the same, and whoever enters it joins as a member:
  a roommate in a roommates household, a family member in a family.
- **A role invite.** **Invite with Role** makes a code for one person in a chosen role (**Wife /
  Spouse**, **Roommate / Flatmate** or **Family Dependent**). It is single use and is valid for 7
  days. A roommates household takes only roommate invites, and a family takes no roommate
  invites. Only admins make them.
- **Profiles before they join.** **Add Member / Dependent** creates a profile for someone who has
  no account yet, or for a child. An invite linked to that profile lets the person who joins take
  over its history and allowance.
- **Entering a code.** A new person enters it on **Your Household**; a member of another household
  uses **Join Another Household** in the switch sheet.
- **Switching.** The arrows icon on the dashboard, or **Switch Household** in Settings, lists the
  person's households. The app then shows only the chosen one. **Create New Household** is in the
  same sheet.
- **Leaving.** Settings → **Leave Household**. A sole admin is asked to make another member an
  admin first.
- **Financial roles and the type.** In **Members & Admins** an admin changes a member's financial
  role (only the roles that fit the household type are offered) and the household type (rules in
  "Households" above).

---

## 3. Accounts

| Kind | Belongs to | Who sees it | Who moves money |
|---|---|---|---|
| **Personal** (bank, cash, e-wallet, crypto, savings) | The person | Only its owner | Only its owner spends from it or transfers out of it |
| **Shared pool** | The household | Every member | Members pay into it; only admins transfer money out of it |
| **Wife account** | Her husband, assigned to one wife | Only that wife, the account's owner (normally her husband) and her ledger's managers; an admin who is not a wife only when her husband is gone | She spends from it (her personal purchases and her advances). Its owner or her ledger's managers fund it. Nothing is transferred out of it; the only other way money leaves it is a reversal |

### The wife account

- **Made** only by her husband ("Add wife account" on his accounts screen). Nobody can make one
  while her husband is gone. Clients cannot insert one directly.
- **Assigned** to a different wife only by him, and only while it has no history.
- **Archived** by its owner. A client cannot delete an account that a repayment or a reversal used;
  it is archived instead, so corrections stay possible.
- **He does not spend from it.** What is in it is hers to spend; his own expenses come from his own
  accounts.
- A wife may also have **personal accounts of her own**. They are private to her, and no repayment
  ever credits them.

Details: [rule 02, family mode rule 2, "The wife account"](../.agents/rules/02-saudi-fintech-and-islamic-compliance.md#3-islamic-family-finance-nafaqah-vs-roommate-living-groups).

### Adding and managing accounts

- **Accounts & Balances** (Tools, the dashboard's accounts card, or Settings → **SALARY &
  ACCOUNTS** → **Manage**) lists the accounts the person can see. **Add Account** takes a name, a
  type (**Bank Account**, **E-Wallet**, **Crypto Exchange**, **Cash Wallet**, **Shared Household
  Pool** or **Savings Vault**), a currency (SAR, USD, USDT, EUR or AED), the starting balance and
  the **Shared Household Pool** switch. A wife account is not on this list; it has its own action.
- **TOTAL NET WORTH & LIQUIDITY** sums the accounts in SAR (USD and USDT at a fixed 3.75; EUR and
  AED are added unconverted). The eye icon hides every balance on this screen until it is tapped
  again (it is not remembered when the screen closes).
- **Savings Vault** accounts are listed apart under **Savings & Vaults** and are not counted as
  money to spend (see "Operating cash" below).
- Each account card has **Reconcile**, **Activity** and **Transfer Out**:
  - **Reconcile Balance** sets the app's balance to the real figure from the bank or wallet. It
    shows the difference, then saves the new balance; no separate adjustment entry is kept. A
    personal account is reconciled by its owner, a pool by an admin.
  - **Account activity** lists the transfers and repayments that moved the balance.
  - **Transfer Funds** moves money between two accounts, with an optional fee. The rules in the
    table above apply: a personal account is debited only by its owner, money leaves a pool only
    by an admin, and nothing leaves a wife account.
- **Archive Account** hides an account; its history stays.

### Balances and capacity

- An expense saved with an account lowers that account's balance at once, and deleting the expense
  puts it back. The database does this when the expense is saved or deleted.
- Each account card compares the balance with what is still unspent in the budgets linked to it
  (budgets with no linked account count against the first bank, wallet, cash or pool account):

| Status on the card | Meaning |
|---|---|
| **Zero-Based (100% Allocated)** | The balance equals what the linked budgets still need |
| **+X Surplus Buffer** | The account holds X more than they need |
| **Deficit: X** | The account holds X less. **Quick transfer to cover the shortfall (X)** opens Transfer Funds with this account and the amount filled in; the person picks where it comes from |

### Operating cash

- **Operating cash** = the balances of the SAR bank, e-wallet, cash and pool accounts the person
  can see (not archived), minus **pending commitments**. Savings, crypto and wife accounts are not
  counted.
- Pending commitments are the recurring bills not yet paid this cycle plus the installment
  payments due by the end of this cycle, overdue ones included
  ([section 10](#10-bills-installments-and-commitments)).
- The dashboard's accounts card shows the result: "After commitments (X): Y actual available",
  "Deficit: commitments exceed balance by X", or "No pending commitments: full balance available".
- Each person sees the accounts they can read, so two members can see different figures.

---

## 4. Budgets and salary cycles

### The salary cycle

- A cycle runs from the household's payday to the day before the next payday, on the Riyadh
  calendar date ([section 2](#2-households-and-roles) has the payday rules).
- Each cycle has a key that names a month (`cycle_key`, for example `2026-11`). With a payday after
  the 15th it names the month the cycle ends in (payday 27: 27 Oct to 26 Nov is `2026-11`); with a
  payday on or before the 15th, the month it starts in. Payday 1 is the calendar month.
- The database gives every expense its cycle from the expense's date. The app and the API cannot
  set or change it.
- The dashboard, the Budgets tab and the reports have a cycle bar to look at earlier cycles.

### Categories and sub-categories

- Budgets are set per **category** (Groceries, Fuel, Utilities and so on) and, inside a category,
  per **sub-category**. A category's budget is the sum of its sub-categories when they have
  amounts.
- Standard categories come with the app; an admin adds custom ones with **Add Category**, and
  custom sub-categories with **Add Sub-Category**. Standard sub-categories cannot be renamed.
- **Rename Category**: when the category already has expenses, the admin chooses **Replace & Archive
  Old (Recommended)** (a new category for future expenses; the old one keeps the history) or
  **Rename Only** (the name changes on past and future expenses).
- **Deactivate Category** moves it to the **Category Library**. Categories are never deleted, and
  an inactive category can be activated again from the library. An expense in an inactive category
  still counts under it; when the chat files one there, it offers **Reactivate Category** or **File
  Under Other Category**.
- An expense in a category with no budget this cycle is marked **Unbudgeted**: it counts in the
  totals, not in a budget. The hero card shows "Unbudgeted spending: X".
- Her personal purchases (`wife_personal`) never count against a category budget
  ([section 7](#7-expense-kinds)).

### Setting the budgets

- Only admins change budgets. Other members can look at the Budgets tab; the server refuses their
  changes.
- **Edit Allocation** sets the amounts of a category and its sub-categories. A sub-category or
  category marked **Accumulate unspent (Sinking fund)** carries its unspent amount into the next
  cycle and goes back to its base amount once spent.
- **Link Account** names the account that funds a category. **Manual Log** then suggests that
  account for the category, and the chat pays from it when the person may use it.
- **Copy Previous Cycle Allocations** appears when a cycle has no budgets. It copies the last
  cycle's active budgets with their linked accounts; sinking funds add their unspent amount.
- If an expense recorded by chat or receipt is more than what is left in its category, the server
  moves the shortfall from a flexible category that has enough left. The expense shows
  **Reallocated**.

### Is the plan covered? (zero-based checks)

The budget is meant to spend exactly the money there is. The app checks this in three places:

| Where | What it compares | What it shows |
|---|---|---|
| Each account card ([section 3](#3-accounts)) | The account's balance and the unspent budgets linked to it | **Zero-Based (100% Allocated)**, **+X Surplus Buffer** or **Deficit: X** with a quick transfer |
| Budgets tab, **Cycle Funding Capacity** | All allocations and the income recorded this cycle (without any, the account balances before commitments plus what was spent from accounts) | "Within cycle capacity (X buffer)" or "Allocations exceed cycle funding capacity by X" |
| Budgets tab, account warning | An account and the unspent budgets that rely on it | "*Account* Capacity Deficit: X" with **Fix**, which opens a transfer into it |

- When allocations are over the capacity, **Shrink to Match Cash** scales the variable categories
  down to the cash and leaves fixed ones (rent, utilities) as they are.
- **Log Prior Spending** (admins, shown with the over-capacity warning above) is for a household
  that joins mid-cycle: it records what was already spent before using the app as an **Opening
  Spend Adjustment**, so the cycle matches the bank.

### Payday check-in and salary distribution

- From payday, the dashboard shows **Payday Cycle Started!** with **Log Salary** (the timing is
  in [section 2](#2-households-and-roles)).
- **Payday Check-in** asks for **Base Salary**, **Overtime**, **Bonus**, **Side Gigs** and
  **Deductions (GOSI/Tax)**, shows the **NET TAKE-HOME PAY**, and deposits it into the chosen
  account with **Confirm & Deposit**. It is saved as one salary income record
  ([section 5](#5-income)).
- **Distribute Salary** opens next. The person types an amount for each other account; the sheet
  shows what stays as **Remaining in Bank**. **Execute Distribution** makes one transfer per
  account, under the normal transfer rules. **Keep All in Bank** skips it. The assistant does not
  suggest amounts itself.

### When a new cycle starts (rollover)

- When someone first opens the dashboard or the Budgets tab in a new cycle, the server copies
  each active category of the last cycle that the new cycle does not have yet, with the same
  amount and linked account and nothing spent.
- What happens to the money left over follows the household's rollover rule (`households.rollover_rule`):

| Rule (app name) | What the code does today |
|---|---|
| **Send All to Savings** (default) | The leftover of the copied categories (never below zero) is added to the household's savings reserve figure, only when the new cycle had no budgets at all. This is a number on the household; no money moves between accounts |
| **Rollover to Same Categories** | Each category's leftover, or its overspend, is kept as its carryover and shown on its card as +X or −X. The category's budget amount itself stays the same |
| **Fresh Start (Zero Carryover)** | Nothing is carried and nothing is added to savings |

- A sinking fund accumulates whatever the rule.
- The app has no screen today to change the rule or to see the savings reserve: the "Budget Rollover
  Policy" card exists in the code but is not shown. The rule can be changed only through the API,
  by an admin, so households use the default.

---

## 5. Income

- Income is recorded with **Record Income** (Tools, the dashboard's quick access, the Accounts &
  Balances screen, or the setup checklist) or with the payday check-in
  ([section 4](#4-budgets-and-salary-cycles)).
- The sources are **Salary**, **Overtime**, **Bonus**, **Freelance / Side Gig**, **Roommate
  Share** and **Other Income**. For **Salary**, the sheet also takes **Overtime (+)**, **Bonus (+)**
  and **Deductions (GOSI/Tax) (−)**.
- The net amount (base + overtime + bonus − deductions) must be above zero. **Deposit Income** adds
  it to the chosen **Deposit Destination Account** at once and saves an income record for the
  current cycle.
- Income goes into the person's own personal account or into a shared pool. The server refuses
  another member's personal account.
- Income records are never edited. **Delete Income Record** → **Delete & Revert** removes one and
  takes its amount back out of the account. Its recorder, the account's owner or an admin may do
  this.
- Accounts & Balances shows **Cycle Income** with the records of the cycle; the **Income & Cash
  Flow Report** shows them as the **Income Records Ledger** ([section 11](#11-dashboard-reports-and-exports)).
- The household also has a **monthly income** figure (`households.monthly_income`). The dashboard
  falls back to it only when no income is recorded this cycle and there are no accounts to count
  ([section 11](#11-dashboard-reports-and-exports)). The app has no screen to set it
  today (the card for it exists in the code but is not shown); the API can.

---

## 6. Recording an expense

Every way below ends in the same kind of expense. In a family household each one asks "Who paid,
and for whom?" ([section 7](#7-expense-kinds)); in a roommates household, who paid and whether it
is shared ([section 9](#9-roommate-settlements)).

### Manual Log

- **Add Expense** → **Manual Log**. It takes the amount, the merchant, the date (**Current Cycle**,
  **Previous Cycle** or a picked date, with an optional **Different Recorded Date**), the category,
  the **Payment Account** and who paid.
- The accounts offered are the person's own bank, wallet and cash accounts, the pools if they are
  an admin, and, for a wife, her wife account.
- If the amount is more than a SAR account holds, **Insufficient Funds** asks first; the person can
  still record it.
- Saved with an account, the expense lowers its balance ([section 3](#3-accounts)).

### Receipt scanner

- **Add Expense** → **Scan Receipt**. The person adds one or more photos (**Snap Photo**, **Snap
  Next Page**, **Gallery**; the server takes at most 8 photos for one receipt, the app does not
  stop at 8), and can add the receipt's ZATCA QR
  code with **Scan QR Camera** or **Paste Text**. A QR code alone is enough to record the total.
- **The ZATCA Phase 2 QR code** is read on the phone: seller name, VAT number, date and time,
  total including VAT, and VAT amount. A valid code shows **ZATCA Verified**.
- **Reading the photos.** The photos go to the server, which sends them to the AI model set by the
  owner (Gemini by default) and gets back the merchant, date, category and line items. There is no
  reading on the phone itself.
- The person reviews the result (merchant, total, VAT, items, who paid, the paying account) and
  saves it. Within 15 minutes the server saves what it showed, without a second AI call; after that
  it reads the receipt again.
- **The stored photo.** When the person saves, the app first uploads the **first** photo and sends
  its place with the expense. The server joins all the pages into one image only when no photo
  came with the request (for example when that upload failed). So a long receipt normally keeps its
  first page only, and a save that fails afterwards leaves an uploaded photo linked to no expense
  ([section 19](#19-accepted-limits-and-follow-ups)).
- **Batch Scan Receipts** (Tools) photographs several receipts in a row and reviews them one by
  one (**Save & Next →**, and **Save & Finish** on the last one).

### Voice and the AI chat

- The centre button of the bottom bar, or **Add Expense** → **Voice & AI Assistant**, opens the
  **AI Transaction Chat**. The person types or speaks, for example "Danube 145 SAR: milk 20, chicken
  125", in Arabic, English or Urdu.
- **Voice**: the microphone button uses the phone's speech recognition, in the chosen **Voice
  language** (Saudi Arabic, English or Urdu), and puts the words in the chat.
- The chat answers with **Confirm Expense Details** (store, amount, date, who paid). **Confirm & Add
  Expense** saves it. The chat picks the paying account itself: the account linked to the
  category's budget, or the person's only account; otherwise none.
- A question such as "Can I buy a 1200 SAR iPad?" gets an affordability answer instead
  (**Can I Afford This?** in Tools does the same): **Comfortably Affordable**, **Caution
  (Reallocation Needed)** or **Unaffordable / Exceeds Budget**.
- A question about the app gets an answer with buttons to the right screen (for example **Launch
  Setup Tutor** or **Manage Envelopes**).
- The chat is for money only. After 3 off-topic messages within an hour it is locked for 15
  minutes, with a warning before that.

### Duplicate warnings

- The chat and the receipt scanner look for the same expense already recorded: the same ZATCA QR
  code at any time, or the same amount (within 0.05 SAR) at a similar merchant within the last 24
  hours. Only expenses the person can read are compared.
- The chat offers **Enrich Existing Transaction** (add the items to the one already there), **Log
  as New** or **Discard**. The scanner's duplicate card also offers to enrich the existing
  expense, besides **Log as Separate** or **Discard Duplicate**.
- Manual Log has no duplicate check.

### Offline

- Without a connection, a manual expense, a chat message or a receipt is kept in a queue on the
  phone (SQLite). A receipt with a ZATCA QR code is filled in from the code; photos alone wait as
  an **Offline Draft** and are read when the phone is back online. Nothing is guessed.
- A queued chat message is saved directly when it is sent, without the confirmation card and
  without the duplicate check.
- The queue is sent when the connection returns, or with **Sync Now** (dashboard banner, or
  Settings → **REPORTS & OFFLINE QUEUE**). An item the server keeps refusing is set aside after 5
  tries.
- Signing out with items still queued warns first; they stay on the phone until that person signs
  in again.

### Editing and deleting

- Tapping an expense opens **Edit Transaction**: merchant, amount, category, date, items, who paid,
  the family choice, and **Convert to BNPL Installment Plan**.
- A member edits or deletes their own expenses; an admin any expense they can read
  ([section 2](#2-households-and-roles)). Others see "Added by another member · only admins can
  change it".
- Swiping an expense away on **Transactions** first asks **Delete Transaction**. After the delete,
  **UNDO** is offered for a short time, only on the person's own expenses (an admin cannot undo the
  delete of another member's expense). The budget and the account balance follow.

---

## 7. Expense kinds

- **Ordinary expense.** Visible to the whole household. Its creator edits it; an admin edits any
  ordinary expense.
- **Roommates.** Shared costs are split equally, and the settlement simplifies the debts between
  several roommates so nobody pays in circles.
- **Family.** Nothing is ever split 50/50 or by percentage between the spouses: Nafaqah (household
  maintenance) is the husband's. When an expense is recorded in a family household, the app asks
  **Who paid, and for whom?** The labels depend on who is recording ({wife} and {husband} are their
  names):

| Kind | The husband sees | The wife sees | Another admin sees | What it means | Effect |
|---|---|---|---|---|---|
| Household expense | **I paid (household expense)** | **{husband} paid** | **Household expense (no debt)** | The husband pays for shared things, or buys something for his wife | An ordinary household expense: no debt |
| Her advance (`wife_reimbursable`) | **{wife} paid for the home — I pay her back** | **I paid for the home — he pays me back** | **{wife} paid for the home — owed to her** | The wife pays for the home, the children or her husband from her own money | Her husband now owes her that amount. Visible to the whole household |
| Her personal purchase (`wife_personal`) | **{wife}'s personal purchase — from her allowance** | **For me personally — from my allowance** | **{wife}'s personal purchase — from her allowance** | The wife buys something for herself | Counted against her personal allowance for the current cycle, never against the category budgets. Private (see [section 16](#16-who-sees-what)) |

- Only the wife, the household's provider or an admin can mark a family expense as her advance or
  her personal purchase.
- A wife expense is paid from one of her own personal accounts, from her wife account, or from no
  account. It can never be paid from a shared pool or from her husband's account.
- **Her allowance** is an amount per salary cycle. Her husband (admin or not) or an admin who is
  not a wife sets it; a wife never does, not for herself and not for a co-wife. The app shows
  allocated, spent and remaining. Overspending shows a negative remainder and is never blocked.
- A wife's voluntary contribution (Tabarru') is only ever an explicit opt-in; it is never assumed.

Details: [rule 02, family mode rules 1 to 4](../.agents/rules/02-saudi-fintech-and-islamic-compliance.md#3-islamic-family-finance-nafaqah-vs-roommate-living-groups).

---

## 8. Paying her back: repayments, requests and reversals

**What is owed** = her advances − repayments + reversals. Pending requests never count.

Example used below: she pays 400 SAR for groceries from her wife account and records it as
"I paid for the home — he pays me back". Her husband now owes her 400.

### Direct repayment

1. He taps **Reimburse Wife** on the family card, enters 100, picks the account it leaves (his own personal account, or a
   shared pool if he is an admin) and the wife account it goes into.
2. His account goes down by 100 and her wife account goes up by 100, as one transfer. Each
   account's history shows "Repayment to wife". What is owed drops to 300.
3. No budget and no expense changes: her expense already counted when she recorded it.

### Her request ("I received X")

1. She taps **Mark as received**, enters 100 and chooses which of her wife accounts it went into. The request is
   **pending**: nothing moves and what is owed does not change.
2. She can cancel it while it is pending.
3. Her husband **approves** it (he picks the account it leaves; the money moves exactly as in a
   direct repayment, into the wife account she chose unless he switches to another of hers), or
   **declines** it with an optional reason (at most 200 characters).
4. Her pending requests together can never exceed what is owed. When something lowers what is
   owed (a direct repayment, an approval, a smaller advance), pending requests that no longer fit
   close as **Already repaid**, most recent first, and nothing moves.

### Corrections are reversals

- Nothing is deleted, edited or voided. To correct a repayment he **reverses** it: the amount
  leaves the wife account it was paid into and returns to the account it came from, and it is owed
  to her again. The repayment stays in the history, marked **Reversed**. He then records the right
  amount.
- A repayment can be reversed once. A reversal is refused when her wife account no longer holds
  the amount (she has spent it), or when either account is archived or deleted.

### Rules that always apply

- Every repayment comes out of a real account in the app. A cash repayment comes out of his Cash
  account. Insufficient funds are refused.
- If she has no wife account that is not archived, the repayment is refused and the app offers
  him **Create her wife account**.
- If the connection drops before an answer, the sheet keeps the same request key, so trying again
  can never pay twice.
- Old app versions that send a repayment without an account get "please update the app"
  (HTTP 426), and nothing is recorded.
- **Who acts:** only her husband repays, approves, declines and reverses (an admin who is not a
  wife once he is gone). She only makes and cancels her own requests. No wife ever acts for a
  co-wife, even as an admin.
- A reversal is done by her ledger's current manager, from the account the money left: his own
  personal account as its owner, or a pool as an admin. A replaced husband or a demoted admin can
  no longer reverse, even a repayment from his own account (accepted by the owner).

Details: [rule 02, "How a repayment moves money"](../.agents/rules/02-saudi-fintech-and-islamic-compliance.md#3-islamic-family-finance-nafaqah-vs-roommate-living-groups).

---

## 9. Roommate settlements

- Shared costs are split equally between the roommates.
- The settlement engine nets everyone's balances and simplifies the debts so the fewest transfers
  settle everything. A settle message can be copied to share, for example on WhatsApp.
- Roommates can keep a shared pool for monthly dues and pay shared bills from it.
- Each expense says who paid and whether it is **Split Equally (All)** (divided equally between all
  roommates, to the halala) or **Personal (100%)** (the payer's own, no debt).
- The balances cover the expenses since the start of the current salary cycle.
- The roommates card (on the dashboard, and in Settings → **PARTNER SETTLEMENT**) shows "Your
  balance", who owes whom, and **Fewest transfers** ("Combines debts so fewer payments are
  needed").
- **Settle** records a settlement payment: the amount (with **Full** and **Half** shortcuts) and the
  method (**STC Pay**, **Bank** or **Cash**). It records that the money was paid; it moves no
  account balance in the app. The payer, the recipient or an admin records it.
- **Share via WhatsApp** copies a ready message to paste; the app does not open WhatsApp itself.
- This settlement exists only in a roommates household. A family has no split
  ([section 7](#7-expense-kinds)).

---

## 10. Bills, installments and commitments

The dashboard's **Commitments** heading holds two cards: recurring bills and installments.

### Recurring bills

- **Recurring Bills & Reserves** lists the bills of the current cycle with their due day and a
  status (paid, upcoming or **Overdue**), and the amount **Reserved** for those not paid yet.
- A bill comes from one of three places:
  - a budgeted sub-category the household marked as recurring (**Configure** → **Manage
    Recurring Bills**: switch it on and pick its due day, 1 to 31);
  - a known provider in the expense history (for example STC, Mobily, Zain, Saudi Electricity,
    National Water, Netflix, Shahid, rent);
  - the **recurring bill detector**: the same merchant paid about a month apart (25 to 35 days)
    with amounts within 25% of their average.
- **Pay** on a bill, then **Confirm Paid**, records an expense of the bill's usual amount in its
  category, paid by the person, with no paying account (no balance changes).
- Any member can mark sub-categories as recurring; the budgets themselves stay admin-only.

### Installment plans (BNPL)

- **Installments & BNPL** lists the active plans: provider, merchant, "Installment N of M paid ·
  next *date*", and what is due before payday.
- **Add Installment Plan** opens **New Installment Plan**: a **New Purchase** or an **Ongoing Plan
  (In Progress)**, with merchant, total, provider (**Tamara**, **Tabby** or **Bank / Other**), the
  number of installments (1, 2, 3, 4, 6, 12 or a custom number up to 60) and the schedule
  (**Monthly** or **Every 2 weeks**; Tabby or Tamara in 4 start as every 2 weeks), and whether the
  first was paid at checkout.
- **Convert to BNPL Installment Plan** in **Edit Transaction** turns an expense already recorded
  into a plan.
- **Record Payment** opens **Record Installment Payment** with the amount filled in. Saving it
  records the expense (from the chosen account) and counts one installment as paid.
- **Edit Installment Plan** (where the providers are **Tamara**, **Tabby**, **Bank** and **Other**)
  and delete are on each plan. Who can read the plan of a wife's personal
  purchase is in [section 16](#16-who-sees-what).

### Commitments and operating cash

- Unpaid bills of this cycle and installments due by the end of this cycle are the **pending
  commitments**. They are taken off the money to spend: operating cash, the hero card's daily
  figure and the accounts card ([section 3](#3-accounts), [section 11](#11-dashboard-reports-and-exports)).

### Savings

- There are no savings goals in the app today.
- A **Savings Vault** account holds savings; it is kept out of operating cash
  ([section 3](#3-accounts)). Money reaches it by a transfer or as income.
- The household's **savings reserve** is a figure on the server, raised by the rollover rule
  ([section 4](#4-budgets-and-salary-cycles)). The app does not show it today.

---

## 11. Dashboard, reports and exports

### The dashboard, top to bottom

| Part | What it shows |
|---|---|
| Cycle bar | The cycle on show; arrows go to earlier cycles |
| Banners | Items waiting to sync (**Sync Now**), a household marked for deletion ([section 18](#18-account-deletion)), the payday check-in ([section 4](#4-budgets-and-salary-cycles)) |
| Setup card | While the cycle has no budgets: the setup checklist, or "Budgets not set up yet" for a member ([section 1](#1-getting-started)) |
| Hero card | "Left until payday", one daily amount and one verdict (below) |
| Over-budget alerts | The categories spent over their budget |
| **Quick Access** | Accounts, **Record Income**, **Income & Cash Flow Report**, Wife Allowance, Bills, and Smart Basket (which opens Tools, not the optimizer itself); **Show all** opens Tools |
| **Accounts & Balances** | Shown once there are 2 or more accounts: balances and what is left after commitments ([section 3](#3-accounts)) |
| Household balances | The family card (what is owed to the wife, her allowance) or the roommates card ([section 9](#9-roommate-settlements)) |
| **Commitments** | Recurring bills and installments ([section 10](#10-bills-installments-and-commitments)) |
| **Category budgets** | One card per category, most at risk first, with spent / budget, a percentage and any carryover; tapping one shows its sub-categories |

### The hero card

- **The figure.** When the household has accounts to count, "Left until payday" is the operating
  balance the person can see. Without accounts it is the income minus what was spent; without an
  income either, it is "Left in your budgets until payday" (budgets minus spent).
- **The daily amount**: "X a day until payday" = what is left, minus pending commitments, divided by
  the days left, today included.
- **The verdict**: "On track for payday", "At this pace the money runs out around *date*" (when the
  spending so far would use up the money before payday), or "Over by X this cycle".
- It also shows **Allocated**, **Spent**, the percentage spent, unbudgeted spending, and short lines
  for money owed (for example "Your husband owes you X").
- A past cycle shows "Left at the end of this cycle", with no daily amount.

### Reports

- **Income & Cash Flow Report** (Tools, Quick Access, or **View Full Report** on Accounts &
  Balances), per cycle: **Total Inflow**, **Total Outflow**, **Net Cash Flow**, **Savings Rate**,
  **Spending by Category** and the **Income Records Ledger**.
- **Price Tracker** (Tools): the price history of items, built from the line items of scanned
  receipts and chat entries: latest and lowest price, how often bought, a trend and a store
  comparison.
- **Smart Basket Optimizer** (Tools): compare a shopping list across stores. Where the household
  has no recorded price for an item, the store prices are placeholder figures in the code, not real
  prices (an owner-approved known gap, [PROJECT_DETAILS §4.1](PROJECT_DETAILS.md#41-known-gaps--owner-approved-exceptions)).

### CSV export

- Settings → **REPORTS & OFFLINE QUEUE** → **Export Monthly Report** → **Export CSV**: the current
  cycle's expenses, without settlements and without a wife's personal purchases.
- **Transactions** → ⋮ → **Export CSV**: **All Records**, every row of the household the person can
  read, with no filter: settlement rows and the wife's personal purchases they can read are
  included, unlike the Settings export.
- Both show a preview; **Copy CSV** copies it to paste into Excel or Google Sheets. No file is saved.
  The columns are Date, Merchant, Category, Amount (SAR), VAT (SAR), Spent By, Source and Items
  Breakdown.

### Monthly PDF statement

- **Transactions** → ⋮ → **Export PDF** shows a **Monthly Statement (PDF)** dialog; **Download &
  Share** downloads the current cycle's statement and opens the phone's share sheet, to open, save
  or send it.
- It has the cycle's totals and budgets, an estimated 15% VAT, spending by who spent it, spending by
  category and the latest 15 expenses. It lists only what the person can read. It is in English
  only.

---

## 12. Reminders and notifications

### Reminders on the phone

- The app schedules **local reminders** on the phone, at 09:00 Riyadh time. Nothing is sent from a
  server.

| Reminder | When |
|---|---|
| **Payday check-in** ("It's payday") | On payday |
| **3 days before payday** | Three days before the next payday |
| **Recurring bills** ("*Merchant* is due today") | On each monthly bill's expected day, at most the next two dates per bill |
| **Installments** ("*Provider* installment due today") | On each installment's due date |

- All four are on by default. Settings → **REMINDERS** switches each one off or on, on this phone.
- They follow the active household's payday, bills and plans, and are scheduled for the next 62
  days (at most 48 at a time). Signing out cancels them.
- The phone must allow the app's notifications (Settings → **HARDWARE & APP PERMISSIONS** →
  **Notifications**).

### What does not exist

- There are **no push notifications** from a server (no Firebase messaging), and no in-app
  notification inbox. The bell icon on the dashboard opens **Help & Support**.
- The **Notifications** permission card's text speaks of budget threshold alerts and sync status;
  the app sends neither. Over-budget categories and items waiting to sync are shown on the
  dashboard instead.

### Banners and emails

- In the app: the payday check-in banner, the offline queue banner and the household deletion
  banner ([section 18](#18-account-deletion)).
- Emails: the sign-in emails (confirmation, password reset), and the account deletion emails,
  which stay off until the owner switches them on ([section 18](#18-account-deletion)). A message
  sent to the developer from the app is answered by email ([section 14](#14-help-support-and-the-in-app-guide)).

---

## 13. Settings

Settings is the last tab of the bottom bar. Its sections fold open and closed:

| Section | What is in it |
|---|---|
| **HOUSEHOLD & MEMBERSHIP** | The household card: name, join code (admins), **Copy Code**, **Share invite**, **Invite with Role**, members and dependents, **Add Member / Dependent**, switch, create, join and **Leave Household**; **Members & Admins** (roles, the household provider, financial roles, the household type); **Household Setup Checklist** ([section 2](#2-households-and-roles)) |
| **SALARY & ACCOUNTS** | **Salary & Payday Cycle**: presets for the 27th (Govt / Standard), the 1st (Calendar Month) and the 25th, or any day 1 to 31, saved with **Save Payday** (admins only); **Accounts & Balances** → **Manage** |
| **PARTNER SETTLEMENT** | When the household has more than one member: the family card or the roommates card |
| **APPEARANCE & LANGUAGE** | **System Default**, **Light Mode** or **Dark Mode**; **English**, **العربية** or **اردو** |
| **REMINDERS** | The four reminder switches ([section 12](#12-reminders-and-notifications)) |
| **HARDWARE & APP PERMISSIONS** | Camera, microphone and notifications, each with **Grant Access** while not granted. The camera has **Test Camera** (it opens the QR scanner); the others show a gear icon (**Open App Settings**) once granted |
| **REPORTS & OFFLINE QUEUE** | **Export Monthly Report** (CSV) and the offline queue with **Sync Now** |
| **HELP & SUPPORT** | **App Guide & Tutorial**, **Help Center & AI Support**, **Contact Developer** (copies the developer's email) |
| **ACCOUNT** | **Sign Out** and **Delete account** ([section 18](#18-account-deletion)) |

- Theme and language are kept on the phone. On first start the app follows the phone's language
  when it is Arabic or Urdu, and is in English otherwise. Arabic and Urdu read right to left.
- Not in Settings today: the rollover rule ([section 4](#4-budgets-and-salary-cycles)) and the
  household's monthly income ([section 5](#5-income)).

---

## 14. Help, support and the in-app guide

### The Interactive Setup Tutor

- A step-by-step guide that opens by itself once per phone, the first time the dashboard has loaded
  the household (it is remembered on that phone, not on the account; the flag is
  `has_seen_setup_tutor_v3`, so people who saw the earlier tutor see this one once).
- It shows the steps for the person's role, from the household's member list (display only; the
  server still checks every action):

| Step | An admin | Anyone else |
|---|---|---|
| **Payday & Income** | **Set Payday** (the payday editor) and **Record Income** | "Your household's admin sets this up" for the payday; **Record Income** |
| **Operating Accounts vs. Savings Vaults** | **Set Up Bank & Savings** (Accounts & Balances) | The same |
| **Envelope Budgeting & Joining Mid-Cycle** | **Configure Envelopes** (Budgets); for a household joining mid-cycle it names **Log Prior Spending**, which appears when the Budgets tab warns that the allocations exceed the cycle's funding | The admin sets the budgets; no button |
| **Living Model: Family & Roommates** | **Members & Admins** | The admin sets it up; no button |
| One step for the role | A wife: "Who paid, and for whom?", her allowance, that a repayment he makes with **Reimburse Wife** needs nothing from her, and **Mark as received** only for money he paid her outside the app. The husband: **Add wife account** on Accounts & Balances (shown before his wife has joined too), **Reimburse Wife**, approve or decline, **Reverse**; its button opens Accounts & Balances. Roommates: **Split Equally (All)** / **Personal (100%)**, **Fewest transfers** and **Settle** | The same |
| **Three Ways to Record** | **Add Expense**: **Voice & AI Assistant**, **Scan Receipt** or **Manual Log**; its button closes the tutor | The same |

- A button closes the tutor first, then opens its screen. Without the household (or when its member
  list cannot be loaded, the cached admin flag decides), the buttons that need it are not offered.
- It can be opened again from Settings → **App Guide & Tutorial**, from **Help & Support**
  (**Replay**), and from the AI chat (**Launch Setup Tutor**).

### Help & Support

- Opened from Settings → **Help Center & AI Support**, or from the bell icon on the dashboard.
- **FAQs & Guide**: searchable questions in seven groups (salary cycle, wife expenses and
  allowance, receipts and ZATCA, recurring bills, installments, household and roommates, privacy and
  your account), and the tutor's **Replay** card.
- **AI Assistant**: a support chat that answers questions about the app. When it sees a technical
  problem it offers **Escalate to Developer**.
- **Message the Developer**: a message sent from the signed-in account; the developer answers by
  email. **Copy Full Diagnostic Info** copies the details to email by hand instead. Several
  messages in a short time are refused for a while.

### The household setup checklist

- See [section 1](#1-getting-started). It is a separate thing from the tutor: it tracks this
  household's real setup (payday, income, budgets, invite, provider).

---

## 15. The website

The website is served by the API at its own address. It has three parts.

### The landing page (`/`)

- In Arabic by default; `?lang=en` opens it in English. It has no Urdu: `?lang=ur` shows the English
  page with a note in Urdu that links to the Urdu account deletion page.
- Sections: an illustrative payday card (pick a payday to see the real cycle dates; the amounts are
  samples), "What the app does for you", "How wife expenses work", "Privacy: exactly what happens to
  your data", "Questions", and the early-access form "Try the app before launch". The form stores the
  details and emails the developer (with no mail provider set up, it only stores them); it does
  not create an account.

### The signed-in portal

- **Sign In** or **Create Account** on the landing page (email and password, the same account as in
  the app) opens a portal with **Dashboard**, **Transactions**, **Budgets & Allocations** and **New
  Transaction**.
- **It is an early version and is not a reliable view of the household's money today.** It reads
  some database columns that do not exist, and it assumes a payday on the 27th:
  - **Transactions** shows the real amounts and dates, but every row is labelled "Expense".
  - **Dashboard** shows the income from income records or the monthly income figure (15,000 SAR
    when both are empty), 0 spent, an empty recent list, and a bills card with fixed sample bills.
  - **Budgets & Allocations** shows sample allocations next to the real spending.
  - **New Transaction** fails.
- Use the app for everything except account deletion.

### Account deletion (`/delete-account`)

- In Arabic, English and Urdu, for signed-in and signed-out visitors. A person signs in there and
  requests or cancels the deletion with the same server functions as the app. Someone who cannot
  sign in can send a request form. It stores the request and emails the developer (or only stores
  it when no mail provider is set up); if the request cannot be stored, the page says so and asks
  to try again. It deletes nothing. The full rules are in
  [section 18](#18-account-deletion).

---

## 16. Who sees what

H = her husband. If he is gone, an admin who is not a wife gets H's view of her ledger and her
wife account.

| Item | She | H | Co-wife (even an admin) | Admin who is not a wife | Member |
|---|---|---|---|---|---|
| Her ledger: what is owed, repayments, reversals, her requests and their outcomes, decline reasons | Yes | Yes | No | No | No |
| Her wife account (row, balance, history) | Yes | Yes | No, and the app never shows or tells her it exists | No, and the app never tells them it exists | No, and the app never tells them it exists |
| Repayment lines, also in a pool's history | Yes | Yes | No | No | No: only the pool's balance moves |
| Her allowance | Yes | Yes | No | Yes | No |
| Her personal purchases, their receipts, their installment plans, the transfers of her personal accounts | Yes | Yes | No | Yes | No |
| Her advances (`wife_reimbursable`) | Yes | Yes | Yes | Yes | Yes |
| Ordinary expenses and shared pools | Yes | Yes | Yes | Yes | Yes |

Notes:

- A careful probe can still infer that a wife account exists; the owner accepted this
  ([section 19](#19-accepted-limits-and-follow-ups)).
- The owner of a personal account always reads the transfers of his own account. A member who
  sends money from his account to her personal account, or receives from it, keeps that row; nobody
  else gains it.
- A repayment line is also read by the owner of the personal account the money left or returned to.
- An installment plan of her personal purchase stays hers after the purchase is deleted.
- **Whoever cannot see a row cannot change it.** Asking about it, editing it or deleting it gets the
  same answer as a row that does not exist.

Details: [rule 02, family mode rules 2 and 3](../.agents/rules/02-saudi-fintech-and-islamic-compliance.md#3-islamic-family-finance-nafaqah-vs-roommate-living-groups)
and [rule 04, section 4](../.agents/rules/04-security-and-privacy.md#4-household-roles--permissions-owner-decision-on-db-16--db-18).

---

## 17. Privacy basics

- **No SMS.** The app asks for no SMS permission and never reads text messages. Money comes in only
  by what the person does: typing, a receipt photo or QR code, voice, or the chat. The only
  permissions it asks the person for are the camera, the microphone and notifications, plus speech
  recognition on iOS.
- **Keys.** The app and the website hold only the Supabase publishable key. The secret key and the
  AI model keys stay on the server; the app refuses to start with a secret key built in.
- **Row level security.** Every table checks, in the database, which household a row belongs to
  and who may read or change it ([section 16](#16-who-sees-what)). The API uses the secret key and
  re-checks the signed-in person itself.
- **Receipt photos** are in a private storage area, in the household's folder. The app shows them
  through links that work for one hour. The photo of a wife's personal purchase follows that
  purchase's rule (she, her husband and an admin who is not a wife).
- **The AI.** Chat messages and receipt photos are sent to the AI model the owner configures
  (Gemini by default) to be read. Voice is turned into text by the phone's speech recognition.

Details: [rule 04](../.agents/rules/04-security-and-privacy.md).

---

## 18. Account deletion

### Requesting and cancelling

- In the app: Settings → Delete account. On the web: `/delete-account` (Arabic, English and Urdu),
  using the same server functions as the app.
- It needs a sign-in from the last 15 minutes and a typed confirmation word.
- The account is deleted **30 days** after the request. Until then it works as usual. **Cancel**
  works at any time until the deletion starts deleting data. **Signing in cancels nothing.**
- While the request is pending, the person cannot join or create a household, be made admin, take
  over as primary admin or become a Nafaqah provider.

### Households the person runs

- **Primary admin with other members:** chooses, per household, to **hand it over** to another
  member and leave (the handover happens at once and stays if they cancel later), or to **delete the
  household**. A household marked for deletion takes no new members or invites, and every member
  sees a banner with the date and a reminder to export what they want to keep. Members keep their
  logins but no longer belong to it.
- **Co-admin or member:** simply leaves; the household stays.
- **Only member:** the household and everything in it are deleted.

### What is deleted and what stays

- Their profile, personal accounts and those accounts' entries are deleted.
- Expenses they recorded in a household that stays are kept for the other members and shown as
  **Deleted member**. Their notes on them are removed and the receipt images deleted.
- What they paid stops counting in the settlements of the people who stay, and roommates' equal
  shares for the current cycle are worked out again. Account balances and budget spending do not
  change.

### When a wife deletes her account

- When she schedules the deletion, her husband is shown what he still owes her.
- Her allowance and reimbursement records are deleted. If something is still owed, the household
  keeps one anonymous line: what is owed to a former member, with no name.
- That line is closed by **Record payment** (from an account, like a repayment, but nothing is
  credited because she is gone) or by **Waived by her** (her release of the debt, ibra'), which
  moves no money. A payment can be reversed, which reopens the line, but not after a waiver. Only
  her husband sees and closes it (an admin who is not a wife once he is gone).
- While that line is open, the household cannot switch from family to roommates.
- Her personal purchases are deleted. Her wife accounts are archived and assigned to nobody; they
  stay her husband's with their balance and history (the money she spent stays spent).
- The installment plans of her personal purchases stay hidden: only her husband and the admins who
  are not wives read them.

### When a husband deletes his account

- What he owed his wife stays with the household; an admin who is not a wife now manages her
  ledger and settles it.
- His wife accounts pass, with balance and history, to the household's primary admin, or to the
  wife herself when that admin is another wife.

### Switches the owner controls

The purge worker (`ai_service/account_deletion_worker.py`) deletes nothing until
`ACCOUNT_DELETION_PURGE_ENABLED=1` is set on the Cron service. Deletion emails to account holders
and members need both `ACCOUNT_DELETION_EMAILS_ENABLED=1` and `ACCOUNT_DELETION_PURGE_ENABLED=1`.
Each switch needs the owner's explicit approval. The public request form on the website only stores
the request and emails the developer; it never deletes anything.

Details: [rule 04, section 6](../.agents/rules/04-security-and-privacy.md#6-account-deletion) and the
[purge runbook](runbooks/account-deletion-purge.md).

---

## 19. Accepted limits and follow-ups

### Accepted by the owner

- A purge and a simultaneous edit can, rarely, deadlock. PostgreSQL aborts one of them, and it is
  retried.
- Retry keys for repayments, requests and approvals live only for the app session. If the app is
  closed before a definite answer, the next attempt uses a new key.
- A careful probe can infer that a wife account exists.
- Members see a pool's balance move because of lines hidden from them (repayments).
- A replaced husband or a demoted admin cannot reverse his old repayments.

### Follow-ups

- **Household ownership model** (owner decision, planned after this release): a person owns at most
  one family household and one roommates household, joins any number as a plain member, and keeps
  money accounts only in households they own.
- The transaction list and the Income & Cash Flow Report read at most 1,000 rows, the server's cap
  for one read. The CSV exports read every row page by page.
- Account activity should show an account's full history.
- The receipt scanner and the chat should offer the wife account as the paying account.
- When a wife leaves a household without deleting her account, she is no longer a wife there, so
  her personal purchases become readable like household expenses.
- An admin's "replace category" renames the category on rows the admin cannot read, so budget
  totals can shift.

### Found while writing this guide (2026-11-07)

- **The monthly PDF statement** labels its "Shared Household (Both)" row "50 / 50 Shared Split" in
  every household, family ones included. Family mode has no split between the spouses (rule 02), so
  this label is wrong for a family. The statement is also in English only.
- **The rollover rule** has no screen, and "Rollover to Same Categories" shows the carryover on the
  category card without adding it to the category's budget. Rule 02 says the leftover increases
  each category. The savings reserve figure is not shown anywhere in the app.
- **The household's monthly income figure** has no screen.
- **The web portal** reads columns that do not exist (`households.type` and `currency`,
  `budgets.amount`, `transactions.description`): it assumes a payday on the 27th, labels every
  transaction "Expense", shows 0 spent and fixed sample bills on its dashboard and sample
  allocations on its budgets, and **New Transaction** fails ([section 15](#15-the-website)). Its
  text is also partly not in the translation file.
- **The stored receipt photo** (app bug): the scanner uploads only the first photo before saving,
  so the server's joined image of all pages is used only when that upload fails. A long receipt
  keeps page 1 only, and a save that fails leaves an unlinked photo in storage.
- **The Notifications permission card** promises budget threshold alerts and sync status
  notifications, which the app does not send.
- **Total net worth** adds EUR and AED balances to SAR without converting them.
