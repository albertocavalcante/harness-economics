#!/usr/bin/env bash
# tools/doctor.sh — preflight: confirm required and optional tooling is
# present. Run by `just doctor`.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

hard_missing=0

if command -v just >/dev/null 2>&1; then
  ok doctor "just found ($(just --version))"
else
  fail doctor "just not found"
fi

if command -v jq >/dev/null 2>&1; then
  ok doctor "jq found ($(jq --version))"
else
  fail doctor "jq not found — required"
  hard_missing=1
fi

if command -v claude >/dev/null 2>&1; then
  ok doctor "claude found ($(claude --version))"
else
  fail doctor "claude not found — required"
  hard_missing=1
fi

if command -v copilot >/dev/null 2>&1; then
  ok doctor "copilot found ($(copilot --version 2>/dev/null || echo unknown))"
else
  fail copilot "not installed — Copilot measurement path unavailable"
fi

if command -v podman >/dev/null 2>&1; then
  ok doctor "podman found ($(podman --version))"
else
  fail doctor "podman not installed — optional"
fi

echo "--- disk space (/private/tmp volume) ---"
df -h /private/tmp

if [ "$hard_missing" -eq 0 ]; then
  ok doctor "environment ready"
else
  die doctor "missing hard requirement"
fi
