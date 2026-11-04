"""A stand-in for the `claude` executable (plan task D1). It never contacts anything.

`build_stub` packs this file into a real `claude.exe`, using the launcher that pip uses for
console scripts, so the engine starts it through the same CreateProcess call as the real one
and the test sees exactly what a real child process would receive. The environment is
scrubbed, so the stub cannot be told what to do through a variable: it reads its canned
answers from a file beside the executable, and records each call beside it too.
"""

from __future__ import annotations

import io
import json
import os
import sys
import zipfile
from pathlib import Path

_SOURCE = Path(__file__)


def build_stub(folder: Path, *answers: dict) -> Path:
    """Each answer is `{"stdout": str, "stderr": str, "exit": int}`. The last one repeats."""
    import pip

    folder.mkdir(parents=True, exist_ok=True)
    launcher = Path(pip.__file__).parent / "_vendor" / "distlib" / "t64.exe"
    archive = io.BytesIO()
    with zipfile.ZipFile(archive, "w") as packed:
        packed.writestr("__main__.py", _SOURCE.read_text(encoding="utf-8"))
    shebang = f'#!"{sys.executable}"\r\n'.encode()
    exe = folder / "claude.exe"
    exe.write_bytes(launcher.read_bytes() + shebang + archive.getvalue())
    exe.with_suffix(".answers.json").write_text(json.dumps(answers), encoding="utf-8")
    return exe


def calls_of(exe: Path) -> list[dict]:
    """What each started process really received: argv, working folder and environment."""
    log = exe.with_suffix(".calls.jsonl")
    if not log.exists():
        return []
    return [json.loads(line) for line in log.read_text(encoding="utf-8").splitlines()]


def _main() -> int:
    exe = Path(sys.argv[0])
    answers = json.loads(exe.with_suffix(".answers.json").read_text(encoding="utf-8"))
    done = len(calls_of(exe))
    answer = answers[min(done, len(answers) - 1)]
    call = {"argv": sys.argv[1:], "cwd": os.getcwd(), "env": dict(os.environ)}
    with exe.with_suffix(".calls.jsonl").open("a", encoding="utf-8") as log:
        log.write(json.dumps(call) + "\n")
    sys.stdout.buffer.write(answer.get("stdout", "").encode("utf-8"))
    sys.stderr.buffer.write(answer.get("stderr", "").encode("utf-8"))
    return answer.get("exit", 0)


if __name__ == "__main__":
    sys.exit(_main())
