"""The body of the fake `adb.exe` that the capture tests build (tests/capture_helpers.py).

It is a real program, started as a real process, so the tests see exactly the arguments and the
environment that a real `adb` would get. It never talks to a phone. `scenario.json` beside the
executable sets its behaviour, and the folder `phone/` stands in for the phone's storage.
"""

import json
import os
import shutil
import sys
import time

HOME = os.path.dirname(os.path.abspath(sys.argv[0]))
PHONE = os.path.join(HOME, "phone")
CALLS = os.path.join(HOME, "calls")
STOP_FILE = os.path.join(PHONE, "screenrecord_stop_requested")
DEMO_FLAG = os.path.join(PHONE, "demo_mode_is_on")
RECORDING_BYTES = b"recording from the fake phone"
SCREENSHOT_BYTES = b"\x89PNG\r\n\x1a\n" + b"screen from the fake phone" + b"IEND\xaeB`\x82"
SCREENCAP_OUTPUT = {
    "good": SCREENSHOT_BYTES,
    "empty": b"",
    "not_a_png": b"error: no screen",
    "cut_off": SCREENSHOT_BYTES[:-5],
}


def previous_calls() -> list[list[str]]:
    calls = []
    for name in sorted(os.listdir(CALLS)):
        if name.endswith(".json"):
            with open(os.path.join(CALLS, name), encoding="utf-8") as handle:
                calls.append(json.load(handle)["argv"])
    return calls


def log_call(argv: list[str]) -> None:
    """One file per call, because the recorder and the stop signal run at the same time, and two
    processes appending to one file can overwrite each other on Windows."""
    name = f"{time.time_ns():020d}_{os.getpid()}"
    temporary = os.path.join(CALLS, f"{name}.tmp")
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump({"argv": argv, "env": sorted(os.environ)}, handle)
    os.replace(temporary, os.path.join(CALLS, f"{name}.json"))


def wait_for_the_recorder_to_be_logged() -> None:
    """The recorder is a process just started, so the test's instant Enter can beat it here."""
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if any("screenrecord" in without_serial(call)[1:] for call in previous_calls()):
            return
        time.sleep(0.01)


def without_serial(argv: list[str]) -> list[str]:
    return argv[2:] if argv[:1] == ["-s"] else argv


def on_phone(remote: str) -> str:
    return os.path.join(PHONE, remote.rsplit("/", 1)[-1])


def fail_if_told_to(scenario: dict, argv: list[str], seen: list[list[str]]) -> None:
    joined = " ".join(without_serial(argv))
    for rule in scenario.get("fail", []):
        if rule["match"] not in joined:
            continue
        earlier = sum(rule["match"] in " ".join(without_serial(call)) for call in seen)
        if rule.get("skip", 0) <= earlier < rule.get("times", 1_000_000):
            print(rule.get("stderr", "adb: told to fail"), file=sys.stderr)
            raise SystemExit(rule.get("code", 1))


def screenrecord(scenario: dict, remote: str) -> None:
    deadline = time.monotonic() + scenario.get("recording_runs_for", 60)
    while time.monotonic() < deadline and not os.path.exists(STOP_FILE):
        time.sleep(0.01)
    if os.path.exists(STOP_FILE):
        os.remove(STOP_FILE)
    with open(on_phone(remote), "wb") as handle:
        handle.write(RECORDING_BYTES)


def shell(scenario: dict, args: list[str]) -> None:
    if args[:1] == ["screenrecord"]:
        screenrecord(scenario, args[1])
    elif args[:2] == ["pkill", "-INT"]:
        # Appears whole: Windows refuses to delete a file another process still has open, and
        # the recorder deletes this one the moment it sees it.
        temporary = f"{STOP_FILE}.{os.getpid()}"
        with open(temporary, "w", encoding="utf-8"):
            pass
        os.replace(temporary, STOP_FILE)
    elif args[:2] == ["rm", "-f"]:
        if os.path.exists(on_phone(args[2])):
            os.remove(on_phone(args[2]))
    elif "command" in args:
        word = args[args.index("command") + 1]
        if word == "enter":
            with open(DEMO_FLAG, "w", encoding="utf-8"):
                pass
        elif word == "exit" and os.path.exists(DEMO_FLAG):
            os.remove(DEMO_FLAG)


def main() -> None:
    os.makedirs(PHONE, exist_ok=True)
    os.makedirs(CALLS, exist_ok=True)
    with open(os.path.join(HOME, "scenario.json"), encoding="utf-8") as handle:
        scenario = json.load(handle)
    argv = sys.argv[1:]
    args = without_serial(argv)
    if args[:2] == ["shell", "pkill"]:
        wait_for_the_recorder_to_be_logged()
    seen = previous_calls()
    log_call(argv)
    fail_if_told_to(scenario, argv, seen)

    if args == ["devices"]:
        print(scenario.get("devices", "List of devices attached\nFAKE0001\tdevice\n"))
    elif args[:1] == ["shell"]:
        shell(scenario, args[1:])
    elif args == ["exec-out", "screencap", "-p"]:
        sys.stdout.buffer.write(SCREENCAP_OUTPUT[scenario.get("screencap", "good")])
    elif args[:1] == ["pull"]:
        if scenario.get("pull_leaves_empty_file"):
            with open(args[2], "wb"):
                pass
        else:
            shutil.copyfile(on_phone(args[1]), args[2])


if __name__ == "__main__":
    main()
