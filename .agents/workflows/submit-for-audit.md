---
description: Submit implemented changes to the multi-round subagent code review pipeline (Round 1 Opus 5.5 high, Round 2 Opus 5.5 high adversarial break, Round 3 Fable high for sensitive changes).
---

# Workflow: Submit Branch for Multi-Round Code Review

1. **Verify Worktree & Branch Isolation**
   - Verify execution is on an isolated task branch (`git branch --show-current`). Never work on `main`.
   - Ensure one worktree per task. Two agents must never edit the same file concurrently.

2. **Run Mandatory Pre-Review Verification Gate (Tests Pass First)**
   - `cd flutter_app && flutter analyze` (0 issues)
   - `cd flutter_app && flutter test` (100% passing)
   - `cd ai_service && .venv\Scripts\pytest -v` (100% passing)
   - Do not trigger any review round until all tests pass cleanly.

3. **Stage and Commit Changes**
   - Stage and commit using Conventional Commits.

4. **Classify Sensitivity**
   - Check [`docs/sensitive.md`](../../docs/sensitive.md).
   - Any change touching sensitive paths, moving money, altering balances, changing permissions, deleting data, or touching secrets is **Sensitive: yes**.
   - Rule: You may raise to sensitive, never lower it. When in doubt, it is sensitive.

5. **Execute Fresh Subagent Review Pipeline**
   - Each review round runs as an independent, fresh subagent seeing ONLY the specification and the `git diff` (never the author's internal reasoning):
   - **Round 1 (Claude Opus 5.5, effort high):**
     - Prompt focus: Specification fidelity and completeness. Does the code do what the spec asks? What edge cases, null states, or input ranges are missing?
   - **Round 2 (Claude Opus 5.5, effort high):**
     - Prompt focus: Adversarial break testing. Assume a bug exists and try to break it: permissions, empty data, concurrency, race conditions, balance leakage. The reviewer MUST prove every claim with a failing test or exact reproduction steps.
   - **Round 3 (Fable, effort high) [Mandatory if Sensitive: yes]:**
     - Prompt focus: Security audit, ledger invariant verification, RLS multi-tenancy guarantees, and Islamic fintech/nafaqah compliance.

6. **Handle the Verdict**
   - **If all review rounds pass with zero findings:** Present the audit summary to the user.
   - **If any finding or bug is identified:** Transition immediately to [`.agents/workflows/address-review.md`](address-review.md).
   - **If any blocking note or architectural dispute arises:** Stop immediately and escalate to the user with the exact tradeoff.
   - **No Repeat Round Without Real Change:** Never re-run a review round without real code edits addressing the findings.

7. **User Gate & Push**
   - Stop and ask the user for explicit sign-off before pushing remote or merging to `main`.
