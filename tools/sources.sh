#!/usr/bin/env bash
# tools/sources.sh — enforce a minimum citation density per track document
# (URLs + measurement refs). Run by `just sources [min]` (default 10).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$(repo_root)"

min="${1:-10}"
failed=0
for f in docs/*.md; do
  urls=$({ grep -o 'https\?://' "$f" || true; } | wc -l | tr -d ' ')
  meas=$({ grep -o 'measurements/' "$f" || true; } | wc -l | tr -d ' ')
  n=$((urls + meas))
  if [ "$n" -lt "$min" ]; then
    echo "✗ sources: $f has $n citations, minimum is $min" >&2
    failed=1
  fi
done
[ "$failed" -eq 0 ] || exit 1
ok sources "every track document meets the citation minimum"
