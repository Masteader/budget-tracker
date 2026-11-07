# PR & Multi-Agent Audit Pipeline Rules

## 1. Orchestrator Role & Delegation Model
- The agent in chat is the **Orchestrator (Claude Opus 5.5)**. The user communicates exclusively with the Orchestrator.
- **Never implement directly in the main session.** The Orchestrator delegates implementation, code review, and plan writing to subagents.
- The Orchestrator may perform small targeted file reads to verify status or context. Subagents must return actionable conclusions and concise summaries, **not raw file dumps**.

## 2. Model Selection & Work Distribution
- **Implementation & Plans:** Claude Opus 5.5, effort high (Subagent `Model: 'pro'`).
- **Small Tasks Only:** Claude Sonnet, effort high. Restricted to tasks with **zero** auth, money, data, or schema logic. If a small task expands in scope, it must immediately be returned to Opus.
- **Parallel Work & Branch Isolation:** One dedicated git worktree/branch per task (`Workspace: 'branch'`). Two agents must **never** edit the same file concurrently.
- **Order of Execution:** Tests pass first (TDD & verification gate), then review.

## 3. Sensitivity Governance
- Governed by [`docs/sensitive.md`](docs/sensitive.md). Any change touching sensitive paths is sensitive automatically: migrations, auth, payments, RLS policies, moving money, changing permissions, deleting data, or touching secrets.
- **Unidirectional Escalation:** The Orchestrator may raise a task to sensitive, but **never lower it**. When in doubt, classify as sensitive.
- **Mandatory Plan Declaration:** Every implementation plan must explicitly state:
  > **Sensitive:** yes or no, because [exact justification].

## 4. Multi-Round Code Review Pipeline
Every review round is executed by a **fresh subagent** that receives only the task specification and the git diff (not the author's internal reasoning):
- **Round 1 (Claude Opus 5.5, effort high):** Specification fidelity & gap analysis. Does the code do what the spec says, and what edge case is missing?
- **Round 2 (Claude Opus 5.5, effort high):** Adversarial break testing. Assume there is a bug and actively attempt to break it: permissions, empty data, null handling, concurrency. **Every claim must be proven** with a failing test or exact reproduction steps.
- **Round 3 (Fable, effort high):** Mandatory for all **Sensitive** tasks. Deep audit of security, ledger invariants, RLS multi-tenancy, and Islamic fintech compliance.
- **Review Hygiene:** No repeat review round without a real code change. Any blocking note must be escalated immediately to the user.

### 4.1 Owner Scope Waiver (2026-11-06)
The owner waived parts of this section and section 6. These scope rules override the text above:
- **Changes that need testing get two rounds:** Round 1 and Round 2. This includes every social engine (`marketing/social_engine/`) batch.
- **Round 3 (Fable) runs only when the change actually touches sensitive code** as defined in [`docs/sensitive.md`](docs/sensitive.md). If sensitive code was not touched, skip Round 3. The login (auth deep link) and payday fixes touch sensitive code, so they keep all three rounds.
- **Changes that need no testing,** such as docs and comments only, get no test runs and Round 1 only.
- **One agent at a time.** Do not run parallel agents unless the owner asks for it.
- **One plan section at a time.** Show the owner the section and get their go-ahead before starting it.

## 5. Supabase MCP Database Rules
- **Read-Only on Production:** The Supabase MCP server is strictly read-only on live/production databases.
- **Writes on Development Only:** Live mutations and test fixtures are restricted to the local/development database environment.
- **Migration Discipline:** Schema changes are permitted **only** as reviewed timestamped migration files (`supabase/migrations/YYYYMMDDHHMMSS_*.sql`) with corresponding proof tests in `supabase/tests/`.
- **RLS Verification:** Every new table must have Row Level Security (`ENABLE ROW LEVEL SECURITY`) explicitly verified.

## 6. Mandatory Pre-Review Verification Gate
Before triggering any review round or committing, the implementing subagent must confirm:
1. `cd flutter_app && flutter analyze` (0 issues)
2. `cd flutter_app && flutter test` (100% passing)
3. `cd ai_service && .venv\Scripts\pytest -v` (100% passing)

**Owner scope waiver (2026-11-06):** run only the checks for the areas the change touched. Do not run the others.
- `flutter_app/` changed: `flutter analyze` and `flutter test`.
- `ai_service/` changed: `ai_service` pytest.
- `marketing/social_engine/` changed: that engine's own test suites only.
- `web_app/` changed: `npm run lint` and `npm run build`.
- `supabase/` changed: the local database tests.
- Docs or comments only: no test runs.

## 7. Explicit User Approval Invariants
Always stop and ask the user for explicit confirmation before:
- Deploying to any environment.
- Deleting data, files, or accounts.
- Accessing or updating secrets/credentials.
- Any action that incurs financial spend.
- Any external side effect.
- Any blocking note or architectural dispute.

## 8. Context Window Threshold (80% Guardrail)
When conversational context reaches an actual **80% capacity** (without guessing), the Orchestrator must write a structured handoff document (`docs/review/HANDOFF_<session>.md`) and instruct the user to continue in a fresh session.
