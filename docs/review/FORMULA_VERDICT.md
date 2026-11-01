# Evaluating the Operating Cash Formula

## 1. Verdict: Yes, your formula double-deducts spending

You're right on most points: Account Balance is the source of truth, and excluding savings is correct. The error is subtracting **Spent Amount** from the balance.

Because `trg_update_account_balance_on_transaction` already decrements `accounts.balance` on every insert, edit, or delete, the balance **already reflects** everything you've spent. Subtracting `spent` again counts the same riyals twice.

**Worked example:**

| Step | Value |
|---|---|
| Liquid balance at start of month | 10,000 SAR |
| You spend 3,000 SAR (trigger deducts it) | Balance is now **7,000 SAR** |
| Unpaid bills/installments due this period | 2,000 SAR |
| **Your formula:** 7,000 − 2,000 − 3,000 | **2,000 SAR** ❌ (understated by 3,000) |
| **Correct:** 7,000 − 2,000 | **5,000 SAR** ✅ |

**Rule:** *Spent Amount* belongs to the **budget** (plan vs. actual). It never appears in the **cash** formula. Cash comes only from balances.

---

## 2. Correct Definitions & Formulas

### A. Liquid Balance (Live Spendable Money)
**Definition:** Money you can spend right now, held in accounts that are not set aside.

```
Liquid Balance = Σ accounts.balance
  WHERE type IN ('current', 'wallet', 'cash')   -- e.g., bank current acct, STC Pay, cash
    AND type NOT IN ('savings', 'investment')
    AND type <> 'credit_card'                    -- liability, not cash
    AND is_active = true
```
**Implementation notes:**
- **Use an `include_in_liquid` flag** on `accounts` rather than hard-coding types. Users may want to exclude a specific wallet.
- **Credit cards:** spending on a card reduces the card balance, not liquid cash. The cash impact shows up when the **statement payment is due**, so add it to Commitments.
- **Transfers:** a current → savings transfer correctly lowers Liquid Balance. It must **not** count as "spent" in the budget.

### B. Commitments (Upcoming Unpaid Obligations)
**Definition:** Money already promised but not yet paid, within the current period.

```
Commitments = Σ (amount_due − amount_paid)
  FROM bills + installments (+ credit card statement dues)
  WHERE status IN ('unpaid', 'partial', 'overdue')
    AND due_date <= period_end        -- include overdue
```

### C. Operating Cash (Spendable Headroom)
**Definition:** Net liquid cash available for discretionary allocation after reserving funds for all period commitments. Spent amount is strictly excluded from this formula because transaction triggers already reduce `accounts.balance` at write time.

```
Operating Cash = Liquid Balance − Commitments
```

**Implementation SSOT:**
- Represented in Flutter code by `OperatingCashCalculator.calculate(liquidAccounts, commitments)`.
- Represented in PostgreSQL by zero-based trigger accounting ensuring `accounts.balance` remains the canonical live balance.
```

### C. Operating Cash (Spendable Headroom)
**Definition:** Net liquid cash available for discretionary allocation after reserving funds for all period commitments. Spent amount is strictly excluded from this formula because transaction triggers already reduce `accounts.balance` at write time.

```
Operating Cash = Liquid Balance − Commitments
```

**Implementation SSOT:**
- Represented in Flutter code by `OperatingCashCalculator.calculate(liquidAccounts, commitments)`.
- Represented in PostgreSQL by zero-based trigger accounting ensuring `accounts.balance` remains the canonical live balance.
