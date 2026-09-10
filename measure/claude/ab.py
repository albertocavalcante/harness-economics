"""Interleaved A/B of two `claude -p` configurations, with a seeded bootstrap CI.

Ported from measure/claude/ab.sh, which had three defects this file fixes:

  * It computed cache_read_share as cr/(cr+inp), omitting cache creation, while
    run.sh used cr/(cr+cc+inp). Both now call the one shared formula.
  * It omitted source_surface, token_semantics, billing_basis and
    cache_attr_coverage, so every record it produced was schema-invalid. Nothing
    caught that, because nothing read the schema.
  * It seeded the bootstrap with awk's bare `srand()`, i.e. wall-clock seconds,
    so the published interval could not be re-derived.
"""

from __future__ import annotations

import argparse
import platform
import sys
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
from measure.lib.stats import DEFAULT_SEED, BootstrapCI, bootstrap_ci

VARIABLES: Final = ("model", "mcp", "system-prompt")


def arm_flags(variable: str, value: str) -> list[str]:
    """Translate an arm's value into claude flags.

    `none` and empty mean "attach nothing", which is the control arm for the mcp
    comparison — not a flag with an empty value.
    """
    if not value or value == "none":
        return []
    if variable == "model":
        return ["--model", value]
    if variable == "mcp":
        return ["--mcp-config", value]
    return ["--append-system-prompt", value]


def build_record(
    reps_a: list[Rep],
    reps_b: list[Rep],
    coverage_flags: list[bool],
    ci: BootstrapCI | None,
    *,
    variable: str,
    value_a: str,
    value_b: str,
    task_id: str,
) -> dict[str, Any]:
    """Assemble the measurement. Separated from run_ab so it is testable without
    invoking `claude`. The shell version emitted four schema violations and
    nothing caught them, because nothing read the schema."""
    all_reps = reps_a + reps_b
    valid = [r for r in all_reps if r.valid]

    aggregates: dict[str, Any] = {
        "cache_read_share": share_from_reps(valid, TokenSemantics.EXCLUDES_CACHE_READ),
        "cache_attr_coverage": (
            sum(coverage_flags) / len(coverage_flags) if coverage_flags else None
        ),
        "mean_cost_usd": mean([r.total_cost_usd for r in valid]),
        "mean_input_tokens": mean([r.usage.input_tokens for r in valid]),
        "mean_output_tokens": mean([r.usage.output_tokens for r in valid]),
        "mean_cache_read_tokens": mean([r.usage.cache_read_input_tokens for r in valid]),
        "mean_cache_creation_tokens": mean([r.usage.cache_creation_input_tokens for r in valid]),
        "invalid_rep_rate": (1 - len(valid) / len(all_reps)) if all_reps else None,
        "valid_reps": len(valid),
        "total_reps": len(all_reps),
        "paired_diff_metric": "total_cost_usd (B - A)",
        "paired_diff_n": ci.n if ci else 0,
        # Numbers or null — never the string "n/a" the shell version emitted.
        "paired_diff_mean": ci.mean if ci else None,
        "paired_diff_ci95_low": ci.ci95_low if ci else None,
        "paired_diff_ci95_high": ci.ci95_high if ci else None,
        "bootstrap_seed": ci.seed if ci else None,
        "bootstrap_resamples": ci.resamples if ci else None,
    }

    return {
        "schema_version": "1",
        "timestamp_utc": utc_now(),
        "harness": "claude",
        "source_surface": "claude-code-cli",
        "token_semantics": TokenSemantics.EXCLUDES_CACHE_READ.value,
        "billing_basis": "api_tokens_usd",
        "harness_version": claude_version(),
        "telemetry_version": claude_version(),
        "model": value_a if variable == "model" else "default",
        "workload": task_id,
        "cache_mode": "warm",
        "variant": {"kind": "ab", "var": variable, "a": value_a, "b": value_b},
        "reps": (
            [rep_to_json(r) | {"arm": "A"} for r in reps_a]
            + [rep_to_json(r) | {"arm": "B"} for r in reps_b]
        ),
        "aggregates": aggregates,
        "environment": {"os": platform.system(), "arch": platform.machine()},
    }


def run_ab(
    *,
    variable: str,
    value_a: str,
    value_b: str,
    reps: int,
    task_id: str,
    seed: int,
) -> tuple[Any, dict[str, Any]]:
    task = load_task(task_id)
    fixture_dir = ensure_fixture()
    flags_a = arm_flags(variable, value_a)
    flags_b = arm_flags(variable, value_b)

    reps_a: list[Rep] = []
    reps_b: list[Rep] = []
    coverage_flags: list[bool] = []
    diffs: list[float] = []

    # Strictly ABAB, never AAABBB. A blocked design confounds the variable under
    # test with drift — server cache warmth, API load by time of day, transient
    # degradation. Interleaving cancels drift out of the paired difference.
    for index in range(reps):
        raw_a = call_claude(fixture_dir, task.prompt, flags_a)
        raw_b = call_claude(fixture_dir, task.prompt, flags_b)

        valid_a = verify_answer(raw_a, task.expected)
        valid_b = verify_answer(raw_b, task.expected)

        coverage_flags.extend([reported_cache_read(raw_a), reported_cache_read(raw_b)])
        rep_a = project_rep(raw_a, rep=index, valid=valid_a, priming=False)
        rep_b = project_rep(raw_b, rep=index, valid=valid_b, priming=False)
        reps_a.append(rep_a)
        reps_b.append(rep_b)

        if valid_a and valid_b:
            diffs.append(rep_b.total_cost_usd - rep_a.total_cost_usd)
            print(f"  rep {index}: paired diff {diffs[-1]:+.6f}", file=sys.stderr)
        else:
            print(
                f"  rep {index}: excluded from paired diff (A valid={valid_a}, B valid={valid_b})",
                file=sys.stderr,
            )

    ci = bootstrap_ci(diffs, seed=seed)
    record = build_record(
        reps_a,
        reps_b,
        coverage_flags,
        ci,
        variable=variable,
        value_a=value_a,
        value_b=value_b,
        task_id=task_id,
    )
    return ci, record


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="ab", description="Interleaved A/B of two claude configurations."
    )
    parser.add_argument("--var", required=True, choices=VARIABLES, dest="variable")
    parser.add_argument("--a", default="", dest="value_a")
    parser.add_argument("--b", default="", dest="value_b")
    parser.add_argument("--reps", type=int, default=5)
    parser.add_argument("--task", default="T2", choices=list(TASK_IDS))
    parser.add_argument(
        "--seed",
        type=int,
        default=DEFAULT_SEED,
        help="bootstrap seed; recorded in the output so the interval can be re-derived",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    if args.reps < 1:
        print("✗ ab: --reps must be >= 1", file=sys.stderr)
        return 2

    try:
        claude_preflight()
        ensure_staging()
        ci, record = run_ab(
            variable=args.variable,
            value_a=args.value_a,
            value_b=args.value_b,
            reps=args.reps,
            task_id=args.task,
            seed=args.seed,
        )
        stamp = utc_now().replace("-", "").replace(":", "")
        out = STAGING / "runs" / f"{stamp}-ab-{args.variable}.json"
        write_validated(record, out)
    except HarnessError as exc:
        print(exc, file=sys.stderr)
        return 1

    print()
    if ci is None:
        warn("ab", "fewer than 2 valid pairs — no confidence interval computed")
    else:
        print(f"paired diff (B - A) over {ci.n} pairs")
        print(f"  mean      {ci.mean:+.6f} USD")
        print(f"  95% CI    [{ci.ci95_low:+.6f}, {ci.ci95_high:+.6f}]")
        print(f"  seed      {ci.seed} ({ci.resamples} resamples) — rerun to reproduce exactly")
        crosses_zero = ci.ci95_low <= 0 <= ci.ci95_high
        print(f"  {'inconclusive: the interval spans zero' if crosses_zero else 'directional'}")
    print()
    ok("ab", f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
