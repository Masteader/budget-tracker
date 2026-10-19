# PR & External Argon Audit Pipeline Rules

## 1. Branch Isolation & Main Protection
- NEVER commit or merge directly to `main` locally.
- All features, bugfixes, and audit rounds MUST be developed on a dedicated branch (`feat/<name>`, `fix/<name>`, or `audit/<name>`).
- Merging into `main` is strictly forbidden until the Pull Request receives explicit `APPROVED` status from the External Argon Auditor.

## 2. Mandatory Pre-PR Verification Gate
Before pushing any branch for review or generating an audit bundle, you MUST run and pass:
1. `cd flutter_app && flutter analyze` (Zero warnings/errors)
2. `cd flutter_app && flutter test` (All tests passing)
3. `cd ai_service && .venv\Scripts\pytest -v` (All backend tests passing)

## 3. Two-Stage External Audit Loop
1. **Submission (`submit-for-audit.md`):**
   - Push the branch to `origin`.
   - Generate `docs/review/PR_AUDIT_BUNDLE.md` containing:
     - **Section 1: Implementation Plan & Architectural Intent** (What was requested, why this approach was chosen, which files were modified, and compliance with Rules 01–05).
     - **Section 2: Test & Analyzer Output Summary**.
     - **Section 3: Baseline Context & Unified Diff (`git diff main...HEAD`)**.
   - Copy the bundle to the Windows clipboard (`Get-Content docs/review/PR_AUDIT_BUNDLE.md -Raw | Set-Clipboard`) so the user can paste it directly to the External Auditor.
2. **Addressing Review (`address-review.md`):**
   - Fetch the External Auditor's comments from the GitHub PR via the GitHub REST API (`https://api.github.com/repos/Masteader/budget-tracker/pulls`) or `gh` CLI (or `docs/review/AUDIT_FEEDBACK.md` if provided locally).
   - Address every finding systematically, write/update tests for each fix, push the new commit to the PR branch, and regenerate the updated audit bundle.
