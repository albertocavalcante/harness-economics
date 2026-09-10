#!/usr/bin/env bash
# tools/leaks.sh — fail if personal paths or credential-shaped strings would
# be committed. Run by `just leaks`.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$(repo_root)"

# Include set covers every text file class in the repo. The extensionless
# `justfile` and the YAML configs were previously outside the gate, which is
# exactly where the first real leak was found.
if grep -rInE "$LEAK_PATTERN" \
  --include='*.md' --include='*.json' --include='*.sh' \
  --include='*.yaml' --include='*.yml' --include='justfile' .; then
  fail leaks "personal path or credential-shaped string found above"
  exit 1
fi
ok leaks "clean"
