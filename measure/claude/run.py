"""Run fixture tasks against `claude -p` N times and record aggregates.

Ported from measure/claude/run.sh.
"""

from __future__ import annotations

import argparse
import platform
import sys
import time
from pathlib import Path
from typing import Any, Final

from measure.claude.cli import (
    TASK_IDS,
    call_claude,
    claude_preflight,
    ensure_fixture,
    load_task,
    verify_answer,
)
from measure.lib.aggregate import TokenSemantics, mean, share_from_reps
from measure.lib.projection import Rep, project_rep, rep_to_json, reported_cache_read
from measure.lib.redact import redact_text
from measure.lib.schema import write_validated
from measure.lib.staging import (
    STAGING,
    HarnessError,
    claude_version,
    ensure_staging,
    ok,
    utc_now,
    warn,
)

# 5-minute TTL plus margin. Cold mode exists to measure the cliff, so the sleep
# has to clear it decisively rather than race it.
COLD_SLEEP_SECONDS: Final = 370


def _aggregate(reps: list[Rep], coverage_flags: list[bool]) -> dict[str, Any]:
    non_priming = [r for r in reps if not r.priming]
    valid = [r for r in non_priming if r.valid]

    # Coverage is computed from the RAW payloads, not from projected reps. The
    # projection coerces a missing cache_read to 0.0, so testing the projected
    # value for null — as run.sh did — made this metric structurally always 1.
    coverage = (sum(coverage_flags) / len(coverage_flags)) if coverage_flags else None

    return {
        "cache_read_share": share_from_reps(
            valid, TokenSemantics.EXCLUDES_CACHE_READ, coverage=coverage
        ),
        "cache_attr_coverage": coverage,
        "mean_cost_usd": mean([r.total_cost_usd for r in valid]),
        "mean_input_tokens": mean([r.usage.input_tokens for r in valid]),
        "mean_output_tokens": mean([r.usage.output_tokens for r in valid]),
        "mean_cache_read_tokens": mean([r.usage.cache_read_input_tokens for r in valid]),
        "mean_cache_creation_tokens": mean([r.usage.cache_creation_input_tokens for r in valid]),
        "invalid_rep_rate": (1 - len(valid) / len(non_priming)) if non_priming else None,
        "valid_reps": len(valid),
        "total_reps": len(reps),
    }


def build_record(
    reps: list[Rep],
    coverage_flags: list[bool],
    *,
    task_id: str,
    mode: str,
    model: str | None,
) -> dict[str, Any]:
    """Assemble the measurement. Separated from run_task so it is testable
    without invoking `claude` — the schema is now strict, so an undeclared key
    is a hard failure and must be caught by the suite, not by a paid run."""
    return {
        "schema_version": "1",
        "timestamp_utc": utc_now(),
        "harness": "claude",
        "source_surface": "claude-code-cli",
        "token_semantics": TokenSemantics.EXCLUDES_CACHE_READ.value,
        "billing_basis": "api_tokens_usd",
        "harness_version": claude_version(),
        "telemetry_version": claude_version(),
        "model": model or "default",
        "workload": task_id,
        "cache_mode": mode,
        "variant": {"kind": "single"},
        "reps": [rep_to_json(r) for r in reps],
        "aggregates": _aggregate(reps, coverage_flags),
        "environment": {"os": platform.system(), "arch": platform.machine()},
    }


def run_task(
    task_id: str,
    *,
    reps: int,
    mode: str,
    model: str | None,
    label: str,
    raw_capture: bool,
) -> Path:
    task = load_task(task_id)
    fixture_dir = ensure_fixture()
    extra = ["--model", model] if model else []

    collected: list[Rep] = []
    coverage_flags: list[bool] = []

    for index in range(reps):
        if mode == "cold" and index > 0:
            print(f"  sleeping {COLD_SLEEP_SECONDS}s to clear the cache TTL...", file=sys.stderr)
            time.sleep(COLD_SLEEP_SECONDS)

        priming = mode == "warm" and index == 0
        raw = call_claude(fixture_dir, task.prompt, extra)

        if raw_capture:
            target = STAGING / "raw" / f"{task_id}-rep{index}.json"
            target.write_text(redact_text(str(raw)))

        valid = verify_answer(raw, task.expected)
        if not priming:
            coverage_flags.append(reported_cache_read(raw))
        collected.append(project_rep(raw, rep=index, valid=valid, priming=priming))
        print(f"  rep {index}: valid={valid} priming={priming}", file=sys.stderr)

    record = build_record(
        collected,
        coverage_flags,
        task_id=task_id,
        mode=mode,
        model=model,
    )
    aggregates = record["aggregates"]

    ensure_staging()
    stamp = utc_now().replace("-", "").replace(":", "")
    suffix = f"-{label}" if label else ""
    out = STAGING / "runs" / f"{stamp}-{task_id}{suffix}.json"
    write_validated(record, out)

    if aggregates["invalid_rep_rate"]:
        warn(
            "run",
            f"{aggregates['invalid_rep_rate']:.0%} of reps gave the wrong answer — "
            "a harness that gives up early looks flatteringly cheap",
        )
    return out


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="run", description="Measure `claude -p` on the fixture.")
    parser.add_argument("--task", required=True, choices=[*TASK_IDS, "all"])
    parser.add_argument("--reps", type=int, default=5)
    parser.add_argument("--mode", default="warm", choices=("cold", "warm"))
    parser.add_argument("--model", default="")
    parser.add_argument("--label", default="")
    parser.add_argument(
        "--raw-capture",
        action="store_true",
        help="write redacted raw payloads to $STAGING/raw for debugging (never committable)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    if args.reps < 1:
        print("✗ run: --reps must be >= 1", file=sys.stderr)
        return 2

    try:
        claude_preflight()
        ensure_staging()
        task_ids = list(TASK_IDS) if args.task == "all" else [args.task]
        written = [
            run_task(
                task_id,
                reps=args.reps,
                mode=args.mode,
                model=args.model or None,
                label=args.label,
                raw_capture=args.raw_capture,
            )
            for task_id in task_ids
        ]
    except HarnessError as exc:
        print(exc, file=sys.stderr)
        return 1

    print()
    for path in written:
        ok("run", f"wrote {path}")
    print()
    print(f"Promote with: just record {written[0]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
