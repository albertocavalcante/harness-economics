"""The projection is the safety control. These tests are what make it mechanical."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest

from measure.lib.projection import (
    EXPECTED_KEYS,
    Rep,
    flatten_keys,
    project_rep,
    rep_to_json,
    reported_cache_read,
)

CANARY = "CANARY-b7f3e1"

FIXTURES = Path(__file__).resolve().parents[1] / "measure" / "lib" / "emit_fixtures.json"


def poisoned_raw() -> dict[str, Any]:
    """A payload where every field that must NOT leak carries the canary.

    Modelled on a real `claude -p --output-format json` result: conversation
    text, session identifiers, absolute paths, per-model cost breakdowns and
    tool-permission records.
    """
    return {
        "type": "result",
        "subtype": "success",
        "is_error": False,
        "result": f"the answer is 42 {CANARY}",
        "session_id": CANARY,
        "uuid": CANARY,
        "cwd": f"/Users/{CANARY}/dev/secret-client",
        "permission_denials": [{"tool_name": CANARY, "tool_input": {"path": CANARY}}],
        "modelUsage": {CANARY: {"costUSD": 1.0, "inputTokens": 7}},
        "usage": {
            "input_tokens": 10,
            "output_tokens": 3,
            "cache_read_input_tokens": 8,
            "server_tool_use": {CANARY: 1},
        },
        "total_cost_usd": 0.5,
        "num_turns": 2,
        "duration_ms": 900,
    }


def test_projection_emits_exactly_the_allowlist() -> None:
    out = rep_to_json(project_rep(poisoned_raw(), rep=0, valid=True, priming=False))

    # Value leak: no canary anywhere in the serialised bytes.
    assert CANARY not in json.dumps(out)

    # Key leak: catches `**raw` even when the smuggled fields are purely numeric
    # and therefore carry no canary. This assertion is the teeth.
    assert flatten_keys(out) == EXPECTED_KEYS


def test_rep_rejects_unknown_fields() -> None:
    """`Rep(**raw)` must fail loudly rather than widen the output."""
    with pytest.raises(TypeError, match=r"unexpected keyword argument"):
        Rep(**poisoned_raw())  # type: ignore[arg-type]


def test_rep_is_frozen_and_slotted() -> None:
    rep = project_rep(poisoned_raw(), rep=0, valid=True, priming=False)
    with pytest.raises(Exception):  # noqa: B017 - FrozenInstanceError or AttributeError
        rep.total_cost_usd = 99.0  # type: ignore[misc]
    with pytest.raises(AttributeError):
        rep.session_id = CANARY  # type: ignore[attr-defined]


# --- nullability, from measure/lib/emit_fixtures.json -------------------------
# These three shapes were written to exercise emit.sh and then never wired to a
# runner. They are the reason this file exists.


def _fixtures() -> list[dict[str, Any]]:
    return json.loads(FIXTURES.read_text())


def test_fixture_file_is_present_and_shaped() -> None:
    fixtures = _fixtures()
    assert len(fixtures) == 3
    assert {f["_name"] for f in fixtures} == {
        "full-cache-creation-object",
        "cache_creation-absent",
        "null-ephemerals",
    }


@pytest.mark.parametrize("fixture", _fixtures(), ids=lambda f: str(f["_name"]))
def test_projection_survives_every_nullability_shape(fixture: dict[str, Any]) -> None:
    out = rep_to_json(project_rep(fixture, rep=1, valid=True, priming=False))
    assert flatten_keys(out) == EXPECTED_KEYS
    usage = out["usage"]
    assert isinstance(usage["cache_creation_input_tokens"], float)
    assert isinstance(usage["cache_creation"]["ephemeral_5m_input_tokens"], float)
    assert isinstance(usage["cache_creation"]["ephemeral_1h_input_tokens"], float)


def test_explicit_zero_beats_the_derived_sum() -> None:
    """jq's `//` treats 0 as truthy; Python's `or` does not.

    An explicit 0 from the payload must win over the sum of the ephemerals, or
    the port silently changes what every historical measurement meant.
    """
    raw = {
        "usage": {
            "cache_creation_input_tokens": 0,
            "cache_creation": {
                "ephemeral_5m_input_tokens": 111,
                "ephemeral_1h_input_tokens": 222,
            },
        }
    }
    rep = project_rep(raw, rep=0, valid=True, priming=False)
    assert rep.usage.cache_creation_input_tokens == 0.0


def test_absent_total_is_derived_from_ephemerals() -> None:
    raw = {
        "usage": {
            "cache_creation": {
                "ephemeral_5m_input_tokens": 111,
                "ephemeral_1h_input_tokens": 222,
            }
        }
    }
    rep = project_rep(raw, rep=0, valid=True, priming=False)
    assert rep.usage.cache_creation_input_tokens == 333.0


def test_reported_cache_read_distinguishes_silence_from_zero() -> None:
    """The distinction run.sh destroyed by coercing before measuring coverage."""
    assert reported_cache_read({"usage": {"cache_read_input_tokens": 0}}) is True
    assert reported_cache_read({"usage": {}}) is False
    assert reported_cache_read({"usage": {"cache_read_input_tokens": None}}) is False
