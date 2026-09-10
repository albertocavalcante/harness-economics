#!/usr/bin/env bash
# measure/fixture/make.sh — deterministic synthetic codebase generator.
#
# Generates a plausible ~27-file, ~150-250KB fake source tree into
# /private/tmp/harness-econ/fixture/. The SAME output, byte-for-byte, on
# every machine: no $RANDOM, no timestamps, no hostnames, no network. The
# only "randomness" is a fixed-seed linear congruential generator done in
# pure bash integer arithmetic (deterministic on any POSIX bash — no
# floating point, no locale dependence) and it is used ONLY for cosmetic
# filler comments. Every fact a task can ask about is a hand-picked literal
# constant in this script, not a generated value — so the EXPECTED: answers
# in measure/fixture/tasks/*.md are known ahead of time and never drift
# across a regeneration.
#
# Usage:
#   measure/fixture/make.sh            # generate into $STAGING/fixture
#   measure/fixture/make.sh --verify   # regenerate into a temp dir and
#                                       # confirm the hash matches
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091 source=../lib/common.sh
source "$REPO_ROOT/measure/lib/common.sh"

FIXTURE_SEED=20260910   # fixed. Changing this changes filler bytes only —
                         # it does not touch any of the embedded facts below,
                         # so task EXPECTED values never need to change.

# --- embedded facts -----------------------------------------------------
# These constants are the single source of truth for every fixture task's
# EXPECTED: answer. If you change one here, update the matching task file.
#
#   T1 — src/core/invoice.go defines exactly one function that computes an
#        invoice total, named ComputeInvoiceTotal.
#   T2 — config/settings.yaml sets max_retry_count to CFG_MAX_RETRY, and
#        that key/value appears nowhere else in the tree.
#   T3 — exactly 5 files match `*_test.go`; each has a header comment
#        `// CHECKSUM: <int>`; the five values sum to CHECKSUM_SUM.
#   T4 — exactly one file per module (core/util/api) defines
#        `func ProcessBatch() int { return <int> }`; the three values sum
#        to PROCESSBATCH_SUM.
CFG_MAX_RETRY=7
CHECKSUM_INVOICE=11
CHECKSUM_UTIL1=23
CHECKSUM_UTIL2=37
CHECKSUM_API1=41
CHECKSUM_API2=59
CHECKSUM_SUM=$((CHECKSUM_INVOICE + CHECKSUM_UTIL1 + CHECKSUM_UTIL2 + CHECKSUM_API1 + CHECKSUM_API2))
PROCESSBATCH_CORE=17
PROCESSBATCH_UTIL=29
PROCESSBATCH_API=53
PROCESSBATCH_SUM=$((PROCESSBATCH_CORE + PROCESSBATCH_UTIL + PROCESSBATCH_API))

# Guard the two derived sums against a future edit to one constant without
# updating the matching task's EXPECTED: line — this is what actually uses
# CHECKSUM_SUM and PROCESSBATCH_SUM (not dead code, despite what a linter
# that can't see measure/fixture/tasks/*.md would conclude).
[ "$CHECKSUM_SUM" -eq 171 ] || die "fixture" "CHECKSUM_SUM is $CHECKSUM_SUM, expected 171 — update measure/fixture/tasks/T3.md's EXPECTED line"
[ "$PROCESSBATCH_SUM" -eq 99 ] || die "fixture" "PROCESSBATCH_SUM is $PROCESSBATCH_SUM, expected 99 — update measure/fixture/tasks/T4.md's EXPECTED line"

# --- deterministic filler --------------------------------------------------
# A fixed word list plus a fixed-seed LCG. Pure integer arithmetic — no
# floats, no locale, no $RANDOM. Same sequence every time, on every machine.
WORDS=(alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu
       xi omicron pi rho sigma tau upsilon phi chi psi omega ledger cache
       queue shard replica cursor manifest ticket policy session token
       invoice batch ridge basin quorum vector matrix kernel)

LCG_STATE=$FIXTURE_SEED
lcg_next() {
  LCG_STATE=$(( (LCG_STATE * 1103515245 + 12345) % 2147483648 ))
  echo "$LCG_STATE"
}

# pad_comment_lines <n> <comment_prefix>  — print n deterministic filler
# comment lines to stdout. Safe to redirect into any file regardless of
# language, since it's always a comment line.
pad_comment_lines() {
  local n="$1" prefix="$2" i idx1 idx2 num
  for ((i = 0; i < n; i++)); do
    idx1=$(( $(lcg_next) % ${#WORDS[@]} ))
    idx2=$(( $(lcg_next) % ${#WORDS[@]} ))
    num=$(( $(lcg_next) % 10000 ))
    printf '%s note: %s %s handles case %d\n' "$prefix" "${WORDS[$idx1]}" "${WORDS[$idx2]}" "$num"
  done
}

# write_go_file <path> <package> <body-generator-fn> <pad-lines>
write_go_file() {
  local path="$1" package="$2" body_fn="$3" pad_lines="$4"
  {
    printf 'package %s\n\n' "$package"
    "$body_fn"
    printf '\n// --- filler below: deterministic, not load-bearing ---\n'
    pad_comment_lines "$pad_lines" '//'
  } > "$path"
}

# --- module bodies ----------------------------------------------------
core_invoice_body() {
  cat <<GO
// ComputeInvoiceTotal sums line items and applies the configured tax rate.
// This is the one function in this file that computes an invoice total.
func ComputeInvoiceTotal(lineItems []int, taxBasisPoints int) int {
	sum := 0
	for _, item := range lineItems {
		sum += item
	}
	return sum + (sum*taxBasisPoints)/10000
}
GO
}

core2_body() {
  cat <<GO
// ProcessBatch returns a fixed sentinel used by the core module's batch
// pipeline smoke check.
func ProcessBatch() int {
	return $PROCESSBATCH_CORE
}

func normalizeLedgerEntry(entry string) string {
	return entry
}
GO
}

filler_body_n() {
  local n="$1"
  cat <<GO
func helperFunctionNumber${n}(x int) int {
	return x * ${n}
}

func supportRoutine${n}() string {
	return "routine-${n}"
}
GO
}

util1_body() {
  cat <<GO
// ProcessBatch returns a fixed sentinel used by the util module's batch
// pipeline smoke check.
func ProcessBatch() int {
	return $PROCESSBATCH_UTIL
}

func dedupeTokens(tokens []string) []string {
	seen := map[string]bool{}
	out := []string{}
	for _, t := range tokens {
		if !seen[t] {
			seen[t] = true
			out = append(out, t)
		}
	}
	return out
}
GO
}

api1_body() {
  cat <<GO
// ProcessBatch returns a fixed sentinel used by the api module's batch
// pipeline smoke check.
func ProcessBatch() int {
	return $PROCESSBATCH_API
}

func encodeCursor(offset int) string {
	return "cursor-" + itoaFast(offset)
}

func itoaFast(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	digits := []byte{}
	for n > 0 {
		digits = append([]byte{byte('0' + n%10)}, digits...)
		n /= 10
	}
	if neg {
		return "-" + string(digits)
	}
	return string(digits)
}
GO
}

write_test_go_file() {
  local path="$1" package="$2" checksum="$3" fn_name="$4" pad_lines="$5"
  {
    printf '// CHECKSUM: %s\n' "$checksum"
    printf 'package %s\n\n' "$package"
    printf 'import "testing"\n\n'
    printf 'func %s(t *testing.T) {\n' "$fn_name"
    printf '\t// deterministic fixture test; not executed by this repo\n'
    printf '\tif 1+1 != 2 {\n\t\tt.Fatal("arithmetic broke")\n\t}\n'
    printf '}\n\n'
    printf '// --- filler below: deterministic, not load-bearing ---\n'
    pad_comment_lines "$pad_lines" '//'
  } > "$path"
}

generate_into() {
  local root="$1"
  rm -rf "$root"
  mkdir -p "$root/src/core" "$root/src/util" "$root/src/api" "$root/config" "$root/docs"

  # Reset the LCG so filler content is identical regardless of what ran
  # before this call (make.sh normal run vs --verify's second generation).
  LCG_STATE=$FIXTURE_SEED

  # --- top-level docs ---
  cat > "$root/README.md" <<MD
# fixture-app

A synthetic codebase generated by \`measure/fixture/make.sh\` for measuring
agentic-coding-harness token and cost economics. It is not a real
application; nothing here is meant to compile or run.

## Layout

- \`src/core/\` — invoicing and batch-processing core logic
- \`src/util/\` — shared helpers
- \`src/api/\` — request/response handling
- \`config/settings.yaml\` — runtime configuration
- \`docs/ARCHITECTURE.md\` — module overview
MD

  cat > "$root/docs/ARCHITECTURE.md" <<MD
# Architecture

Three modules: \`core\`, \`util\`, \`api\`. Each module exposes a
\`ProcessBatch\` entry point used by the (fictional) batch scheduler. Core
additionally owns invoice computation.

Configuration lives in \`config/settings.yaml\`. Tests live alongside the
code they cover and are named \`*_test.go\`.
MD

  cat > "$root/Makefile" <<'MAKE'
.PHONY: build test
build:
	@echo "this is a fixture; there is nothing to build"
test:
	@echo "this is a fixture; there is nothing to test"
MAKE

  cat > "$root/config/settings.yaml" <<YAML
# Runtime configuration for fixture-app.
service_name: fixture-app
log_level: info
max_retry_count: $CFG_MAX_RETRY
timeout_seconds: 30
YAML

  # --- src/core ---
  write_go_file "$root/src/core/invoice.go" core core_invoice_body 190
  write_test_go_file "$root/src/core/invoice_test.go" core "$CHECKSUM_INVOICE" TestComputeInvoiceTotal 50
  write_go_file "$root/src/core/core2.go" core core2_body 190
  for n in 3 4 5 6; do
    write_go_file "$root/src/core/core${n}.go" core "filler_body_wrapper_core_${n}" 190
  done

  # --- src/util ---
  write_go_file "$root/src/util/util1.go" util util1_body 190
  write_test_go_file "$root/src/util/util1_test.go" util "$CHECKSUM_UTIL1" TestProcessBatch 50
  write_go_file "$root/src/util/util2.go" util "filler_body_wrapper_util_2" 190
  write_test_go_file "$root/src/util/util2_test.go" util "$CHECKSUM_UTIL2" TestDedupeTokens 50
  for n in 3 4 5 6; do
    write_go_file "$root/src/util/util${n}.go" util "filler_body_wrapper_util_${n}" 190
  done

  # --- src/api ---
  write_go_file "$root/src/api/api1.go" api api1_body 190
  write_test_go_file "$root/src/api/api1_test.go" api "$CHECKSUM_API1" TestProcessBatch 50
  write_go_file "$root/src/api/api2.go" api "filler_body_wrapper_api_2" 190
  write_test_go_file "$root/src/api/api2_test.go" api "$CHECKSUM_API2" TestEncodeCursor 50
  for n in 3 4 5 6; do
    write_go_file "$root/src/api/api${n}.go" api "filler_body_wrapper_api_${n}" 190
  done
}

# filler_body_wrapper_<module>_<n> functions — one per filler file, each just
# calls filler_body_n with a distinct literal so file contents differ.
filler_body_wrapper_core_3() { filler_body_n 3; }
filler_body_wrapper_core_4() { filler_body_n 4; }
filler_body_wrapper_core_5() { filler_body_n 5; }
filler_body_wrapper_core_6() { filler_body_n 6; }
filler_body_wrapper_util_2() { filler_body_n 12; }
filler_body_wrapper_util_3() { filler_body_n 13; }
filler_body_wrapper_util_4() { filler_body_n 14; }
filler_body_wrapper_util_5() { filler_body_n 15; }
filler_body_wrapper_util_6() { filler_body_n 16; }
filler_body_wrapper_api_2() { filler_body_n 22; }
filler_body_wrapper_api_3() { filler_body_n 23; }
filler_body_wrapper_api_4() { filler_body_n 24; }
filler_body_wrapper_api_5() { filler_body_n 25; }
filler_body_wrapper_api_6() { filler_body_n 26; }

# compute_fixture_hash <dir> — sha256 over the sorted file list AND contents.
# Excludes FIXTURE.sha256 itself (it doesn't exist yet on first generation,
# and must not be part of its own hash on a re-verify).
compute_fixture_hash() {
  local dir="$1"
  (
    cd "$dir"
    find . -type f ! -name 'FIXTURE.sha256' -print | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s\n' "$f"
      cat "$f"
    done
  ) | sha256_of_stdin
}

main() {
  if [ "${1:-}" = "--verify" ]; then
    ensure_staging
    local existing_hash_file="$STAGING/fixture/FIXTURE.sha256"
    if [ ! -f "$existing_hash_file" ]; then
      die "fixture" "no fixture at $STAGING/fixture yet — run 'measure/fixture/make.sh' first"
    fi
    local existing_hash
    existing_hash="$(cat "$existing_hash_file")"

    # Deliberately NOT `local`: the EXIT trap below fires after main()
    # returns, once the whole script is exiting — under `set -u` a trap that
    # references a local variable whose owning function already returned is
    # an "unbound variable" error, not a no-op. VERIFY_TMP_DIR is global so
    # it's still in scope when the trap actually runs.
    VERIFY_TMP_DIR="$(mktemp -d "${STAGING}/verify.XXXXXX")"
    trap 'rm -rf "$VERIFY_TMP_DIR"' EXIT
    generate_into "$VERIFY_TMP_DIR/fixture"
    local fresh_hash
    fresh_hash="$(compute_fixture_hash "$VERIFY_TMP_DIR/fixture")"

    if [ "$fresh_hash" = "$existing_hash" ]; then
      ok "fixture" "hash matches"
    else
      die "fixture" "hash mismatch: regenerated=$fresh_hash existing=$existing_hash"
    fi
    return 0
  fi

  require_free_space 200 "$STAGING"
  ensure_staging
  generate_into "$STAGING/fixture"
  local hash
  hash="$(compute_fixture_hash "$STAGING/fixture")"
  echo "$hash" > "$STAGING/fixture/FIXTURE.sha256"
  local size_kb
  size_kb="$(du -sk "$STAGING/fixture" | awk '{print $1}')"
  local file_count
  file_count="$(find "$STAGING/fixture" -type f ! -name 'FIXTURE.sha256' | wc -l | tr -d ' ')"
  ok "fixture" "generated $file_count files (${size_kb}KB) at $STAGING/fixture — sha256 $hash"
}

main "$@"
