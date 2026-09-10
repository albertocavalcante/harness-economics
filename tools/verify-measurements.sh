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

# Real JSON-Schema validation. This used to be a five-key `jq has()` check that
# never opened schema.json — it passed records missing three required top-level
# keys and every required aggregate, which is how a whole emitter shipped
# schema-invalid without anyone noticing.
if ! command -v uv >/dev/null 2>&1; then
  echo "✗ measurements: uv not installed (brew install uv) — cannot validate" >&2
  exit 1
fi
if ! uv run --locked python -m measure.lib.schema "${files[@]}"; then
  echo "✗ measurements: schema validation failed above" >&2
  exit 1
fi

if grep -rInE "$LEAK_PATTERN" "${files[@]}"; then
  echo "✗ measurements: personal path or credential-shaped string found above" >&2
  exit 1
fi
echo "✓ measurements: ${#files[@]} file(s) valid"
