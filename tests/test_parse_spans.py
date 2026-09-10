"""The two OTLP captures hand-verified during the port, pinned as tests."""

from __future__ import annotations

import json
from typing import Any

from measure.copilot.parse_spans import (
    aggregate_spans,
    build_record,
    iter_spans,
)

CANARY = "CANARY-b7f3e1"


def _span(name: str, **attrs: float | None) -> dict[str, Any]:
    keys = {
        "input_tokens": "gen_ai.usage.input_tokens",
        "output_tokens": "gen_ai.usage.output_tokens",
        "cache_read": "gen_ai.usage.cache_read.input_tokens",
        "cache_creation": "gen_ai.usage.cache_creation.input_tokens",
    }
    return {
        "name": name,
        "attributes": [
            {"key": keys[k], "value": {"intValue": str(int(v))}}
            for k, v in attrs.items()
            if v is not None
        ],
    }


def _envelope(*spans: dict[str, Any]) -> list[str]:
    return [json.dumps({"resourceSpans": [{"scopeSpans": [{"spans": list(spans)}]}]})]


def test_parent_rollup_is_excluded_from_sums() -> None:
    """microsoft/vscode#331438 reproduced in our own parser, now guarded.

    The parent's totals already contain both children. Summing all three gives
    6000 input and a 0.436 share; only the leaves are correct.
    """
    lines = _envelope(
        _span(
            "invoke_agent",
            input_tokens=3000,
            output_tokens=300,
            cache_read=2400,
            cache_creation=100,
        ),
        _span("chat", input_tokens=2000, output_tokens=200, cache_read=1600, cache_creation=60),
        _span("chat", input_tokens=1000, output_tokens=100, cache_read=800, cache_creation=40),
    )
    agg = aggregate_spans(iter_spans(lines))

    assert agg.leaf_spans == 2
    assert agg.parent_spans == 1
    assert agg.input_tokens == 3000, "parent was summed — double-count regression"
    assert agg.cache_read == 2400
    assert agg.cache_attr_coverage == 1.0
    assert agg.cache_read_share == 0.8


def test_missing_attribute_yields_null_not_zero() -> None:
    """A silent meter must not read as a cache miss.

    The second span carries no cache attributes at all. The shell original
    defaulted them to 0 and reported a confident 0.348 share.
    """
    lines = _envelope(
        _span("chat", input_tokens=2000, output_tokens=200, cache_read=1600),
        _span("chat", input_tokens=1000, output_tokens=100),
    )
    agg = aggregate_spans(iter_spans(lines))

    assert agg.leaf_spans == 2
    assert agg.cache_attr_coverage == 0.5
    assert agg.cache_read_share is None, "incomplete coverage must refuse a number"
    assert agg.cache_creation is None


def test_copilot_share_uses_input_alone_as_denominator() -> None:
    """Copilot's input_tokens already includes cache reads (copilot-sdk#1160)."""
    lines = _envelope(_span("chat", input_tokens=1000, cache_read=800, cache_creation=0))
    agg = aggregate_spans(iter_spans(lines))
    assert agg.cache_read_share == 0.8


def test_record_never_carries_span_content() -> None:
    """Same allowlist guarantee as the Claude projection, on the Copilot path."""
    poisoned = {
        "name": "chat",
        "status": {"message": CANARY},
        "traceId": CANARY,
        "attributes": [
            {"key": "gen_ai.usage.input_tokens", "value": {"intValue": "100"}},
            {"key": "gen_ai.usage.cache_read.input_tokens", "value": {"intValue": "80"}},
            {"key": "gen_ai.prompt", "value": {"stringValue": CANARY}},
            {"key": "code.filepath", "value": {"stringValue": f"/Users/{CANARY}/secret.go"}},
        ],
    }
    lines = [json.dumps({"resourceSpans": [{"scopeSpans": [{"spans": [poisoned]}]}]})]
    agg = aggregate_spans(iter_spans(lines))
    record = build_record(agg, surface="copilot-cli", label="t")

    assert CANARY not in json.dumps(record)
    assert record["aggregates"]["mean_input_tokens"] == 100


def test_unrelated_span_names_are_ignored() -> None:
    lines = _envelope(
        _span("http.request", input_tokens=999999),
        _span("chat", input_tokens=100, cache_read=80),
    )
    agg = aggregate_spans(iter_spans(lines))
    assert agg.leaf_spans == 1
    assert agg.input_tokens == 100


def test_malformed_lines_are_skipped_not_fatal() -> None:
    lines = ["not json", "", *_envelope(_span("chat", input_tokens=100, cache_read=80))]
    agg = aggregate_spans(iter_spans(lines))
    assert agg.leaf_spans == 1


def test_pretty_printed_capture_still_parses() -> None:
    """Found by running the CLI, not by the suite.

    A hand-saved or `jq .`-piped capture is one JSON document across many lines.
    Line-by-line parsing yields nothing, and the run silently read as zero spans.
    """
    envelope = {
        "resourceSpans": [
            {"scopeSpans": [{"spans": [_span("chat", input_tokens=1000, cache_read=800)]}]}
        ]
    }
    agg = aggregate_spans(iter_spans(json.dumps(envelope, indent=2).splitlines()))
    assert agg.leaf_spans == 1
    assert agg.input_tokens == 1000


def test_trailing_valid_line_does_not_suppress_the_fallback() -> None:
    """The subtle half of that bug.

    In a pretty-printed capture the closing line is often a complete JSON object
    on its own. A "did any line parse?" flag flips true on it, suppresses the
    whole-document fallback, and the file reads as zero spans — indistinguishable
    from a session that made no model calls.
    """
    lines = [
        '{"resourceSpans":[{"scopeSpans":[{"spans":[',
        json.dumps(_span("invoke_agent", input_tokens=3000, cache_read=2400)) + ",",
        json.dumps(_span("chat", input_tokens=1000, cache_read=800)),
        "]}]}]}",
    ]
    # The third line is valid JSON standalone, but carries no resourceSpans.
    assert json.loads(lines[2])
    agg = aggregate_spans(iter_spans(lines))
    assert agg.leaf_spans == 1, "fallback was suppressed by a standalone-valid line"
    assert agg.parent_spans == 1
    assert agg.input_tokens == 1000


def test_record_is_schema_valid() -> None:
    """The shell original emitted four schema violations and nothing caught it."""
    from measure.lib.schema import validation_errors

    lines = _envelope(_span("chat", input_tokens=1000, cache_read=800, cache_creation=0))
    agg = aggregate_spans(iter_spans(lines))
    record = build_record(agg, surface="copilot-vscode", label="T2")

    assert validation_errors(record) == []


def test_shell_originals_four_violations_would_now_fail() -> None:
    """Documents exactly what the bash version emitted, so the fix cannot regress."""
    from measure.lib.schema import validation_errors

    legacy = {
        "schema_version": "1",
        "timestamp_utc": "2026-09-10T12:00:00Z",
        "harness": "github-copilot",  # not in the enum
        "workload": {"id": "t", "source": "manual"},  # object, schema wants a string
        "aggregates": {"cache_read_ratio": 0.8},  # old name, missing required fields
    }
    errors = validation_errors(legacy)
    joined = " ".join(errors)
    assert "harness" in joined
    assert "workload" in joined
    assert len(errors) >= 4
