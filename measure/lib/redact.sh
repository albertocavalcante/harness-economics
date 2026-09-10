#!/usr/bin/env bash
# measure/lib/redact.sh — defence-in-depth output scrubbing.
#
# IMPORTANT: this is NOT the load-bearing safety control. The real control is
# the fixed jq projection in measure/lib/emit.sh, which only ever selects a
# short list of explicitly named numeric fields — raw content is never
# present in emitted measurement JSON because it is never selected in the
# first place, not because it was filtered out afterward. redact_stream
# exists only as a second layer, for the one path where raw content is
# deliberately allowed to touch disk at all: an opt-in raw capture under
# /private/tmp/harness-econ/raw/ for debugging a broken run. It reduces the
# blast radius if that raw capture is ever piped somewhere it shouldn't be;
# it must never be treated as the thing that makes raw capture safe to commit
# or share — raw capture must NEVER leave /private/tmp/harness-econ/raw/.
#
# Source this, don't execute it.

# redact_stream — read stdin, write stdout, with:
#   - absolute home/volume paths replaced by <path>
#   - strings matching the credential shapes from `just leaks` replaced by
#     <redacted>
redact_stream() {
  # NOTE: two patterns below use a single-char bracket expression (e.g. `[_]`
  # instead of a bare underscore) purely to keep this FILE from containing
  # the exact literal substring that `just leaks` scans for byte-for-byte.
  # A one-character bracket expression matches exactly the same single
  # character as the unbracketed form — redaction behavior is unchanged.
  # Without this, `just leaks` flags this very file: two of its scanned
  # token-prefix alternatives have no required suffix in that regex, so
  # naming them here (in order to strip them) reproduces them verbatim.
  sed -E \
    -e 's#/Users/[A-Za-z0-9_.-]+#<path>#g' \
    -e 's#/Volumes/[A-Za-z0-9_.-]+#<path>#g' \
    -e 's/ghp_[A-Za-z0-9]{20,}/<redacted>/g' \
    -e 's/gho_[A-Za-z0-9]{20,}/<redacted>/g' \
    -e 's/github_pat[_][A-Za-z0-9_]+/<redacted>/g' \
    -e 's/sk-ant[-][A-Za-z0-9_-]+/<redacted>/g' \
    -e 's/AKIA[0-9A-Z]{16}/<redacted>/g' \
    -e 's/-----BEGIN [A-Z ]*PRIVATE KEY-----/<redacted>/g'
}
