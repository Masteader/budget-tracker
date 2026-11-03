"""The backend's display name is Qawam Money (Arabic: قوام المال, Urdu: Qawam Money in Latin letters).

Three groups of tests:
- every user-visible surface shows the new name;
- a guard scans the backend's own modules so the old or the withdrawn name cannot come back;
- the technical identifiers that merely contain the old name stay exactly as they are: renaming
  them would break deep links or invalidate open preview tokens.

``static/`` (built web output) is out of scope here: it is refreshed from ``web_app``.
"""

from __future__ import annotations

import ast
import base64
import hashlib
import pathlib
import re
import zlib
from email.utils import parseaddr
from unittest.mock import MagicMock, patch

import pytest

import landing_page
import mail_service
import preview_token
import support_agent
from main import app
from pdf_statement_generator import generate_monthly_pdf_statement
from routes.inquiries import _compose

NAME_EN = "Qawam Money"
NAME_AR = "قوام المال"
SENDER_ADDRESS = "fmscoinfo@fmsco.com.sa"

SERVICE_DIR = pathlib.Path(__file__).resolve().parent.parent
BACKEND_MODULES = sorted([*SERVICE_DIR.glob("*.py"), *(SERVICE_DIR / "routes").glob("*.py")])
# Whole-file checks (comments and docstrings too) for the files that carried the name.
RENAMED_FILES = [
    "support_agent.py",
    "pdf_statement_generator.py",
    "mail_service.py",
    "routes/inquiries.py",
    "landing_page.py",
    "main.py",
    ".env.example",
]


def _read(relative: str) -> str:
    return (SERVICE_DIR / relative).read_text(encoding="utf-8")


# ── Support assistant ───────────────────────────────────────────────────────────


@pytest.mark.parametrize("payday", [None, 27])
@pytest.mark.parametrize(
    "lang, expected",
    [("en", NAME_EN), ("ar", NAME_AR), ("ar", NAME_EN), ("ur", NAME_EN)],
)
def test_support_prompt_names_the_app_in_every_language(lang, expected, payday):
    assert expected in support_agent.build_support_prompt(lang, payday)


@pytest.mark.parametrize("lang", ["en", "ar", "ur"])
def test_support_prompt_tells_the_assistant_how_to_answer_about_the_name(lang):
    prompt = support_agent.build_support_prompt(lang, None)
    first_line = prompt.splitlines()[0]
    assert first_line.startswith(f"You are the AI Support Assistant for {NAME_EN}")
    assert "asked what the app is called" in prompt
    assert "any other name" in prompt


def test_arabic_prompt_requires_the_arabic_name_in_arabic_replies():
    prompt = support_agent.build_support_prompt("ar", None)
    assert f"answer {NAME_AR}" in prompt


def test_urdu_prompt_keeps_the_name_in_latin_letters():
    prompt = support_agent.build_support_prompt("ur", None)
    assert "Latin letters" in prompt
    assert "never transliterate" in prompt
    # No Urdu or Arabic script form of the name may be offered to the model to copy.
    assert "قوام" not in prompt


@pytest.mark.asyncio
@pytest.mark.parametrize("lang, expected", [("en", NAME_EN), ("ar", NAME_AR), ("ur", NAME_EN)])
async def test_support_model_receives_the_name_in_its_system_prompt(lang, expected):
    choice = MagicMock()
    choice.message.content = "[ESCALATE: FALSE]\n[SUMMARY: NONE]\nok"
    response = MagicMock(choices=[choice])
    with patch("support_agent.litellm.completion", return_value=response) as completion:
        await support_agent.handle_support_query(message="What is this app called?", language=lang)
    system = completion.call_args.kwargs["messages"][0]
    assert system["role"] == "system"
    assert expected in system["content"]


@pytest.mark.parametrize("payday", [None, 27])
@pytest.mark.parametrize("lang, expected", [("en", NAME_EN), ("ar", NAME_AR), ("ur", NAME_EN)])
def test_support_fallback_welcome_names_the_app(lang, expected, payday):
    assert expected in support_agent.general_fallback(lang, payday)


def test_urdu_fallback_has_no_script_form_of_either_name():
    reply = support_agent.general_fallback("ur", None)
    assert "قوام" not in reply
    assert "بجٹ" not in reply
    assert "ٹریکر" not in reply


@pytest.mark.asyncio
@pytest.mark.parametrize("lang, expected", [("en", NAME_EN), ("ar", NAME_AR), ("ur", NAME_EN)])
async def test_support_reply_names_the_app_when_the_model_is_unavailable(lang, expected):
    # conftest blocks every real LLM call, so this reply is the fallback path.
    reply, escalate, _ = await support_agent.handle_support_query(message="hello", language=lang)
    assert escalate is False
    assert expected in reply


# ── PDF statement ───────────────────────────────────────────────────────────────


def _rendered_pdf_text(pdf: bytes) -> str:
    """The decoded content streams of a reportlab PDF (ASCII85 + Flate), latin-1 for byte safety."""
    decoded = []
    for raw in re.findall(rb"stream\r?\n(.*?)\r?\n?endstream", pdf, re.DOTALL):
        try:
            data = base64.a85decode(raw.strip().removesuffix(b"~>"))
            decoded.append(zlib.decompress(data).decode("latin-1"))
        except ValueError:
            continue
        except zlib.error:
            continue
    return "\n".join(decoded)


@pytest.fixture
def statement_text():
    empty = MagicMock()
    empty.data = []
    chain = MagicMock()
    for method in ("select", "eq", "gte", "lte", "order"):
        getattr(chain, method).return_value = chain
    chain.execute.return_value = empty
    client = MagicMock()
    client.table.return_value = chain
    cycle = {"cycle_key": "2026-09", "label": "Sep 2026", "cycle_start": "2026-08-27", "cycle_end": "2026-09-26"}
    with (
        patch("pdf_statement_generator.get_client", return_value=client),
        patch("pdf_statement_generator.get_household_payday", return_value=27),
        patch("pdf_statement_generator.get_cycle_info_for_key", return_value=cycle),
    ):
        return _rendered_pdf_text(generate_monthly_pdf_statement("household-1", cycle_key="2026-09"))


def test_pdf_header_shows_the_new_name(statement_text):
    assert "QAWAM MONEY" in statement_text
    assert "FINANCIAL STATEMENT" in statement_text


def test_pdf_footer_shows_the_new_name(statement_text):
    assert f"{NAME_EN} KSA" in statement_text


def test_pdf_does_not_show_the_old_name(statement_text):
    assert "budget tracker" not in statement_text.lower()


def test_pdf_generator_keeps_the_name_latin_because_its_fonts_cannot_shape_arabic():
    # Only the built-in Helvetica faces are used, with no Arabic font, reshaper or bidi step, so
    # Arabic letters would print as empty boxes. Replace this test when that support is added.
    source = _read("pdf_statement_generator.py")
    assert "registerFont" not in source
    assert "arabic_reshaper" not in source
    assert NAME_AR not in source


# ── Mail ────────────────────────────────────────────────────────────────────────


def test_default_sender_changes_the_display_name_only():
    assert parseaddr(mail_service.DEFAULT_SENDER) == (NAME_EN, SENDER_ADDRESS)


def test_mail_service_docstring_matches_the_default_sender():
    assert f'default "{mail_service.DEFAULT_SENDER}"' in (mail_service.__doc__ or "").replace("\n", " ")


def test_inquiry_email_subject_and_body_use_the_new_name():
    message = _compose(
        inquiry_type="support",
        reference="ref-1",
        reply_to="user@example.com",
        subject_identity="user@example.com",
        fields=[],
        message=None,
    )
    assert message.subject == f"[{NAME_EN}] Support — user@example.com"
    assert message.body.splitlines()[0] == f"New Support request from {NAME_EN}"


def test_env_example_sender_changes_the_display_name_only():
    lines = _read(".env.example").splitlines()
    mail_from = next(line for line in lines if line.startswith("MAIL_FROM="))
    assert parseaddr(mail_from.split("=", 1)[1]) == (NAME_EN, SENDER_ADDRESS)
    assert any(line.startswith(f"# {NAME_EN} ") for line in lines[:5])


# ── HTML pages and the API docs ─────────────────────────────────────────────────


def test_fallback_landing_page_shows_both_forms_of_the_name():
    html = landing_page.FALLBACK_LANDING_HTML
    assert f"<title>{NAME_EN} • {NAME_AR}</title>" in html
    assert f"<h1>{NAME_EN} • {NAME_AR}</h1>" in html
    assert "ميزانية الأسرة" not in html


def test_auth_page_titles_use_the_arabic_name():
    html = landing_page.AUTH_CONFIRM_HTML
    assert f"<title>تأكيد البريد الإلكتروني | {NAME_AR}</title>" in html
    assert f"document.title = 'إعادة تعيين كلمة المرور | {NAME_AR}';" in html


def test_api_docs_title_uses_the_new_name():
    assert app.title == f"{NAME_EN} AI Service"
    assert app.openapi()["info"]["title"] == f"{NAME_EN} AI Service"


# ── Guard: the old and the withdrawn name stay out ──────────────────────────────

_OLD_NAME = re.compile(r"budget[\s_\-]*tracker|بجٹ\s*ٹریکر|بجت\s*تراكر", re.IGNORECASE)
# "وفير" alone also sits inside "توفير" (saving), hence the word boundary on the short forms.
_WITHDRAWN_NAME = re.compile(
    r"\bwa+f+(?:ee|ei|ie|i|y)r\b|وفيير|وفّير|وفییر|وافير|وافیر|\bوفير\b|\bوفیر\b",
    re.IGNORECASE,
)
# Identifiers, not display text. See the "must stay" tests below.
_ALLOWED_IDENTIFIERS = (
    "budgettracker://",
    "io.supabase.budgettracker",
    "budget-tracker/preview-token/v1",
    "budget_tracker_ai",
)
# A generic description in a sensitive money module, not the brand.
_ALLOWED_PHRASES = {"chat_parser.py": ("Saudi budget tracker",)}


def _strip_allowed(text: str, filename: str = "") -> str:
    for allowed in (*_ALLOWED_IDENTIFIERS, *_ALLOWED_PHRASES.get(filename, ())):
        text = text.replace(allowed, "")
    return text


def _runtime_strings(source: str) -> list[str]:
    """Every string a module can show at runtime: all literals except docstrings."""
    tree = ast.parse(source)
    docstrings = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)) and node.body:
            first = node.body[0]
            if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant):
                docstrings.add(id(first.value))
    strings = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and id(node) not in docstrings:
            if isinstance(node.value, str):
                strings.append(node.value)
            elif isinstance(node.value, bytes):
                strings.append(node.value.decode("utf-8", "ignore"))
    return strings


def _old_name_in_runtime_strings(source: str, filename: str = "") -> list[str]:
    return [s for s in _runtime_strings(source) if _OLD_NAME.search(_strip_allowed(s, filename))]


def test_guard_scans_the_backend_modules():
    names = {path.name for path in BACKEND_MODULES}
    assert {"support_agent.py", "landing_page.py", "main.py", "inquiries.py", "chat.py"} <= names


@pytest.mark.parametrize("path", BACKEND_MODULES, ids=lambda p: p.relative_to(SERVICE_DIR).as_posix())
def test_no_module_can_show_the_old_name(path):
    found = _old_name_in_runtime_strings(path.read_text(encoding="utf-8"), path.name)
    assert not found, f"{path.name} still shows the old name: {found}"


@pytest.mark.parametrize("relative", RENAMED_FILES)
def test_renamed_files_do_not_mention_the_old_name_at_all(relative):
    found = _OLD_NAME.findall(_strip_allowed(_read(relative), pathlib.Path(relative).name))
    assert not found, f"{relative}: {found}"


@pytest.mark.parametrize(
    "path",
    [*BACKEND_MODULES, SERVICE_DIR / ".env.example"],
    ids=lambda p: p.relative_to(SERVICE_DIR).as_posix(),
)
def test_withdrawn_name_never_appears(path):
    found = _WITHDRAWN_NAME.findall(path.read_text(encoding="utf-8"))
    assert not found, f"{path.name}: {found}"


@pytest.mark.parametrize(
    "leak",
    [
        'x = "Budget Tracker"',
        'x = "BUDGET TRACKER — FINANCIAL STATEMENT"',
        'x = "budget-tracker support"',
        'x = "BudgetTracker"',
        'x = b"Budget Tracker"',
        'x = f"[Budget Tracker] {y}"',
        'x = "بجٹ ٹریکر سپورٹ"',
        'x = "بجت تراكر"',
        'def f():\n    return "Welcome to Budget Tracker"',
    ],
)
def test_guard_catches_the_old_name(leak):
    assert _old_name_in_runtime_strings(leak)


@pytest.mark.parametrize(
    "clean",
    [
        '"""Service for Budget Tracker."""',
        'def f():\n    """Used by Budget Tracker."""',
        "# Budget Tracker\nx = 1",
        'x = "budgettracker://login"',
        'x = b"budget-tracker/preview-token/v1|"',
        'x = "budget tracking"',
    ],
)
def test_guard_ignores_docstrings_comments_and_identifiers(clean):
    assert not _old_name_in_runtime_strings(clean)


def test_guard_allows_the_generic_phrase_only_in_chat_parser():
    source = 'x = "assistant for a Saudi budget tracker"'
    assert not _old_name_in_runtime_strings(source, "chat_parser.py")
    assert _old_name_in_runtime_strings(source, "support_agent.py")


@pytest.mark.parametrize("leak", ["Wafeer", "WAFEER", "Wafir", "Waffeer", "Wafeir", "وفيير", "وفّير", "وفير", "وافير"])
def test_guard_catches_the_withdrawn_name(leak):
    assert _WITHDRAWN_NAME.search(f"Welcome to {leak} support")


@pytest.mark.parametrize("word", ["توفير", "التوفير", "wafer", "Qawam Money", "قوام المال"])
def test_withdrawn_name_guard_does_not_flag_ordinary_words(word):
    assert not _WITHDRAWN_NAME.search(f"text {word} text")


# ── Identifiers that must stay: renaming these is a bug, not a cleanup ──────────


def test_app_deep_links_keep_their_scheme():
    html = landing_page.AUTH_CONFIRM_HTML
    assert 'href="budgettracker://login"' in html
    assert "btn.href = 'budgettracker://reset-password' + (hash || search);" in html


def test_preview_token_key_derivation_label_is_unchanged(monkeypatch):
    secret = "x" * 40
    monkeypatch.setenv(preview_token.PREVIEW_TOKEN_SECRET_ENV, secret)
    preview_token.reset_preview_token_key()
    try:
        key, _ = preview_token._load_key()
    finally:
        preview_token.reset_preview_token_key()
    assert key == hashlib.sha256(b"budget-tracker/preview-token/v1|" + secret.encode("utf-8")).digest()


def test_container_name_is_unchanged():
    assert "container_name: budget_tracker_ai" in _read("docker-compose.yml")
