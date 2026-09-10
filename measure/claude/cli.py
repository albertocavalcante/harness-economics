"""Task loading, the `claude -p` invocation, and answer verification.

Ported from measure/claude/lib.sh. Kept out of measure/lib because it is
Claude-CLI-specific, not generic to every script in the repo.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Final, final

from measure.lib.staging import STAGING, die, repo_root, require_cmd, require_free_space

TASK_IDS: Final = ("T1", "T2", "T3", "T4")

# Deliberate: --bare strips hooks, LSP, plugin sync, auto-memory and CLAUDE.md
# discovery, so the only variable between reps is the prompt and the fixture
# tree — not whatever happens to be in ~/.claude that day.
#
# --bare also forces credential resolution through ANTHROPIC_API_KEY, skipping
# the subscription auth path. Every total_cost_usd this harness reports is
# therefore an API-key list-price figure, NOT what a Claude subscription would
# have billed for the same work. Do not present these as subscription-equivalent.
BARE_FLAGS: Final = ("--output-format", "json", "--bare", "--max-turns", "12")


@final
@dataclass(frozen=True, slots=True)
class Task:
    task_id: str
    prompt: str
    expected: str


def load_task(task_id: str) -> Task:
    """Read measure/fixture/tasks/<task_id>.md."""
    path = repo_root() / "measure" / "fixture" / "tasks" / f"{task_id}.md"
    if not path.is_file():
        die("load_task", f"unknown task '{task_id}' (no {path})")

    expected = ""
    prompt_lines: list[str] = []
    for line in path.read_text().splitlines():
        if line.startswith("EXPECTED:") and not expected:
            expected = line.removeprefix("EXPECTED:").strip()
            continue
        if line.startswith("EXPECTED:"):
            continue
        prompt_lines.append(line)

    if not expected:
        die("load_task", f"{path} has no EXPECTED: line")

    while prompt_lines and not prompt_lines[-1].strip():
        prompt_lines.pop()

    return Task(task_id=task_id, prompt="\n".join(prompt_lines), expected=expected)


def call_claude(fixture_dir: Path, prompt: str, extra: list[str] | None = None) -> dict[str, Any]:
    """Invoke `claude -p` and return the parsed result payload."""
    cmd = [
        "claude",
        "-p",
        prompt,
        *BARE_FLAGS,
        "--add-dir",
        str(fixture_dir),
        *(extra or []),
    ]
    completed = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if completed.returncode != 0:
        die(
            "call_claude", f"claude exited {completed.returncode}: {completed.stderr.strip()[:400]}"
        )
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        die("call_claude", f"could not parse claude output as JSON: {exc}")
    if not isinstance(payload, dict):
        die("call_claude", "claude output was not a JSON object")
    return payload


def verify_answer(raw: dict[str, Any], expected: str) -> bool:
    """Match EXPECTED as an extended regex against the trimmed `.result`.

    Deliberately `re.search`, not `re.fullmatch`: the shell original used an
    unanchored `grep -Eq`, so `EXPECTED: 7` matches "17" and "note: 7 of 9".
    Tightening it here would silently change every historical validity
    judgement, which is a separate decision from porting the language.
    """
    result = str(raw.get("result") or "").strip()
    try:
        return re.search(expected, result) is not None
    except re.error:
        # A malformed EXPECTED pattern must not read as a failed answer.
        die("verify_answer", f"EXPECTED is not a valid regex: {expected!r}")
        return False


def claude_preflight() -> None:
    """Refuse to run in a degraded environment rather than emit a misleading number."""
    require_cmd("claude")
    if not os.environ.get("ANTHROPIC_API_KEY"):
        die(
            "preflight",
            "--bare requires ANTHROPIC_API_KEY — refusing to run and emit "
            "unauthenticated/misleading numbers",
        )
    require_free_space(200, STAGING)


def ensure_fixture() -> Path:
    """Materialise the deterministic fixture if it is not already staged."""
    fixture_dir = STAGING / "fixture"
    if not (fixture_dir / "FIXTURE.sha256").is_file():
        script = repo_root() / "measure" / "fixture" / "make.sh"
        completed = subprocess.run(["bash", str(script)], check=False)
        if completed.returncode != 0:
            die("fixture", f"{script} failed with exit {completed.returncode}")
    return fixture_dir
