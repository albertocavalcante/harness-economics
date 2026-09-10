"""Staging-directory management and console helpers. Ported from measure/lib/common.sh.

Generated artifacts NEVER land in the repo. They go under $STAGING, which is
outside any git tree, and reach `measurements/` only via an explicit `just record`.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Final

STAGING: Final[Path] = Path(os.environ.get("STAGING", "/private/tmp/harness-econ"))

# Exactly these three, matching common.sh's ensure_staging.
_SUBDIRS: Final[tuple[str, ...]] = ("fixture", "raw", "runs")


def repo_root() -> Path:
    """Repo root, resolved from this file rather than the caller's cwd."""
    return Path(__file__).resolve().parents[2]


def ok(name: str, message: str) -> None:
    print(f"✓ {name}: {message}")


def warn(name: str, message: str) -> None:
    """Completed, but the number is not trustworthy. Must look different from ok."""
    print(f"! {name}: {message}", file=sys.stderr)


def fail(name: str, message: str) -> None:
    print(f"✗ {name}: {message}", file=sys.stderr)


class HarnessError(RuntimeError):
    """Fatal, already-formatted. Entry points catch this and exit 1."""


def die(name: str, message: str) -> None:
    raise HarnessError(f"✗ {name}: {message}")


def require_cmd(cmd: str) -> None:
    if shutil.which(cmd) is None:
        die("require_cmd", f"'{cmd}' not found in PATH — install it and re-run")


def ensure_staging() -> None:
    for sub in _SUBDIRS:
        (STAGING / sub).mkdir(parents=True, exist_ok=True)


def require_free_space(min_mb: int = 500, path: Path | None = None) -> None:
    """Refuse to run rather than discover a full disk as a wedge mid-measurement."""
    target = path or STAGING
    probe = target
    while not probe.exists() and probe != probe.parent:
        probe = probe.parent
    try:
        usage = shutil.disk_usage(probe)
    except OSError as exc:
        die("require_free_space", f"could not stat {probe}: {exc}")
    free_mb = usage.free // (1024 * 1024)
    if free_mb < min_mb:
        die(
            "require_free_space",
            f"{free_mb} MB free at {probe}, need {min_mb} MB",
        )


def claude_version() -> str:
    try:
        out = subprocess.run(
            ["claude", "--version"],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return "unknown"
    first = out.stdout.strip().splitlines()
    return first[0] if first else "unknown"


def utc_now() -> str:
    """ISO-8601, second precision, matching common.sh's `date -u`."""
    return datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_of(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()
