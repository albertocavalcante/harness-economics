#!/usr/bin/env bash
# tools/record.sh — validate FILE against the measurement schema and leak
# pattern, then promote it into measurements/. Run by `just record FILE`.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$(repo_root)"

src="$1"
if [ ! -f "$src" ]; then
  echo "✗ record: $src not found" >&2
  exit 1
fi
if ! jq -e 'has("schema_version") and has("timestamp_utc") and has("harness") and has("workload") and has("aggregates")' "$src" >/dev/null 2>&1; then
  echo "✗ record: $src failed to parse or is missing a required key (schema_version, timestamp_utc, harness, workload, aggregates)" >&2
  exit 1
fi
if grep -rInE "$LEAK_PATTERN" "$src"; then
  echo "✗ record: personal path or credential-shaped string found in $src" >&2
  exit 1
fi
harness=$(jq -r '.harness // "unknown"' "$src")
# workload may be a bare string or an object carrying an id — accept either,
# otherwise an object serializes into the filename as a JSON blob.
workload=$(jq -r 'if (.workload | type) == "object" then (.workload.id // "unknown") else (.workload // "unknown") end' "$src")
label=$(printf '%s-%s' "$harness" "$workload" | tr '[:upper:] ' '[:lower:]-' | tr -s '-')
dest="measurements/$(date -u +%Y-%m-%d)-${label}.json"
if [ -e "$dest" ]; then
  echo "✗ record: $dest already exists — refusing to overwrite" >&2
  exit 1
fi
cp "$src" "$dest"
echo "✓ record: promoted $src -> $dest"
