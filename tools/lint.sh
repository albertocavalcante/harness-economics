#!/usr/bin/env bash
# tools/lint.sh — static-analyse every shell script. Run by `just lint`.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$(repo_root)"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "✗ lint: shellcheck not installed (brew install shellcheck)" >&2
  exit 1
fi
mapfile -t files < <(sh_files)
if [ "${#files[@]}" -eq 0 ]; then
  echo "✓ lint: no shell scripts to check"
  exit 0
fi
if ! shellcheck -S warning "${files[@]}"; then
  echo "✗ lint: shellcheck reported issues above" >&2
  exit 1
fi
echo "✓ lint: ${#files[@]} script(s) clean"

# Python arm. ruff comes from the dev dependency group, so `uv run` supplies it
# with no separate install step.
mapfile -t py_files < <(py_files)
if [ "${#py_files[@]}" -gt 0 ]; then
  if ! command -v uv >/dev/null 2>&1; then
    echo "✗ lint: uv not installed (brew install uv) but Python sources exist" >&2
    exit 1
  fi
  if ! uv run --locked ruff check .; then
    echo "✗ lint: ruff reported issues above" >&2
    exit 1
  fi
  echo "✓ lint: ${#py_files[@]} Python file(s) clean"
fi
