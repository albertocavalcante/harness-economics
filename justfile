default: check

# Run every repository check
check: leaks links refs sources verify-measurements lint fmt-check
    @echo "✓ all checks passed"

# Fail if a reference-style link is used but never defined, or defined but unused
refs:
    @./tools/refs.sh

# Static-analyse every shell script
lint:
    @./tools/lint.sh

# Rewrite every shell script in the canonical format
fmt:
    @./tools/fmt.sh

# Fail if any shell script deviates from the canonical format
fmt-check:
    @./tools/fmt.sh --check

# Fail if personal paths or credential-shaped strings would be committed
leaks:
    @./tools/leaks.sh

# Fail on broken relative links between documents
links:
    @./tools/links.sh

# Enforce a minimum citation density per track document (URLs + measurement refs)
sources min='10':
    @./tools/sources.sh {{ min }}

# Validate every recorded measurement file's schema, then re-run the leak scan over it
verify-measurements:
    @./tools/verify-measurements.sh

# Preflight: confirm required and optional tooling is present
doctor:
    @./tools/doctor.sh

# Remove the local measurement staging directory
clean:
    @./tools/clean.sh

# Regenerate measurements/SUMMARY.md from every recorded measurement file
summary:
    @./tools/summary.sh

# Word count and citation count per document
stats:
    @./tools/stats.sh

# Generate the deterministic synthetic fixture into /private/tmp/harness-econ and print its hash
fixture:
    #!/usr/bin/env bash
    set -euo pipefail
    bash measure/fixture/make.sh

# Regenerate the fixture into a temp dir and confirm it hashes identically
fixture-verify:
    #!/usr/bin/env bash
    set -euo pipefail
    bash measure/fixture/make.sh --verify

# Run all four fixture tasks against `claude -p` N times and record aggregates
measure-cache reps='5' mode='warm':
    #!/usr/bin/env bash
    set -euo pipefail
    just doctor
    bash measure/claude/run.sh --task all --reps {{ reps }} --mode {{ mode }}

# A/B two claude configurations (model | mcp | system-prompt) on the same task, interleaved
measure-ab var a b reps='5':
    #!/usr/bin/env bash
    set -euo pipefail
    just doctor
    bash measure/claude/ab.sh --var '{{ var }}' --a '{{ a }}' --b '{{ b }}' --reps {{ reps }}

# Preset: measure-ab comparing an MCP server attached (mcp_config) vs not attached at all
measure-mcp mcp_config reps='5':
    #!/usr/bin/env bash
    set -euo pipefail
    just doctor
    bash measure/claude/ab.sh --var mcp --a none --b '{{ mcp_config }}' --reps {{ reps }}

# Validate FILE against the measurement schema and leak pattern, then promote it into measurements/
record FILE:
    @./tools/record.sh "{{ FILE }}"

# Start a local OTLP collector for capturing GitHub Copilot spans (podman, disk-gated)
collector-up:
    #!/usr/bin/env bash
    set -euo pipefail
    bash measure/collector/up.sh

# Stop and remove the local OTLP collector, retaining captured spans on disk
collector-down:
    #!/usr/bin/env bash
    set -euo pipefail
    bash measure/collector/down.sh
