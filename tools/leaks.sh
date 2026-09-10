#!/usr/bin/env bash
# tools/leaks.sh — fail if personal paths or credential-shaped strings would
# be committed. Run by `just leaks`.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$(repo_root)"

# Include set covers every text file class in the repo. The extensionless
# `justfile` and the YAML configs were previously outside the gate, which is
# exactly where the first real leak was found.
#
# .venv is excluded because it is machine-local, gitignored, and full of vendored
# third-party sources whose absolute paths would drown the signal. `grep -r` does
# not read .gitignore, so this has to be explicit — the gate exists to check what
# WE would commit, and nothing in .venv is committable.
if grep -rInE "$LEAK_PATTERN" \
  --exclude-dir='.venv' --exclude-dir='.git' \
  --exclude-dir='__pycache__' --exclude-dir='.pytest_cache' --exclude-dir='.ruff_cache' \
  --include='*.md' --include='*.json' --include='*.sh' --include='*.py' \
  --include='*.toml' --include='*.yaml' --include='*.yml' --include='justfile' .; then
  fail leaks "personal path or credential-shaped string found above"
  exit 1
fi
ok leaks "clean"
