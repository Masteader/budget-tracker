"""Where batch F's studio meets batch G's wrapper. G runs `remotion render <template> <file>` with
no entry point, so each composition ID has to equal a `template` value, and Remotion has to find
the entry point by itself. `npm run render:check` proves the same with the real CLI.

Remotion picks its entry point in this order: a first argument naming an existing file, then
`Config.setEntryPoint`, then the first of its common paths that exists, starting with
`src/index.ts`. (`findEntryPoint` in `@remotion/cli` 4.0.540.)
"""

import json
import re
import shutil
from pathlib import Path
from typing import get_args

import pytest
from render_support import Rig

from core.paths import ENGINE_ROOT
from core.render import render_reel
from core.render_props import Template

STUDIO = ENGINE_ROOT / "remotion_studio"
TEMPLATES = list(get_args(Template))
ENTRY_POINT = Path("src") / "index.ts"

_ZOD_ENUM = re.compile(r"export const TemplateSchema = z\.enum\(\[(.*?)\]\)", re.DOTALL)
_QUOTED = re.compile(r"'([^']+)'")
_TEMPLATE_RECORD = re.compile(r"TEMPLATES: Record<Template, TemplateDefinition> = \{(.*?)\}")
_COMPOSITION = re.compile(r"<Composition\b.*?/>", re.DOTALL)
_MAPPED_IDS = "TemplateSchema.options.map((template) =>"


def _read(studio: Path, relative: str) -> str:
    return (studio / relative).read_text(encoding="utf-8")


def template_problems(studio: Path) -> list[str]:
    """The same three names in the Python contract, the JSON schema, the Zod schema and the
    studio's table of templates."""
    problems = []
    zod = _ZOD_ENUM.search(_read(studio, "src/props.ts"))
    if zod is None or _QUOTED.findall(zod.group(1)) != TEMPLATES:
        problems.append("src/props.ts does not list the templates core/render_props.py lists")
    schema = json.loads(_read(studio, "props.schema.json"))
    if schema["properties"]["template"]["enum"] != TEMPLATES:
        problems.append("props.schema.json does not list the templates")
    record = _TEMPLATE_RECORD.search(_read(studio, "src/compositions/templates.ts"))
    names = [] if record is None else [name.strip() for name in record.group(1).split(",")]
    if sorted(names) != sorted(TEMPLATES):
        problems.append("src/compositions/templates.ts does not hold each template")
    return problems


def composition_id_problems(studio: Path) -> list[str]:
    """One `<Composition>`, made once per template, whose ID is the template's own name."""
    root = _read(studio, "src/Root.tsx")
    problems = []
    compositions = _COMPOSITION.findall(root)
    if len(compositions) != 1:
        problems.append(f"src/Root.tsx has {len(compositions)} compositions, not one per template")
    if _MAPPED_IDS not in root:
        problems.append("src/Root.tsx does not make a composition for each template")
    if not any(re.search(r"\bid=\{template\}", item) for item in compositions):
        problems.append("the composition ID in src/Root.tsx is not the template")
    return problems


def entry_point_problems(studio: Path) -> list[str]:
    """Remotion has to reach `src/index.ts` by itself, and that file has to register this root."""
    problems = []
    entry = studio / ENTRY_POINT
    if not entry.is_file():
        return [f"{ENTRY_POINT.as_posix()} is missing, so Remotion cannot find an entry point"]
    text = entry.read_text(encoding="utf-8")
    if "registerRoot(RemotionRoot)" not in text:
        problems.append(f"{ENTRY_POINT.as_posix()} does not register the studio's root")
    if "setEntryPoint" in _read(studio, "remotion.config.ts"):
        problems.append("remotion.config.ts sets another entry point")
    # A file at the top with a template's name would be read as the entry point.
    problems += [
        f"{name} at the top of the studio would be taken for the entry point"
        for name in TEMPLATES
        if (studio / name).exists()
    ]
    return problems


def all_problems(studio: Path) -> list[str]:
    return [
        *template_problems(studio),
        *composition_id_problems(studio),
        *entry_point_problems(studio),
    ]


# --- The real studio -----------------------------------------------------------------------


def test_the_studio_and_the_wrapper_agree():
    assert all_problems(STUDIO) == []


# --- The check catches drift ---------------------------------------------------------------


def _replace(relative: str, old: str, new: str):
    def change(studio: Path) -> None:
        file = studio / relative
        text = file.read_text(encoding="utf-8")
        assert old in text, f"{old!r} is no longer in {relative}"
        file.write_text(text.replace(old, new), encoding="utf-8")

    return change


def _move_entry_point(studio: Path) -> None:
    (studio / ENTRY_POINT).rename(studio / "src" / "main.ts")


def _shadow_a_template(studio: Path) -> None:
    (studio / "DailyTip").write_text("x", encoding="utf-8")


@pytest.mark.parametrize(
    "drift",
    [
        pytest.param(_replace("src/Root.tsx", "id={template}", "id={`Reel${template}`}"), id="id"),
        pytest.param(_replace("src/Root.tsx", "id={template}", 'id="FeatureDemo"'), id="fixed id"),
        pytest.param(
            _replace("src/Root.tsx", _MAPPED_IDS, "['FeatureDemo'].map((template) =>"),
            id="only one composition",
        ),
        pytest.param(_replace("src/props.ts", "'MythVsFact'", "'Myth'"), id="zod name"),
        pytest.param(
            _replace("props.schema.json", '"MythVsFact"', '"Myth"'), id="json schema name"
        ),
        pytest.param(
            _replace("src/compositions/templates.ts", ", MythVsFact}", "}"), id="template dropped"
        ),
        pytest.param(_move_entry_point, id="entry point moved"),
        pytest.param(
            _replace("src/index.ts", "registerRoot(RemotionRoot)", "registerRoot(Other)"),
            id="entry point registers something else",
        ),
        pytest.param(
            _replace(
                "remotion.config.ts", "Config.setCodec('h264');", "Config.setEntryPoint('a.ts');"
            ),
            id="config sets an entry point",
        ),
        pytest.param(_shadow_a_template, id="a file named like a template"),
    ],
)
def test_the_check_fails_when_the_two_drift(tmp_path, drift):
    studio = tmp_path / "remotion_studio"
    shutil.copytree(STUDIO, studio, ignore=shutil.ignore_patterns("golden", "test_data"))
    assert all_problems(studio) == [], "the copy must start out clean"
    drift(studio)
    assert all_problems(studio)


# --- What the wrapper really runs ----------------------------------------------------------


@pytest.fixture
def rig(tmp_path, monkeypatch) -> Rig:
    return Rig(tmp_path, monkeypatch)


@pytest.mark.parametrize("template", TEMPLATES)
def test_the_wrapper_names_the_template_as_the_composition_and_no_entry_point(rig, template):
    clips = []
    if template == "FeatureDemo":
        rig.add_clip()
        clips = [rig.clip_use()]
    request = rig.request(template=template, clips=clips)
    render_reel(
        request, store=rig.reels, config=rig.config, paths=rig.paths, engine_root=rig.engine
    )
    command = rig.fake.renders[0].command
    assert command[1:5] == ["--no", "remotion", "render", template]
    assert command[5].startswith("out/") and command[5].endswith(".mp4")
    assert not any(part.endswith((".ts", ".tsx", ".js", ".mjs")) for part in command)
    assert rig.fake.renders[0].props["template"] == template
