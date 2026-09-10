"""Parse Copilot OTLP spans into a measurement record.

Reads the JSON-lines file written by the local collector and projects ONLY named
numeric token attributes out of it. Same safety property as
measure/lib/projection.py: span content cannot leak because content is never
selected. Do not "improve" this by dumping whole spans and filtering afterwards —
the allowlist is the control.

Two behaviours here are load-bearing and were bugs in the shell original:

  * Only leaf `chat` spans are summed. `invoke_agent` is a parent rollup whose
    totals already contain its children, so adding both double-counts every
    nested call — the same defect microsoft/vscode#331438 fixed in Copilot's own
    billing telemetry.
  * A missing attribute yields None, not 0. Defaulting to zero conflates "the
    meter said nothing" with "the cache genuinely missed", and several Copilot
    paths never populate these fields at all (microsoft/vscode#309207, #308370).
"""

from __future__ import annotations

import argparse
import json
import platform
import sys
from collections.abc import Iterable, Iterator
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Final, final

from measure.lib.aggregate import TokenSemantics, cache_read_share
from measure.lib.schema import write_validated
from measure.lib.staging import (
    STAGING,
    HarnessError,
    die,
    ensure_staging,
    ok,
    utc_now,
    warn,
)

LEAF_SPAN: Final = "chat"
PARENT_SPAN: Final = "invoke_agent"

SURFACES: Final = ("copilot-vscode", "copilot-cli", "copilot-sdk")

# The complete set of attributes that may ever be read out of a span.
ATTR_INPUT: Final = "gen_ai.usage.input_tokens"
ATTR_OUTPUT: Final = "gen_ai.usage.output_tokens"
ATTR_CACHE_READ: Final = "gen_ai.usage.cache_read.input_tokens"
ATTR_CACHE_CREATION: Final = "gen_ai.usage.cache_creation.input_tokens"


@final
@dataclass(frozen=True, slots=True)
class SpanTokens:
    """One span's token attributes. None means the attribute was absent."""

    name: str
    input_tokens: float | None
    output_tokens: float | None
    cache_read: float | None
    cache_creation: float | None


@final
@dataclass(frozen=True, slots=True)
class SpanAggregate:
    leaf_spans: int
    parent_spans: int
    input_tokens: float | None
    output_tokens: float | None
    cache_read: float | None
    cache_creation: float | None
    cache_attr_coverage: float | None
    cache_read_share: float | None


def _attr(span: dict[str, Any], key: str) -> float | None:
    """Read one OTLP attribute. intValue arrives as a string, hence the coercion."""
    for attribute in span.get("attributes") or []:
        if not isinstance(attribute, dict) or attribute.get("key") != key:
            continue
        value = attribute.get("value")
        if not isinstance(value, dict):
            return None
        raw = value.get("intValue", value.get("doubleValue"))
        if raw is None:
            return None
        try:
            return float(raw)
        except (TypeError, ValueError):
            return None
    return None


def _spans_in(payload: Any) -> Iterator[SpanTokens]:
    if not isinstance(payload, dict):
        return
    for resource in payload.get("resourceSpans") or []:
        for scope in resource.get("scopeSpans") or []:
            for span in scope.get("spans") or []:
                name = span.get("name") or "unknown"
                if name not in (LEAF_SPAN, PARENT_SPAN):
                    continue
                yield SpanTokens(
                    name=name,
                    input_tokens=_attr(span, ATTR_INPUT),
                    output_tokens=_attr(span, ATTR_OUTPUT),
                    cache_read=_attr(span, ATTR_CACHE_READ),
                    cache_creation=_attr(span, ATTR_CACHE_CREATION),
                )


def iter_spans(lines: Iterable[str]) -> Iterator[SpanTokens]:
    """Walk the OTLP envelope, yielding only model-call spans.

    The collector writes JSON Lines, one envelope per line, which is the fast
    path. A pretty-printed capture — hand-saved, or piped through `jq .` — is
    still one valid JSON document, so fall back to parsing the whole text rather
    than silently yielding nothing. Silence here is indistinguishable from a
    session that made no model calls, which is a very different claim.
    """
    text_lines = list(lines)
    yielded = 0

    for line in text_lines:
        stripped = line.strip()
        if not stripped:
            continue
        try:
            payload = json.loads(stripped)
        except json.JSONDecodeError:
            continue
        for span in _spans_in(payload):
            yielded += 1
            yield span

    # Gate on spans yielded, not on lines parsed. In a pretty-printed capture the
    # final line is often a complete, valid JSON object on its own — so a
    # "did any line parse?" flag flips true, suppresses the fallback, and the
    # whole file silently reads as zero spans.
    if yielded:
        return

    joined = "\n".join(text_lines).strip()
    if not joined:
        return
    try:
        whole = json.loads(joined)
    except json.JSONDecodeError:
        return
    if isinstance(whole, list):
        for entry in whole:
            yield from _spans_in(entry)
    else:
        yield from _spans_in(whole)


def _total(values: list[float | None]) -> float | None:
    present = [v for v in values if v is not None]
    return sum(present) if present else None


def _aggregate_from(leaves: list[SpanTokens], parents: int) -> SpanAggregate:
    n = len(leaves)
    coverage = (sum(1 for s in leaves if s.cache_read is not None) / n) if n else None
    input_tokens = _total([s.input_tokens for s in leaves])
    cache_read = _total([s.cache_read for s in leaves])

    return SpanAggregate(
        leaf_spans=n,
        parent_spans=parents,
        input_tokens=input_tokens,
        output_tokens=_total([s.output_tokens for s in leaves]),
        cache_read=cache_read,
        cache_creation=_total([s.cache_creation for s in leaves]),
        cache_attr_coverage=coverage,
        cache_read_share=cache_read_share(
            cache_read=cache_read or 0.0,
            cache_creation=0.0,
            input_tokens=input_tokens or 0.0,
            semantics=TokenSemantics.INCLUDES_CACHE_READ,
            coverage=coverage,
        ),
    )


def aggregate_spans(spans: Iterable[SpanTokens]) -> SpanAggregate:
    """Materialise once, then split leaves from parents."""
    materialised = list(spans)
    leaves = [s for s in materialised if s.name == LEAF_SPAN]
    parents = sum(1 for s in materialised if s.name == PARENT_SPAN)
    return _aggregate_from(leaves, parents)


def build_record(agg: SpanAggregate, *, surface: str, label: str) -> dict[str, Any]:
    """Assemble the measurement. Only named fields; nothing from the spans."""
    return {
        "schema_version": "1",
        "timestamp_utc": utc_now(),
        "harness": "copilot",
        "source_surface": surface,
        "token_semantics": TokenSemantics.INCLUDES_CACHE_READ.value,
        "billing_basis": "ai_credits",
        "harness_version": "unknown",
        "telemetry_version": "unknown",
        "model": "unknown",
        "workload": label,
        "cache_mode": "warm",
        "variant": {"kind": "manual"},
        "reps": [],
        "aggregates": {
            "spans": agg.leaf_spans,
            "cache_read_share": agg.cache_read_share,
            "cache_attr_coverage": agg.cache_attr_coverage,
            "mean_input_tokens": agg.input_tokens,
            "mean_output_tokens": agg.output_tokens,
            "mean_cache_read_tokens": agg.cache_read,
            "mean_cache_creation_tokens": agg.cache_creation,
            "mean_cost_usd": None,
            "invalid_rep_rate": None,
            "valid_reps": None,
            "total_reps": None,
        },
        "environment": {"os": platform.system(), "arch": platform.machine()},
    }


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="parse_spans",
        description="Parse Copilot OTLP spans into a measurement record.",
    )
    parser.add_argument("spans", type=Path, help="JSON-lines file written by the collector")
    parser.add_argument(
        "--surface",
        required=True,
        choices=SURFACES,
        help=(
            "Which Copilot surface produced these spans. Mandatory and unguessable "
            "from the spans: the extension, CLI and SDK have reported different "
            "numbers for the same spend."
        ),
    )
    parser.add_argument("--label", default="copilot", help="workload slug")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)

    try:
        if not args.spans.is_file():
            die("parse-spans", f"{args.spans} is not a file")
        text = args.spans.read_text()
        if not text.strip():
            die(
                "parse-spans",
                f"{args.spans} is empty — was the collector running while you used Copilot?",
            )

        agg = aggregate_spans(iter_spans(text.splitlines()))
        # Three different failures used to share one misleading message. An
        # unparseable file reported "only parent rollups were captured", which
        # sends you to look at Copilot instead of at the capture.
        if agg.leaf_spans == 0 and agg.parent_spans == 0:
            die(
                "parse-spans",
                f"{args.spans} parsed no OTLP spans at all — expected JSON Lines from the "
                "collector's file exporter. Check the file is the collector's output and "
                "not, say, a truncated copy.",
            )
        if agg.leaf_spans == 0:
            die(
                "parse-spans",
                f"captured {agg.parent_spans} '{PARENT_SPAN}' rollup(s) but no leaf "
                f"'{LEAF_SPAN}' spans. Summing rollups would double-count nested calls, "
                "so there is nothing safe to report.",
            )

        ensure_staging()
        out = STAGING / "runs" / f"{utc_now()[:10]}-{args.label}.json"
        write_validated(build_record(agg, surface=args.surface, label=args.label), out)
    except HarnessError as exc:
        print(exc, file=sys.stderr)
        return 1

    print()
    rows = (
        ("leaf chat spans", agg.leaf_spans),
        ("parent spans (excl.)", agg.parent_spans),
        ("input tokens", agg.input_tokens),
        ("output tokens", agg.output_tokens),
        ("cache read", agg.cache_read),
        ("cache creation", agg.cache_creation),
        ("cache attr coverage", agg.cache_attr_coverage),
        ("cache read share", agg.cache_read_share),
    )
    print(f"{'FIELD':<24}{'VALUE':>12}")
    for name, value in rows:
        print(f"{name:<24}{'n/a' if value is None else value:>12}")
    print()

    if agg.cache_read_share is None:
        missing = 1.0 - (agg.cache_attr_coverage or 0.0)
        warn(
            "parse-spans",
            f"cache_read_share is null — attributes missing on {missing:.0%} of spans",
        )
        print("  A silent meter is not a cache miss. Do not read this run as low-cost.")
        print("  See reference/KNOWN-ISSUES.md — several Copilot paths never populate these.")
        print()

    ok("parse-spans", f"wrote {out}")
    print(f"Review it, then promote with: just record {out}")
    print()
    print("Note: harness_version, telemetry_version and model are 'unknown' — the spans")
    print("do not carry them. Fill them in by hand before recording, or the record is not")
    print("interpretable: Copilot's meter changed at eight VS Code versions.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
