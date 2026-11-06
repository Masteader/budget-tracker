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
import json
import pathlib
import re
import zlib
from email.utils import parseaddr
from unittest.mock import MagicMock, patch

import pytest
from fastapi import FastAPI

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
# The one place the old names may appear: it tells the support model they are this app's former
# names. It names them on purpose: a catch-all would also cover other apps, such as Tabby or Tamara.
FORMER_NAME_CLAUSE = (
    "If the user calls this app Budget Tracker or ميزانية الأسرة, that is this app's former name; "
    "reply using the correct name."
)
# Urdu only: it also names the Urdu-script form, because that is the one Urdu users saw.
FORMER_NAME_CLAUSE_UR = (
    "If the user calls this app Budget Tracker, ميزانية الأسرة or بجٹ ٹریکر, that is this app's former name; "
    "reply using the correct name."
)
FORMER_NAME_CLAUSES = {"en": FORMER_NAME_CLAUSE, "ar": FORMER_NAME_CLAUSE, "ur": FORMER_NAME_CLAUSE_UR}
URDU_OLD_NAME = "بجٹ ٹریکر"


_NOT_BACKEND_DIRS = {"tests", "static", "venv", "__pycache__"}


def _backend_modules(root: pathlib.Path) -> list[pathlib.Path]:
    """Every backend .py file, so a new subpackage is covered. Hidden dirs cover .venv and caches."""
    modules = []
    for path in root.rglob("*.py"):
        folders = path.relative_to(root).parts[:-1]
        if not any(part in _NOT_BACKEND_DIRS or part.startswith(".") for part in folders):
            modules.append(path)
    return sorted(modules)


BACKEND_MODULES = _backend_modules(SERVICE_DIR)
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
    assert "The app's name is" in prompt
    expected = NAME_AR if lang == "ar" else NAME_EN
    assert f"when asked what the app is called, answer {expected}." in prompt.replace("When asked", "when asked")


@pytest.mark.parametrize("lang", ["en", "ar", "ur"])
def test_support_prompt_does_not_ask_for_an_introduction_on_every_reply(lang):
    # routes/chat.py sends app_guidance messages here without history, so an unconditional
    # instruction fires on every reply, and the model cannot tell which contact is the first.
    prompt = support_agent.build_support_prompt(lang, None).lower()
    assert "introduce" not in prompt
    assert "first message" not in prompt
    assert "first contact" not in prompt


@pytest.mark.parametrize("lang", ["en", "ar", "ur"])
def test_former_name_clause_names_the_former_names_and_nothing_wider(lang):
    prompt = support_agent.build_support_prompt(lang, None)
    clause = FORMER_NAME_CLAUSES[lang]
    assert clause in prompt
    assert "Budget Tracker" in clause
    assert "ميزانية الأسرة" in clause
    assert prompt.count("former name") == 1
    for catch_all in ("a different name", "another name", "other name", "any name", "same app", "other app", "another app"):
        assert catch_all not in clause, catch_all
    for catch_all in ("a different name", "another name", "same app", "other app", "another app"):
        assert catch_all not in prompt, catch_all


def test_only_the_urdu_prompt_names_the_urdu_former_name():
    assert URDU_OLD_NAME in FORMER_NAME_CLAUSE_UR
    assert URDU_OLD_NAME in support_agent.build_support_prompt("ur", None)
    assert URDU_OLD_NAME not in support_agent.build_support_prompt("en", None)
    assert URDU_OLD_NAME not in support_agent.build_support_prompt("ar", None)


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

_OLD_NAME = re.compile(
    r"budget[\s_\-]*tracker|بجٹ\s*ٹریکر|بجت\s*تراكر|بدجت\s*تراكر|ميزانية\s*الأسرة",
    re.IGNORECASE,
)
# An Arabic-script letter or mark. Punctuation and digits (، ؟ ۔ ٣) are not, so a name next to them
# is still a whole word.
_AR_LETTER = "[ؐ-ؚؠ-ٟٮ-ۓە-ۯۺ-ۿ]"
# Same pattern as flutter_app/test/support/brand_names.dart: keep the two in step.
_WITHDRAWN_NAME = re.compile(
    r"wa+f+(?:ee|ei|ie|i|y)r"
    # Doubled ي/ی, a shadda or an alef: not ordinary words, so these match anywhere.
    r"|وفّ?[يی]{2}ر|وفّ[يی]ر|وافّ?[يی]{1,2}ر"
    # وفير/وفیر is also the ordinary word for "abundant", and sits inside توفير/توفیر (saving). It
    # matches as a whole word with at most one attached proclitic (ب ل و ف ك, or وب ول فب فل):
    # the ت of توفير is not one, so "saving" stays unflagged.
    rf"|(?<!{_AR_LETTER})(?:[وف][بل]|[بلوفك])?وف[يی]ر(?!{_AR_LETTER})",
    re.IGNORECASE,
)
# Identifiers, not display text. See the "must stay" tests below.
_ALLOWED_IDENTIFIERS = (
    "budgettracker://",
    "budget-tracker/preview-token/v1",
    "budget_tracker_ai",
)
# Exact text allowed in one file only, keyed by its path under ai_service/.
_ALLOWED_PHRASES = {
    "chat_parser.py": ("Saudi budget tracker",),  # a generic description in a money module, not the brand
    "support_agent.py": (FORMER_NAME_CLAUSE, FORMER_NAME_CLAUSE_UR),
}
_ZERO_WIDTH = dict.fromkeys(map(ord, "​‌‍"))


def _normalize(text: str) -> str:
    """Spacing that reads as a space, and characters that do not show, must not hide a name."""
    return text.replace("&nbsp;", " ").replace(" ", " ").translate(_ZERO_WIDTH)


def _strip_allowed(text: str, relative: str = "") -> str:
    for allowed in (*_ALLOWED_IDENTIFIERS, *_ALLOWED_PHRASES.get(relative, ())):
        text = text.replace(allowed, "")
    return text


def _has_old_name(text: str, relative: str = "") -> bool:
    return bool(_OLD_NAME.search(_strip_allowed(_normalize(text), relative)))


def _has_withdrawn_name(text: str) -> bool:
    return bool(_WITHDRAWN_NAME.search(_normalize(text)))


def _relative(path: pathlib.Path) -> str:
    return path.relative_to(SERVICE_DIR).as_posix()


def _openapi_text(application: FastAPI) -> str:
    # ensure_ascii=False: the default escapes Arabic, which the name patterns could then never match.
    return json.dumps(application.openapi(), ensure_ascii=False)


def _container_names(compose: str) -> list[str]:
    """The container_name values of a compose file: only a real key counts, never a comment."""
    return re.findall(r"""^[ \t]*container_name:[ \t]*["']?([^\s"'#]+)""", compose, re.MULTILINE)


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


def _old_name_in_runtime_strings(source: str, relative: str = "") -> list[str]:
    return [s for s in _runtime_strings(source) if _has_old_name(s, relative)]


def test_guard_scans_the_backend_modules():
    names = {_relative(path) for path in BACKEND_MODULES}
    assert {"support_agent.py", "landing_page.py", "main.py", "routes/inquiries.py", "routes/chat.py"} <= names
    assert not any(name.startswith(("tests/", "static/")) for name in names)


def test_guard_covers_new_subpackages_but_not_tests_venv_static_or_caches(tmp_path):
    expected = {"top.py", "routes/a.py", "newpkg/mod.py", "newpkg/deep/mod.py"}
    excluded = {
        "tests/test_x.py",
        ".venv/lib/site.py",
        "venv/lib/site.py",
        "static/gen.py",
        "__pycache__/top.py",
        "newpkg/__pycache__/mod.py",
        ".pytest_cache/x.py",
    }
    for relative in expected | excluded:
        target = tmp_path / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("x = 1\n", encoding="utf-8")
    assert {p.relative_to(tmp_path).as_posix() for p in _backend_modules(tmp_path)} == expected


@pytest.mark.parametrize("path", BACKEND_MODULES, ids=_relative)
def test_no_module_can_show_the_old_name(path):
    found = _old_name_in_runtime_strings(path.read_text(encoding="utf-8"), _relative(path))
    assert not found, f"{_relative(path)} still shows the old name: {found}"


@pytest.mark.parametrize("relative", RENAMED_FILES)
def test_renamed_files_do_not_mention_the_old_name_at_all(relative):
    assert not _has_old_name(_read(relative), relative), relative


@pytest.mark.parametrize("path", [*BACKEND_MODULES, SERVICE_DIR / ".env.example"], ids=_relative)
def test_withdrawn_name_never_appears(path):
    assert not _has_withdrawn_name(path.read_text(encoding="utf-8")), _relative(path)


def test_published_api_docs_have_neither_name():
    text = _openapi_text(app)
    assert NAME_EN in text
    assert not _has_old_name(text)
    assert not _has_withdrawn_name(text)


@pytest.mark.parametrize("leak", ["Budget Tracker", "ميزانية الأسرة", "بجٹ ٹریکر", "Wafeer", "وفيير"])
def test_published_api_docs_guard_catches_a_docstring_leak(leak):
    def handler():
        return {}

    sample = FastAPI(title="sample")
    sample.add_api_route("/sample", handler, description=f"Part of {leak}.")
    text = _openapi_text(sample)
    assert _has_old_name(text) or _has_withdrawn_name(text)


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
        'x = "بدجت تراكر"',
        'x = "ميزانية الأسرة"',
        'x = "io.supabase.budgettracker"',
        'x = "Budget&nbsp;Tracker"',
        'def f():\n    return "Welcome to Budget Tracker"',
    ],
)
def test_guard_catches_the_old_name(leak):
    assert _old_name_in_runtime_strings(leak)


@pytest.mark.parametrize(
    "leak",
    [
        "Budget&nbsp;Tracker",
        "Budget Tracker",
        "Budget​Tracker",
        "Bud​get Tracker",
        "Budget‌ ‍Tracker",
        "بجٹ‌ٹریکر",
        "بجٹ&nbsp;ٹریکر",
        "ميزانية الأسرة",
        "ميزانية&nbsp;الأسرة",
        "ميزا‌نية الأسرة",
        "بدجت‍تراكر",
    ],
)
def test_guard_sees_through_spacing_entities_and_zero_width_characters(leak):
    assert _has_old_name(leak), repr(leak)


@pytest.mark.parametrize("leak", ["Waf​eer", "Wafeer&nbsp;Money", "وفي‌ير", "و‍فيير"])
def test_withdrawn_name_guard_sees_through_zero_width_characters(leak):
    assert _has_withdrawn_name(leak), repr(leak)


@pytest.mark.parametrize("clause", [FORMER_NAME_CLAUSE, FORMER_NAME_CLAUSE_UR], ids=["en-ar", "ur"])
def test_former_name_clause_is_allowed_only_in_the_support_agent(clause):
    assert not _has_old_name(clause, "support_agent.py")
    assert _has_old_name(clause, "routes/chat.py")
    assert _has_old_name(clause, "landing_page.py")
    assert _has_old_name(clause)


@pytest.mark.parametrize(
    "leak",
    [
        "Welcome to Budget Tracker",
        "مرحبا في ميزانية الأسرة",
        "Budget Tracker or ميزانية الأسرة",
        URDU_OLD_NAME,
        f"{URDU_OLD_NAME} سپورٹ میں خوش آمدید",
        f"Budget Tracker, ميزانية الأسرة or {URDU_OLD_NAME}",
    ],
)
def test_support_agent_allowance_does_not_cover_other_uses_of_the_old_names(leak):
    assert _has_old_name(leak, "support_agent.py")
    assert _has_old_name(f"{FORMER_NAME_CLAUSE} {leak}", "support_agent.py")
    assert _has_old_name(f"{FORMER_NAME_CLAUSE_UR} {leak}", "support_agent.py")


def test_urdu_old_name_elsewhere_in_the_real_support_agent_file_still_fails():
    source = _read("support_agent.py")
    assert not _old_name_in_runtime_strings(source, "support_agent.py")
    # The same real file with one new string that shows the old Urdu name.
    leaked = f'{source}\nWELCOME = "{URDU_OLD_NAME} سپورٹ میں خوش آمدید"\n'
    assert _old_name_in_runtime_strings(leaked, "support_agent.py")
    assert _has_old_name(leaked, "support_agent.py")


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
    assert _old_name_in_runtime_strings(source, "routes/chat_parser.py")


@pytest.mark.parametrize(
    "leak",
    [
        "Wafeer", "WAFEER", "wafeer", "WafeerApp", "Wafeer_Money", "myWafeer", "wafeer.money",
        "Wafir", "Waffeer", "Wafeir",
        # The standard spellings, Arabic ي (U+064A) and Persian/Urdu ی (U+06CC).
        "وفير", "وفیر", "وفيير", "وفییر", "وفّير", "وافير", "وافیر",
        # One attached proclitic (ب ل و ف ك) or two (وب ول فب فل).
        "لوفير", "بوفير", "ووفير", "فوفير", "كوفير", "لوفیر", "بوفیر",
        "وبوفير", "ولوفير", "فبوفير", "فلوفير",
        "لوفيير", "بوفيير", "ووفيير",
    ],
)
def test_guard_catches_the_withdrawn_name(leak):
    assert _has_withdrawn_name(f"Welcome to {leak} support"), leak
    assert _has_withdrawn_name(leak), leak


@pytest.mark.parametrize(
    "text",
    ["مرحباً بك في وفير", "رزق وفير", "(وفير)", "«وفير»", "وفير،", "وفير؟", "وفير.", "وفیر۔", "تطبيق وفير"],
)
def test_guard_catches_the_withdrawn_name_next_to_punctuation(text):
    assert _has_withdrawn_name(text), text


@pytest.mark.parametrize(
    "word",
    [
        "توفير", "التوفير", "توفیر", "التوفیر", "للتوفير", "بالتوفير", "وفيرة", "وفي التخزين", "يوفر",
        "wafer", "waffle", "Qawam Money", "قوام المال",
    ],
)
def test_withdrawn_name_guard_does_not_flag_ordinary_words(word):
    assert not _has_withdrawn_name(f"text {word} text"), word
    assert not _has_withdrawn_name(word), word


def test_withdrawn_name_in_the_real_support_agent_file_fails():
    source = _read("support_agent.py")
    assert not _has_withdrawn_name(source)
    # The same real file with the withdrawn name in the Arabic fallback reply.
    leaked = source.replace(f"لتطبيق {NAME_AR}!", f"لتطبيق {NAME_AR} (وفير)!", 1)
    assert leaked != source
    assert _has_withdrawn_name(leaked)


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
    assert _container_names(_read("docker-compose.yml")) == ["budget_tracker_ai"]


@pytest.mark.parametrize(
    "compose, expected",
    [
        ("services:\n  ai:\n    container_name: budget_tracker_ai\n", ["budget_tracker_ai"]),
        ('services:\n  ai:\n    container_name: "budget_tracker_ai"  # keep\n', ["budget_tracker_ai"]),
        ("# container_name: budget_tracker_ai\nservices:\n  ai:\n    container_name: renamed\n", ["renamed"]),
        ("    # container_name: budget_tracker_ai\nservices:\n  ai:\n    image: x\n", []),
        ("services:\n  ai:\n    image: x  # container_name: budget_tracker_ai\n", []),
    ],
)
def test_container_name_pin_reads_the_value_not_a_comment(compose, expected):
    assert _container_names(compose) == expected
