---
description: Trigger Claude Opus 5.5 architectural audit on the current branch via Anthropic API, then copy results or present verdict to the user.
---

# Workflow: Submit Branch for Opus Audit

1. **Ensure Branch Safety**
   - Verify you are NOT on `main` (`git branch --show-current`). If on `main`, create and switch to a feature/fix branch (`git checkout -b feat/<short-name>` or `fix/<short-name>`) before committing.

2. **Run Mandatory Verification Suite**
   - Run `cd flutter_app && flutter analyze`
   - Run `cd flutter_app && flutter test`
   - Run `cd ai_service && .venv\Scripts\pytest -v`
   - Do not proceed until all checks pass with zero warnings or failures.

3. **Stage and Commit Changes**
   - Stage and commit all changes using Conventional Commits.

4. **Trigger Claude Opus 5.5 Review via Anthropic API**
   - Run: `python scripts/claude_auditor.py --mode review --verbose`
   - The script reads changed files (full content, not git diff), sends them to Claude Opus for architectural review against `.agents/rules/`, and writes the verdict to `docs/review/AUDIT_FEEDBACK.md`.
   - For batch processing (50% off, user must explicitly request): `python scripts/claude_auditor.py --mode review --batch --verbose`

5. **Handle the Verdict**
   - **If APPROVED (exit code 0):** Inform the user that Claude Opus has approved the changes and all project rules are satisfied. Wait for the user's explicit sign-off before pushing or merging to main.
   - **If REVISE (exit code 1):** Read `docs/review/AUDIT_FEEDBACK.md`, fix every CRITICAL and HIGH finding, re-run verification (Step 2), re-commit, and re-trigger the audit (Step 4). Repeat until APPROVED.

6. **Push Branch to GitHub (After User Approval)**
   - Push the branch to remote: `git push -u origin HEAD`
   - If `gh` CLI is available, create or update the PR: `gh pr create --fill`
   - Otherwise, print the PR URL: `https://github.com/Masteader/budget-tracker/pull/new/<branch-name>`
