---
name: security-audit
description: Use when asked to review code, perform an audit, inspect vulnerabilities, or fix security gaps across application code, APIs, and configuration files.
---

# Security Audit & Vulnerability Remediation

## Overview

A disciplined, defensive protocol for reviewing codebases, auditing potential vulnerabilities, and applying surgical security patches.

**Core Principles:**
1. **OWASP Top 10 Baseline:** Every audit systematically benchmarks against OWASP categories.
2. **Surgical Scope:** Never touch outside files or refactor adjacent logic; change only lines strictly required to eliminate the vulnerability.
3. **Deterministic Gate:** No patch is declared complete without fresh, passing test suite and linter evidence.
4. **Grill-Me Protocol:** For complex architectural or auth changes, interview the user one question at a time before altering application context.

---

## When to Use

- When the user asks to **"review code"**, **"perform an audit"**, or **"fix security gaps"**.
- When inspecting endpoints, database queries, authentication flows, or external integrations for vulnerabilities.
- When applying security patches, hardening dependencies, or verifying input sanitization.

### When NOT to Use
- For general UI/UX redesigns or cosmetic cleanups.
- For non-security bug fixes with straightforward logic bugs (use `systematic-debugging` instead).
- For offensive security operations or exploit payload authoring (prohibited).

---

## The 4-Phase Audit & Remediation Workflow

```
[Phase 1: Audit & Discovery]
        │
        ▼ (Check against OWASP Top 10)
[Phase 2: Complexity Check]
   ├─► Highly complex / Auth / Architecture ──► [Grill-Me Protocol: 1 Question at a Time]
   │                                                        │ (User approved)
   └─► Self-contained / Targeted ───────────────────────────┴─► [Phase 3: Surgical Patch]
                                                                        │
                                                                        ▼
                                                             [Phase 4: Deterministic Gate]
                                                             (Run Full Tests & Linter)
                                                                        │
                                                                        ▼ (Pass with 0 errors)
                                                             [Document Evidence & Report]
```

---

### Phase 1: Audit & Discovery (OWASP Top 10 Baseline)

Perform static analysis and tracing against the OWASP Top 10 guidelines (see [references/owasp-top-10-checklist.md](./references/owasp-top-10-checklist.md)):

1. **A01: Broken Access Control:** Audit object-level permissions, tenant isolation (`household_id` / `user_id` scoping), and route guards.
2. **A02: Cryptographic Failures:** Scan for hardcoded credentials, API keys, cleartext transmission, and weak hashing algorithms.
3. **A03: Injection:** Check SQL/PostgREST queries, shell command execution, regex denial-of-service, and unescaped HTML/templates.
4. **A04: Insecure Design:** Review rate limiting, business logic validation, and idempotency safeguards.
5. **A05: Security Misconfiguration:** Inspect debug flags, CORS policies, verbose stack traces, and default permissions.
6. **A06: Vulnerable Components:** Review dependencies in `requirements.txt` or `pubspec.yaml` for known CVEs.
7. **A07: Identification & Auth:** Audit session management, token validation, password hashing, and reset flows.
8. **A08: Software & Data Integrity:** Inspect untrusted deserialization, upload mime validation, and file handlers.
9. **A09: Logging & Monitoring Failures:** Verify security audit trails while ensuring sensitive data (passwords, tokens, PII) is never logged.
10. **A10: SSRF:** Check endpoints making outbound HTTP calls with user-controlled URLs.

Document each identified finding with:
- **Severity:** Critical, High, Medium, or Low
- **Location:** File path and line numbers
- **Vulnerability Category:** OWASP reference (e.g. A01, A03)
- **Root Cause & Impact:** Why the current code is vulnerable and what an attacker could achieve

---

### Phase 2: Architectural Risk Check & "Grill-Me" Interview Protocol

Before touching code, evaluate whether the planned remediation is **highly complex**.

#### What Counts as Highly Complex?
- Changes affecting authentication/session management, JWT handling, or token refresh logic.
- Changes to database schema, Row-Level Security (RLS) policies, or multi-tenant boundary models.
- Changes altering cryptographic keys, encryption mechanisms, or identity provider integrations.
- Changes requiring breaking API contract modifications or database data migrations.

#### The "Grill-Me" Rules:
If the fix qualifies as highly complex:
1. **DO NOT modify application context or code files yet.**
2. **Interview the user ONE question at a time.**
3. Focus each question on resolving trade-offs, architecture decisions, or edge cases.
4. Wait for the user's explicit response before asking the next question or proposing code changes.
5. Once aligned, confirm the proposed surgical approach before proceeding to Phase 3.

---

### Phase 3: Surgical Patch Implementation

When writing the patch, enforce strict **surgical scope**:

1. **Zero Blast Radius:** Modify **ONLY** the specific lines directly tied to the security gap.
2. **No Extraneous Refactoring:**
   - Do NOT reformat adjacent code or rename unrelated functions.
   - Do NOT update unrequested styles or dependencies.
   - Do NOT optimize code outside the vulnerable path.
3. **No Outside File Edits Without Permission:**
   - If a fix requires touching an additional file not initially flagged, request explicit permission from the user before modifying it.
4. **Preserve Compatibility:** Maintain backward compatibility with existing tests and callers unless the user explicitly requested a breaking change.

---

### Phase 4: Deterministic Gate Verification

```
THE DETERMINISTIC GATE IS NON-NEGOTIABLE:
NO COMPLETION CLAIMS WITHOUT FRESH, PASSING VERIFICATION EVIDENCE.
```

Before declaring any security fix finished, passing, or resolved:

1. **Identify the Project's Verification Suite:**
   - Backend Python: `.\venv\Scripts\python.exe -m pytest`
   - Mobile Flutter: `flutter test` and/or `flutter analyze`
   - Web/Node: `npm test` and `npm run lint`
2. **Execute the Full Test Suite:**
   - Run the full test suite locally—never assume a partial test run covers regressions.
3. **Inspect Output for Failures & Warnings:**
   - Ensure exit code is `0`.
   - Verify that all existing tests continue to pass and no regressions were introduced.
4. **Present Fresh Evidence:**
   - Present the exact command output (number of passed tests, execution duration) to the user as proof of correctness.

---

## Rationalization Prevention Table

| Rationalization | Reality |
| :--- | :--- |
| *"The fix is tiny, I don't need to run the full test suite."* | **Deterministic Gate:** Tiny security fixes frequently break existing callers. Run the full test suite. |
| *"While I'm here, I'll clean up and refactor this entire service class."* | **Surgical Scope:** Modifying unrelated code increases blast radius and introduces hidden defects. Touch only the vulnerability. |
| *"I need to change 4 other files to make this cleaner."* | **Permission Required:** Ask the user before modifying outside files. |
| *"The architecture change is obvious, no need to ask questions."* | **Grill-Me Protocol:** High-complexity security decisions require user alignment. Interview one question at a time. |
| *"Linter passed, so tests should pass too."* | Linting verifies syntax; tests verify runtime security invariants. Run both. |

---

## Red Flags - STOP and Verify

- 🚩 About to modify a second or third file without asking the user.
- 🚩 About to say "the security gap is fixed" without showing fresh test output.
- 🚩 Asking multiple architectural questions in a single giant message instead of one question at a time.
- 🚩 Modifying existing security behavior without checking OWASP Top 10 implications.
- 🚩 Removing security assertions or skipping tests to make the build pass.

---

## Quick Reference Checklist

Before declaring the task complete, verify every box is checked:

- [ ] Audit evaluated against OWASP Top 10 checklist categories.
- [ ] If complex/architectural, "grill-me" interview protocol executed (one question at a time).
- [ ] Surgical patch applied strictly to vulnerable lines; no outside files modified without permission.
- [ ] Full local test suite executed with exit code 0.
- [ ] Linter/analyzer verified with 0 errors.
- [ ] Fresh verification evidence presented in the final response.
