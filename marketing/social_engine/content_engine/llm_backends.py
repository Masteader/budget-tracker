"""The two routes to Claude: `claude -p` and the Anthropic SDK (spec Section 6.3, D9, D10, D20).

Claude only. A backend takes an `LlmRequest` and returns validated output, or raises one of the
errors below. Which tools a run gets follows from its step and nothing else: research gets web
search and fetch, and writing and review get none. Everything a run returns is treated as data.

The `claude` subprocess starts with an allowlisted environment, which still holds HOME and
USERPROFILE because login needs them. So user-level MCP servers and settings stay reachable by
path, and only `--strict-mcp-config` and an empty `--setting-sources` keep them out. The working
folder must be empty and outside the repo, or `-p` would load its hooks, servers and CLAUDE.md.

Spec Section 6.3 gives `--output-format json`, which carries no tool log, while Section 6.4 needs
one. So research alone uses `stream-json --verbose`, the documented way to see tool calls (decision
D34). Its `system/init` event also shows which tools and MCP servers the run was given. Anything in
that stream the code does not recognise fails the run. All flags stay subject to LIVE-2.

WebFetch under `claude -p` hands back what a small model made of the page, not the page. So
`ToolCall.text` proves what the run was told a page said, and nothing about the page itself (spec
Section 6.4). The Anthropic API route returns the fetched text as it is.
"""

from __future__ import annotations

import json
import math
import os
import re
import subprocess
import tempfile
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal, Protocol

from pydantic import BaseModel, ValidationError

from core.config import EngineConfig, Llm
from core.paths import EnginePaths, PathConfigError, expand_path, resolve_data_root
from core.secrets import check_startup_environment, load_env_file, scrubbed_env

Step = Literal["research", "write", "review"]
ToolName = Literal["web_search", "web_fetch"]

_STEPS = ("research", "write", "review")
_API_KEY_VAR = "ANTHROPIC_API_KEY"
_CLAUDE_ALIASES = {
    "opus": "claude-opus-5-5",
    "sonnet": "claude-sonnet-5-5",
    "haiku": "claude-haiku-5-5",
    "fable": "claude-fable-5-1",
}
_CLAUDE_MODEL_ID = re.compile(r"claude-[a-z0-9][a-z0-9.\-]*")


class LlmError(Exception):
    """Base of everything a backend raises. Messages carry no prompt, page or model text."""


class LlmRunFailed(LlmError):
    """This try failed and another may work. Counts against the retry budget."""


class UsageLimitReached(LlmError):
    """Plan or credit limit. Wait for a later tick, send one notice. Not counted as a failure."""


class LoginExpired(LlmError):
    """The login or key no longer works. The owner has to act, so retrying now is pointless."""


class BudgetExceeded(LlmError):
    """`llm.max_budget_usd` is used up, or the spend cannot be proved to be within it."""


class LlmSetupError(LlmError):
    """The run must not start as configured. Retrying cannot help."""


class SpendTracker:
    """What one reel's Claude runs have cost, across steps and retries, against the cap."""

    def __init__(self, limit_usd: float) -> None:
        self.limit_usd = limit_usd
        self.spent_usd = 0.0

    def remaining(self) -> float:
        return self.limit_usd - self.spent_usd

    def add(self, cost_usd: float) -> None:
        self.spent_usd += cost_usd
        if self.spent_usd > self.limit_usd:
            raise BudgetExceeded(
                f"spent ${self.spent_usd:.4f} of the ${self.limit_usd:.2f} cap, output discarded"
            )

    def require_headroom(self, minimum_usd: float) -> None:
        if self.remaining() < minimum_usd:
            raise BudgetExceeded(f"the ${self.limit_usd:.2f} cap is used up")


def spend_for_reel(config: EngineConfig) -> SpendTracker:
    """One per reel, so `llm.max_budget_usd` covers every step and every retry of that reel."""
    return SpendTracker(config.llm.max_budget_usd)


@dataclass(frozen=True)
class LlmRequest:
    """`instructions` are ours and trusted. `data` holds anything that came from outside."""

    step: Step
    instructions: str
    data: str
    schema: type[BaseModel]

    def __post_init__(self) -> None:
        if self.step not in _STEPS:
            raise ValueError(f"unknown step: {self.step!r}")

    @property
    def uses_web(self) -> bool:
        return self.step == "research"


@dataclass(frozen=True)
class ToolCall:
    """One web tool call in a run. `text` is untrusted and kept for the copy check. Under
    `claude_cli` it is a model's summary of the page, not the page (spec Section 6.4)."""

    name: ToolName
    url: str | None
    text: str
    succeeded: bool


@dataclass(frozen=True)
class LlmResult:
    output: Any  # an instance of the request's schema
    tool_log: tuple[ToolCall, ...]
    cost_usd: float | None


class LlmBackend(Protocol):
    def run(self, request: LlmRequest, spend: SpendTracker) -> LlmResult: ...


def _is_claude_model(model: str) -> bool:
    return model in _CLAUDE_ALIASES or bool(_CLAUDE_MODEL_ID.fullmatch(model))


def _check_model(model: str) -> None:
    # Config validation already refuses these. The backends check again, because this is the
    # last point before a name reaches a command line or a request.
    if not _is_claude_model(model):
        raise LlmSetupError(f"Claude models only (decision D9), got {model[:40]!r}")


def _env_value(env: Mapping[str, str], name: str) -> str:
    return next((value for key, value in env.items() if key.upper() == name), "")


def _validated(schema: type[BaseModel], raw: Any) -> BaseModel:
    try:
        return schema.model_validate(raw)
    except ValidationError as error:
        # str(error) quotes the input, which is model output.
        raise LlmRunFailed(
            f"output does not match the schema: {error.error_count()} errors"
        ) from None


# --- `claude -p` -------------------------------------------------------------------------

_WEB_TOOLS_FLAG = "WebSearch,WebFetch"
_CLI_TOOL_NAMES: dict[str, ToolName] = {"WebSearch": "web_search", "WebFetch": "web_fetch"}
_STRUCTURED_OUTPUT_TOOL = "StructuredOutput"  # how `--json-schema` returns its answer
_MCP_TOOL_PREFIX = "mcp__"
_TOOLS_A_RESEARCH_RUN_MAY_HOLD = {*_CLI_TOOL_NAMES, _STRUCTURED_OUTPUT_TOOL}
_ASSISTANT_BLOCKS = {"text", "thinking", "redacted_thinking", "tool_use"}
_USER_BLOCKS = {"text", "tool_result"}
_TIMEOUT_SECONDS = 900
_KILL_SECONDS = 10
_MAX_COMMAND_CHARS = 32_000  # Windows stops at 32,767 characters and calls it WinError 206
_SMALLEST_FLAG_BUDGET = 0.01
_USAGE_ERRORS = {"rate_limit", "billing_error"}
_LOGIN_ERRORS = {"authentication_failed", "oauth_org_not_allowed"}
_USAGE_WORDS = (
    "hit your",
    "usage limit",
    "spend limit",
    "credit balance",
    "usage credits required",
    "temporarily limiting requests",
    "request rejected (429)",
)
_LOGIN_WORDS = (
    "/login",
    "not logged in",
    "login expired",
    "authentication required",
    "could not resolve authentication",
    "invalid api key",
    "invalid auth token",
    "oauth token",
    "invalid authentication credentials",
    "does not have access to claude",
)
_NPM_EXE = Path("node_modules", "@anthropic-ai", "claude-code", "bin", "claude.exe")


def _find_claude_exe(env: Mapping[str, str]) -> Path | None:
    """Only absolute PATH entries, so a `claude.exe` planted in the current folder is not found.
    An npm install puts just a batch shim on PATH, with the real executable beneath it."""
    for entry in _env_value(env, "PATH").split(os.pathsep):
        folder = Path(entry)
        if not entry or not folder.is_absolute():
            continue
        if (folder / "claude.exe").is_file():
            return folder / "claude.exe"
        if (folder / "claude.cmd").is_file() and (folder / _NPM_EXE).is_file():
            return folder / _NPM_EXE
    return None


def _resolve_claude_path(llm: Llm, env: Mapping[str, str], *, scheduled: bool) -> Path:
    if not llm.claude_path.strip():
        found = None if scheduled else _find_claude_exe(env)
        if found is None:
            raise LlmSetupError("set llm.claude_path to the absolute path of claude.exe")
        return found
    try:
        path = expand_path(llm.claude_path, env)
    except PathConfigError as error:
        raise LlmSetupError(f"llm.claude_path: {error}") from error
    if not path.is_absolute():
        raise LlmSetupError(f"llm.claude_path must be absolute, got {llm.claude_path!r}")
    # cmd.exe parses a batch file's arguments again, so page text in a prompt could run as a
    # command there. Only a real executable receives its arguments untouched.
    if path.suffix.casefold() != ".exe":
        raise LlmSetupError(f"llm.claude_path must be an .exe, got {path.name!r}")
    if not path.is_file():
        raise LlmSetupError(f"llm.claude_path not found: {path}")
    return path


def _ready_working_folder(folder: Path) -> Path:
    try:
        real = resolve_data_root(str(folder))
    except PathConfigError as error:
        raise LlmSetupError(f"claude_cwd is not allowed: {error}") from error
    try:
        real.mkdir(parents=True, exist_ok=True)
        if any(real.iterdir()):
            raise LlmSetupError(f"claude_cwd must be empty: {real}")
    except OSError as error:
        raise LlmSetupError(f"claude_cwd cannot be used: {error}") from error
    return real


def _usable_cost(result: Mapping[str, Any]) -> float | None:
    cost = result.get("total_cost_usd")
    if isinstance(cost, bool) or not isinstance(cost, int | float):
        return None
    try:
        value = float(cost)
    except OverflowError:
        return None
    return value if math.isfinite(value) and value >= 0 else None


def _parse_events(stdout: str, *, streaming: bool) -> tuple[list[dict[str, Any]], bool]:
    """The events that could be read, and whether every line could. A page quoted in a tool result
    stays inside one JSON-encoded line, so it cannot pose as an event. Only a newline ends a line:
    JSON.stringify leaves U+2028 and its like raw in a string, and `str.splitlines` would break
    the line there."""
    lines = stdout.split("\n") if streaming else [stdout]
    events: list[dict[str, Any]] = []
    whole = True
    for line in lines:
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except ValueError, RecursionError:
            whole = False
            continue
        if isinstance(event, dict):
            events.append(event)
        else:
            whole = False
    return events, whole


def _kill_tree(process: subprocess.Popen[bytes]) -> None:
    """A child of `claude` would outlive `process.kill()`. The full path keeps a `taskkill` planted
    on PATH out of it."""
    taskkill = Path(os.environ.get("SYSTEMROOT", r"C:\Windows"), "System32", "taskkill.exe")
    try:
        subprocess.run(
            [str(taskkill), "/PID", str(process.pid), "/T", "/F"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=_KILL_SECONDS,
            check=False,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    except OSError, subprocess.SubprocessError:
        pass
    process.kill()
    try:
        process.wait(timeout=_KILL_SECONDS)
    except subprocess.TimeoutExpired:
        pass


def _run_claude(
    argv: list[str], *, cwd: Path, env: Mapping[str, str], timeout: float
) -> subprocess.CompletedProcess[bytes]:
    """Output goes to files, not pipes. A pipe stays open as long as any descendant holds it, so
    `subprocess.run` would wait for that descendant long after the timeout. The files are outside
    the working folder, which must stay empty, and are gone when this returns."""
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        process = subprocess.Popen(
            argv,
            cwd=cwd,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=out,
            stderr=err,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            _kill_tree(process)
            raise
        out.seek(0)
        err.seek(0)
        return subprocess.CompletedProcess(argv, code, out.read(), err.read())


def _failure_for(
    result: Mapping[str, Any], events: list[dict[str, Any]], stderr: str
) -> LlmError | None:
    """Only called for a run that really failed, so model text in a normal result that merely
    says "please run /login" cannot trigger these."""
    if result.get("subtype") == "error_max_budget_usd":
        return BudgetExceeded("the run stopped at --max-budget-usd")
    errors = {
        event["error"]
        for event in events
        if event.get("type") == "assistant" and isinstance(event.get("error"), str)
    }
    status = result.get("api_error_status")
    listed = result.get("errors")
    texts = [result.get("result"), *(listed if isinstance(listed, list) else []), stderr]
    text = " ".join(item for item in texts if isinstance(item, str)).casefold()
    if status == 429 or errors & _USAGE_ERRORS or any(word in text for word in _USAGE_WORDS):
        return UsageLimitReached("Claude usage limit reached")
    if status == 401 or errors & _LOGIN_ERRORS or any(word in text for word in _LOGIN_WORDS):
        return LoginExpired("Claude login or key failed. Run /login, or check the key")
    return None


def _blocks_of(event: Mapping[str, Any]) -> list[dict[str, Any]]:
    message = event.get("message")
    content = message.get("content") if isinstance(message, dict) else None
    return (
        [block for block in content if isinstance(block, dict)] if isinstance(content, list) else []
    )


def _result_text(block: Mapping[str, Any]) -> str:
    content = block.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(
            part["text"]
            for part in content
            if isinstance(part, dict) and isinstance(part.get("text"), str)
        )
    return ""


def _tool_log_from(events: list[dict[str, Any]]) -> tuple[ToolCall, ...]:
    """Refuses the whole run if any tool but web search and fetch was used. A page that talks
    the model into trying something else then costs a try, and nothing else."""
    calls: dict[str, dict[str, Any]] = {}
    outcomes: dict[str, tuple[str, bool]] = {}
    for event in events:
        kind = event.get("type")
        if kind == "assistant":
            for block in _blocks_of(event):
                if block.get("type") not in _ASSISTANT_BLOCKS:
                    raise LlmRunFailed("the reply held a block this step does not know")
                if block.get("type") == "tool_use":
                    name = block.get("name")
                    known = name == _STRUCTURED_OUTPUT_TOOL or (
                        isinstance(name, str) and name in _CLI_TOOL_NAMES
                    )
                    if not known:
                        raise LlmRunFailed("the run used a tool outside web search and fetch")
                    calls[str(block.get("id"))] = block
        elif kind == "user":
            if any(block.get("type") not in _USER_BLOCKS for block in _blocks_of(event)):
                raise LlmRunFailed("a tool answer held a block this step does not know")
            results = [b for b in _blocks_of(event) if b.get("type") == "tool_result"]
            details = event.get("tool_use_result")
            code = details.get("code") if isinstance(details, dict) and len(results) == 1 else None
            for block in results:
                http_ok = not isinstance(code, int) or 200 <= code < 300
                outcome = (_result_text(block), http_ok and not block.get("is_error"))
                outcomes[str(block.get("tool_use_id"))] = outcome
    log = []
    for tool_id, block in calls.items():
        tool = _CLI_TOOL_NAMES.get(block["name"])
        if tool is None:
            continue
        tool_input = block.get("input")
        url = tool_input.get("url") if isinstance(tool_input, dict) else None
        text, succeeded = outcomes.get(tool_id, ("", False))
        log.append(ToolCall(tool, url if isinstance(url, str) else None, text, succeeded))
    return tuple(log)


def _check_isolation(events: list[dict[str, Any]]) -> None:
    """What the run was offered, not only what it used. Fails on anything it cannot read."""
    inits = [e for e in events if e.get("type") == "system" and e.get("subtype") == "init"]
    if not inits:
        raise LlmRunFailed("no init event, so the run's isolation cannot be confirmed")
    for init in inits:
        tools = init.get("tools")
        named = tools if isinstance(tools, list) else []
        if init.get("mcp_servers") != [] or any(
            str(tool).startswith(_MCP_TOOL_PREFIX) for tool in named
        ):
            raise LlmRunFailed("an MCP server was present despite --strict-mcp-config")
        if not isinstance(tools, list) or any(
            not isinstance(tool, str) or tool not in _TOOLS_A_RESEARCH_RUN_MAY_HOLD
            for tool in tools
        ):
            raise LlmRunFailed("the run was offered a tool outside web search and fetch")


class ClaudeCliBackend:
    def __init__(
        self, llm: Llm, claude_cwd: Path, *, env: Mapping[str, str], scheduled: bool = False
    ) -> None:
        _check_model(llm.model)
        if scheduled and llm.auth == "subscription":
            raise LlmSetupError(
                "a scheduled run cannot use auth: subscription (decision D20). Set llm.auth: "
                "api_key, or start the run by hand"
            )
        self._env = scrubbed_env(llm.auth, env)
        self._uses_api_key = llm.auth == "api_key"
        # With no key, `claude -p` would quietly fall back to the plan's login.
        if self._uses_api_key and not _env_value(self._env, _API_KEY_VAR).strip():
            raise LlmSetupError(f"auth: api_key needs {_API_KEY_VAR} in the .env file")
        self._llm = llm
        self._cwd = claude_cwd
        self._exe = _resolve_claude_path(llm, env, scheduled=scheduled)

    def _argv(self, request: LlmRequest, spend: SpendTracker) -> list[str]:
        web = request.uses_web
        argv = [
            str(self._exe),
            "-p",
            f"{request.instructions}\n\n{request.data}",
            "--model",
            self._llm.model,
            "--output-format",
            *(["stream-json", "--verbose"] if web else ["json"]),
            "--json-schema",
            json.dumps(request.schema.model_json_schema()),
            "--tools",
            _WEB_TOOLS_FLAG if web else "",
            *(["--allowedTools", _WEB_TOOLS_FLAG] if web else []),
            "--permission-prompts",
            "none",
            "--strict-mcp-config",
            "--setting-sources",
            "",
            "--no-session-persistence",
            "--max-turns",
            str(self._llm.max_turns),
        ]
        if self._uses_api_key:
            cents = math.floor(spend.remaining() * 100)
            argv += ["--max-budget-usd", f"{cents / 100:.2f}"]
        return argv

    def _unknown_spend(self, reason: str) -> LlmError:
        """With a key, a run whose cost cannot be read could have spent anything, so a retry
        could pass the cap. On the plan, no money moves and the try simply failed."""
        if self._uses_api_key:
            return BudgetExceeded(f"the cost of this run is unknown ({reason})")
        return LlmRunFailed(reason)

    def run(self, request: LlmRequest, spend: SpendTracker) -> LlmResult:
        if self._uses_api_key:
            spend.require_headroom(_SMALLEST_FLAG_BUDGET)
        cwd = _ready_working_folder(self._cwd)
        argv = self._argv(request, spend)
        if argv[2].startswith("-"):
            raise LlmSetupError("a prompt must not start with a dash, or it reads as a flag")
        if len(subprocess.list2cmdline(argv)) > _MAX_COMMAND_CHARS:
            raise LlmSetupError("the prompt is too long for a Windows command line")
        try:
            completed = _run_claude(argv, cwd=cwd, env=self._env, timeout=_TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired:
            raise self._unknown_spend(f"timed out after {_TIMEOUT_SECONDS} s") from None
        except (OSError, ValueError) as error:
            raise LlmSetupError(f"claude could not start: {type(error).__name__}") from error
        return self._read_outcome(completed, request, spend)

    def _read_outcome(
        self,
        completed: subprocess.CompletedProcess[bytes],
        request: LlmRequest,
        spend: SpendTracker,
    ) -> LlmResult:
        stderr = completed.stderr.decode("utf-8", "replace")
        code = completed.returncode
        try:
            stdout = completed.stdout.decode("utf-8")
        except UnicodeDecodeError:
            raise self._unknown_spend("output is not UTF-8") from None
        events, whole = _parse_events(stdout, streaming=request.uses_web)
        result = next((e for e in reversed(events) if e.get("type") == "result"), None)
        if result is None:
            known = _failure_for({}, [], stderr) if code else None
            raise known or self._unknown_spend(f"exit {code}, and no result event at the end")

        # The cost comes first, so a stream that fails below still counts what it spent.
        cost = _usable_cost(result)
        if self._uses_api_key and cost is not None:
            spend.add(cost)
        if code != 0 or result.get("is_error") is not False or result.get("subtype") != "success":
            subtype = str(result.get("subtype"))[:40]
            known = _failure_for(result, events, stderr)
            if known is not None:
                raise known
            if cost is None:
                raise self._unknown_spend(f"exit {code}, {subtype}")
            raise LlmRunFailed(f"exit {code}, {subtype}")
        if self._uses_api_key and cost is None:
            raise BudgetExceeded("the run reported no usable cost, so the cap cannot be proved")
        if cost is None and result.get("total_cost_usd") is not None:
            raise LlmRunFailed("the run reported a cost that cannot be read")
        if not whole or events[-1] is not result:
            raise LlmRunFailed("the stream did not end cleanly in its result")

        if result.get("permission_denials"):
            raise LlmRunFailed("a tool call was denied, so the run went outside its job")
        tool_log: tuple[ToolCall, ...] = ()
        if request.uses_web:
            _check_isolation(events)
            tool_log = _tool_log_from(events)
        output = result.get("structured_output")
        if not isinstance(output, dict):
            raise LlmRunFailed("the result holds no structured_output")
        return LlmResult(_validated(request.schema, output), tool_log, cost)


# --- The Anthropic SDK -------------------------------------------------------------------

_API_BASE_URL = "https://api.anthropic.com"
_EFFORT = "high"
_MAX_TOKENS = 32_000
_SMALLEST_USEFUL_REPLY = 1024
_WEB_TOOLS = (
    {"type": "web_search_20260209", "name": "web_search", "max_uses": 5},
    {
        "type": "web_fetch_20260209",
        "name": "web_fetch",
        "max_uses": 8,
        "max_content_tokens": 20_000,
    },
)
_LOGGED_SERVER_TOOLS: dict[str, ToolName] = {"web_search": "web_search", "web_fetch": "web_fetch"}
# web_search_20260209 and web_fetch_20260209 filter results by running code on the server.
_SERVER_TOOLS_ALLOWED = {
    *_LOGGED_SERVER_TOOLS,
    "code_execution",
    "bash_code_execution",
    "text_editor_code_execution",
}
_CLIENT_TOOL_BLOCKS = {"tool_use", "mcp_tool_use"}
# Dollars per million tokens, input then output (checked 2026-10-06). Claude Haiku 5.5 is at its
# higher rate for prompts over 100K tokens, and a name not listed here at the highest rate of
# all, so the cap errs towards stopping early.
_PRICES = {
    "claude-fable-5-1": (10.0, 50.0),
    "claude-fable-5": (10.0, 50.0),
    "claude-opus-5-5": (4.0, 20.0),
    "claude-opus-5": (5.0, 25.0),
    "claude-opus-4-8": (5.0, 25.0),
    "claude-opus-4-7": (5.0, 25.0),
    "claude-opus-4-6": (5.0, 25.0),
    "claude-sonnet-5-5": (2.0, 10.0),
    "claude-sonnet-5": (2.0, 10.0),
    "claude-sonnet-4-6": (3.0, 15.0),
    "claude-haiku-5-5": (0.5, 2.5),
    "claude-haiku-4-5": (1.0, 5.0),
}
_HIGHEST_PRICE = (10.0, 50.0)
_CACHE_WRITE_FACTOR = 1.25
_CACHE_READ_FACTOR = 0.1
_USD_PER_WEB_SEARCH = 0.01


def _cost_of(model: str, usage: Any) -> float:
    input_price, output_price = _PRICES.get(model, _HIGHEST_PRICE)
    tokens = (
        (usage.input_tokens or 0) * input_price
        + (usage.cache_creation_input_tokens or 0) * input_price * _CACHE_WRITE_FACTOR
        + (usage.cache_read_input_tokens or 0) * input_price * _CACHE_READ_FACTOR
        + (usage.output_tokens or 0) * output_price
    )
    server_tools = getattr(usage, "server_tool_use", None)
    searches = (server_tools.web_search_requests or 0) if server_tools else 0
    return tokens / 1_000_000 + searches * _USD_PER_WEB_SEARCH


def _api_call_result(block: Any, call: Any) -> ToolCall:
    """Server-tool errors arrive as an object in `content` with HTTP 200, and do not raise."""
    content = block.content
    if call.name == "web_search":
        return ToolCall("web_search", None, "", isinstance(content, list))
    if getattr(content, "type", None) != "web_fetch_result":
        return ToolCall("web_fetch", call.input.get("url"), "", False)
    source = getattr(content.content, "source", None)
    text = source.data if getattr(source, "type", None) == "text" else ""
    return ToolCall("web_fetch", content.url, text, True)


def _tool_calls_in(content: list[Any], *, web: bool) -> tuple[ToolCall, ...]:
    calls = {}
    log = []
    for block in content:
        kind = block.type
        if kind in _CLIENT_TOOL_BLOCKS:
            raise LlmRunFailed("the reply used a tool outside web search and fetch")
        if kind == "server_tool_use":
            if not web or block.name not in _SERVER_TOOLS_ALLOWED:
                raise LlmRunFailed("the reply used a tool this step may not have")
            calls[block.id] = block
        elif kind in {"web_search_tool_result", "web_fetch_tool_result"}:
            call = calls.get(block.tool_use_id)
            if call is not None and call.name in _LOGGED_SERVER_TOOLS:
                log.append(_api_call_result(block, call))
    return tuple(log)


def _final_output(content: list[Any]) -> Any:
    texts = [block.text for block in content if block.type == "text"]
    if not texts:
        raise LlmRunFailed("the reply holds no text")
    try:
        output = json.loads(texts[-1])
    except ValueError, RecursionError:
        raise LlmRunFailed("the reply is not valid JSON") from None
    if not isinstance(output, dict):
        raise LlmRunFailed("the reply is not a JSON object")
    return output


class AnthropicApiBackend:
    def __init__(self, llm: Llm, client: Any) -> None:
        _check_model(llm.model)
        self._llm = llm
        self._model = _CLAUDE_ALIASES.get(llm.model, llm.model)
        self.client = client

    def _max_tokens(self, spend: SpendTracker) -> int:
        """Holds back output the budget could not pay for, so the cap also acts in advance."""
        _, output_price = _PRICES.get(self._model, _HIGHEST_PRICE)
        affordable = int(spend.remaining() / output_price * 1_000_000)
        if affordable < _SMALLEST_USEFUL_REPLY:
            raise BudgetExceeded("too little of the cap is left for a useful reply")
        return min(affordable, _MAX_TOKENS)

    def _ask(self, spend: SpendTracker, **settings: Any) -> Any:
        import anthropic

        try:
            with self.client.messages.stream(
                max_tokens=self._max_tokens(spend), **settings
            ) as live:
                return live.get_final_message()
        except anthropic.RateLimitError:
            raise UsageLimitReached("API rate or usage limit reached") from None
        except anthropic.AuthenticationError, anthropic.PermissionDeniedError:
            raise LoginExpired("the API key was refused") from None
        except anthropic.BadRequestError as error:
            if "credit balance" in str(error).casefold():
                raise UsageLimitReached("API credits have run out") from None
            raise LlmRunFailed("the API refused the request") from error
        except anthropic.AnthropicError as error:
            raise LlmRunFailed(f"API call failed: {type(error).__name__}") from error

    def run(self, request: LlmRequest, spend: SpendTracker) -> LlmResult:
        settings: dict[str, Any] = {
            "model": self._model,
            "system": request.instructions,
            "thinking": {"type": "adaptive"},
            "output_config": {
                "effort": _EFFORT,
                "format": {"type": "json_schema", "schema": _api_schema(request.schema)},
            },
        }
        if request.uses_web:
            settings["tools"] = [dict(tool) for tool in _WEB_TOOLS]
        messages: list[dict[str, Any]] = [{"role": "user", "content": request.data}]
        tool_log: list[ToolCall] = []
        total_cost = 0.0
        for _ in range(self._llm.max_turns):
            reply = self._ask(spend, messages=messages, **settings)
            if reply.usage is None:
                raise BudgetExceeded("the reply has no usage, so the cap cannot be proved")
            cost = _cost_of(self._model, reply.usage)
            total_cost += cost
            spend.add(cost)
            # No server-side fallback model: a refusal costs a try, and the cost stays predictable.
            if reply.stop_reason == "refusal":
                raise LlmRunFailed("Claude refused the request")
            tool_log.extend(_tool_calls_in(reply.content, web=request.uses_web))
            if reply.stop_reason == "pause_turn":
                messages.append({"role": "assistant", "content": reply.content})
                continue
            if reply.stop_reason != "end_turn":
                raise LlmRunFailed(f"the reply stopped early: {reply.stop_reason}")
            output = _validated(request.schema, _final_output(reply.content))
            return LlmResult(output, tuple(tool_log), total_cost)
        raise LlmRunFailed("the run kept pausing and never finished")


def _api_schema(schema: type[BaseModel]) -> dict[str, Any]:
    """The API refuses some JSON Schema constraints, and the SDK moves those into descriptions.
    The local validation still applies them."""
    from anthropic import transform_schema

    return transform_schema(schema)


def _real_client(api_key: str) -> Any:
    from anthropic import Anthropic

    # The address is explicit, so ANTHROPIC_BASE_URL cannot send the key somewhere else.
    return Anthropic(api_key=api_key, base_url=_API_BASE_URL)


def make_backend(
    config: EngineConfig,
    paths: EnginePaths,
    *,
    scheduled: bool = False,
    env: Mapping[str, str] | None = None,
    client_factory: Callable[[str], Any] = _real_client,
) -> LlmBackend:
    """`scheduled` is true for a run started by Task Scheduler, which refuses the plan's login."""
    merged = {**(os.environ if env is None else env), **load_env_file(paths.data_root)}
    check_startup_environment(merged)
    if config.llm.backend == "claude_cli":
        return ClaudeCliBackend(config.llm, paths.claude_cwd, env=merged, scheduled=scheduled)
    key = _env_value(merged, _API_KEY_VAR).strip()
    if not key:
        raise LlmSetupError(f"backend anthropic_api needs {_API_KEY_VAR} in the .env file")
    _check_model(config.llm.model)
    return AnthropicApiBackend(config.llm, client_factory(key))
