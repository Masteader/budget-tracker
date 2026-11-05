"""The operator command line: dry run by default, no raw personal data, never an HTTP route."""

from __future__ import annotations

import importlib.util
import logging
import pathlib
from typing import Any, Dict, List, Optional

import pytest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "account_deletion_operator.py"


def _load():
    spec = importlib.util.spec_from_file_location("account_deletion_operator", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


operator = _load()

EMAIL = "holder.private@example.com"
USER_ID = "aaaaaaaa-0000-4000-8000-000000000001"
HOUSEHOLD = "bbbbbbbb-0000-4000-8000-000000000001"
SUCCESSOR = "cccccccc-0000-4000-8000-000000000001"
REQUEST = "dddddddd-0000-4000-8000-000000000001"


class FakeError(Exception):
    """Carries a PostgREST hint and text that must not be logged."""

    def __init__(self, hint: str):
        super().__init__(f"raw database text about {EMAIL}")
        self.hint = hint
        self.code = "22023"
        self.message = f"raw database text about {EMAIL}"
        self.details = None


class FakeClient:
    def __init__(self, preview: Optional[Dict[str, Any]] = None, error: Optional[Exception] = None):
        self.preview = preview if preview is not None else _preview()
        self.error = error
        self.calls: List[tuple] = []

    def rpc(self, name: str, params: Dict[str, Any]):
        self.calls.append((name, params))
        client = self

        class _Query:
            def execute(self):
                class _Result:
                    data = None
                if name == "get_account_deletion_operator_preview":
                    _Result.data = client.preview
                    return _Result
                if client.error:
                    raise client.error
                _Result.data = {"success": True, "request_id": REQUEST, "status": "scheduled",
                                "already_requested": False, "cancelled": True,
                                "scheduled_for": "2026-12-05T21:30:00+00:00"}
                return _Result

        return _Query()

    def names(self) -> List[str]:
        return [name for name, _ in self.calls]


def _preview(**overrides) -> Dict[str, Any]:
    body = {
        "inquiry_valid": True,
        "inquiry_email_matches": True,
        "account_found": True,
        "user_id": USER_ID,
        "deletion": {"status": "none", "can_cancel": False},
        "households": [],
    }
    body.update(overrides)
    return body


def _admin_household() -> List[Dict[str, Any]]:
    return [{"household_id": HOUSEHOLD, "position": "primary_admin", "needs_choice": True, "other_members": 2}]


BASE = ["--email", EMAIL, "--inquiry-id", "ref-1", "--verified-by", "dev_one"]


def test_dry_run_is_the_default_and_writes_nothing(capsys):
    client = FakeClient()
    assert operator.main(BASE, client=client) == 0
    assert client.names() == ["get_account_deletion_operator_preview"]
    out = capsys.readouterr().out
    assert "DRY RUN" in out and "--execute" in out


def test_execute_schedules_with_the_reference_and_handle():
    client = FakeClient()
    assert operator.main([*BASE, "--execute"], client=client) == 0
    name, params = client.calls[-1]
    assert name == "schedule_account_deletion_by_operator"
    assert params == {
        "p_user_id": USER_ID,
        "p_inquiry_reference": "ref-1",
        "p_verified_by": "dev_one",
        "p_household_choices": [],
        "p_locale": None,
    }


@pytest.mark.parametrize("missing", ["--email", "--inquiry-id", "--verified-by"])
def test_every_identifying_argument_is_required(missing, capsys):
    argv = list(BASE)
    index = argv.index(missing)
    del argv[index:index + 2]
    with pytest.raises(SystemExit) as stop:
        operator.main([*argv, "--execute"], client=FakeClient())
    assert stop.value.code == 2


def test_no_matching_account_stops_without_saying_more(capsys):
    client = FakeClient(_preview(account_found=False, user_id=None))
    assert operator.main([*BASE, "--execute"], client=client) == 2
    assert client.names() == ["get_account_deletion_operator_preview"]
    assert "No account matches" in capsys.readouterr().out


@pytest.mark.parametrize("args", [[], ["--execute"], ["--cancel", "--execute"]])
def test_an_address_two_accounts_share_is_refused(args, capsys):
    """Two accounts whose addresses differ only in case: the address does not say which one."""
    deletion = {"status": "scheduled", "can_cancel": True, "scheduled_for": "2026-12-05T21:30:00+00:00"}
    client = FakeClient(_preview(ambiguous=True, account_found=True, user_id=None, deletion=deletion))
    assert operator.main([*BASE, *args], client=client) == 2
    assert client.names() == ["get_account_deletion_operator_preview"]
    out = capsys.readouterr().out
    assert "more than one account" in out
    assert EMAIL not in out


@pytest.mark.parametrize("hint", ["inquiry_reused", "inquiry_invalid"])
def test_a_reused_or_unknown_reference_is_a_refusal(hint, capsys):
    client = FakeClient(error=FakeError(hint))
    assert operator.main([*BASE, "--execute"], client=client) == 2
    assert hint in capsys.readouterr().out


def test_an_invalid_inquiry_stops_before_anything_is_written():
    client = FakeClient(_preview(inquiry_valid=False))
    assert operator.main([*BASE, "--execute"], client=client) == 2
    assert client.names() == ["get_account_deletion_operator_preview"]


def test_a_household_needing_a_choice_is_refused_not_guessed(capsys):
    client = FakeClient(_preview(households=_admin_household()))
    assert operator.main([*BASE, "--execute"], client=client) == 2
    assert client.names() == ["get_account_deletion_operator_preview"]
    out = capsys.readouterr().out
    assert HOUSEHOLD in out and "--choice" in out


def test_the_dry_run_also_says_a_choice_is_missing(capsys):
    client = FakeClient(_preview(households=_admin_household()))
    assert operator.main(BASE, client=client) == 2
    assert "--choice" in capsys.readouterr().out


@pytest.mark.parametrize("choice, expected", [
    (f"{HOUSEHOLD}:delete", {"household_id": HOUSEHOLD, "action": "delete"}),
    (f"{HOUSEHOLD}:transfer:{SUCCESSOR}", {"household_id": HOUSEHOLD, "action": "transfer", "successor_user_id": SUCCESSOR}),
])
def test_an_explicit_choice_is_passed_through(choice, expected):
    client = FakeClient(_preview(households=_admin_household()))
    assert operator.main([*BASE, "--choice", choice, "--execute"], client=client) == 0
    assert client.calls[-1][1]["p_household_choices"] == [expected]


@pytest.mark.parametrize("choice", [
    "delete",
    f"{HOUSEHOLD}:transfer",
    f"{HOUSEHOLD}:delete:{SUCCESSOR}",
    f"{HOUSEHOLD}:move",
    f"not-a-uuid:delete",
    f"{HOUSEHOLD}:transfer:not-a-uuid",
])
def test_a_malformed_choice_stops_before_any_call(choice):
    client = FakeClient()
    with pytest.raises(SystemExit) as stop:
        operator.main([*BASE, "--choice", choice, "--execute"], client=client)
    assert stop.value.code == 2
    assert client.calls == []


@pytest.mark.parametrize("handle", ["someone@example.com", "", "two words"])
def test_verified_by_is_a_handle_never_an_address(handle):
    client = FakeClient()
    with pytest.raises(SystemExit):
        operator.main(["--email", EMAIL, "--inquiry-id", "ref-1", "--verified-by", handle, "--execute"], client=client)
    assert client.calls == []


def test_an_existing_request_is_reported_and_nothing_new_is_written(capsys):
    deletion = {"status": "scheduled", "can_cancel": True, "scheduled_for": "2026-12-05T21:30:00+00:00"}
    client = FakeClient(_preview(deletion=deletion))
    assert operator.main([*BASE, "--execute"], client=client) == 0
    assert client.names() == ["get_account_deletion_operator_preview"]
    assert "already" in capsys.readouterr().out


def test_cancel_is_dry_run_by_default_too(capsys):
    deletion = {"status": "scheduled", "can_cancel": True, "scheduled_for": "2026-12-05T21:30:00+00:00"}
    client = FakeClient(_preview(deletion=deletion))
    assert operator.main([*BASE, "--cancel"], client=client) == 0
    assert client.names() == ["get_account_deletion_operator_preview"]
    assert "DRY RUN" in capsys.readouterr().out


def test_cancel_with_execute_calls_the_operator_cancel():
    deletion = {"status": "scheduled", "can_cancel": True, "scheduled_for": "2026-12-05T21:30:00+00:00"}
    client = FakeClient(_preview(deletion=deletion))
    assert operator.main([*BASE, "--cancel", "--execute"], client=client) == 0
    assert client.calls[-1] == ("cancel_account_deletion_by_operator", {
        "p_user_id": USER_ID, "p_inquiry_reference": "ref-1", "p_verified_by": "dev_one",
    })


@pytest.mark.parametrize("args", [[], ["--execute"], ["--cancel", "--execute"]])
def test_no_personal_data_is_printed_or_logged(args, capsys, caplog):
    caplog.set_level(logging.DEBUG)
    deletion = {"status": "scheduled", "can_cancel": True, "scheduled_for": "2026-12-05T21:30:00+00:00"} if "--cancel" in args else {"status": "none"}
    client = FakeClient(_preview(deletion=deletion, households=[
        {"household_id": HOUSEHOLD, "position": "member", "needs_choice": False, "other_members": 3},
    ]))
    assert operator.main([*BASE, *args], client=client) == 0
    captured = capsys.readouterr()
    for text in (captured.out, captured.err, caplog.text):
        assert EMAIL not in text
        assert USER_ID not in text


def test_a_refusal_prints_the_code_and_never_the_raw_error(capsys, caplog):
    caplog.set_level(logging.DEBUG)
    client = FakeClient(error=FakeError("household_choice_missing"))
    assert operator.main([*BASE, "--execute"], client=client) == 2
    captured = capsys.readouterr()
    assert "household_choice_missing" in captured.out
    for text in (captured.out, captured.err, caplog.text):
        assert EMAIL not in text


def test_an_unknown_failure_is_exit_one_with_the_type_only(capsys, caplog):
    caplog.set_level(logging.DEBUG)
    client = FakeClient(error=RuntimeError(f"connection failed for {EMAIL}"))
    assert operator.main([*BASE, "--execute"], client=client) == 1
    captured = capsys.readouterr()
    for text in (captured.out, captured.err, caplog.text):
        assert EMAIL not in text


def test_the_action_is_logged_with_reference_and_handle_only(caplog):
    caplog.set_level(logging.INFO)
    assert operator.main([*BASE, "--execute"], client=FakeClient()) == 0
    assert "ref-1" in caplog.text and "dev_one" in caplog.text and REQUEST in caplog.text


def test_the_web_api_gains_no_operator_route():
    from main import app

    for route in app.routes:
        low = getattr(route, "path", "").lower()
        assert "operator" not in low, low
        assert "schedule" not in low, low


def test_the_api_process_does_not_import_the_script():
    root = SCRIPT.parents[1]
    for path in [root / "main.py", *(root / "routes").glob("*.py")]:
        source = path.read_text(encoding="utf-8")
        assert "account_deletion_operator" not in source, path
        assert "schedule_account_deletion_by_operator" not in source, path
