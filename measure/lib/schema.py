"""Real JSON-Schema validation.

Until now `measurements/schema.json` was decorative: `tools/record.sh` and
`tools/verify-measurements.sh` each ran an identical five-key `jq has()` check and
never opened the schema. Three of its eight required keys went unverified, and
every A/B record ever produced was schema-invalid without anything noticing.

Validation runs in-process at emit time, so a regression aborts the run before
bytes reach $STAGING/runs/ — not later, if someone remembers to run the gate.
"""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator

from measure.lib.staging import repo_root

SCHEMA_PATH = "measurements/schema.json"


@lru_cache(maxsize=1)
def _validator() -> Draft202012Validator:
    schema = json.loads((repo_root() / SCHEMA_PATH).read_text())
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema)


def validation_errors(document: dict[str, Any]) -> list[str]:
    """Every error, sorted by path. Empty means valid."""
    errors = sorted(_validator().iter_errors(document), key=lambda e: list(e.absolute_path))
    return [f"{'/'.join(str(p) for p in e.absolute_path) or '<root>'}: {e.message}" for e in errors]


def validate(document: dict[str, Any]) -> None:
    """Raise with every error listed, not just the first."""
    errors = validation_errors(document)
    if errors:
        joined = "\n  ".join(errors)
        raise ValueError(f"measurement does not match {SCHEMA_PATH}:\n  {joined}")


def write_validated(document: dict[str, Any], path: Path) -> Path:
    """Validate, then write. Never the other way round."""
    validate(document)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(document, indent=2) + "\n")
    return path


def main() -> int:
    """CLI so the shell gates can call real validation: `uv run -m measure.lib.schema FILE...`"""
    import sys

    paths = sys.argv[1:]
    if not paths:
        print("usage: python -m measure.lib.schema <file.json>...", file=sys.stderr)
        return 2

    bad = 0
    for raw_path in paths:
        path = Path(raw_path)
        try:
            document = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError) as exc:
            print(f"✗ schema: {path} could not be read as JSON: {exc}", file=sys.stderr)
            bad += 1
            continue
        errors = validation_errors(document)
        if errors:
            bad += 1
            print(f"✗ schema: {path}", file=sys.stderr)
            for error in errors:
                print(f"    {error}", file=sys.stderr)
    if bad:
        return 1
    print(f"✓ schema: {len(paths)} measurement(s) valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
