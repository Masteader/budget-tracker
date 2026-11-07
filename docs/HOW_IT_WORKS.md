# How the App Works

A plain guide for the owner and for new developers to how Qawam Money (قوام المال) behaves today:
who the people are, how money moves, who sees what, and what happens when someone deletes their
account. It describes behaviour, not code. Where you need the exact rule, the database objects or
the review history, follow the links to the project rules:

- [Rule 02, Saudi fintech and Islamic compliance](../.agents/rules/02-saudi-fintech-and-islamic-compliance.md):
  payday cycles, family mode rules 1 to 4, the wife ledger and the wife account.
- [Rule 04, security and privacy](../.agents/rules/04-security-and-privacy.md): roles, row level
  security, who reads what, account deletion.

The database enforces every rule below. The API re-checks them for the signed-in user, and the app
only hides what the server would refuse anyway.

Last checked against the code: 2026-11-07 (branch `release/2026-11-07`).

---

## 1. Households and roles

### Households

- A **household** is the space people share. It is created as one of two types:
  - **Family**: a husband, one or more wives, and other family members.
  - **Roommates**: people sharing a flat, with equal splits and settle-ups.
- An admin can switch the type later. A family cannot become a roommates household while it has a
  wife member or any family ledger records (her expenses, allowances, repayments, or an open
  record of what a former wife is owed).
- People **join by invite code**. Only admins see the codes. Codes are single use and expire, and
  repeated wrong codes lock the person out for 15 minutes. An existing member cannot claim an
  invite of their own household.
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
  [section 6](#6-who-sees-what)) are out of their reach too.

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

---

## 2. Accounts

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

---

## 3. Expense kinds

- **Ordinary expense.** Visible to the whole household. Its creator edits it; an admin edits any
  ordinary expense.
- **Roommates.** Shared costs are split equally, and the settlement simplifies the debts between
  several roommates so nobody pays in circles.
- **Family.** Nothing is ever split 50/50 or by percentage between the spouses: Nafaqah (household
  maintenance) is the husband's. When an expense is recorded in a family household, the app asks
  who paid and for what:

| App choice | What it means | Effect |
|---|---|---|
| **Husband paid (household expense)** | The husband pays for shared things, or buys something for his wife | An ordinary household expense: no debt |
| **Shared for family (husband reimburses)** | The wife pays for the home, the children or her husband from her own money (`wife_reimbursable`, her "advance") | Her husband now owes her that amount. Visible to the whole household |
| **Personal (from my/her allowance)** | The wife buys something for herself (`wife_personal`) | Counted against her personal allowance for the current cycle, never against the category budgets. Private (see [section 6](#6-who-sees-what)) |

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

## 4. Paying her back: repayments, requests and reversals

**What is owed** = her advances − repayments + reversals. Pending requests never count.

Example used below: she pays 400 SAR for groceries from her wife account and records it as
"Shared for family (husband reimburses)". Her husband now owes her 400.

### Direct repayment

1. He opens **Repay**, enters 100, picks the account it leaves (his own personal account, or a
   shared pool if he is an admin) and the wife account it goes into.
2. His account goes down by 100 and her wife account goes up by 100, as one transfer. Each
   account's history shows "Repayment to wife". What is owed drops to 300.
3. No budget and no expense changes: her expense already counted when she recorded it.

### Her request ("I received X")

1. She marks "I received 100" and chooses which of her wife accounts it went into. The request is
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

## 5. Roommate settlements

- Shared costs are split equally between the roommates.
- The settlement engine nets everyone's balances and simplifies the debts so the fewest transfers
  settle everything. A settle message can be copied to share, for example on WhatsApp.
- Roommates can keep a shared pool for monthly dues and pay shared bills from it.

---

## 6. Who sees what

H = her husband. If he is gone, an admin who is not a wife gets H's view of her ledger and her
wife account.

| Item | She | H | Co-wife (even an admin) | Admin who is not a wife | Member |
|---|---|---|---|---|---|
| Her ledger: what is owed, repayments, reversals, her requests and their outcomes, decline reasons | Yes | Yes | No | No | No |
| Her wife account (row, balance, history) | Yes | Yes | No, and cannot learn it exists | No | No |
| Repayment lines, also in a pool's history | Yes | Yes | No | No | No: only the pool's balance moves |
| Her allowance | Yes | Yes | No | Yes | No |
| Her personal purchases, their receipts, their installment plans, the transfers of her personal accounts | Yes | Yes | No | Yes | No |
| Her advances ("Shared for family") | Yes | Yes | Yes | Yes | Yes |
| Ordinary expenses and shared pools | Yes | Yes | Yes | Yes | Yes |

Notes:

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

## 7. Account deletion

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

## 8. Accepted limits and follow-ups

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
- The older transaction list, the report and the CSV export stop at 1,000 rows.
- Account activity should show an account's full history.
- The receipt scanner and the chat should offer the wife account as the paying account.
- When a wife leaves a household without deleting her account, she is no longer a wife there, so
  her personal purchases become readable like household expenses.
- An admin's "replace category" renames the category on rows the admin cannot read, so budget
  totals can shift.
