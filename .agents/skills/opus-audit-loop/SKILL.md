---
name: opus-audit-loop
description: "Use when orchestrating any task. Manages the Claude Opus 5.5 Orchestrator workflow: plans and delegates to subagents (Opus 5.5 high / Sonnet high), enforces sensitivity via docs/sensitive.md, multi-round fresh subagent reviews (Round 1 spec fidelity, Round 2 adversarial break, Round 3 Fable for sensitive), and asks user first on external effects."
---

# Opus Multi-Agent Orchestration & Audit Loop

This skill governs the development and verification pipeline orchestrated by the **Claude Opus 5.5 Orchestrator** in chat, delegating all code tasks to specialized subagents.

## Core Hierarchy

```
User (Product Owner)
  │
  ▼
Orchestrator (Claude Opus 5.5 in Chat)
  ├─► Implementation Subagent (Opus 5.5 high / Sonnet high for small non-financial)
  │     └─► Isolated Worktree / Branch (`Workspace: 'branch'`)
  │     └─► TDD (Tests First -> Code -> Verification Gate)
  │
  └─► Fresh Review Subagents (Spec & Diff only, no author rationalization)
        ├─► Round 1: Opus 5.5 high (Specification fidelity & missing edge cases)
        ├─► Round 2: Opus 5.5 high (Adversarial break testing: permissions, concurrency, nulls)
        └─► Round 3: Fable high [Mandatory if Sensitive: yes] (Security, Ledger, Islamic Fintech)
```

---

## Operating Protocol

### 1. Orchestrator Duties
- The chat assistant is the **Orchestrator**. It talks only to the user.
- **Never implement code directly.** All implementation, code review, and plan writing are delegated to subagents.
- Small targeted reads are permitted to understand state; subagents return conclusions and concise summaries, not file dumps.

### 2. Sensitivity Protocol (`docs/sensitive.md`)
- Every plan must declare:
  > **Sensitive: yes or no, because [exact justification].**
- Automatic sensitive triggers:
  - Touches paths in [`docs/sensitive.md`](../../../docs/sensitive.md) (migrations, auth, payments, RLS, financial calculations, nafaqah rules).
  - Moves money, modifies account/ledger balances, changes permissions, deletes data, or touches secrets.
- Invariant: Orchestrator may raise to sensitive, never lower it. When in doubt, it is sensitive.

### 3. Model Assignment
- **Implementation & Planning:** Claude Opus 5.5, effort high.
- **Small Tasks Only:** Claude Sonnet, effort high (strictly restricted to non-auth, non-financial, non-schema UI/styling or formatting). If scope grows, return to Opus.

### 4. Parallel Work & Isolation
- One git worktree/branch per task (`Workspace: 'branch'`).
- Two subagents must never edit the same file concurrently.

### 5. Multi-Round Fresh Review Pipeline
After implementation and tests pass:
1. **Round 1 (Opus 5.5 high):** Fresh subagent compares diff against specification. Identifies missing edge cases, unexpected omissions, or requirement deviations.
2. **Round 2 (Opus 5.5 high):** Fresh subagent assumes bugs exist and attempts adversarial breaking: empty data, role escalation, concurrency, boundary overflows. Every claim must include reproduction steps or failing test.
3. **Round 3 (Fable high) [For Sensitive Tasks]:** In-depth audit of ledger invariants, security boundaries, RLS policies, and Saudi/Islamic compliance.
4. **No Repeat Round Without Real Change:** Never re-review without actual code fixes.

### 6. Supabase MCP Guardrails
- **Read-Only on Production:** Never perform writes, schema migrations, or test fixtures against live production Supabase.
- **Writes on Development Only:** Test and verify mutations locally or on development replicas.
- **Reviewed Migrations:** Database changes must be checked in as timestamped migrations with test proof in `supabase/tests/`. Every new table must verify RLS.

### 7. Explicit User Approval Invariants
Always stop and ask the user first before:
- Deploying to any environment.
- Deletion of any data, accounts, or files.
- Secrets or credential modifications.
- Spending money or external API costs.
- Any external side effect.
- Any blocking note or architectural dispute.

### 8. Context Window Threshold (80% Guardrail)
When context reaches actual 80% capacity without guessing, write a handoff file (`docs/review/HANDOFF_<session>.md`) and continue in a fresh session.
