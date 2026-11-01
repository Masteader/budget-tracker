---
description: Address findings from the multi-round review pipeline using TDD subagents, re-verify with tests first, and re-review.
---

# Workflow: Address Review Findings & Re-Verify

1. **Extract Review Findings**
   - Review the findings returned by the review subagents (Round 1, Round 2, or Round 3).
   - Check if any finding is a blocking note, architectural disagreement, or security concern. If an unresolvable dispute or blocker exists, stop immediately and escalate to the user.

2. **Delegate Implementation to Subagent**
   - The Orchestrator delegates the fix to an implementation subagent:
     - **Default:** Claude Opus 5.5, effort high.
     - **Small tasks only:** Claude Sonnet, effort high (strictly restricted to non-auth, non-money, non-schema changes). If it expands, return to Opus.
   - One worktree/branch per task; ensure no concurrent file edits.

3. **Implement Fixes via TDD (Rule 05)**
   - Subagent writes a reproduction test proving the finding.
   - Subagent verifies test failure.
   - Subagent applies minimal, clean fix.
   - Subagent verifies test passes.

4. **Run Mandatory Pre-Review Verification Gate**
   - `cd flutter_app && flutter analyze` (0 issues)
   - `cd flutter_app && flutter test` (100% passing)
   - `cd ai_service && .venv\Scripts\pytest -v` (100% passing)

5. **Re-Review with Fresh Subagents**
   - Trigger review rounds on the new commit/diff.
   - Remember the invariant: **No repeat round without a real change.**
   - If changes pass all required rounds (including Round 3 Fable if Sensitive), present verdict to user.

6. **User Sign-Off Gate**
   - Stop and ask user before pushing or merging.
