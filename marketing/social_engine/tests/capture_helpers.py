"""Shared by the capture and ingest tests: a fake `adb.exe`, scripted answers and configs."""

from __future__ import annotations

import copy
import io
import json
import sys
import zipfile
from datetime import date
from pathlib import Path

import pip._vendor.distlib as distlib_package
import yaml

from core.config import DEFAULT_CONFIG_PATH, EngineConfig

FIXTURES = Path(__file__).parent / "fixtures"
RECORDING_BYTES = b"recording from the fake phone"
NAME_CHOSEN_ON = date(2026, 11, 3)


class FakeAdb:
    """A real executable, built the way pip builds `Scripts\\pytest.exe`: the launcher stub, a
    shebang line and a zip holding `__main__.py`. A batch file would not do, because the code
    under test refuses those: cmd.exe would read the arguments a second time."""

    def __init__(self, folder: Path, **scenario):
        self.folder = Path(folder)
        self.folder.mkdir(parents=True, exist_ok=True)
        self.path = self.folder / "adb.exe"
        self.path.write_bytes(_launcher_bytes())
        self.configure(**scenario)

    def configure(self, **scenario) -> None:
        (self.folder / "scenario.json").write_text(json.dumps(scenario), encoding="utf-8")

    @property
    def records(self) -> list[dict]:
        log = self.folder / "calls"
        if not log.exists():
            return []
        return [json.loads(file.read_text(encoding="utf-8")) for file in sorted(log.glob("*.json"))]

    @property
    def calls(self) -> list[list[str]]:
        return [record["argv"] for record in self.records]

    @property
    def commands(self) -> list[str]:
        """Each call as one string, without the `-s <serial>` that comes first."""
        return [" ".join(argv[2:] if argv[:1] == ["-s"] else argv) for argv in self.calls]

    @property
    def phone(self) -> Path:
        return self.folder / "phone"

    @property
    def demo_is_on(self) -> bool:
        return (self.phone / "demo_mode_is_on").exists()

    @property
    def recording_on_phone(self) -> Path:
        return self.phone / "social_engine_tmp.mp4"


def _launcher_bytes() -> bytes:
    stub = Path(distlib_package.__file__).parent / "t64.exe"
    # -I and -S: nothing from the repo or site-packages gets in, and the fake starts fast.
    shebang = f'#!"{sys.executable}" -I -S\r\n'.encode()
    archive = io.BytesIO()
    with zipfile.ZipFile(archive, "w") as bundle:
        bundle.write(FIXTURES / "fake_adb.py", "__main__.py")
    return stub.read_bytes() + shebang + archive.getvalue()


class Answers:
    """Stands in for `input`. Each entry is the reply to one prompt. An exception class is raised
    instead, and a callable runs first and gives the reply."""

    def __init__(self, *replies):
        self.replies = list(replies)
        self.prompts: list[str] = []

    def __call__(self, prompt: str = "") -> str:
        self.prompts.append(prompt)
        assert self.replies, f"an unexpected question: {prompt!r}"
        reply = self.replies.pop(0)
        if isinstance(reply, type) and issubclass(reply, BaseException):
            raise reply()
        return reply() if callable(reply) else reply


def shipped_data() -> dict:
    with DEFAULT_CONFIG_PATH.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def config_data(data_root: Path, adb_path: Path | str | None = None) -> dict:
    data = shipped_data()
    data["paths"]["data_root"] = str(data_root)
    if adb_path is not None:
        data["capture"]["adb_path"] = str(adb_path)
    return data


def build_config(data_root: Path, adb_path: Path | str | None = None) -> EngineConfig:
    return EngineConfig.model_validate(config_data(data_root, adb_path))


def gate_met_data(data_root: Path, adb_path: Path | str | None = None) -> dict:
    """Every launch gate field filled in. The caller points `core.brand_gate.ENGINE_ROOT` at a
    folder holding the logo, as tests/test_brand_gate.py does."""
    data = copy.deepcopy(config_data(data_root, adb_path))
    data["engine"]["mode"] = "live"
    data["brand"]["logo_path"] = "assets/branding/approved_logo.svg"
    data["brand"]["handles"] = {
        "instagram": "@qawam_money",
        "facebook": "qawam.money",
        "tiktok": "@qawammoney",
        "youtube": "@qawammoney",
    }
    data["brand"]["hashtags"] = ["#QawamMoney", "#قوام_المال"]
    data["brand"]["clearance"] = {
        "google_play_checked_on": NAME_CHOSEN_ON,
        "app_store_checked_on": NAME_CHOSEN_ON,
        "saip_checked_on": NAME_CHOSEN_ON,
        "approved_by_owner_on": NAME_CHOSEN_ON,
    }
    return data


def build_gate_met_config(
    monkeypatch, tmp_path: Path, data_root: Path, adb_path: Path | str | None = None
) -> EngineConfig:
    import core.brand_gate as brand_gate_module

    root = tmp_path / "engine_with_logo"
    logo = root / "assets" / "branding" / "approved_logo.svg"
    logo.parent.mkdir(parents=True, exist_ok=True)
    logo.write_text("<svg/>", encoding="utf-8")
    monkeypatch.setattr(brand_gate_module, "ENGINE_ROOT", root)
    return EngineConfig.model_validate(gate_met_data(data_root, adb_path))
