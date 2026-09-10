#!/usr/bin/env bash
# measure/claude/ab.sh — A/B two configurations of `claude -p` against the
# same task set, interleaved.
#
# Usage:
#   ab.sh --var <model|mcp|system-prompt> --a <valueA> --b <valueB>
#         --reps <N> [--task <id>]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091 source=../lib/common.sh
source "$REPO_ROOT/measure/lib/common.sh"
# shellcheck disable=SC1091 source=../lib/emit.sh
source "$REPO_ROOT/measure/lib/emit.sh"
# shellcheck disable=SC1091 source=lib.sh
source "$REPO_ROOT/measure/claude/lib.sh"

VAR=""
VAL_A=""
VAL_B=""
REPS=5
TASK="T2" # moderate cost by default — see usage note below

usage() {
  cat <<'USAGE'
Usage: ab.sh --var <model|mcp|system-prompt> --a <valueA> --b <valueB> --reps <N> [--task <id>]

  --var model          --a/--b are model ids, e.g. claude-haiku-4-5 vs claude-sonnet-4-5
  --var mcp            --a/--b are ".mcp.json" paths, or the literal string
                        "none" for the no-MCP-attached baseline
  --var system-prompt  --a/--b are literal --append-system-prompt strings
                        (use "" for "no extra system prompt")

Default --task is T2 if not given (moderate cost; avoids T1's near-zero
signal and T4's higher variance for a generic first look).
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --var)
      VAR="$2"
      shift 2
      ;;
    --a)
      VAL_A="$2"
      shift 2
      ;;
    --b)
      VAL_B="$2"
      shift 2
      ;;
    --reps)
      REPS="$2"
      shift 2
      ;;
    --task)
      TASK="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "ab" "unknown argument: $1" ;;
  esac
done

[ -n "$VAR" ] || {
  usage
  die "ab" "--var is required"
}
case "$VAR" in model | mcp | system-prompt) ;; *) die "ab" "--var must be one of model, mcp, system-prompt" ;; esac
case "$REPS" in '' | *[!0-9]*) die "ab" "--reps must be a positive integer, got '$REPS'" ;; esac
[ "$REPS" -ge 1 ] || die "ab" "--reps must be >= 1"

claude_preflight

FIXTURE_DIR="$STAGING/fixture"
if [ ! -f "$FIXTURE_DIR/FIXTURE.sha256" ]; then
  ok "ab" "no fixture present, generating one"
  bash "$REPO_ROOT/measure/fixture/make.sh"
fi
ensure_staging

load_task "$TASK"

# claude_args_for_arm <A|B> — builds the extra `claude -p` flags for one arm,
# based on --var. Kept as a function (not inline) so both arms go through
# identical logic and only the variable under test differs.
claude_args_for_arm() {
  local arm="$1" val
  if [ "$arm" = "A" ]; then val="$VAL_A"; else val="$VAL_B"; fi
  case "$VAR" in
    model)
      printf -- '--model\n%s\n' "$val"
      ;;
    mcp)
      if [ "$val" = "none" ] || [ -z "$val" ]; then
        : # no extra flags — baseline with no MCP server attached
      else
        printf -- '--mcp-config\n%s\n' "$val"
      fi
      ;;
    system-prompt)
      if [ -n "$val" ]; then
        printf -- '--append-system-prompt\n%s\n' "$val"
      fi
      ;;
  esac
}

run_one_rep() {
  local arm="$1" rep_index="$2" args=()
  while IFS= read -r line; do
    [ -n "$line" ] && args+=("$line")
  done < <(claude_args_for_arm "$arm")

  local raw valid rep_json
  raw="$(call_claude "$FIXTURE_DIR" "$TASK_PROMPT" "${args[@]}")"
  valid="$(verify_answer "$raw" "$TASK_EXPECTED")"
  rep_json="$(printf '%s' "$raw" | emit_measurement "$rep_index" "$valid" false)"
  printf '%s' "$rep_json"
}

# Interleaved ABABAB, NOT AAABBB. A blocked design (run all of A, then all of
# B) confounds the variable under test with anything that drifts across the
# run window — server-side cache warmth changing, API load varying by time
# of day, a transient degradation on one side of the run. Interleaving means
# both arms see the same drift, so it cancels out of the paired difference
# instead of masquerading as an effect of --var.
reps_a="[]"
reps_b="[]"
diffs_file="$(mktemp "${STAGING}/ab-diffs.XXXXXX")"
trap 'rm -f "$diffs_file"' EXIT

for ((i = 0; i < REPS; i++)); do
  echo "rep $i: arm A ($VAL_A)" >&2
  rep_a="$(run_one_rep A "$i")"
  echo "rep $i: arm B ($VAL_B)" >&2
  rep_b="$(run_one_rep B "$i")"

  reps_a="$(printf '%s' "$reps_a" | jq --argjson r "$rep_a" '. + [$r]')"
  reps_b="$(printf '%s' "$reps_b" | jq --argjson r "$rep_b" '. + [$r]')"

  valid_a="$(printf '%s' "$rep_a" | jq -r '.valid')"
  valid_b="$(printf '%s' "$rep_b" | jq -r '.valid')"
  if [ "$valid_a" = "true" ] && [ "$valid_b" = "true" ]; then
    cost_a="$(printf '%s' "$rep_a" | jq -r '.total_cost_usd')"
    cost_b="$(printf '%s' "$rep_b" | jq -r '.total_cost_usd')"
    diff="$(awk -v a="$cost_a" -v b="$cost_b" 'BEGIN{printf "%.10f", b - a}')"
    echo "$diff" >>"$diffs_file"
    echo "  rep $i paired diff (B-A, total_cost_usd): $diff" >&2
  else
    echo "  rep $i excluded from paired diff — A valid=$valid_a B valid=$valid_b" >&2
  fi
done

n_pairs="$(wc -l <"$diffs_file" | tr -d ' ')"
if [ "$n_pairs" -lt 2 ]; then
  fail "ab" "fewer than 2 valid pairs ($n_pairs) — skipping bootstrap CI"
  mean_delta="n/a"
  ci_low="n/a"
  ci_high="n/a"
else
  read -r mean_delta ci_low ci_high < <(
    awk '
      { diffs[NR] = $1; n = NR }
      END {
        srand()
        mean = 0
        for (i = 1; i <= n; i++) mean += diffs[i]
        mean /= n

        B = 2000
        for (b = 1; b <= B; b++) {
          s = 0
          for (i = 1; i <= n; i++) {
            idx = int(rand() * n) + 1
            s += diffs[idx]
          }
          boot[b] = s / n
        }
        for (i = 1; i <= B; i++)
          for (j = i + 1; j <= B; j++)
            if (boot[j] < boot[i]) { t = boot[i]; boot[i] = boot[j]; boot[j] = t }

        lo = int(0.025 * B); if (lo < 1) lo = 1
        hi = int(0.975 * B); if (hi > B) hi = B
        printf "%.10f %.10f %.10f\n", mean, boot[lo], boot[hi]
      }
    ' "$diffs_file"
  )
fi

measurement="$(
  jq -n \
    --arg schema_version "1" \
    --arg timestamp_utc "$(utc_now)" \
    --arg harness "claude" \
    --arg harness_version "$(claude_version)" \
    --arg workload "$TASK" \
    --arg var "$VAR" \
    --arg a "$VAL_A" \
    --arg b "$VAL_B" \
    --arg os "$(uname -s)" \
    --arg arch "$(uname -m)" \
    --argjson reps_a "$reps_a" \
    --argjson reps_b "$reps_b" \
    --arg mean_delta "$mean_delta" \
    --arg ci_low "$ci_low" \
    --arg ci_high "$ci_high" \
    --argjson n_pairs "$n_pairs" \
    '{
    schema_version: $schema_version,
    timestamp_utc: $timestamp_utc,
    harness: $harness,
    harness_version: $harness_version,
    workload: $workload,
    variant: { var: $var, a: $a, b: $b },
    reps: (($reps_a | map(. + {arm: "A"})) + ($reps_b | map(. + {arm: "B"}))),
    aggregates: {
      cache_read_ratio: (
        (($reps_a + $reps_b) | map(select(.valid == true)) | map(.usage.cache_read_input_tokens) | add // 0) as $cr
        | (($reps_a + $reps_b) | map(select(.valid == true)) | map(.usage.input_tokens) | add // 0) as $inp
        | (if ($cr + $inp) > 0 then $cr / ($cr + $inp) else 0 end)
      ),
      mean_cost_usd: (
        (($reps_a + $reps_b) | map(select(.valid == true)) | map(.total_cost_usd)) as $costs
        | (if ($costs | length) > 0 then ($costs | add) / ($costs | length) else 0 end)
      ),
      mean_input_tokens: (
        (($reps_a + $reps_b) | map(select(.valid == true)) | map(.usage.input_tokens)) as $ins
        | (if ($ins | length) > 0 then ($ins | add) / ($ins | length) else 0 end)
      ),
      mean_cache_read_tokens: (
        (($reps_a + $reps_b) | map(select(.valid == true)) | map(.usage.cache_read_input_tokens)) as $crs
        | (if ($crs | length) > 0 then ($crs | add) / ($crs | length) else 0 end)
      ),
      invalid_rep_rate: (
        (($reps_a + $reps_b) | length) as $total
        | (($reps_a + $reps_b) | map(select(.valid == true)) | length) as $valid
        | (if $total > 0 then 1 - ($valid / $total) else 0 end)
      ),
      valid_reps: (($reps_a + $reps_b) | map(select(.valid == true)) | length),
      total_reps: (($reps_a + $reps_b) | length),
      paired_diff_metric: "total_cost_usd (B - A)",
      paired_diff_n: $n_pairs,
      paired_diff_mean: $mean_delta,
      paired_diff_ci95_low: $ci_low,
      paired_diff_ci95_high: $ci_high
    },
    environment: { os: $os, arch: $arch }
  }'
)"

out_file="$STAGING/runs/$(date -u +%Y%m%dT%H%M%SZ)-ab-${VAR}.json"
printf '%s\n' "$measurement" >"$out_file"
ok "ab" "wrote $out_file"

echo ""
echo "=== A/B summary ($VAR: A=$VAL_A vs B=$VAL_B, task=$TASK) ==="
echo "paired diffs (B-A, total_cost_usd), n=$n_pairs:"
cat "$diffs_file" 2>/dev/null || true
echo "mean delta:     $mean_delta"
echo "95% CI (boot):  [$ci_low, $ci_high]"
echo ""
