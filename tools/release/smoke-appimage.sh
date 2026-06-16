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

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/opencode-desktop-appimage-smoke.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT INT TERM

chmod +x "$appimage"
(
  cd "$tmpdir"
  APPIMAGE_EXTRACT_AND_RUN=1 "$appimage" --appimage-extract >/dev/null 2>&1
)

root="$tmpdir/squashfs-root"
[ -f "$root/opencode-desktop.desktop" ] || {
  printf '%s\n' 'smoke-appimage.sh: missing top-level desktop entry in extracted AppImage' >&2
  exit 1
}
[ -f "$root/opencode-desktop.png" ] || {
  printf '%s\n' 'smoke-appimage.sh: missing top-level icon in extracted AppImage' >&2
  exit 1
}
[ -d "$root/usr/share/opencode-desktop/app" ] || {
  printf '%s\n' 'smoke-appimage.sh: missing bundled app directory in extracted AppImage' >&2
  exit 1
}
[ -x "$root/usr/bin/wizardry-host" ] || {
  printf '%s\n' 'smoke-appimage.sh: missing host binary in extracted AppImage' >&2
  exit 1
}
[ -f "$root/usr/share/opencode-desktop/app/index.html" ] || {
  printf '%s\n' 'smoke-appimage.sh: missing app/index.html in extracted AppImage' >&2
  exit 1
}
[ -f "$root/usr/share/opencode-desktop/app/.host/shared/wizardry-bridge.js" ] || {
  printf '%s\n' 'smoke-appimage.sh: missing bundled wizardry bridge in extracted AppImage' >&2
  exit 1
}

printf '%s\n' "$appimage"
