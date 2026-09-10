#!/usr/bin/env bash
# Parse Copilot OTLP spans into a measurement record.
#
# Reads the JSON-lines file written by the local collector and projects ONLY named
# numeric token attributes out of it. Same safety property as measure/lib/emit.sh:
# span content cannot leak because content is never selected. Do not "improve" this
# by dumping whole spans and filtering afterwards — the allowlist is the control.
#
# Usage: ./parse-spans.sh <spans.jsonl> [--label <slug>]
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

require_cmd jq

SPANS="${1:-}"
LABEL="copilot"

shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --label) LABEL="${2:-copilot}"; shift 2 ;;
    *) die "parse-spans" "unknown argument: $1" ;;
  esac
done

if [ -z "$SPANS" ] || [ ! -f "$SPANS" ]; then
  die "parse-spans" "usage: parse-spans.sh <spans.jsonl> [--label <slug>]"
fi

if [ ! -s "$SPANS" ]; then
  die "parse-spans" "$SPANS is empty — was the collector running while you used Copilot?"
fi

ensure_staging
OUT="$STAGING/runs/$(date -u +%Y-%m-%d)-${LABEL}.json"

# Attribute names per VS Code's documented GenAI semconv emission. Each OTLP
# attribute is {"key": "...", "value": {"intValue": "..."}}; intValue arrives as a
# string, hence the tonumber. Any attribute absent from a span defaults to 0 rather
# than crashing, because cache attributes are documented as present only "when
# available" — a span without them is a real case, not a parse error.
ATTR_QUERY='
  def attr($k):
    ( .attributes // [] )
    | map(select(.key == $k))
    | first
    | ( .value.intValue // .value.doubleValue // 0 )
    | tonumber? // 0;

  {
    input:          attr("gen_ai.usage.input_tokens"),
    output:         attr("gen_ai.usage.output_tokens"),
    cache_read:     attr("gen_ai.usage.cache_read.input_tokens"),
    cache_creation: attr("gen_ai.usage.cache_creation.input_tokens"),
    span_name:      ( .name // "unknown" )
  }
'

# Walk the OTLP envelope down to individual spans, keeping only model-call spans.
SPAN_ROWS=$(
  jq -c '
    ( .resourceSpans // [] )[]
    | ( .scopeSpans // [] )[]
    | ( .spans // [] )[]
  ' "$SPANS" 2>/dev/null \
  | jq -c "$ATTR_QUERY" \
  | jq -c 'select(.span_name == "chat" or .span_name == "invoke_agent")'
) || die "parse-spans" "could not parse $SPANS as OTLP JSON lines"

if [ -z "$SPAN_ROWS" ]; then
  die "parse-spans" "no chat/invoke_agent spans found — check the VS Code OTel settings"
fi

AGG=$(printf '%s\n' "$SPAN_ROWS" | jq -s '
  {
    spans:          length,
    input:          ( map(.input)          | add // 0 ),
    output:         ( map(.output)         | add // 0 ),
    cache_read:     ( map(.cache_read)     | add // 0 ),
    cache_creation: ( map(.cache_creation) | add // 0 )
  }
  | . + {
      cache_read_ratio:
        ( if (.cache_read + .cache_creation + .input) > 0
          then (.cache_read / (.cache_read + .cache_creation + .input))
          else 0 end )
    }
')

jq -n \
  --arg ts "$(utc_now)" \
  --arg label "$LABEL" \
  --argjson agg "$AGG" \
  '{
    schema_version: "1",
    timestamp_utc: $ts,
    harness: "github-copilot",
    harness_version: "unknown",
    model: "unknown",
    workload: { id: $label, source: "manual", note: "hand-run via measure/copilot/SETUP.md" },
    cache_mode: "warm",
    variant: { kind: "manual" },
    reps: [],
    aggregates: {
      spans: $agg.spans,
      cache_read_ratio: $agg.cache_read_ratio,
      total_input_tokens: $agg.input,
      total_output_tokens: $agg.output,
      total_cache_read_tokens: $agg.cache_read,
      total_cache_creation_tokens: $agg.cache_creation,
      invalid_rep_rate: null,
      valid_reps: null,
      total_reps: null
    },
    environment: { os: "'"$(uname -s)"'", arch: "'"$(uname -m)"'" }
  }' > "$OUT"

echo
printf '%-24s %10s\n' FIELD VALUE
printf '%-24s %10s\n' "spans"           "$(echo "$AGG" | jq -r .spans)"
printf '%-24s %10s\n' "input tokens"    "$(echo "$AGG" | jq -r .input)"
printf '%-24s %10s\n' "output tokens"   "$(echo "$AGG" | jq -r .output)"
printf '%-24s %10s\n' "cache read"      "$(echo "$AGG" | jq -r .cache_read)"
printf '%-24s %10s\n' "cache creation"  "$(echo "$AGG" | jq -r .cache_creation)"
printf '%-24s %10s\n' "cache read ratio" "$(echo "$AGG" | jq -r '.cache_read_ratio | . * 1000 | round / 1000')"
echo

ok "parse-spans" "wrote $OUT"
echo "Review it, then promote with: just record $OUT"
echo
echo "Note: harness_version and model are 'unknown' — the spans do not carry them."
echo "Fill them in by hand before recording, or the measurement is not interpretable."
