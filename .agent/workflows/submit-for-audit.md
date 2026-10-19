---
description: Package the implementation plan, verification results, and unified git diff against main, push the branch to GitHub, and copy the complete audit bundle to clipboard for External Argon Audit.
---

# Workflow: Submit Branch & Diff for External Audit

1. **Ensure Branch Safety**
   - Verify you are NOT on `main` (`git branch --show-current`). If on `main`, create and switch to a feature/fix branch (`git checkout -b feat/<short-name>` or `fix/<short-name>`) before committing.

2. **Run Mandatory Verification Suite**
   - Run `cd flutter_app && flutter analyze`
   - Run `cd flutter_app && flutter test`
   - Run `cd ai_service && .venv\Scripts\pytest -v`
   - Do not proceed until all checks pass with zero warnings or failures.

3. **Stage, Commit, and Push Branch to GitHub**
   - Stage and commit all changes using Conventional Commits.
   - Push the branch to remote: `git push -u origin HEAD`
   - Check if `gh` is available (`where.exe gh`). If installed and authenticated, create or update the PR using `gh pr create --fill` (if not already open). If `gh` is not installed, print the direct GitHub PR URL: `https://github.com/Masteader/budget-tracker/pull/new/<branch-name>`.

4. **Generate `docs/review/PR_AUDIT_BUNDLE.md`**
   - Create or overwrite `docs/review/PR_AUDIT_BUNDLE.md` (ensure it is either git-ignored or excluded from the code diff) with this exact structure:
     - **Header:** Branch name, base branch (`main`), head commit SHA, and PR URL (or creation URL).
     - **1. Implementation Plan & Intent:**
       - **Objective:** What problem/feature this PR solves.
       - **Architectural Approach:** How it was designed and why.
       - **Files Modified & Summary of Changes:** Bullet list of every touched file and what changed.
       - **Rule 01–05 Compliance Check:** Brief note confirming Saudi 27th cycle/Nafaqah, RTL/trilingual l10n, RLS security, and TDD coverage.
     - **2. Verification Output:** Summary of `flutter analyze`, `flutter test`, and `pytest` results.
     - **3. Unified Diff (`main...HEAD`):** Append the complete raw output of `git diff main...HEAD` inside a ```` ```diff ```` block.

5. **Copy Bundle to Clipboard & Notify User**
   - Run in PowerShell: `Get-Content -Path "docs/review/PR_AUDIT_BUNDLE.md" -Raw | Set-Clipboard`
   - Inform the user that the complete Plan + Diff Audit Bundle is now copied to their clipboard and ready to paste into the External Auditor chat (or open as a PR on GitHub).
