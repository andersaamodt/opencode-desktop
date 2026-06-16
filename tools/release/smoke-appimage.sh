#!/bin/sh

set -eu

appimage=${1-}
[ -n "$appimage" ] || {
  printf '%s\n' 'smoke-appimage.sh: AppImage path required' >&2
  exit 2
}
[ -f "$appimage" ] || {
  printf '%s\n' "smoke-appimage.sh: AppImage not found: $appimage" >&2
  exit 1
}
chmod +x "$appimage"

[ -s "$appimage" ] || {
  printf '%s\n' 'smoke-appimage.sh: AppImage is empty' >&2
  exit 1
}

file_output=$(file "$appimage")
printf '%s\n' "$file_output"
printf '%s\n' "$file_output" | grep -E 'ELF .* executable' >/dev/null || {
  printf '%s\n' 'smoke-appimage.sh: output is not an ELF executable AppImage' >&2
  exit 1
}

printf '%s\n' "$appimage"
