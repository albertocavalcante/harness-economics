#!/usr/bin/env bash
# measure/lib/emit.sh — the load-bearing safety control for this repo.
#
# WHY THIS IS THE REAL CONTROL (not redact.sh): a raw `claude -p
# --output-format json` result contains the full conversation text, file
# paths from --add-dir, the session id, and anything else the model said.
# None of that may ever reach measurements/ (which IS committed) or even
# /private/tmp/harness-econ/runs/ (which is promoted into the repo by `just
# record`). The only way to guarantee that is to never give the leaking
# content a path into the output at all — not "filter it out", which
# requires an exhaustive and inevitably incomplete denylist, but build the
# output as a NEW object via a jq projection that names every field it wants
# and nothing else. A field that isn't named in the jq filter below cannot
# appear in emit_measurement's output, full stop, regardless of what the raw
# payload contains. This is impossible-by-construction, not
# impossible-by-diligence.
#
# NULLABILITY — read before touching this function. Per docs/02-prompt-caching.md
# (verified 2026-09-10 against the CLI's own --output-format json):
#   - `usage.cache_creation` may be ABSENT entirely (older CLI/model paths
#     never had prompt caching in play for that turn).
#   - `usage.cache_creation.ephemeral_5m_input_tokens` and
#     `...ephemeral_1h_input_tokens` may each be explicitly `null` even when
#     the parent object IS present.
#   - `usage.cache_creation_input_tokens` may be absent; when present it is
#     documented as the sum of the two ephemeral fields, but do not trust
#     that invariant blindly — a script that assumes any of these are
#     numbers will crash on `null + 5` or `absent.foo`. jq's behavior is our
#     friend here: indexing a field that doesn't exist yields `null` (not an
#     error), and `null // 0` yields `0`. That is why every leaf below is
#     wrapped in `// 0` and why `.usage.cache_creation.ephemeral_5m_input_tokens`
#     is safe to write even when `.usage.cache_creation` itself is missing.
#
# Source this, don't execute it.

# emit_measurement <rep_index> <valid: true|false> <priming: true|false>
#
# Reads one raw `claude -p --output-format json` result on stdin. Writes a
# single schema-shaped "rep" JSON object to stdout — see
# measurements/schema.json's `reps[]` item shape. rep_index/valid/priming are
# control-flow metadata the CALLER already knows (loop counters and verify
# results) — passed via --argjson, never interpolated into the jq program
# text, so there is no injection surface even though they're caller-supplied.
emit_measurement() {
  local rep_index="${1:?emit_measurement: rep_index required}"
  local valid="${2:?emit_measurement: valid required (true|false)}"
  local priming="${3:?emit_measurement: priming required (true|false)}"

  jq --argjson rep_index "$rep_index" \
    --argjson valid "$valid" \
    --argjson priming "$priming" \
    '
    {
      rep: $rep_index,
      valid: $valid,
      priming: $priming,
      usage: {
        input_tokens:            (.usage.input_tokens // 0),
        output_tokens:           (.usage.output_tokens // 0),
        cache_read_input_tokens: (.usage.cache_read_input_tokens // 0),
        cache_creation: {
          ephemeral_5m_input_tokens: (.usage.cache_creation.ephemeral_5m_input_tokens // 0),
          ephemeral_1h_input_tokens: (.usage.cache_creation.ephemeral_1h_input_tokens // 0)
        },
        # Documented as the sum of the two ephemerals when present; derive it
        # ourselves when the field is absent rather than trusting a value we
        # cannot cross-check.
        cache_creation_input_tokens: (
          .usage.cache_creation_input_tokens //
          ((.usage.cache_creation.ephemeral_5m_input_tokens // 0) +
           (.usage.cache_creation.ephemeral_1h_input_tokens // 0))
        )
      },
      total_cost_usd: (.total_cost_usd // 0),
      num_turns:      (.num_turns // 0),
      duration_ms:    (.duration_ms // 0)
    }
  '
}
