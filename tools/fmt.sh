#!/usr/bin/env bash
# tools/fmt.sh — rewrite every shell script in the canonical format. With
# --check, fail instead if any script deviates from it. Run by `just fmt`
# and `just fmt-check`.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$(repo_root)"

if [ "${1:-}" = "--check" ]; then
  if ! command -v shfmt >/dev/null 2>&1; then
    echo "✗ fmt-check: shfmt not installed (brew install shfmt)" >&2
    exit 1
  fi
  mapfile -t files < <(sh_files)
  if [ "${#files[@]}" -eq 0 ]; then
    echo "✓ fmt-check: no shell scripts to check"
    exit 0
  fi
  if ! diff=$(shfmt -i 2 -ci -d "${files[@]}") || [ -n "$diff" ]; then
    printf '%s\n' "$diff"
    echo "✗ fmt-check: run \`just fmt\` to fix the above" >&2
    exit 1
  fi
  echo "✓ fmt-check: ${#files[@]} script(s) correctly formatted"

  mapfile -t py_check < <(py_files)
  if [ "${#py_check[@]}" -gt 0 ]; then
    if ! uv run --locked ruff format --check .; then
      echo "✗ fmt-check: run \`just fmt\` to fix the above" >&2
      exit 1
    fi
    echo "✓ fmt-check: ${#py_check[@]} Python file(s) correctly formatted"
  fi
  exit 0
fi

mapfile -t files < <(sh_files)
if [ "${#files[@]}" -eq 0 ]; then
  echo "✓ fmt: nothing to format"
  exit 0
fi
shfmt -i 2 -ci -w "${files[@]}"
echo "✓ fmt: formatted ${#files[@]} script(s)"

mapfile -t py_fmt < <(py_files)
if [ "${#py_fmt[@]}" -gt 0 ]; then
  uv run --locked ruff format .
  echo "✓ fmt: formatted ${#py_fmt[@]} Python file(s)"
fi
