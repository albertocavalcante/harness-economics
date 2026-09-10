#!/usr/bin/env bash
# measure/claude/run.sh — run one (or all) fixture tasks against `claude -p`
# N times and emit a schema-valid measurement file.
#
# Usage:
#   run.sh --task <T1|T2|T3|T4|all> --reps <N> --mode <cold|warm>
#          [--model <id>] [--label <slug>]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091 source=../lib/common.sh
source "$REPO_ROOT/measure/lib/common.sh"
# shellcheck disable=SC1091 source=../lib/emit.sh
source "$REPO_ROOT/measure/lib/emit.sh"
# shellcheck disable=SC1091 source=lib.sh
source "$REPO_ROOT/measure/claude/lib.sh"

TASK=""
REPS=5
MODE="warm"
MODEL=""
LABEL=""

usage() {
  cat <<'USAGE'
Usage: run.sh --task <T1|T2|T3|T4|all> --reps <N> --mode <cold|warm> [--model <id>] [--label <slug>]

  --mode cold   sleep 370s between reps so the 5-minute cache TTL expires
  --mode warm   reps run back-to-back; rep 0 is a discarded priming run
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --task) TASK="$2"; shift 2 ;;
    --reps) REPS="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "run" "unknown argument: $1" ;;
  esac
done

[ -n "$TASK" ] || { usage; die "run" "--task is required"; }
case "$MODE" in cold|warm) ;; *) die "run" "--mode must be 'cold' or 'warm', got '$MODE'" ;; esac
case "$REPS" in ''|*[!0-9]*) die "run" "--reps must be a positive integer, got '$REPS'" ;; esac
[ "$REPS" -ge 1 ] || die "run" "--reps must be >= 1"

# Preflight — refuse to run in a degraded environment rather than emitting a
# number that doesn't mean what it looks like it means.
claude_preflight

FIXTURE_DIR="$STAGING/fixture"
if [ ! -f "$FIXTURE_DIR/FIXTURE.sha256" ]; then
  ok "run" "no fixture present, generating one"
  bash "$REPO_ROOT/measure/fixture/make.sh"
fi

ensure_staging

RAW_CAPTURE="${HARNESS_RAW_CAPTURE:-0}"
# shellcheck disable=SC1091 source=../lib/redact.sh
source "$REPO_ROOT/measure/lib/redact.sh"

# run_one_task <task_id> — runs REPS reps of <task_id>, writes one
# measurement file, prints one summary table. Returns the path it wrote via
# stdout (last line) so the caller can collect it for --task all.
run_one_task() {
  local task_id="$1"
  load_task "$task_id"

  local claude_args=()
  [ -n "$MODEL" ] && claude_args+=(--model "$MODEL")

  local reps_json="[]"
  local i is_priming valid raw rep_json

  for ((i = 0; i < REPS; i++)); do
    if [ "$MODE" = "cold" ] && [ "$i" -gt 0 ]; then
      echo "  (cold mode: sleeping 370s so the 5-minute cache TTL expires)" >&2
      sleep 370
    fi

    is_priming=false
    if [ "$MODE" = "warm" ] && [ "$i" -eq 0 ]; then
      is_priming=true
    fi

    raw="$(call_claude "$FIXTURE_DIR" "$TASK_PROMPT" "${claude_args[@]}")"

    if [ "$RAW_CAPTURE" = "1" ]; then
      printf '%s' "$raw" | redact_stream > "$STAGING/raw/${task_id}-rep${i}.json"
    fi

    # An agent that gives up early, refuses, or answers a different question
    # produces a flatteringly low cost/token number — averaging cost across
    # reps that did different amounts of work would make an unreliable
    # harness look cheap instead of unreliable. Verify every rep against
    # EXPECTED and exclude non-matching reps from aggregates, but keep them
    # in reps[] and surface invalid_rep_rate as a headline number so that
    # can't happen silently.
    valid="$(verify_answer "$raw" "$TASK_EXPECTED")"

    rep_json="$(printf '%s' "$raw" | emit_measurement "$i" "$valid" "$is_priming")"
    reps_json="$(printf '%s' "$reps_json" | jq --argjson rep "$rep_json" '. + [$rep]')"

    echo "  rep $i: valid=$valid priming=$is_priming" >&2
  done

  local aggregates
  aggregates="$(printf '%s' "$reps_json" | jq '
    (map(select(.priming == false))) as $nonpriming
    | ($nonpriming | length) as $total_nonpriming
    | (map(select(.priming == false and .valid == true))) as $valid_reps
    | ($valid_reps | length) as $n_valid
    | {
        cache_read_ratio: (
          ($valid_reps | map(.usage.cache_read_input_tokens) | add // 0) as $cr
          | ($valid_reps | map(.usage.input_tokens) | add // 0) as $inp
          | (if ($cr + $inp) > 0 then $cr / ($cr + $inp) else 0 end)
        ),
        mean_cost_usd: (if $n_valid > 0 then ($valid_reps | map(.total_cost_usd) | add) / $n_valid else 0 end),
        mean_input_tokens: (if $n_valid > 0 then ($valid_reps | map(.usage.input_tokens) | add) / $n_valid else 0 end),
        mean_cache_read_tokens: (if $n_valid > 0 then ($valid_reps | map(.usage.cache_read_input_tokens) | add) / $n_valid else 0 end),
        invalid_rep_rate: (if $total_nonpriming > 0 then 1 - ($n_valid / $total_nonpriming) else 0 end),
        valid_reps: $n_valid,
        total_reps: (. | length)
      }
  ')"

  local measurement
  measurement="$(jq -n \
    --arg schema_version "1" \
    --arg timestamp_utc "$(utc_now)" \
    --arg harness "claude" \
    --arg harness_version "$(claude_version)" \
    --arg workload "$task_id" \
    --arg model "${MODEL:-default}" \
    --arg cache_mode "$MODE" \
    --arg os "$(uname -s)" \
    --arg arch "$(uname -m)" \
    --argjson reps "$reps_json" \
    --argjson aggregates "$aggregates" \
    '{
      schema_version: $schema_version,
      timestamp_utc: $timestamp_utc,
      harness: $harness,
      harness_version: $harness_version,
      workload: $workload,
      model: $model,
      cache_mode: $cache_mode,
      reps: $reps,
      aggregates: $aggregates,
      environment: { os: $os, arch: $arch }
    }'
  )"

  local out_file
  out_file="$STAGING/runs/$(date -u +%Y%m%dT%H%M%SZ)-${task_id}${LABEL:+-$LABEL}.json"
  printf '%s\n' "$measurement" > "$out_file"
  ok "run" "wrote $out_file"

  print_summary "$task_id" "$measurement"
  # Global, not a printed/captured return value — keeps this function's
  # human-readable output (the ok/summary lines above) on the terminal
  # instead of forcing every caller to redirect stdout to get the path.
  LAST_OUT_FILE="$out_file"
}

print_summary() {
  local task_id="$1" measurement="$2"
  echo ""
  echo "=== $task_id summary ==="
  printf '%s\n' "$measurement" | jq -r '
    "total reps:        \(.aggregates.total_reps)",
    "valid reps:        \(.aggregates.valid_reps)",
    "invalid rep rate:  \(.aggregates.invalid_rep_rate)",
    "mean cost (USD):   \(.aggregates.mean_cost_usd)",
    "mean input tokens: \(.aggregates.mean_input_tokens)",
    "mean cache-read:   \(.aggregates.mean_cache_read_tokens)",
    "cache read ratio:  \(.aggregates.cache_read_ratio)"
  '
  echo ""
}

LAST_OUT_FILE=""
if [ "$TASK" = "all" ]; then
  written=()
  for t in T1 T2 T3 T4; do
    run_one_task "$t"
    written+=("$LAST_OUT_FILE")
  done
  ok "run" "wrote ${#written[@]} measurement files: ${written[*]}"
else
  run_one_task "$TASK"
fi
