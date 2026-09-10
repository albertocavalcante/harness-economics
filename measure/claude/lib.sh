#!/usr/bin/env bash
# measure/claude/lib.sh — shared by run.sh and ab.sh: task loading, the
# actual `claude -p` invocation, and answer verification. Kept out of
# common.sh because it is Claude-CLI-specific, not generic to every script
# in the repo.
#
# Source this, don't execute it. Callers must already have sourced
# measure/lib/common.sh and set REPO_ROOT.

# load_task <task_id> — sets TASK_PROMPT and TASK_EXPECTED globals from
# measure/fixture/tasks/<task_id>.md. Dies if the file or its EXPECTED: line
# is missing.
load_task() {
  local task_id="$1" file
  file="$REPO_ROOT/measure/fixture/tasks/${task_id}.md"
  [ -f "$file" ] || die "load_task" "unknown task '$task_id' (no $file)"

  TASK_EXPECTED="$(grep -m1 '^EXPECTED:' "$file" | sed -E 's/^EXPECTED:[[:space:]]*//')"
  [ -n "$TASK_EXPECTED" ] || die "load_task" "$file has no EXPECTED: line"

  # Prompt is every line except EXPECTED:, with trailing blank lines trimmed.
  # shellcheck disable=SC2034  # global — consumed by callers of load_task (run.sh, ab.sh)
  TASK_PROMPT="$(grep -v '^EXPECTED:' "$file" | awk '
    { lines[NR] = $0; last = NR }
    END {
      while (last > 0 && lines[last] == "") last--
      for (i = 1; i <= last; i++) print lines[i]
    }
  ')"
}

# call_claude <fixture_dir> <prompt> [extra claude args...]
#
# --bare is deliberate: it strips hooks, LSP, plugin sync, auto-memory, and
# CLAUDE.md discovery, so the only variable between reps is the prompt and
# the fixture tree — not whatever happens to be in ~/.claude that day.
# --bare also forces credential resolution through ANTHROPIC_API_KEY (it
# skips the interactive/subscription auth path), so every total_cost_usd
# this harness reports is an API-key list-price figure, NOT what a Claude
# subscription would have billed for the same work. Do not present these
# numbers as subscription-equivalent cost.
call_claude() {
  local fixture_dir="$1"; shift
  local prompt="$1"; shift
  claude -p "$prompt" \
    --output-format json \
    --bare \
    --add-dir "$fixture_dir" \
    --max-turns 12 \
    "$@"
}

# verify_answer <raw_json> <expected_pattern> — prints "true" or "false".
# EXPECTED: lines are matched as an extended regex (grep -E) against the
# trimmed `.result` field, so a task file can use either a literal string or
# a real pattern.
verify_answer() {
  local raw="$1" expected="$2" result
  result="$(printf '%s' "$raw" | jq -r '.result // empty' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if printf '%s' "$result" | grep -Eq "$expected"; then
    echo true
  else
    echo false
  fi
}

# claude_preflight — refuse to run in a degraded environment rather than
# silently emitting a number that doesn't mean what it looks like it means.
claude_preflight() {
  require_cmd jq
  require_cmd claude
  if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    die "preflight" "--bare requires ANTHROPIC_API_KEY to be set — refusing to run and emit unauthenticated/misleading numbers"
  fi
  require_free_space 200 "$STAGING"
}
