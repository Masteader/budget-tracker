# PR & External Opus Audit Pipeline Rules

## 1. Branch Isolation & Main Protection
- NEVER commit or merge directly to `main` locally.
- All features, bugfixes, and audit rounds MUST be developed on a dedicated branch (`feat/<name>`, `fix/<name>`, or `audit/<name>`).
- Merging into `main` is strictly forbidden until:
  1. Claude Opus 5.5 issues `AUDIT VERDICT: APPROVED` in `docs/review/AUDIT_FEEDBACK.md`.
  2. The user gives explicit sign-off ("Approve", "Proceed", "Push it").

## 2. Mandatory Pre-PR Verification Gate
Before triggering the Opus audit or pushing any branch, you MUST run and pass:
1. `cd flutter_app && flutter analyze` (Zero warnings/errors)
2. `cd flutter_app && flutter test` (All tests passing)
3. `cd ai_service && .venv\Scripts\pytest -v` (All backend tests passing)

## 3. Automated Opus Audit Pipeline

### Planning Phase
- When the user provides a task, generate an implementation plan via Claude Opus:
  ```powershell
  python scripts/claude_auditor.py --mode plan --task "<task description>" --verbose
  ```
- Read and follow the plan in `docs/review/OPUS_PLAN.md`.

### Review Phase
- After implementation and verification (Step 2), trigger the audit:
  ```powershell
  python scripts/claude_auditor.py --mode review --verbose
  ```
- The script sends **full file contents** of changed files (NOT git diff) to Claude Opus 5.5 via the Anthropic API with prompt caching.
- Opus writes findings to `docs/review/AUDIT_FEEDBACK.md`.

### Resolution Phase
- If `AUDIT VERDICT: REVISE`: fix all CRITICAL/HIGH findings, re-verify (Step 2), and re-audit.
- If `AUDIT VERDICT: APPROVED`: present the verdict to the user and wait for sign-off.

### Batch Processing
- The user can request batch processing (50% token discount, 15-45 min turnaround) by saying "use batch" in the chat.
- Add `--batch` flag: `python scripts/claude_auditor.py --mode review --batch --verbose`

## 4. Initial Full-Project Audit ("First Landing")
- On first integration or when the user requests a full review:
  ```powershell
  python scripts/claude_auditor.py --mode landing --batch --verbose
  ```
- Results written to `docs/review/MASTER_CODEBASE_AUDIT.md`.

## 5. Security Constraints
- `ANTHROPIC_API_KEY` must be set as a User environment variable or in `.env.audit` (which is gitignored).
- NEVER commit, log, or expose the API key in code, artifacts, or terminal output.
- The audit script sends file contents to the Anthropic API -- never send `.env` files, secrets, or service-role keys.

## 6. Strict Budget Ceiling ($10.00 Max Spend)
- A hard stop ceiling of **$10.00 USD** is strictly enforced by `scripts/claude_auditor.py` and tracked in `docs/review/audit_spend.json`.
- Before executing ANY call to Anthropic API, the runner verifies cumulative spend. If cumulative spend reaches or exceeds $10.00, it **immediately aborts** with exit code 3 (`CRITICAL HARD STOP: API BUDGET CEILING REACHED`).
- View current spend anytime without spending tokens: `python scripts/claude_auditor.py --spend`.
- Warning alert triggers automatically at 90% usage ($9.00).
- Never attempt to bypass or suppress the budget guardrail.
