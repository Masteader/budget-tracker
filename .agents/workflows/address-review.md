---
description: Fetch external audit review comments from the active GitHub PR (via GitHub Public REST API or gh CLI) or local feedback file, implement all requested fixes, verify tests, update the PR, and generate a delta audit bundle.
---

# Workflow: Address External PR Review & Update Diff

1. **Fetch the Latest PR Audit Comments**
   - First, check if the user pasted feedback into `docs/review/AUDIT_FEEDBACK.md` or directly in the prompt.
   - Next, query the public GitHub REST API via PowerShell to retrieve the open PR and its comments for the current branch (`$branch = git branch --show-current`):
     ```powershell
     $prs = Invoke-RestMethod -Uri "https://api.github.com/repos/Masteader/budget-tracker/pulls?state=open"
     $pr = $prs | Where-Object { $_.head.ref -eq $branch } | Select-Object -First 1
     if ($pr) {
       Write-Output "=== PR #$($pr.number): $($pr.title) ==="
       Write-Output "=== ISSUE COMMENTS ==="
       Invoke-RestMethod -Uri "https://api.github.com/repos/Masteader/budget-tracker/issues/$($pr.number)/comments" | ForEach-Object { Write-Output "[$($_.user.login) at $($_.created_at)]:`n$($_.body)`n---" }
       Write-Output "=== REVIEW BODIES ==="
       Invoke-RestMethod -Uri "https://api.github.com/repos/Masteader/budget-tracker/pulls/$($pr.number)/reviews" | ForEach-Object { Write-Output "[$($_.user.login) - $($_.state)]:`n$($_.body)`n---" }
       Write-Output "=== INLINE CODE COMMENTS ==="
       Invoke-RestMethod -Uri "https://api.github.com/repos/Masteader/budget-tracker/pulls/$($pr.number)/comments" | ForEach-Object { Write-Output "[$($_.path):$($_.line)]:`n$($_.body)`n---" }
     }
     ```

2. **Parse Findings & Build an Action Checklist**
   - Extract every `CRITICAL`, `HIGH`, `MEDIUM`, and `LOW` / `NIT` item from the latest review comment.
   - Track each item using `manage_task` before modifying code.

3. **Implement Fixes Following TDD (Rule 05)**
   - For each review item, add or update the corresponding unit/widget/pytest test first.
   - Implement the code fix cleanly without breaking Rules 01–05.

4. **Run Full Verification Gate**
   - Run `cd flutter_app && flutter analyze`
   - Run `cd flutter_app && flutter test`
   - Run `cd ai_service && .venv\Scripts\pytest -v`

5. **Commit, Push to PR Branch, and Generate Re-Audit Bundle**
   - Commit the review fixes: `git commit -m "fix(review): address external audit findings for PR"`
   - Push to the active PR branch: `git push origin HEAD`
   - Update `docs/review/PR_AUDIT_BUNDLE.md` with:
     - **1. Audit Resolution Table:** Every finding ID, how it was fixed, and exact file/line references.
     - **2. Delta Diff (Changes in this Review Round):** `git diff HEAD~1...HEAD`
     - **3. Full Cumulative PR Diff against `main`:** `git diff main...HEAD`
   - Copy `docs/review/PR_AUDIT_BUNDLE.md` to clipboard via `Set-Clipboard` and notify the user.
