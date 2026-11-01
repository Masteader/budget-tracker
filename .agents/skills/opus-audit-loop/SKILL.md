---
name: opus-audit-loop
description: "Use when implementing any task. Orchestrates the full development loop: Claude Opus 5.5 plans → Antigravity implements → Opus reviews → push to main on approval."
---

# Opus Audit Loop — Automated Development Pipeline

This skill governs the automated development loop between **Claude Opus 5.5** (External Architect & Auditor via Anthropic API) and **Antigravity** (Gemini 3.8 Flash High — Local Implementer).

## Architecture

```
User (Product Owner)
  │
  ├─► Claude Opus 5.5 (API)  ── Plans & Reviews
  │     ↕
  └─► Antigravity (Gemini)   ── Implements & Tests
        ↕
      GitHub main branch      ── Protected, merge on approval
```

## The Full Loop (7 Steps)

### Step 1: User Requests a Task
The user describes what they want built. Examples:
- "Add installment payment notifications"
- "Fix the wife reimbursement ledger calculation"
- "Enhance the receipt OCR to handle Arabic text"

### Step 2: Opus Creates the Plan
Run the auditor script to get Opus's implementation plan:

```powershell
python scripts/claude_auditor.py --mode plan --task "USER'S TASK DESCRIPTION HERE" --verbose
```

**For batch processing (50% off, 15-45 min):**
```powershell
python scripts/claude_auditor.py --mode plan --task "USER'S TASK DESCRIPTION HERE" --batch --verbose
```

The plan is written to `docs/review/OPUS_PLAN.md`. Read it and follow it exactly.

### Step 3: Antigravity Implements the Plan
1. Create a feature branch: `git checkout -b feat/<name>`
2. Follow the plan in `docs/review/OPUS_PLAN.md` step by step.
3. Write tests FIRST (TDD — Rule 05).
4. Implement the code changes.
5. Run the full verification gate:
   ```powershell
   cd flutter_app && flutter analyze
   cd flutter_app && flutter test
   cd ai_service && .venv\Scripts\pytest -v
   ```
6. All checks MUST pass before proceeding.

### Step 4: Opus Reviews the Implementation
Trigger the Opus review. Claude Opus outputs **ONLY a straight-forward prompt for Antigravity (Gemini 3.8 Flash High)** with zero human explanations:

```powershell
python scripts/claude_auditor.py --mode review --verbose
```

The verdict is written to `docs/review/AUDIT_FEEDBACK.md`.

### Step 5: Antigravity Executes Fixes or Presents Green Light

**If `AUDIT VERDICT: REVISE` (exit code 1):**
- `docs/review/AUDIT_FEEDBACK.md` contains a direct `PROMPT FOR ANTIGRAVITY (GEMINI 3.8 FLASH HIGH)`.
- Antigravity immediately executes every fix instruction, writes the tests first, re-runs analyzer & test suite.
- Antigravity re-triggers `python scripts/claude_auditor.py --mode review --verbose`.
- Repeat until Opus outputs `AUDIT VERDICT: APPROVED`.

**If `AUDIT VERDICT: APPROVED` (exit code 0):**
- Antigravity stops and presents the green light directly to the user in chat:
  > *"Claude Opus 5.5 has approved all changes. All tests pass. Ready for your sign-off to push to main."*

### Step 6: User Approves
The user reviews the green light and says "Approve" or "Push".

### Step 7: Push to Main
Antigravity merges and pushes to GitHub `main`.

## User Controls

### Choosing Real-Time vs Batch Processing
The user can control this in the chat:
- **"use batch"** or **"batch mode"** → Add `--batch` flag to all auditor calls.
- **"use realtime"** or **"live mode"** → Use standard real-time API (default).
- **"use batch for planning only"** → `--batch` only on `--mode plan`.

### Running the Initial Full-Project Audit ("First Landing")
When the user says "review the whole project" or "full audit":

```powershell
python scripts/claude_auditor.py --mode landing --batch --verbose
```

This runs 4 architectural passes (Database, Backend, Flutter, Compliance) at 50% batch discount. Results in `docs/review/MASTER_CODEBASE_AUDIT.md`.

## Critical Rules

1. **NEVER skip the Opus review.** Every implementation must be audited before merge.
2. **NEVER push to main without user approval.** Opus approval alone is not sufficient.
3. **NEVER ignore CRITICAL findings.** They must be fixed before re-review.
4. **NEVER modify the auditor script** (`scripts/claude_auditor.py`) without user permission.
5. **Always use `--verbose`** so the user can see token costs.
6. **Full file contents, NOT git diff** — the review script sends complete file contents of changed files. This gives Opus better context and avoids diff-syntax token overhead.

## Cost Reference

| Operation | Real-Time Cost | Batch Cost (50% off) |
|-----------|---------------|---------------------|
| Plan creation | ~$0.15 - $0.30 | ~$0.08 - $0.15 |
| PR review (5-10 files) | ~$0.25 - $0.40 | ~$0.12 - $0.20 |
| Full codebase landing (4 passes) | ~$1.70 - $2.50 | ~$0.85 - $1.25 |

## Error Handling

- **Exit code 0:** Success (APPROVED for review, plan generated for plan).
- **Exit code 1:** REVISE required (review found issues).
- **Exit code 2:** Error (missing API key, missing dependencies, API failure).
- **Exit code 3:** Hard Budget Limit Reached (exceeded $10.00 ceiling).

## Strict Budget Ceiling ($10.00 Max Spend)

A hard stop ceiling of **$10.00 USD** is enforced locally in `scripts/claude_auditor.py` and saved to `docs/review/audit_spend.json`:
1. Every API call automatically records fresh input, cached reads, and output tokens.
2. Before making any call, the script checks if `total_spent_usd >= $10.00`. If so, it aborts immediately.
3. Check the budget balance anytime without calling the API:
   ```powershell
   python scripts/claude_auditor.py --spend
   ```
4. Warning alert is printed if cumulative spend crosses 90% ($9.00).

