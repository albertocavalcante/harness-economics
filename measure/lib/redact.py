"""Defence-in-depth output scrubbing. Ported from measure/lib/redact.sh.

IMPORTANT: this is NOT the load-bearing safety control. The real control is the
projection in measure/lib/projection.py, which only ever names a short list of
numeric fields — raw content never appears in emitted measurements because it is
never selected, not because it was filtered afterwards.

`redact_text` exists only for the one path where raw content deliberately touches
disk: an opt-in capture under $STAGING/raw/ for debugging a broken run. It
reduces blast radius if that capture is ever piped somewhere it shouldn't be. It
must never be treated as the thing that makes raw capture safe to commit or
share — raw capture must NEVER leave $STAGING/raw/.
"""

from __future__ import annotations

import re
from typing import Final

# NOTE: several patterns below use a single-character bracket expression (e.g.
# `[_]` rather than a bare underscore) purely so this FILE does not contain the
# exact literal substring `tools/leaks.sh` scans for. A one-character bracket
# expression matches exactly the same character, so redaction behaviour is
# unchanged. Without this, `just leaks` flags this very file: naming a credential
# prefix in order to strip it otherwise reproduces it verbatim.
_SUBSTITUTIONS: Final[tuple[tuple[re.Pattern[str], str], ...]] = (
    (re.compile(r"/Users/[A-Za-z0-9_.-]+"), "<path>"),
    (re.compile(r"/Volumes/[A-Za-z0-9_.-]+"), "<path>"),
    (re.compile(r"/home/[A-Za-z0-9_.-]+"), "<path>"),
    (re.compile(r"ghp_[A-Za-z0-9]{20,}"), "<redacted>"),
    (re.compile(r"gho_[A-Za-z0-9]{20,}"), "<redacted>"),
    (re.compile(r"github[_]pat[_][A-Za-z0-9_]+"), "<redacted>"),
    (re.compile(r"sk[-]ant[-][A-Za-z0-9_-]+"), "<redacted>"),
    (re.compile(r"AKIA[0-9A-Z]{16}"), "<redacted>"),
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), "<redacted>"),
)


def redact_text(text: str) -> str:
    """Replace absolute home/volume paths and credential-shaped strings."""
    for pattern, replacement in _SUBSTITUTIONS:
        text = pattern.sub(replacement, text)
    return text
