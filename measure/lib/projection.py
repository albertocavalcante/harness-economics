"""The load-bearing safety control for this repo. Ported from measure/lib/emit.sh.

WHY THIS IS THE REAL CONTROL (not redact.py): a raw `claude -p --output-format
json` result contains the full conversation text, file paths from --add-dir, the
session id, and anything else the model said. None of that may ever reach
measurements/ (which IS committed) or even $STAGING/runs/ (which is promoted into
the repo by `just record`). The only way to guarantee that is to never give the
leaking content a path into the output at all — not "filter it out", which
requires an exhaustive and inevitably incomplete denylist, but build the output as
a NEW object naming every field it wants and nothing else. A field that isn't
named below cannot appear in the output, full stop, regardless of what the raw
payload contains. Impossible-by-construction, not impossible-by-diligence.

In bash that property came from a jq object constructor. In Python it comes from
frozen, slotted dataclasses, which is strictly stronger:

  * `Rep(**raw)` raises TypeError naming the offending key, on the first run.
  * slots=True means no attribute can be added after construction.
  * frozen=True means no field can be swapped for a richer value later.
  * asdict() can only emit declared fields.

NULLABILITY — read before touching this. Per docs/02-prompt-caching.md, verified
2026-09-10 against the CLI's own --output-format json:

  * `usage.cache_creation` may be ABSENT entirely.
  * `usage.cache_creation.ephemeral_5m_input_tokens` and `...ephemeral_1h_...`
    may each be explicitly `null` even when the parent object IS present.
  * `usage.cache_creation_input_tokens` may be absent; when present it is
    documented as the sum of the two ephemerals, but do not trust that invariant
    blindly.

jq's `//` was doing the work in the bash version. Python's `or` is NOT the same
operator: jq treats 0 as truthy, Python treats it as falsy. Using `x or 0` here
would silently replace an explicit, meaningful 0 with a derived sum. Every
coercion below is therefore an explicit `is None` check via `_num`.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any, Final, final

# Every key that may ever appear in a projected rep, fully qualified. Frozen here
# so that widening the output is a deliberate, reviewable edit to the file that
# documents the control. tests/test_projection.py asserts equality against this.
EXPECTED_KEYS: Final[frozenset[str]] = frozenset(
    {
        "rep",
        "valid",
        "priming",
        "total_cost_usd",
        "num_turns",
        "duration_ms",
        "usage",
        "usage.input_tokens",
        "usage.output_tokens",
        "usage.cache_read_input_tokens",
        "usage.cache_creation_input_tokens",
        "usage.cache_creation",
        "usage.cache_creation.ephemeral_5m_input_tokens",
        "usage.cache_creation.ephemeral_1h_input_tokens",
    }
)


def _num(value: Any, default: float = 0.0) -> float:
    """jq's `// default`, minus the falsy-zero bug Python's `or` would introduce."""
    if value is None or isinstance(value, bool):
        return default
    if isinstance(value, int | float):
        return float(value)
    return default


@final
@dataclass(frozen=True, slots=True)
class CacheCreation:
    ephemeral_5m_input_tokens: float
    ephemeral_1h_input_tokens: float


@final
@dataclass(frozen=True, slots=True)
class Usage:
    input_tokens: float
    output_tokens: float
    cache_read_input_tokens: float
    cache_creation: CacheCreation
    cache_creation_input_tokens: float


@final
@dataclass(frozen=True, slots=True)
class Rep:
    rep: int
    valid: bool
    priming: bool
    usage: Usage
    total_cost_usd: float
    num_turns: float
    duration_ms: float


def project_rep(
    raw: dict[str, Any],
    *,
    rep: int,
    valid: bool,
    priming: bool,
) -> Rep:
    """Project one raw `claude -p --output-format json` payload into a Rep.

    `rep`, `valid` and `priming` are control-flow metadata the caller already
    knows (loop counters and verify results). They are passed as keyword
    arguments, never read out of `raw`.
    """
    usage = raw.get("usage")
    usage = usage if isinstance(usage, dict) else {}

    creation = usage.get("cache_creation")
    creation = creation if isinstance(creation, dict) else {}

    eph_5m = _num(creation.get("ephemeral_5m_input_tokens"))
    eph_1h = _num(creation.get("ephemeral_1h_input_tokens"))

    # Documented as the sum of the two ephemerals when present; derive it
    # ourselves when the field is absent rather than trusting a value we cannot
    # cross-check. An explicit 0 in the payload wins over the derived sum, which
    # is why this is an `is None` test and not `or`.
    declared_creation = usage.get("cache_creation_input_tokens")
    creation_total = _num(declared_creation) if declared_creation is not None else eph_5m + eph_1h

    return Rep(
        rep=rep,
        valid=valid,
        priming=priming,
        usage=Usage(
            input_tokens=_num(usage.get("input_tokens")),
            output_tokens=_num(usage.get("output_tokens")),
            cache_read_input_tokens=_num(usage.get("cache_read_input_tokens")),
            cache_creation=CacheCreation(
                ephemeral_5m_input_tokens=eph_5m,
                ephemeral_1h_input_tokens=eph_1h,
            ),
            cache_creation_input_tokens=creation_total,
        ),
        total_cost_usd=_num(raw.get("total_cost_usd")),
        num_turns=_num(raw.get("num_turns")),
        duration_ms=_num(raw.get("duration_ms")),
    )


def reported_cache_read(raw: dict[str, Any]) -> bool:
    """Did the payload actually carry a cache-read figure?

    Kept separate from `project_rep` because the projection coerces missing
    values to 0 — which is correct for Anthropic's documented shape, but means a
    projected Rep can no longer distinguish "the meter said 0" from "the meter
    said nothing". `cache_attr_coverage` needs that distinction, and computing it
    after projection is what made the metric structurally always 1 in run.sh.
    """
    usage = raw.get("usage")
    return isinstance(usage, dict) and usage.get("cache_read_input_tokens") is not None


def rep_to_json(rep: Rep) -> dict[str, Any]:
    """Serialise a Rep. Only declared fields can appear."""
    return asdict(rep)


def flatten_keys(obj: Any, prefix: str = "") -> set[str]:
    """Recursively qualified key set, for asserting the projection never widens."""
    keys: set[str] = set()
    if isinstance(obj, dict):
        for key, value in obj.items():
            qualified = f"{prefix}.{key}" if prefix else str(key)
            keys.add(qualified)
            keys |= flatten_keys(value, qualified)
    return keys
