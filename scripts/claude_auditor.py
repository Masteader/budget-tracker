"""
scripts/claude_auditor.py
===========================================================
Claude Opus 5.5 -- External Architectural Auditor Engine
===========================================================

Modes
-----
  --mode plan      Send a task description to Opus, get a structured
                   implementation plan. Output -> docs/review/OPUS_PLAN.md
  --mode review    Send changed files (full content, NOT git diff) to Opus
                   for architectural audit. Output -> docs/review/AUDIT_FEEDBACK.md
  --mode landing   Full codebase 4-pass architectural review (initial onboarding).
                   Output -> docs/review/MASTER_CODEBASE_AUDIT.md

Options
-------
  --batch          Use the Message Batches API (50% off, async 15-45 min).
  --task "..."     Task description for --mode plan.
  --task-file X    Read task description from a file.
  --files f1 f2    Explicit file list to review (overrides git detection).
  --verbose        Print token usage and cost estimate.

Environment
-----------
  ANTHROPIC_API_KEY   Required. Obtain from https://console.anthropic.com
  OPUS_MODEL          Optional. Override model ID (default: claude-opus-4-20250514).

Usage Examples
--------------
  python scripts/claude_auditor.py --mode plan --task "Add installment notifications"
  python scripts/claude_auditor.py --mode review
  python scripts/claude_auditor.py --mode review --batch
  python scripts/claude_auditor.py --mode landing --batch
  python scripts/claude_auditor.py --mode plan --task-file docs/superpowers/task.md --verbose
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Optional

try:
    import anthropic
except ImportError:
    print(
        "ERROR: The 'anthropic' Python package is not installed.\n"
        "Run:  pip install -r scripts/requirements-audit.txt",
        file=sys.stderr,
    )
    sys.exit(2)

# --------------------------------------------------------------
# Configuration
# --------------------------------------------------------------

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RULES_DIR = PROJECT_ROOT / ".agents" / "rules"
DOCS_REVIEW_DIR = PROJECT_ROOT / "docs" / "review"
SPEND_FILE = DOCS_REVIEW_DIR / "audit_spend.json"

# Strict budget ceiling in USD (default $10.00 max spend)
DEFAULT_MAX_BUDGET_USD = 10.00
MAX_BUDGET_USD = float(os.environ.get("AUDIT_MAX_BUDGET_USD", str(DEFAULT_MAX_BUDGET_USD)))

# Model -- configurable via env var for future upgrades
DEFAULT_MODEL = "claude-opus-5-5"
MODEL = os.environ.get("OPUS_MODEL", DEFAULT_MODEL)

# Token pricing for cost estimates (Claude Opus 5.5 as of Nov 2026)
PRICING = {
    "input": 4.00,          # $ per 1M tokens
    "output": 20.00,        # $ per 1M tokens
    "cache_read": 0.20,     # $ per 1M tokens
    "cache_write": 5.00,    # $ per 1M tokens
    "batch_discount": 0.50, # 50% off for batch
}

# --------------------------------------------------------------
# Budget Guardrail & Spend Tracker
# --------------------------------------------------------------

def load_spend_history() -> dict:
    """Load persistent token spend and cost history."""
    if SPEND_FILE.exists():
        try:
            return json.loads(SPEND_FILE.read_text(encoding="utf-8"))
        except Exception:
            pass
    return {
        "max_budget_usd": MAX_BUDGET_USD,
        "total_spent_usd": 0.0,
        "total_calls": 0,
        "total_input_tokens": 0,
        "total_output_tokens": 0,
        "total_cache_read_tokens": 0,
        "total_cache_write_tokens": 0,
        "history": [],
    }

def save_spend_history(data: dict) -> None:
    """Save persistent token spend and cost history."""
    SPEND_FILE.parent.mkdir(parents=True, exist_ok=True)
    SPEND_FILE.write_text(json.dumps(data, indent=2), encoding="utf-8")

def check_budget_guardrail() -> float:
    """Enforce strict $10 budget ceiling BEFORE any API call. Exits if exceeded."""
    history = load_spend_history()
    spent = history.get("total_spent_usd", 0.0)
    ceiling = history.get("max_budget_usd", MAX_BUDGET_USD)

    if spent >= ceiling:
        print("\n" + "=" * 65, file=sys.stderr)
        print("[HARD STOP] CRITICAL HARD STOP: API BUDGET CEILING REACHED!", file=sys.stderr)
        print(f"   Total spent to date: ${spent:.4f} / ${ceiling:.2f} limit", file=sys.stderr)
        print("   All further API calls are strictly blocked to prevent overspending.", file=sys.stderr)
        print("   To adjust the budget, set the AUDIT_MAX_BUDGET_USD environment variable.", file=sys.stderr)
        print("=" * 65 + "\n", file=sys.stderr)
        sys.exit(3)
    return spent

def record_api_spend(mode: str, usage: dict, is_batch: bool = False) -> float:
    """Record spend for a completed API call and print budget status."""
    input_tokens = usage.get("input_tokens", 0)
    output_tokens = usage.get("output_tokens", 0)
    cache_read = usage.get("cache_read_input_tokens", 0)
    cache_write = usage.get("cache_creation_input_tokens", 0)

    discount = PRICING["batch_discount"] if is_batch else 1.0
    cost_input = (input_tokens / 1_000_000) * PRICING["input"] * discount
    cost_output = (output_tokens / 1_000_000) * PRICING["output"] * discount
    cost_cache_read = (cache_read / 1_000_000) * PRICING["cache_read"] * discount
    cost_cache_write = (cache_write / 1_000_000) * PRICING["cache_write"] * discount
    call_cost = cost_input + cost_output + cost_cache_read + cost_cache_write

    data = load_spend_history()
    data["total_spent_usd"] = round(data.get("total_spent_usd", 0.0) + call_cost, 6)
    data["total_calls"] = data.get("total_calls", 0) + 1
    data["total_input_tokens"] = data.get("total_input_tokens", 0) + input_tokens
    data["total_output_tokens"] = data.get("total_output_tokens", 0) + output_tokens
    data["total_cache_read_tokens"] = data.get("total_cache_read_tokens", 0) + cache_read
    data["total_cache_write_tokens"] = data.get("total_cache_write_tokens", 0) + cache_write
    data.setdefault("history", []).append({
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "mode": mode,
        "is_batch": is_batch,
        "tokens": {
            "input": input_tokens,
            "output": output_tokens,
            "cache_read": cache_read,
            "cache_write": cache_write,
        },
        "cost_usd": round(call_cost, 6),
        "cumulative_spent_usd": data["total_spent_usd"],
    })
    save_spend_history(data)

    spent = data["total_spent_usd"]
    ceiling = data.get("max_budget_usd", MAX_BUDGET_USD)
    pct = (spent / ceiling) * 100 if ceiling > 0 else 0
    remaining = max(0.0, ceiling - spent)

    print("\n" + "-" * 55)
    print("[BUDGET] BUDGET GUARDRAIL TELEMETRY:")
    print(f"   Call cost:        ${call_cost:.4f} {'(BATCH 50% OFF)' if is_batch else ''}")
    print(f"   Cumulative spent: ${spent:.4f} / ${ceiling:.2f} ({pct:.1f}% used)")
    print(f"   Remaining budget: ${remaining:.4f}")
    if pct >= 90.0:
        print(f"   [WARNING] WARNING: You have reached {pct:.1f}% of your ${ceiling:.2f} budget limit!")
    print("-" * 55 + "\n")
    return call_cost

def show_budget_status() -> None:
    """Display the current budget status without making any API calls."""
    data = load_spend_history()
    spent = data.get("total_spent_usd", 0.0)
    ceiling = data.get("max_budget_usd", MAX_BUDGET_USD)
    calls = data.get("total_calls", 0)
    in_tok = data.get("total_input_tokens", 0)
    out_tok = data.get("total_output_tokens", 0)
    read_tok = data.get("total_cache_read_tokens", 0)
    write_tok = data.get("total_cache_write_tokens", 0)
    pct = (spent / ceiling) * 100 if ceiling > 0 else 0
    remaining = max(0.0, ceiling - spent)

    print("\n" + "=" * 55)
    print("[DASHBOARD] CLAUDE OPUS API SPEND DASHBOARD")
    print("=" * 55)
    print(f"  Maximum Budget Ceiling:  ${ceiling:.2f}")
    print(f"  Total Amount Spent:      ${spent:.4f} ({pct:.1f}%)")
    print(f"  Remaining Safe Balance:  ${remaining:.4f}")
    print(f"  Total Auditor Calls:     {calls}")
    print(f"  Tokens Consumed:")
    print(f"    * Fresh Input:         {in_tok:,}")
    print(f"    * Output (Thinking):   {out_tok:,}")
    print(f"    * Cache Reads (95% off): {read_tok:,}")
    print(f"    * Cache Writes:        {write_tok:,}")
    print(f"  Spend Log Location:      {SPEND_FILE}")
    print("=" * 55 + "\n")

# Files/dirs to always exclude from scans
EXCLUDE_PATTERNS = {
    ".git", "node_modules", "build", "dist", ".dart_tool",
    ".flutter-plugins", ".flutter-plugins-dependencies",
    "__pycache__", ".pytest_cache", ".venv", "venv",
    "pubspec.lock", ".packages", ".metadata",
    "GeneratedPluginRegistrant", ".mocks.dart",
    "ai_service/static",  # built web assets
}

# --------------------------------------------------------------
# Helpers
# --------------------------------------------------------------

def _run_git(*args: str) -> str:
    """Run a git command and return stdout."""
    result = subprocess.run(
        ["git"] + list(args),
        capture_output=True, text=True, cwd=str(PROJECT_ROOT),
    )
    if result.returncode != 0:
        print(f"git {' '.join(args)} failed:\n{result.stderr}", file=sys.stderr)
    return result.stdout.strip()


def _should_exclude(path: str) -> bool:
    """Check if a file path matches any exclusion pattern."""
    parts = Path(path).parts
    for pattern in EXCLUDE_PATTERNS:
        if pattern in parts or path.endswith(pattern):
            return True
    # Skip binary / non-reviewable files
    if any(path.endswith(ext) for ext in (
        ".png", ".jpg", ".jpeg", ".gif", ".svg", ".ico", ".ttf", ".otf",
        ".woff", ".woff2", ".eot", ".lock", ".g.dart", ".freezed.dart",
    )):
        return True
    # Skip the massive localization file (6000+ lines of key-value data)
    # It gets a targeted check in the landing compliance pass instead
    if path.endswith("app_localizations.dart"):
        return True
    return False


def _read_file_safe(filepath: Path) -> str:
    """Read a file's full content. No truncation -- Opus needs complete context."""
    try:
        return filepath.read_text(encoding="utf-8", errors="replace")
    except Exception as e:
        return f"[ERROR reading file: {e}]"


def load_project_rules() -> str:
    """Load all .agents/rules/ files as cached system context."""
    rules_text = ""
    if RULES_DIR.exists():
        for rule_file in sorted(RULES_DIR.glob("*.md")):
            rules_text += f"\n{'='*60}\n[RULE] {rule_file.name}\n{'='*60}\n"
            rules_text += rule_file.read_text(encoding="utf-8", errors="replace")
    return rules_text


def get_changed_files() -> list[str]:
    """Get list of files changed vs main branch."""
    output = _run_git("diff", "--name-only", "main...HEAD")
    if not output:
        # Fallback: check uncommitted changes
        output = _run_git("diff", "--name-only", "HEAD")
    if not output:
        output = _run_git("diff", "--name-only", "--cached")
    files = [f for f in output.splitlines() if f and not _should_exclude(f)]
    return files


def get_changed_files_summary() -> str:
    """Get a compact stat summary of changes."""
    return _run_git("diff", "--stat", "main...HEAD")


def read_changed_files_content(file_list: list[str]) -> str:
    """Read full content of changed files (NOT git diff -- saves tokens)."""
    content_blocks = []
    for filepath in file_list:
        full_path = PROJECT_ROOT / filepath
        if full_path.exists() and full_path.is_file():
            file_content = _read_file_safe(full_path)
            content_blocks.append(
                f"{'-'*60}\n"
                f"[FILE] {filepath}\n"
                f"{'-'*60}\n"
                f"{file_content}\n"
            )
    return "\n".join(content_blocks)


def estimate_cost(usage: dict, is_batch: bool = False) -> str:
    """Estimate the dollar cost from API usage metadata."""
    input_tokens = usage.get("input_tokens", 0)
    output_tokens = usage.get("output_tokens", 0)
    cache_read = usage.get("cache_read_input_tokens", 0)
    cache_write = usage.get("cache_creation_input_tokens", 0)

    discount = PRICING["batch_discount"] if is_batch else 1.0

    cost_input = (input_tokens / 1_000_000) * PRICING["input"] * discount
    cost_output = (output_tokens / 1_000_000) * PRICING["output"] * discount
    cost_cache_read = (cache_read / 1_000_000) * PRICING["cache_read"] * discount
    cost_cache_write = (cache_write / 1_000_000) * PRICING["cache_write"] * discount
    total = cost_input + cost_output + cost_cache_read + cost_cache_write

    return (
        f"  Input:       {input_tokens:>8,} tokens  (${cost_input:.4f})\n"
        f"  Output:      {output_tokens:>8,} tokens  (${cost_output:.4f})\n"
        f"  Cache Read:  {cache_read:>8,} tokens  (${cost_cache_read:.4f})\n"
        f"  Cache Write: {cache_write:>8,} tokens  (${cost_cache_write:.4f})\n"
        f"  {'BATCH 50% DISCOUNT APPLIED' if is_batch else 'Standard pricing'}\n"
        f"  -----------------------------\n"
        f"  TOTAL COST:  ${total:.4f}"
    )


# --------------------------------------------------------------
# System Prompt (Cached -- 95% discount on repeated calls)
# --------------------------------------------------------------

SYSTEM_PROMPT = """You are the Lead External Architect and Security Auditor for "Budget Tracker", a Saudi household financial operating system.

YOUR IDENTITY:
- You are Claude Opus, the strictest architectural reviewer on this project.
- You enforce Saudi fintech compliance, Islamic family finance (Nafaqah) rules, Supabase RLS multi-tenancy, and TDD discipline.
- You work alongside Antigravity (Gemini 3.8 Flash High) which implements the code you plan and review.

YOUR CONSTRAINTS:
- NEVER approve code that violates the project rules provided below.
- NEVER be lenient on security (RLS bypass, exposed service keys, missing auth checks).
- NEVER skip checking for hardcoded strings (trilingual l10n is mandatory).
- Flag any code that breaks the Saudi payday cycle logic or Nafaqah family finance rules.
- Your feedback must be precise: exact file paths, line references, and actionable fix instructions.

COMMUNICATION STYLE:
- When writing implementation plans: be surgical, specific, and reference exact files and TDD steps.
- When reviewing code: DO NOT write human-facing conversational essays or fluff. Output ONLY direct, actionable prompt instructions for Antigravity (Gemini 3.8 Flash High) to execute.
- When approving: say "AUDIT VERDICT: APPROVED" followed by "Push to main. All rules satisfied."
- When requesting revisions: say "AUDIT VERDICT: REVISE" followed immediately by straight, numbered fix instructions for Antigravity specifying file, line, and exact code fix."""


# --------------------------------------------------------------
# Core Audit Functions
# --------------------------------------------------------------

def _create_client() -> anthropic.Anthropic:
    """Create Anthropic client with validation."""
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print(
            "ERROR: ANTHROPIC_API_KEY environment variable is not set.\n"
            "Set it with:\n"
            '  [System.Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", "sk-ant-...", "User")\n'
            "Then restart your terminal.",
            file=sys.stderr,
        )
        sys.exit(2)
    return anthropic.Anthropic(api_key=api_key)


def _call_realtime(client: anthropic.Anthropic, user_prompt: str, verbose: bool = False) -> tuple[str, dict]:
    """Send a real-time (synchronous) request with prompt caching and budget guardrail."""
    check_budget_guardrail()
    rules = load_project_rules()

    response = client.messages.create(
        model=MODEL,
        max_tokens=16384,
        output_config={"effort": "high"},
        system=[
            {
                "type": "text",
                "text": SYSTEM_PROMPT + "\n\n" + "=" * 60 + "\nPROJECT RULES (MANDATORY COMPLIANCE)\n" + "=" * 60 + "\n" + rules,
                "cache_control": {"type": "ephemeral"},
            }
        ],
        messages=[{"role": "user", "content": user_prompt}],
    )

    text_parts = [b.text for b in response.content if hasattr(b, 'text')]
    result_text = "\n".join(text_parts) if text_parts else "[NO TEXT OUTPUT RETURNED]"
    usage = {}
    if hasattr(response, "usage"):
        usage = {
            "input_tokens": response.usage.input_tokens,
            "output_tokens": response.usage.output_tokens,
            "cache_read_input_tokens": getattr(response.usage, "cache_read_input_tokens", 0),
            "cache_creation_input_tokens": getattr(response.usage, "cache_creation_input_tokens", 0),
        }

    # Record spend in persistent ledger and display budget status
    record_api_spend(mode="realtime", usage=usage, is_batch=False)

    if verbose and usage:
        print("\n[DASHBOARD] DETAILED TOKEN BREAKDOWN:")
        print(estimate_cost(usage, is_batch=False))

    return result_text, usage


def _call_batch(client: anthropic.Anthropic, requests_list: list[dict], verbose: bool = False) -> str:
    """Submit a batch request (50% off, async processing) with budget guardrail."""
    check_budget_guardrail()
    rules = load_project_rules()
    system_block = [
        {
            "type": "text",
            "text": SYSTEM_PROMPT + "\n\n" + "=" * 60 + "\nPROJECT RULES (MANDATORY COMPLIANCE)\n" + "=" * 60 + "\n" + rules,
            "cache_control": {"type": "ephemeral"},
        }
    ]

    batch_requests = []
    for i, req in enumerate(requests_list):
        batch_requests.append({
            "custom_id": req.get("id", f"audit-pass-{i+1}"),
            "params": {
                "model": MODEL,
                "max_tokens": 8192,
                "output_config": {"effort": "high"},
                "system": system_block,
                "messages": [{"role": "user", "content": req["prompt"]}],
            },
        })

    print(f"[BATCH] Submitting batch with {len(batch_requests)} request(s)...")
    print(f"   50% DISCOUNT APPLIED -- estimated turnaround: 15-45 minutes")

    batch = client.messages.batches.create(requests=batch_requests)
    batch_id = batch.id
    print(f"   Batch ID: {batch_id}")
    print(f"   Status:   {batch.processing_status}")

    # Poll for completion
    print("\n[WAIT] Waiting for batch to complete...")
    while True:
        time.sleep(30)
        batch = client.messages.batches.retrieve(batch_id)
        status = batch.processing_status
        print(f"   Status: {status} -- {time.strftime('%H:%M:%S')}")
        if status == "ended":
            break

    # Collect results and aggregate token usage
    results = []
    total_usage = {
        "input_tokens": 0,
        "output_tokens": 0,
        "cache_read_input_tokens": 0,
        "cache_creation_input_tokens": 0,
    }

    for result in client.messages.batches.results(batch_id):
        custom_id = result.custom_id
        if result.result.type == "succeeded":
            msg = result.result.message
            text_parts = [b.text for b in msg.content if hasattr(b, 'text')]
            text = "\n".join(text_parts) if text_parts else "[NO TEXT OUTPUT RETURNED]"
            results.append(f"{'='*60}\n[AUDIT] {custom_id}\n{'='*60}\n{text}")
            if hasattr(msg, "usage"):
                total_usage["input_tokens"] += getattr(msg.usage, "input_tokens", 0)
                total_usage["output_tokens"] += getattr(msg.usage, "output_tokens", 0)
                total_usage["cache_read_input_tokens"] += getattr(msg.usage, "cache_read_input_tokens", 0)
                total_usage["cache_creation_input_tokens"] += getattr(msg.usage, "cache_creation_input_tokens", 0)
        else:
            results.append(f"{'='*60}\n[FAILED] {custom_id} -- FAILED\n{'='*60}\n{result.result}")

    # Record batch spend in persistent ledger
    record_api_spend(mode="batch", usage=total_usage, is_batch=True)

    if verbose:
        print("\n[DASHBOARD] BATCH TOTAL TOKEN USAGE:")
        print(estimate_cost(total_usage, is_batch=True))

    return "\n\n".join(results)


# --------------------------------------------------------------
# Mode: Plan
# --------------------------------------------------------------

def mode_plan(task: str, batch: bool = False, verbose: bool = False) -> int:
    """Ask Opus to create an implementation plan from a task description."""
    client = _create_client()

    prompt = f"""TASK REQUEST FROM THE PRODUCT OWNER:
{task}

YOUR JOB: Create a detailed, surgical implementation plan for Antigravity (Gemini 3.8 Flash High) to execute.

OUTPUT FORMAT (strictly follow this structure):

# IMPLEMENTATION PLAN
**Task:** [one-line summary]
**Branch:** feat/[suggested-branch-name]
**Estimated Complexity:** [LOW | MEDIUM | HIGH]

## 1. Architectural Analysis
- What existing files/modules are affected
- What new files need to be created
- Database migration needed? (yes/no + details)
- API endpoint changes? (yes/no + details)

## 2. Step-by-Step Implementation Instructions
For each step:
- **Step N: [Title]**
  - File: `exact/path/to/file.ext`
  - Action: [CREATE | MODIFY | DELETE]
  - Details: [Exact code changes, function signatures, logic]
  - Tests: [What test to write first -- TDD]

## 3. Test Requirements
- Unit tests to write (with file paths)
- Widget tests needed
- Integration/API tests needed

## 4. Verification Checklist
- [ ] flutter analyze -- zero issues
- [ ] flutter test -- all pass
- [ ] pytest -- all pass
- [ ] Rule 02 Saudi compliance verified
- [ ] Rule 03 trilingual l10n -- no hardcoded strings
- [ ] Rule 04 security -- RLS, no exposed keys
"""

    if batch:
        result = _call_batch(client, [{"id": "plan", "prompt": prompt}], verbose)
    else:
        result, _ = _call_realtime(client, prompt, verbose)

    output_path = DOCS_REVIEW_DIR / "OPUS_PLAN.md"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(result, encoding="utf-8")

    print(f"\n[OK] Plan written to: {output_path}")
    print(f"   Antigravity can now read and execute this plan.")
    return 0


# --------------------------------------------------------------
# Mode: Review (PR Audit)
# --------------------------------------------------------------

def mode_review(
    file_list: Optional[list[str]] = None,
    batch: bool = False,
    verbose: bool = False,
) -> int:
    """Audit changed files against project rules."""
    client = _create_client()

    # Detect changed files
    if file_list:
        changed_files = [f for f in file_list if not _should_exclude(f)]
    else:
        changed_files = get_changed_files()

    if not changed_files:
        print("[INFO]  No changed files detected against main. Nothing to audit.")
        return 0

    change_summary = get_changed_files_summary()
    file_contents = read_changed_files_content(changed_files)

    # Get current branch name
    branch = _run_git("branch", "--show-current")

    prompt = f"""ARCHITECTURAL CODE REVIEW REQUEST
Branch: {branch}
Files Changed: {len(changed_files)}

CHANGE SUMMARY (git diff --stat):
{change_summary}

CHANGED FILE LIST:
{chr(10).join(f'  * {f}' for f in changed_files)}

FULL FILE CONTENTS FOR REVIEW:
(These are the complete current versions of every modified file.
Review them for correctness, security, Saudi fintech compliance, and code quality.)

{file_contents}

YOUR JOB: Perform an architectural and security review.
DO NOT provide conversational explanations, pleasantries, or essay summaries.
Output ONLY straight-forward, actionable prompt instructions for Antigravity (Gemini 3.8 Flash High).

OUTPUT FORMAT:

If all code satisfies project rules:
# AUDIT VERDICT: APPROVED
Push to main. All rules satisfied.

If any flaws, security risks, or rule violations exist:
# AUDIT VERDICT: REVISE

PROMPT FOR ANTIGRAVITY (GEMINI 3.8 FLASH HIGH):
Execute the following fixes immediately:
1. [FILE: exact/path, LINE: approx line]
   - ISSUE: [one-line root cause]
   - FIX: [exact replacement code or surgical change instruction]
   - TEST: [unit/widget test to add or update first]
2. ...

VERIFICATION GATES TO RUN:
- flutter analyze
- flutter test
- pytest
"""

    if batch:
        result = _call_batch(client, [{"id": "pr-review", "prompt": prompt}], verbose)
    else:
        result, _ = _call_realtime(client, prompt, verbose)

    output_path = DOCS_REVIEW_DIR / "AUDIT_FEEDBACK.md"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(result, encoding="utf-8")

    print(f"\n[FEEDBACK] Audit feedback written to: {output_path}")

    if "AUDIT VERDICT: APPROVED" in result:
        print("[OK] STATUS: APPROVED -- Ready for human sign-off to push to main.")
        return 0
    else:
        print("[REVISE] STATUS: REVISE -- Findings require Antigravity to fix before merge.")
        return 1


# --------------------------------------------------------------
# Mode: Landing (Initial Full-Project Audit)
# --------------------------------------------------------------

# Architectural domains for the 4-pass initial audit
LANDING_PASSES = [
    {
        "id": "pass-1-database",
        "title": "Database, Migrations & RLS Security",
        "globs": ["supabase/**/*.sql", "supabase/**/*.py"],
        "focus": (
            "Review all SQL migrations, RLS policies, SECURITY DEFINER functions, "
            "and the test runner. Check for: missing RLS on any table, "
            "policy bypass risks, search_path pinning, SQL injection vectors, "
            "and correct Saudi cycle_key trigger logic."
        ),
    },
    {
        "id": "pass-2-backend",
        "title": "Python AI Service (FastAPI Backend)",
        "globs": ["ai_service/**/*.py"],
        "focus": (
            "Review all FastAPI routes, auth middleware, household permissions, "
            "salary cycle logic, Nafaqah settlement engine, receipt OCR, "
            "and installment service. Check for: missing auth checks, "
            "service-role key exposure, rate limiting, and financial calculation accuracy."
        ),
    },
    {
        "id": "pass-3-flutter",
        "title": "Flutter Mobile App Architecture",
        "globs": [
            "flutter_app/lib/providers/**/*.dart",
            "flutter_app/lib/services/**/*.dart",
            "flutter_app/lib/models/**/*.dart",
            "flutter_app/lib/screens/**/*.dart",
        ],
        "focus": (
            "Review state management (Provider/ChangeNotifier), API clients, "
            "data models, and screen-level views. Check for: hardcoded strings "
            "(must use AppLocalizations), incorrect RTL handling, "
            "missing error boundaries, and reactive state consistency."
        ),
    },
    {
        "id": "pass-4-compliance",
        "title": "Cross-Cutting Compliance & Security Audit",
        "globs": [
            "flutter_app/lib/theme/**/*.dart",
            "flutter_app/lib/widgets/**/*.dart",
            "flutter_app/lib/l10n/**/*.dart",
            "web_app/src/**/*.ts",
            "web_app/src/**/*.tsx",
        ],
        "focus": (
            "Review UI theme compliance (Sovereign OS / Iced Ocean), "
            "widget library, localization completeness (AR/EN/UR), "
            "web landing page (Daylight Coastal theme), and overall "
            "project rule adherence across Rules 01-05."
        ),
    },
]


def _collect_files_by_globs(globs: list[str]) -> list[str]:
    """Collect tracked files matching glob patterns, prioritized by architectural relevance."""
    all_files = _run_git("ls-files").splitlines()
    matched = []
    for filepath in all_files:
        if _should_exclude(filepath):
            continue
        for pattern in globs:
            dir_part = pattern.split("**")[0].rstrip("/") if "**" in pattern else ""
            ext_part = pattern.split("*")[-1] if "*" in pattern else ""
            if (not dir_part or filepath.startswith(dir_part)) and \
               (not ext_part or filepath.endswith(ext_part)):
                matched.append(filepath)
                break

    def _priority_score(p: str) -> int:
        score = 0
        p_lower = p.lower()
        if "schema.sql" in p_lower: score -= 100
        if "main.py" in p_lower: score -= 90
        if "auth.py" in p_lower: score -= 85
        if "salary_cycle.py" in p_lower: score -= 80
        if "household_permissions.py" in p_lower: score -= 80
        if "installment_service.py" in p_lower: score -= 75
        if "supabase_client.py" in p_lower: score -= 75
        if "routes/" in p_lower: score -= 60
        if "providers/" in p_lower: score -= 70
        if "models/" in p_lower: score -= 65
        if "services/api/" in p_lower: score -= 60
        if "migrations/" in p_lower: score -= 50
        if "test" in p_lower or "tests/" in p_lower or "_test.dart" in p_lower:
            score += 50
        return score

    matched.sort(key=lambda f: (_priority_score(f), f))
    return matched


def mode_landing(batch: bool = False, verbose: bool = False) -> int:
    """Full codebase architectural review in 4 targeted passes."""
    client = _create_client()

    print("[LANDING]  INITIAL FULL-PROJECT ARCHITECTURAL AUDIT")
    print(f"   Model: {MODEL}")
    print(f"   Mode:  {'BATCH (50% off)' if batch else 'Real-Time'}")
    print(f"   Passes: {len(LANDING_PASSES)}")
    print()

    requests_list = []

    for audit_pass in LANDING_PASSES:
        files = _collect_files_by_globs(audit_pass["globs"])
        if not files:
            print(f"   [WARNING]  {audit_pass['title']}: No files found, skipping.")
            continue

        # Cap at 30 files per pass to avoid token explosion
        if len(files) > 30:
            print(f"   [INFO]  {audit_pass['title']}: {len(files)} files found, reviewing top 30.")
            files = files[:30]

        file_contents = read_changed_files_content(files)

        prompt = f"""FULL CODEBASE ARCHITECTURAL AUDIT -- {audit_pass['title'].upper()}

AUDIT FOCUS:
{audit_pass['focus']}

FILES IN THIS PASS ({len(files)} files):
{chr(10).join(f'  * {f}' for f in files)}

FULL FILE CONTENTS:
{file_contents}

OUTPUT FORMAT:

# {audit_pass['title']} -- AUDIT REPORT

## 1. Architecture Assessment
[Overall structural health, patterns, anti-patterns]

## 2. Security Findings
[RLS gaps, auth bypasses, key exposure, injection risks]

## 3. Saudi Fintech & Islamic Compliance
[Payday cycle, Nafaqah rules, ZATCA, zero-based budgets]

## 4. Code Quality & Maintainability
[TDD coverage, dead code, error handling, performance]

## 5. Prioritized Recommendations
### CRITICAL (Immediate action)
### HIGH (Before next release)
### MEDIUM (Technical debt)
### LOW (Nice to have)

## 6. Score: [A/B/C/D/F] -- [one-line justification]
"""
        requests_list.append({"id": audit_pass["id"], "prompt": prompt})
        print(f"   [OK] {audit_pass['title']}: {len(files)} files queued")

    if not requests_list:
        print("\n[FAILED] No files found for any audit pass.")
        return 2

    print()

    if batch:
        combined_result = _call_batch(client, requests_list, verbose)
    else:
        # Run passes sequentially in real-time
        results = []
        for req in requests_list:
            print(f"[AUDIT] Running: {req['id']}...")
            result, _ = _call_realtime(client, req["prompt"], verbose)
            results.append(f"{'='*60}\n[AUDIT] {req['id']}\n{'='*60}\n{result}")
        combined_result = "\n\n".join(results)

    output_path = DOCS_REVIEW_DIR / "MASTER_CODEBASE_AUDIT.md"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    header = (
        f"# MASTER CODEBASE AUDIT REPORT\n"
        f"**Generated:** {time.strftime('%Y-%m-%d %H:%M:%S')}\n"
        f"**Model:** {MODEL}\n"
        f"**Mode:** {'Batch (50% off)' if batch else 'Real-Time'}\n"
        f"**Passes:** {len(requests_list)}\n\n---\n\n"
    )
    output_path.write_text(header + combined_result, encoding="utf-8")

    print(f"\n[OK] Full audit written to: {output_path}")
    print(f"   Review the report and prioritize CRITICAL/HIGH findings.")
    return 0


# --------------------------------------------------------------
# CLI Entry Point
# --------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Claude Opus 5.5 -- External Architectural Auditor",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--mode", choices=["plan", "review", "landing"], required=False, default=None,
        help="Audit mode: 'plan' (create plan), 'review' (audit PR), 'landing' (full codebase)",
    )
    parser.add_argument(
        "--batch", action="store_true",
        help="Use Message Batches API (50%% off, async 15-45 min turnaround)",
    )
    parser.add_argument(
        "--task", type=str, default=None,
        help="Task description for --mode plan",
    )
    parser.add_argument(
        "--task-file", type=str, default=None,
        help="Read task description from file for --mode plan",
    )
    parser.add_argument(
        "--files", nargs="+", default=None,
        help="Explicit file list to review (overrides git detection)",
    )
    parser.add_argument(
        "--verbose", action="store_true",
        help="Print token usage and cost estimate after each call",
    )
    parser.add_argument(
        "--spend", action="store_true",
        help="View current cumulative spend and remaining budget without calling API",
    )

    args = parser.parse_args()

    if args.spend:
        show_budget_status()
        return 0

    if not args.mode:
        print("ERROR: --mode {plan,review,landing} or --spend is required.", file=sys.stderr)
        return 2

    # Validate arguments
    if args.mode == "plan":
        task = args.task
        if args.task_file:
            task_path = Path(args.task_file)
            if not task_path.exists():
                print(f"ERROR: Task file not found: {args.task_file}", file=sys.stderr)
                sys.exit(2)
            task = task_path.read_text(encoding="utf-8")
        if not task:
            print("ERROR: --mode plan requires --task or --task-file", file=sys.stderr)
            sys.exit(2)
        return mode_plan(task, batch=args.batch, verbose=args.verbose)

    elif args.mode == "review":
        return mode_review(
            file_list=args.files, batch=args.batch, verbose=args.verbose,
        )

    elif args.mode == "landing":
        return mode_landing(batch=args.batch, verbose=args.verbose)


if __name__ == "__main__":
    sys.exit(main())
