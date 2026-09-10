"""Every emitter's output, against the now-strict schema.

`additionalProperties` is false at the root, in `reps[]` items and in
`aggregates`, so an undeclared key is a hard failure. That must be caught here
and not by a paid `claude -p` run.
"""

from __future__ import annotations

import json

import pytest

from measure.claude import ab, run
from measure.claude.cli import TASK_IDS, load_task, verify_answer
from measure.lib.projection import project_rep
from measure.lib.schema import validation_errors
from measure.lib.stats import bootstrap_ci

CANARY = "CANARY-b7f3e1"


def _raw(cost: float, *, cache_read: float = 800, with_cache_attr: bool = True) -> dict:
    usage: dict = {"input_tokens": 100, "output_tokens": 20}
    if with_cache_attr:
        usage["cache_read_input_tokens"] = cache_read
        usage["cache_creation"] = {
            "ephemeral_5m_input_tokens": 50,
            "ephemeral_1h_input_tokens": 0,
        }
    return {
        "result": f"ComputeInvoiceTotal {CANARY}",
        "session_id": CANARY,
        "usage": usage,
        "total_cost_usd": cost,
        "num_turns": 2,
        "duration_ms": 900,
    }


def _reps(n: int, *, priming_first: bool = True):
    return [
        project_rep(
            _raw(0.01 * (i + 1)),
            rep=i,
            valid=True,
            priming=(priming_first and i == 0),
        )
        for i in range(n)
    ]


def test_run_record_is_schema_valid() -> None:
    record = run.build_record(
        _reps(4),
        [True, True, True],
        task_id="T2",
        mode="warm",
        model=None,
    )
    assert validation_errors(record) == []


def test_ab_record_is_schema_valid() -> None:
    """The shell version emitted four required fields short and nothing noticed."""
    reps_a = _reps(3, priming_first=False)
    reps_b = _reps(3, priming_first=False)
    ci = bootstrap_ci([0.01, -0.002, 0.004], seed=7)
    record = ab.build_record(
        reps_a,
        reps_b,
        [True] * 6,
        ci,
        variable="mcp",
        value_a="none",
        value_b="/tmp/mcp.json",
        task_id="T2",
    )
    assert validation_errors(record) == []


def test_ab_record_carries_the_four_fields_ab_sh_omitted() -> None:
    record = ab.build_record(
        _reps(2, priming_first=False),
        _reps(2, priming_first=False),
        [True] * 4,
        bootstrap_ci([0.01, 0.02], seed=7),
        variable="model",
        value_a="a",
        value_b="b",
        task_id="T2",
    )
    for field in ("source_surface", "token_semantics", "billing_basis"):
        assert field in record, f"ab.sh omitted {field}"
    assert "cache_attr_coverage" in record["aggregates"]


def test_ab_emits_numbers_not_the_string_na() -> None:
    """The shell version passed these through jq --arg, so they serialised as strings."""
    record = ab.build_record(
        _reps(1, priming_first=False),
        _reps(1, priming_first=False),
        [True, True],
        None,  # fewer than two pairs
        variable="model",
        value_a="a",
        value_b="b",
        task_id="T2",
    )
    agg = record["aggregates"]
    for field in ("paired_diff_mean", "paired_diff_ci95_low", "paired_diff_ci95_high"):
        assert agg[field] is None, f"{field} must be null, never the string 'n/a'"
    assert validation_errors(record) == []


def test_ab_records_the_seed_so_the_interval_can_be_re_derived() -> None:
    record = ab.build_record(
        _reps(2, priming_first=False),
        _reps(2, priming_first=False),
        [True] * 4,
        bootstrap_ci([0.01, 0.02, 0.03], seed=4242),
        variable="model",
        value_a="a",
        value_b="b",
        task_id="T2",
    )
    assert record["aggregates"]["bootstrap_seed"] == 4242
    assert record["aggregates"]["bootstrap_resamples"] == 2000


def test_no_record_carries_conversation_content() -> None:
    """The projection guarantee, asserted on the fully assembled records."""
    run_record = run.build_record(_reps(3), [True, True], task_id="T2", mode="warm", model=None)
    ab_record = ab.build_record(
        _reps(2, priming_first=False),
        _reps(2, priming_first=False),
        [True] * 4,
        bootstrap_ci([0.01, 0.02], seed=1),
        variable="model",
        value_a="a",
        value_b="b",
        task_id="T2",
    )
    assert CANARY not in json.dumps(run_record)
    assert CANARY not in json.dumps(ab_record)


def test_coverage_can_actually_be_below_one() -> None:
    """run.sh made this metric structurally always 1 by measuring after coercion."""
    record = run.build_record(_reps(3), [True, False], task_id="T2", mode="warm", model=None)
    assert record["aggregates"]["cache_attr_coverage"] == 0.5


def test_undeclared_key_is_now_rejected() -> None:
    """Proves additionalProperties:false is doing work."""
    record = run.build_record(_reps(2), [True], task_id="T2", mode="warm", model=None)
    record["aggregates"]["surprise_metric"] = 1
    errors = validation_errors(record)
    assert any("surprise_metric" in e for e in errors)


# --- task fixtures -----------------------------------------------------------


@pytest.mark.parametrize("task_id", TASK_IDS)
def test_every_task_file_loads(task_id: str) -> None:
    task = load_task(task_id)
    assert task.prompt.strip()
    assert task.expected
    assert "EXPECTED:" not in task.prompt


def test_verify_answer_stays_unanchored() -> None:
    """Deliberately preserved from `grep -Eq`.

    Tightening this to a full match would silently change every historical
    validity judgement, so the looseness is pinned rather than fixed.
    """
    assert verify_answer({"result": "the answer is 7"}, "7") is True
    assert verify_answer({"result": "17"}, "7") is True, "unanchored match is the ported behaviour"
    assert verify_answer({"result": "  ComputeInvoiceTotal  "}, "ComputeInvoiceTotal") is True
    assert verify_answer({"result": "nope"}, "7") is False
    assert verify_answer({}, "7") is False
