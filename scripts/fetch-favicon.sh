#!/usr/bin/env bash
set -euo pipefail

CACHE_DIR="${1:-$HOME/.local/share/omarchy-megamenu/favicons}"
shift || true

mkdir -p "$CACHE_DIR"

fetch_one() {
  local raw="$1"
  # Extract clean hostname
  local domain
  domain="$(printf '%s' "$raw" | sed -E 's#^[a-zA-Z]+://##; s#^www\.##; s#[/:?#].*$##' | tr '[:upper:]' '[:lower:]')"
  if [[ -z "$domain" || "$domain" != *.* ]]; then
    return 0
  fi

  local out="$CACHE_DIR/${domain}.png"
  if [[ -s "$out" ]]; then
    return 0
  fi

  local tmp="${out}.tmp.$$"
  if curl -fsSL --max-time 5 -A "Mozilla/5.0" \
    "https://www.google.com/s2/favicons?domain=${domain}&sz=64" \
    -o "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
    mv -f "$tmp" "$out"
    return 0
  fi

  if curl -fsSL --max-time 5 -A "Mozilla/5.0" \
    "https://icons.duckduckgo.com/ip3/${domain}.ico" \
    -o "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
    mv -f "$tmp" "$out"
    return 0
  fi

  rm -f "$tmp"
}

for arg in "$@"; do
  if [[ "$arg" != "--list-existing" ]]; then
    fetch_one "$arg" || true
  fi
done

ls -1 "$CACHE_DIR" 2>/dev/null | sed 's/\.png$//' || true
