#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
OUT_DIR=${1-}
WIZARDRY_ROOT=${2-${OPENCODE_DESKTOP_WIZARDRY_APPS_ROOT:-}}

[ -n "$OUT_DIR" ] || {
  printf '%s\n' 'build-appimage.sh: OUT_DIR is required' >&2
  exit 2
}
[ -n "$WIZARDRY_ROOT" ] || {
  printf '%s\n' 'build-appimage.sh: wizardry-apps root is required via arg 2 or OPENCODE_DESKTOP_WIZARDRY_APPS_ROOT' >&2
  exit 2
}
[ -f "$WIZARDRY_ROOT/apps/.host/linux/main.c" ] || {
  printf '%s\n' "build-appimage.sh: missing linux host source under $WIZARDRY_ROOT" >&2
  exit 1
}
[ -f "$WIZARDRY_ROOT/apps/.host/shared/wizardry-bridge.js" ] || {
  printf '%s\n' "build-appimage.sh: missing shared bridge under $WIZARDRY_ROOT" >&2
  exit 1
}
command -v appimagetool >/dev/null 2>&1 || {
  printf '%s\n' 'build-appimage.sh: appimagetool is required' >&2
  exit 1
}

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/opencode-desktop-appimage-build.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT INT TERM

mkdir -p "$OUT_DIR"

cc -O2 \
  "$WIZARDRY_ROOT/apps/.host/linux/main.c" \
  -o "$tmpdir/wizardry-host" \
  $(pkg-config --cflags --libs gtk+-3.0 webkit2gtk-4.1)

appdir="$tmpdir/AppDir"
mkdir -p \
  "$appdir/usr/bin" \
  "$appdir/usr/share/opencode-desktop" \
  "$appdir/usr/share/applications" \
  "$appdir/usr/share/icons/hicolor/1024x1024/apps"

cp "$tmpdir/wizardry-host" "$appdir/usr/bin/wizardry-host"
cp -R "$ROOT_DIR/app" "$appdir/usr/share/opencode-desktop/app"
mkdir -p "$appdir/usr/share/opencode-desktop/app/.host/shared"
cp "$WIZARDRY_ROOT/apps/.host/shared/wizardry-bridge.js" "$appdir/usr/share/opencode-desktop/app/.host/shared/wizardry-bridge.js"
cp "$ROOT_DIR/assets/forge-icon.png" "$appdir/usr/share/icons/hicolor/1024x1024/apps/opencode-desktop.png"

cat > "$appdir/usr/share/applications/opencode-desktop.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=OpenCode
Exec=wizardry-host
Icon=opencode-desktop
Categories=Development;Utility;
DESKTOP

cat > "$appdir/AppRun" <<'APP'
#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
exec "$HERE/usr/bin/wizardry-host" "$HERE/usr/share/opencode-desktop/app"
APP
chmod +x "$appdir/AppRun"

ARCH=x86_64 appimagetool "$appdir" "$OUT_DIR/OpenCode-x86_64.AppImage"
printf '%s\n' "$OUT_DIR/OpenCode-x86_64.AppImage"
