#!/usr/bin/env bash
# tools/stats.sh — word count and citation count per document. Run by
# `just stats`.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$(repo_root)"

printf '%-42s %8s %8s\n' DOCUMENT WORDS CITATIONS
total_w=0
for f in *.md docs/*.md; do
  w=$(wc -w <"$f" | tr -d ' ')
  c=$({ grep -o 'https\?://' "$f" || true; } | wc -l | tr -d ' ')
  printf '%-42s %8s %8s\n' "$f" "$w" "$c"
  total_w=$((total_w + w))
done
printf '%-42s %8s\n' TOTAL "$total_w"
