#!/usr/bin/env bash
# Parse Copilot OTLP spans into a measurement record.
#
# Reads the JSON-lines file written by the local collector and projects ONLY named
# numeric token attributes out of it. Same safety property as measure/lib/emit.sh:
# span content cannot leak because content is never selected. Do not "improve" this
# by dumping whole spans and filtering afterwards — the allowlist is the control.
#
# Usage: ./parse-spans.sh <spans.jsonl> --surface <copilot-vscode|copilot-cli> [--label <slug>]
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

require_cmd jq

SPANS="${1:-}"
LABEL="copilot"
SURFACE=""

shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --label)
      LABEL="${2:-copilot}"
      shift 2
      ;;
    --surface)
      SURFACE="${2:-}"
      shift 2
      ;;
    *) die "parse-spans" "unknown argument: $1" ;;
  esac
done

if [ -z "$SPANS" ] || [ ! -f "$SPANS" ]; then
  die "parse-spans" "usage: parse-spans.sh <spans.jsonl> --surface <copilot-vscode|copilot-cli>"
fi

# The surface is mandatory and unguessable from the spans. Copilot's VS Code
# extension, CLI and SDK are separate implementations that have reported different
# numbers for the same spend, so a record that does not name one compares to nothing.
case "$SURFACE" in
  copilot-vscode | copilot-cli | copilot-sdk) ;;
  *) die "parse-spans" "--surface is required: copilot-vscode | copilot-cli | copilot-sdk" ;;
esac

if [ ! -s "$SPANS" ]; then
  die "parse-spans" "$SPANS is empty — was the collector running while you used Copilot?"
fi

ensure_staging
OUT="$STAGING/runs/$(date -u +%Y-%m-%d)-${LABEL}.json"

# Attribute names per VS Code's documented GenAI semconv emission. Each OTLP
# attribute is {"key": "...", "value": {"intValue": "..."}}; intValue arrives as a
# string, hence the tonumber.
#
# A missing attribute yields null, NOT 0. Defaulting to zero conflates "the meter
# said nothing" with "the cache genuinely missed" — precisely the failure mode
# catalogued in reference/KNOWN-ISSUES.md, where several Copilot paths hardcode or
# never read these fields and a broken meter reads as perfect frugality.
ATTR_QUERY='
  def attr($k):
    ( .attributes // [] )
    | map(select(.key == $k))
    | first
    | if . == null then null
      else ( .value.intValue // .value.doubleValue ) | tonumber? end;

  {
    input:          attr("gen_ai.usage.input_tokens"),
    output:         attr("gen_ai.usage.output_tokens"),
    cache_read:     attr("gen_ai.usage.cache_read.input_tokens"),
    cache_creation: attr("gen_ai.usage.cache_creation.input_tokens"),
    span_name:      ( .name // "unknown" )
  }
'

ALL_ROWS=$(
  jq -c '
    ( .resourceSpans // [] )[]
    | ( .scopeSpans // [] )[]
    | ( .spans // [] )[]
  ' "$SPANS" 2>/dev/null |
    jq -c "$ATTR_QUERY" |
    jq -c 'select(.span_name == "chat" or .span_name == "invoke_agent")'
) || die "parse-spans" "could not parse $SPANS as OTLP JSON lines"

if [ -z "$ALL_ROWS" ]; then
  die "parse-spans" "no chat/invoke_agent spans found — check the VS Code OTel settings"
fi

# Sum ONLY leaf `chat` spans. `invoke_agent` is a parent rollup whose totals already
# contain its children, so adding both double-counts every nested call — the same
# defect microsoft/vscode#331438 fixed in Copilot's own billing telemetry. The parent
# count is reported separately as context, never added.
#
# Copilot's input_tokens ALREADY includes cache reads (copilot-sdk#1160), so the
# share denominator is input alone. Applying Anthropic's
# cache_read / (cache_read + input) here would count cache reads twice.
AGG=$(printf '%s\n' "$ALL_ROWS" | jq -s '
  def total($f): ( .leaf | map(.[$f]) | map(select(. != null)) | add );
  def seen($f):  ( .leaf | map(.[$f]) | map(select(. != null)) | length );
  {
    leaf:    ( map(select(.span_name == "chat")) ),
    parents: ( map(select(.span_name == "invoke_agent")) | length )
  }
  | . + { n: ( .leaf | length ) }
  | {
      spans:          .n,
      parent_spans:   .parents,
      input:          total("input"),
      output:         total("output"),
      cache_read:     total("cache_read"),
      cache_creation: total("cache_creation"),
      cache_attr_coverage:
        ( if .n > 0 then ( seen("cache_read") / .n ) else null end )
    }
  | . + {
      cache_read_share:
        ( if (.cache_attr_coverage // 0) < 1
             or .cache_read == null or .input == null or .input <= 0
          then null
          else ( .cache_read / .input )
          end )
    }
')

COVERAGE=$(echo "$AGG" | jq -r '.cache_attr_coverage // 0')
LEAVES=$(echo "$AGG" | jq -r '.spans')

if [ "$LEAVES" -eq 0 ]; then
  die "parse-spans" "no leaf 'chat' spans — only parent rollups were captured"
fi

jq -n \
  --arg ts "$(utc_now)" \
  --arg label "$LABEL" \
  --arg surface "$SURFACE" \
  --arg os "$(uname -s)" \
  --arg arch "$(uname -m)" \
  --argjson agg "$AGG" \
  '{
    schema_version: "1",
    timestamp_utc: $ts,
    harness: "copilot",
    source_surface: $surface,
    token_semantics: "input_includes_cache_read",
    billing_basis: "ai_credits",
    harness_version: "unknown",
    telemetry_version: "unknown",
    model: "unknown",
    workload: $label,
    cache_mode: "warm",
    variant: { kind: "manual" },
    reps: [],
    aggregates: {
      spans: $agg.spans,
      cache_read_share: $agg.cache_read_share,
      cache_attr_coverage: $agg.cache_attr_coverage,
      mean_input_tokens: $agg.input,
      mean_output_tokens: $agg.output,
      mean_cache_read_tokens: $agg.cache_read,
      mean_cache_creation_tokens: $agg.cache_creation,
      mean_cost_usd: null,
      invalid_rep_rate: null,
      valid_reps: null,
      total_reps: null
    },
    environment: { os: $os, arch: $arch }
  }' >"$OUT"

echo
printf '%-24s %10s\n' FIELD VALUE
printf '%-24s %10s\n' "leaf chat spans" "$LEAVES"
printf '%-24s %10s\n' "parent spans (excl.)" "$(echo "$AGG" | jq -r .parent_spans)"
printf '%-24s %10s\n' "input tokens" "$(echo "$AGG" | jq -r '.input // "n/a"')"
printf '%-24s %10s\n' "output tokens" "$(echo "$AGG" | jq -r '.output // "n/a"')"
printf '%-24s %10s\n' "cache read" "$(echo "$AGG" | jq -r '.cache_read // "n/a"')"
printf '%-24s %10s\n' "cache creation" "$(echo "$AGG" | jq -r '.cache_creation // "n/a"')"
printf '%-24s %10s\n' "cache attr coverage" "$COVERAGE"
printf '%-24s %10s\n' "cache read share" "$(echo "$AGG" | jq -r '.cache_read_share // "null"')"
echo

if [ "$(echo "$AGG" | jq -r '.cache_read_share == null')" = "true" ]; then
  warn "parse-spans" "cache_read_share is null — cache attributes were missing on some spans"
  echo "  A silent meter is not a cache miss. Do not read this run as low-cost."
  echo "  See reference/KNOWN-ISSUES.md — several Copilot paths never populate these."
  echo
fi

ok "parse-spans" "wrote $OUT"
echo "Review it, then promote with: just record $OUT"
echo
echo "Note: harness_version, telemetry_version and model are 'unknown' — the spans do"
echo "not carry them. Fill them in by hand before recording, or the record is not"
echo "interpretable: Copilot's meter changed at eight VS Code versions."
