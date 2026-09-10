#!/usr/bin/env bash
# tools/clean.sh — remove the local measurement staging directory. Run by
# `just clean`.
set -euo pipefail

dir='/private/tmp/harness-econ'
if [ -d "$dir" ]; then
  rm -rf "$dir"
  echo "✓ clean: removed $dir"
else
  echo "✓ clean: $dir did not exist, nothing to remove"
fi
