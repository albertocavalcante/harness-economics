default: check

# Run every repository check
check: leaks links sources verify-measurements
    @echo "✓ all checks passed"

# Fail if personal paths or credential-shaped strings would be committed
leaks:
    #!/usr/bin/env bash
    set -euo pipefail
    pattern='/Volumes/EXTERNAL|/Users/[a-z]|ghp_[A-Za-z0-9]{20}|gho_[A-Za-z0-9]{20}|github_pat_|sk-ant-|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
    if grep -rInE "$pattern" --include='*.md' --include='*.json' --include='*.sh' . ; then
      echo "✗ leaks: personal path or credential-shaped string found above" >&2
      exit 1
    fi
    echo "✓ leaks: clean"

# Fail on broken relative links between documents
links:
    #!/usr/bin/env bash
    set -euo pipefail
    fail=0
    while IFS= read -r line; do
      file="${line%%:*}"
      target="${line#*:}"
      case "$target" in http*|\#*|mailto:*) continue ;; esac
      target="${target%%#*}"
      [ -z "$target" ] && continue
      if [ ! -e "$(dirname "$file")/$target" ]; then
        echo "✗ broken link: $file -> $target" >&2
        fail=1
      fi
    done < <(grep -rIoE '\]\([^)]+\)' --include='*.md' . | sed -E 's/\]\(([^)]*)\)/\1/')
    [ "$fail" -eq 0 ] || exit 1
    echo "✓ links: all relative links resolve"

# Enforce a minimum citation density per track document (URLs + measurement refs)
sources min='10':
    #!/usr/bin/env bash
    set -euo pipefail
    fail=0
    for f in docs/*.md; do
      urls=$( { grep -o 'https\?://' "$f" || true; } | wc -l | tr -d ' ')
      meas=$( { grep -o 'measurements/' "$f" || true; } | wc -l | tr -d ' ')
      n=$((urls + meas))
      if [ "$n" -lt "{{ min }}" ]; then
        echo "✗ sources: $f has $n citations, minimum is {{ min }}" >&2
        fail=1
      fi
    done
    [ "$fail" -eq 0 ] || exit 1
    echo "✓ sources: every track document meets the citation minimum"

# Validate every recorded measurement file's schema, then re-run the leak scan over it
verify-measurements:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    # measurements/schema.json is the JSON Schema records are validated
    # against, not a measurement record — it has none of the five required
    # keys by design and must be excluded from this loop, not checked as one.
    files=()
    for f in measurements/*.json; do
      [ "$f" = "measurements/schema.json" ] || files+=("$f")
    done
    if [ "${#files[@]}" -eq 0 ]; then
      echo "✓ measurements: no measurement files recorded yet"
      exit 0
    fi
    for f in "${files[@]}"; do
      if ! jq -e 'has("schema_version") and has("timestamp_utc") and has("harness") and has("workload") and has("aggregates")' "$f" > /dev/null 2>&1; then
        echo "✗ measurements: $f failed to parse or is missing a required key (schema_version, timestamp_utc, harness, workload, aggregates)" >&2
        exit 1
      fi
    done
    pattern='/Volumes/EXTERNAL|/Users/[a-z]|ghp_[A-Za-z0-9]{20}|gho_[A-Za-z0-9]{20}|github_pat_|sk-ant-|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
    if grep -rInE "$pattern" "${files[@]}" ; then
      echo "✗ measurements: personal path or credential-shaped string found above" >&2
      exit 1
    fi
    echo "✓ measurements: ${#files[@]} file(s) valid"

# Preflight: confirm required and optional tooling is present
doctor:
    #!/usr/bin/env bash
    set -euo pipefail
    hard_missing=0
    if command -v just > /dev/null 2>&1; then
      echo "✓ doctor: just found ($(just --version))"
    else
      echo "✗ doctor: just not found" >&2
    fi
    if command -v jq > /dev/null 2>&1; then
      echo "✓ doctor: jq found ($(jq --version))"
    else
      echo "✗ doctor: jq not found — required" >&2
      hard_missing=1
    fi
    if command -v claude > /dev/null 2>&1; then
      echo "✓ doctor: claude found ($(claude --version))"
    else
      echo "✗ doctor: claude not found — required" >&2
      hard_missing=1
    fi
    if command -v copilot > /dev/null 2>&1; then
      echo "✓ doctor: copilot found ($(copilot --version 2>/dev/null || echo unknown))"
    else
      echo "✗ copilot: not installed — Copilot measurement path unavailable"
    fi
    if command -v podman > /dev/null 2>&1; then
      echo "✓ doctor: podman found ($(podman --version))"
    else
      echo "✗ doctor: podman not installed — optional"
    fi
    echo "--- disk space (/private/tmp volume) ---"
    df -h /private/tmp
    if [ "$hard_missing" -eq 0 ]; then
      echo "✓ doctor: environment ready"
    else
      echo "✗ doctor: missing hard requirement" >&2
      exit 1
    fi

# Remove the local measurement staging directory
clean:
    #!/usr/bin/env bash
    set -euo pipefail
    dir='/private/tmp/harness-econ'
    if [ -d "$dir" ]; then
      rm -rf "$dir"
      echo "✓ clean: removed $dir"
    else
      echo "✓ clean: $dir did not exist, nothing to remove"
    fi

# Regenerate measurements/SUMMARY.md from every recorded measurement file
summary:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    files=()
    for f in measurements/*.json; do
      [ "$f" = "measurements/schema.json" ] || files+=("$f")
    done
    out='measurements/SUMMARY.md'
    {
      echo "# Measurement summary"
      echo
      echo "Generated by \`just summary\`. Do not edit by hand."
      echo
      if [ "${#files[@]}" -eq 0 ]; then
        echo "No measurements have been recorded yet."
      else
        echo "| Date | Harness | Workload | Cache-read ratio | Invalid-rep rate | Source file |"
        echo "|---|---|---|---|---|---|"
        for f in "${files[@]}"; do
          jq -r --arg src "$f" '
            [
              (.timestamp_utc // "unknown"),
              (.harness // "unknown"),
              (if (.workload | type) == "object" then (.workload.id // "unknown") else (.workload // "unknown") end),
              (.aggregates.cache_read_ratio // "n/a" | tostring),
              (.aggregates.invalid_rep_rate // "n/a" | tostring),
              $src
            ] | "| " + join(" | ") + " |"
          ' "$f"
        done
      fi
    } > "$out"
    echo "✓ summary: wrote $out"

# Word count and citation count per document
stats:
    #!/usr/bin/env bash
    set -euo pipefail
    printf '%-42s %8s %8s\n' DOCUMENT WORDS CITATIONS
    total_w=0
    for f in *.md docs/*.md; do
      w=$(wc -w < "$f" | tr -d ' ')
      c=$( { grep -o 'https\?://' "$f" || true; } | wc -l | tr -d ' ')
      printf '%-42s %8s %8s\n' "$f" "$w" "$c"
      total_w=$((total_w + w))
    done
    printf '%-42s %8s\n' TOTAL "$total_w"

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
    bash measure/claude/run.sh --task all --reps {{reps}} --mode {{mode}}

# A/B two claude configurations (model | mcp | system-prompt) on the same task, interleaved
measure-ab var a b reps='5':
    #!/usr/bin/env bash
    set -euo pipefail
    just doctor
    bash measure/claude/ab.sh --var '{{var}}' --a '{{a}}' --b '{{b}}' --reps {{reps}}

# Preset: measure-ab comparing an MCP server attached (mcp_config) vs not attached at all
measure-mcp mcp_config reps='5':
    #!/usr/bin/env bash
    set -euo pipefail
    just doctor
    bash measure/claude/ab.sh --var mcp --a none --b '{{mcp_config}}' --reps {{reps}}

# Validate FILE against the measurement schema and leak pattern, then promote it into measurements/
record FILE:
    #!/usr/bin/env bash
    set -euo pipefail
    src="{{FILE}}"
    if [ ! -f "$src" ]; then
      echo "✗ record: $src not found" >&2
      exit 1
    fi
    if ! jq -e 'has("schema_version") and has("timestamp_utc") and has("harness") and has("workload") and has("aggregates")' "$src" > /dev/null 2>&1; then
      echo "✗ record: $src failed to parse or is missing a required key (schema_version, timestamp_utc, harness, workload, aggregates)" >&2
      exit 1
    fi
    pattern='/Volumes/EXTERNAL|/Users/[a-z]|ghp_[A-Za-z0-9]{20}|gho_[A-Za-z0-9]{20}|github_pat_|sk-ant-|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
    if grep -rInE "$pattern" "$src"; then
      echo "✗ record: personal path or credential-shaped string found in $src" >&2
      exit 1
    fi
    harness=$(jq -r '.harness // "unknown"' "$src")
    # workload may be a bare string or an object carrying an id — accept either,
    # otherwise an object serializes into the filename as a JSON blob.
    workload=$(jq -r 'if (.workload | type) == "object" then (.workload.id // "unknown") else (.workload // "unknown") end' "$src")
    label=$(printf '%s-%s' "$harness" "$workload" | tr '[:upper:] ' '[:lower:]-' | tr -s '-')
    dest="measurements/$(date -u +%Y-%m-%d)-${label}.json"
    if [ -e "$dest" ]; then
      echo "✗ record: $dest already exists — refusing to overwrite" >&2
      exit 1
    fi
    cp "$src" "$dest"
    echo "✓ record: promoted $src -> $dest"

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
