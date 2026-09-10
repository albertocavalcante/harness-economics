#!/usr/bin/env bash
# Regenerate every dark-theme SVG from its light-theme source.
#
# Diagrams are hand-authored once, in light theme, under assets/<name>.svg.
# The dark variant assets/<name>-dark.svg is DERIVED, never edited by hand --
# a hand-maintained pair drifts the moment someone tweaks one and forgets the
# other. `--check` fails if any derived file is stale, and runs in `just check`.
#
# Usage: svg-dark.sh [--check]
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)/common.sh"

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

# Light -> dark colour map. GitHub's dark canvas is #0d1117; the accents are
# chosen from GitHub's own dark palette so the diagrams sit in the page rather
# than glowing out of it.
render_dark() {
  sed -e 's/fill="#ffffff"/fill="#0d1117"/' \
    -e 's/fill="#111827"/fill="#e6edf3"/g' \
    -e 's/fill="#4b5563"/fill="#9198a1"/g' \
    -e 's/fill="#374151"/fill="#9198a1"/g' \
    -e 's/fill="#6b7280"/fill="#7d8590"/g' \
    -e 's/fill="#bbf7d0"/fill="#14351f"/g' \
    -e 's/fill="#fed7aa"/fill="#3a2410"/g' \
    -e 's/fill="#fecaca"/fill="#3d1518"/g' \
    -e 's/fill="#14532d"/fill="#7ee787"/g' \
    -e 's/fill="#7c2d12"/fill="#ffa657"/g' \
    -e 's/fill="#7f1d1d"/fill="#ff7b72"/g' \
    -e 's/fill="#b91c1c"/fill="#ff7b72"/g' \
    -e 's/stroke="#e5e7eb"/stroke="#30363d"/' \
    -e 's/stroke="#16a34a"/stroke="#3fb950"/g' \
    -e 's/stroke="#ea580c"/stroke="#d29922"/g' \
    -e 's/stroke="#dc2626"/stroke="#f85149"/g' \
    "$1"
}

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

shopt -s nullglob
sources=()
for f in assets/*.svg; do
  case "$f" in *-dark.svg) continue ;; esac
  sources+=("$f")
done

if [ "${#sources[@]}" -eq 0 ]; then
  ok "svg" "no diagrams to render"
  exit 0
fi

stale=0
for src in "${sources[@]}"; do
  dst="${src%.svg}-dark.svg"
  if [ "$CHECK" -eq 1 ]; then
    if [ ! -f "$dst" ] || ! render_dark "$src" | diff -q - "$dst" >/dev/null 2>&1; then
      fail "svg" "$dst is missing or stale — run \`just svg\`"
      stale=1
    fi
  else
    render_dark "$src" >"$dst"
  fi
done

if [ "$CHECK" -eq 1 ]; then
  [ "$stale" -eq 0 ] || exit 1
  ok "svg" "${#sources[@]} diagram(s), dark variants current"
else
  ok "svg" "rendered ${#sources[@]} dark variant(s)"
fi
