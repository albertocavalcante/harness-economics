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


# --- the coverage guard, at its call site ------------------------------------
# These exist because the guard shipped DEAD on the Claude path for two commits.
# share_from_reps() neither accepted nor forwarded `coverage`, so a run with half
# its cache attributes missing still published a confident number. The suite
# missed it because test_aggregate.py exercises cache_read_share() directly.
# Assert through build_record, which is the indirection that hid the bug.


def test_run_refuses_a_share_when_coverage_is_incomplete() -> None:
    record = run.build_record(_reps(3), [True, False], task_id="T2", mode="warm", model=None)
    agg = record["aggregates"]
    assert agg["cache_attr_coverage"] == 0.5
    assert agg["cache_read_share"] is None, "a silent meter must not publish a share"


def test_run_publishes_a_share_at_full_coverage() -> None:
    record = run.build_record(_reps(3), [True, True], task_id="T2", mode="warm", model=None)
    agg = record["aggregates"]
    assert agg["cache_attr_coverage"] == 1.0
    assert agg["cache_read_share"] is not None


def test_ab_refuses_a_share_when_coverage_is_incomplete() -> None:
    record = ab.build_record(
        _reps(2, priming_first=False),
        _reps(2, priming_first=False),
        [True, False, True, False],
        bootstrap_ci([0.01, 0.02], seed=1),
        variable="model",
        value_a="a",
        value_b="b",
        task_id="T2",
    )
    assert record["aggregates"]["cache_attr_coverage"] == 0.5
    assert record["aggregates"]["cache_read_share"] is None


# --- A/B design fixes --------------------------------------------------------


def test_ab_reports_invalid_rate_per_arm() -> None:
    """Pooled, a config failing only in arm B read as half-strength."""
    good = [project_rep(_raw(0.01), rep=i, valid=True, priming=False) for i in range(2)]
    bad = [project_rep(_raw(0.01), rep=i, valid=False, priming=False) for i in range(2)]
    record = ab.build_record(
        good,
        bad,
        [True] * 4,
        None,
        variable="model",
        value_a="a",
        value_b="b",
        task_id="T2",
    )
    agg = record["aggregates"]
    assert agg["invalid_rep_rate_a"] == 0.0
    assert agg["invalid_rep_rate_b"] == 1.0
    assert agg["invalid_rep_rate"] == 0.5, "pooled rate is still reported, but no longer alone"
    assert validation_errors(record) == []


def test_ab_excludes_priming_reps_from_aggregates() -> None:
    """Rep 0 of each arm is a cold first call; counting it skewed every mean."""
    reps_a = [project_rep(_raw(1.0), rep=0, valid=True, priming=True)] + [
        project_rep(_raw(0.01), rep=i, valid=True, priming=False) for i in (1, 2)
    ]
    reps_b = [project_rep(_raw(1.0), rep=0, valid=True, priming=True)] + [
        project_rep(_raw(0.01), rep=i, valid=True, priming=False) for i in (1, 2)
    ]
    record = ab.build_record(
        reps_a, reps_b, [True] * 4, None, variable="model", value_a="a", value_b="b", task_id="T2"
    )
    agg = record["aggregates"]
    assert agg["total_reps"] == 6, "priming reps are retained in the record"
    assert agg["valid_reps"] == 4, "but excluded from the scored set"
    assert agg["mean_cost_usd"] == pytest.approx(0.01), (
        "the 1.0 priming cost must not pull the mean"
    )


# --- cache-mode variable -----------------------------------------------------


def test_cache_mode_is_a_timing_variable_not_a_flag() -> None:
    assert ab.arm_flags("cache-mode", "cold") == []
    assert ab.arm_flags("cache-mode", "warm") == []
    assert ab.arm_sleep("cache-mode", "cold", 370) == 370
    assert ab.arm_sleep("cache-mode", "warm", 370) == 0
    assert ab.arm_sleep("model", "cold", 370) == 0, "only cache-mode idles"


def test_cache_mode_record_is_labelled_mixed_and_records_the_sleep() -> None:
    """Claiming 'warm' for a run whose whole point is a cold arm would misdescribe it."""
    record = ab.build_record(
        _reps(2, priming_first=False),
        _reps(2, priming_first=False),
        [True] * 4,
        bootstrap_ci([0.01, 0.02], seed=1),
        variable="cache-mode",
        value_a="warm",
        value_b="cold",
        task_id="T2",
        cold_sleep=300,
    )
    assert record["cache_mode"] == "mixed"
    assert record["variant"]["cold_sleep_seconds"] == 300
    assert validation_errors(record) == []


def test_other_variables_stay_warm_and_omit_the_sleep() -> None:
    record = ab.build_record(
        _reps(2, priming_first=False),
        _reps(2, priming_first=False),
        [True] * 4,
        None,
        variable="mcp",
        value_a="none",
        value_b="/tmp/mcp.json",
        task_id="T2",
    )
    assert record["cache_mode"] == "warm"
    assert "cold_sleep_seconds" not in record["variant"]
    assert validation_errors(record) == []


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


def test_verify_answer_matcher_stays_unanchored() -> None:
    """The MATCHER is deliberately preserved from `grep -Eq`.

    Tightening `re.search` to `re.fullmatch` would silently change every
    historical validity judgement. The looseness is pinned here; individual tasks
    anchor their own EXPECTED pattern instead (see below).
    """
    assert verify_answer({"result": "the answer is 7"}, "7") is True
    assert verify_answer({"result": "17"}, "7") is True, "unanchored match is the ported behaviour"
    assert verify_answer({"result": "  ComputeInvoiceTotal  "}, "ComputeInvoiceTotal") is True
    assert verify_answer({"result": "nope"}, "7") is False
    assert verify_answer({}, "7") is False


def test_numeric_tasks_anchor_their_expectations() -> None:
    """invalid_rep_rate is the headline aggregate; a loose pattern flatters it.

    The fixture's filler is `// note: <word> <word> handles case <0-9999>`, and in
    the current corpus 1,186 of those lines contain a 7, 106 contain 99 and 10
    contain 171. With a bare `EXPECTED: 7`, any answer quoting a filler line
    scored as correct.
    """
    for task_id in ("T2", "T3", "T4", "T5"):
        assert load_task(task_id).expected.startswith("^"), f"{task_id} is not anchored"
        assert load_task(task_id).expected.endswith("$"), f"{task_id} is not anchored"


def test_anchored_expectations_reject_filler_echoes() -> None:
    t2 = load_task("T2").expected
    assert verify_answer({"result": "7"}, t2) is True
    assert verify_answer({"result": "  7  "}, t2) is True, "the result is trimmed before matching"
    assert verify_answer({"result": "// note: kappa xi handles case 5171"}, t2) is False
    assert verify_answer({"result": "the max retry count is 7"}, t2) is False

    t4 = load_task("T4").expected
    assert verify_answer({"result": "99"}, t4) is True
    assert verify_answer({"result": "// note: handles case 1994"}, t4) is False


def test_t5_is_the_long_horizon_task() -> None:
    """T1-T4 finish in 2-7 turns, well short of the break-even regime."""
    t5 = load_task("T5")
    assert verify_answer({"result": "171, 99, 16929"}, t5.expected) is True
    assert verify_answer({"result": "171,99,16929"}, t5.expected) is False, "format is specified"
    assert verify_answer({"result": "16929"}, t5.expected) is False, "all three are required"
    assert 171 * 99 == 16929
