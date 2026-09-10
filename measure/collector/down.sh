#!/usr/bin/env bash
# Stop and remove the local OTLP collector.
#
# Leaves the captured spans on disk under /private/tmp so they can still be parsed
# after teardown. `just clean` removes the whole staging tree when you are done.
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

CONTAINER="harness-econ-otelcol"

require_cmd podman

if ! podman container exists "$CONTAINER" 2>/dev/null; then
  ok "collector" "not running, nothing to stop"
  exit 0
fi

podman stop "$CONTAINER" >/dev/null 2>&1 || true
podman rm "$CONTAINER" >/dev/null 2>&1 || true

ok "collector" "stopped and removed"

SPANS="$STAGING/collector/spans.jsonl"
if [ -s "$SPANS" ]; then
  lines=$(wc -l < "$SPANS" | tr -d ' ')
  ok "collector" "$lines span record(s) retained at $SPANS"
fi
