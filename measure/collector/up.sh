#!/usr/bin/env bash
# Start a local OTLP collector for capturing GitHub Copilot spans.
#
# Staged entirely under /private/tmp — never inside the repo, and never under a
# path that is a symlink onto an external volume, because podman volume mounts
# do not resolve those reliably.
#
# Disk-gated on purpose: a full volume is a known trigger for a wedged podman VM
# that reports "running" while every connection fails. Refusing to start is a
# much better failure than discovering that state later.
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

# Pin by tag here for readability. For a reproducible run, resolve the digest once
# and pin it instead:
#   podman image inspect "$IMAGE" --format '{{index .RepoDigests 0}}'
IMAGE="${COLLECTOR_IMAGE:-docker.io/otel/opentelemetry-collector-contrib:0.140.0}"
CONTAINER="harness-econ-otelcol"
MIN_FREE_MB="${COLLECTOR_MIN_FREE_MB:-2048}"

require_cmd podman

COLLECTOR_DIR="$STAGING/collector"
mkdir -p "$COLLECTOR_DIR"

require_free_space "$MIN_FREE_MB" "$COLLECTOR_DIR"

if podman container exists "$CONTAINER" 2>/dev/null; then
  fail "collector" "container '$CONTAINER' already exists — run collector-down first"
  exit 1
fi

cp "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/otelcol.yaml" "$COLLECTOR_DIR/otelcol.yaml"
: >"$COLLECTOR_DIR/spans.jsonl"

podman run -d \
  --name "$CONTAINER" \
  -p 4317:4317 \
  -p 4318:4318 \
  -v "$COLLECTOR_DIR/otelcol.yaml:/etc/otelcol/config.yaml:ro" \
  -v "$COLLECTOR_DIR:/data" \
  "$IMAGE" \
  --config /etc/otelcol/config.yaml >/dev/null

ok "collector" "listening on localhost:4318 (OTLP/HTTP) and :4317 (gRPC)"
ok "collector" "spans → $COLLECTOR_DIR/spans.jsonl"
echo
echo "Next: enable OTel in VS Code settings, then run the fixture tasks."
echo "See measure/copilot/SETUP.md step 2."
