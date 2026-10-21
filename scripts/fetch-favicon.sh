#!/usr/bin/env bash
set -euo pipefail

CACHE_DIR="${1:-$HOME/.local/share/omarchy-megamenu/favicons}"
shift || true

# Cap each provider response / cache file so a hostile endpoint cannot fill the disk.
# Real favicons at sz=64 are typically a few KiB; 64 KiB is a generous hard ceiling.
MAX_FAVICON_BYTES=65536

mkdir -p -m 700 "$CACHE_DIR"
chmod 700 "$CACHE_DIR" 2>/dev/null || true

file_size() {
  local path="$1"
  if stat -c%s "$path" >/dev/null 2>&1; then
    stat -c%s "$path"
  else
    wc -c < "$path" | tr -d '[:space:]'
  fi
}

accept_tmp() {
  local tmp="$1"
  local out="$2"
  if [[ ! -s "$tmp" ]]; then
    rm -f "$tmp"
    return 1
  fi
  local size
  size="$(file_size "$tmp")"
  if ! [[ "$size" =~ ^[0-9]+$ ]] || (( size > MAX_FAVICON_BYTES )); then
    rm -f "$tmp"
    return 1
  fi
  chmod 600 "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$out"
  return 0
}

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
    local existing
    existing="$(file_size "$out")"
    if [[ "$existing" =~ ^[0-9]+$ ]] && (( existing > MAX_FAVICON_BYTES )); then
      rm -f "$out"
    else
      return 0
    fi
  fi

  local tmp="${out}.tmp.$$"
  rm -f "$tmp"

  if curl -fsSL --max-time 5 --max-filesize "$MAX_FAVICON_BYTES" -A "Mozilla/5.0" \
    "https://www.google.com/s2/favicons?domain=${domain}&sz=64" \
    -o "$tmp" 2>/dev/null && accept_tmp "$tmp" "$out"; then
    return 0
  fi

  rm -f "$tmp"
  if curl -fsSL --max-time 5 --max-filesize "$MAX_FAVICON_BYTES" -A "Mozilla/5.0" \
    "https://icons.duckduckgo.com/ip3/${domain}.ico" \
    -o "$tmp" 2>/dev/null && accept_tmp "$tmp" "$out"; then
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
