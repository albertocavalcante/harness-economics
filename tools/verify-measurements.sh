#!/usr/bin/env bash
# tools/verify-measurements.sh — validate every recorded measurement file's
# schema, then re-run the leak scan over it. Run by `just verify-measurements`.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$(repo_root)"

shopt -s nullglob
# measurements/schema.json is the JSON Schema records are validated
# against, not a measurement record — it has none of the five required
# keys by design and must be excluded from this loop, not checked as one.
files=()
for f in measurements/*.json; do
  [ "$f" = "measurements/schema.json" ] || files+=("$f")
done

if [ "${#files[@]}" -eq 0 ]; then
  echo "✓ measurements: no measurement files recorded yet"
  exit 0
fi

for f in "${files[@]}"; do
  if ! jq -e 'has("schema_version") and has("timestamp_utc") and has("harness") and has("workload") and has("aggregates")' "$f" >/dev/null 2>&1; then
    echo "✗ measurements: $f failed to parse or is missing a required key (schema_version, timestamp_utc, harness, workload, aggregates)" >&2
    exit 1
  fi
done

if grep -rInE "$LEAK_PATTERN" "${files[@]}"; then
  echo "✗ measurements: personal path or credential-shaped string found above" >&2
  exit 1
fi
echo "✓ measurements: ${#files[@]} file(s) valid"
