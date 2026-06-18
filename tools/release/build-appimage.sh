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

patch_linux_host_source() {
  host_source=$1
  patch_script="$tmpdir/patch-linux-host.pl"
  cat > "$patch_script" <<'EOF'
use strict;
use warnings;

my $needle = <<'NEEDLE';
    "  if (typeof window.wizardry.rpc !== 'function') {"
    "    window.wizardry.rpc = rpcBridge;"
    "  }"
    "})();";
NEEDLE

my $replacement = <<'REPLACEMENT';
    "  if (typeof window.wizardry.rpc !== 'function') {"
    "    window.wizardry.rpc = rpcBridge;"
    "  }"
    "  function opencodeDesktopHostedPage() {"
    "    var host = (window.location && window.location.hostname) ? String(window.location.hostname).toLowerCase() : '';"
    "    return host === '127.0.0.1' || host === 'localhost' || host === 'opencode.local';"
    "  }"
    "  function opencodeDesktopAppBase() {"
    "    var marker = '__opencode_desktop_app_base__=';"
    "    var name = String(window.name || '');"
    "    var index = name.indexOf(marker);"
    "    var value = '';"
    "    if (index < 0) {"
    "      return '';"
    "    }"
    "    value = name.slice(index + marker.length).split('\\n')[0];"
    "    if (!value) {"
    "      return '';"
    "    }"
    "    try {"
    "      return decodeURIComponent(value);"
    "    } catch (error) {"
    "      return value;"
    "    }"
    "  }"
    "  function opencodeDesktopOpenPreferences() {"
    "    var base = opencodeDesktopAppBase();"
    "    var preferencesUrl = '';"
    "    if (!base || !window.wizardry || typeof window.wizardry.exec !== 'function') {"
    "      return;"
    "    }"
    "    try {"
    "      preferencesUrl = new URL('preferences.html', base).href;"
    "    } catch (error) {"
    "      return;"
    "    }"
    "    window.wizardry.exec(['__wizardry_host_open_window', preferencesUrl, 'OpenCode Preferences', '920', '760']).catch(function () {});"
    "  }"
    "  function opencodeDesktopMountPreferencesButton() {"
    "    var button;"
    "    if (!opencodeDesktopHostedPage() || !document.body) {"
    "      return;"
    "    }"
    "    button = document.getElementById('opencode-desktop-preferences-btn');"
    "    if (button) {"
    "      return;"
    "    }"
    "    button = document.createElement('button');"
    "    button.id = 'opencode-desktop-preferences-btn';"
    "    button.type = 'button';"
    "    button.textContent = 'Local Models';"
    "    button.setAttribute('aria-label', 'Open OpenCode Preferences');"
    "    button.style.position = 'fixed';"
    "    button.style.top = '18px';"
    "    button.style.right = '18px';"
    "    button.style.zIndex = '2147483647';"
    "    button.style.padding = '10px 14px';"
    "    button.style.borderRadius = '999px';"
    "    button.style.border = '1px solid rgba(27, 31, 36, 0.12)';"
    "    button.style.background = 'rgba(255, 250, 243, 0.94)';"
    "    button.style.backdropFilter = 'blur(12px)';"
    "    button.style.color = '#1f1a16';"
    "    button.style.font = '600 13px -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif';"
    "    button.style.boxShadow = '0 12px 32px rgba(31, 26, 22, 0.18)';"
    "    button.style.cursor = 'pointer';"
    "    button.addEventListener('click', function (event) {"
    "      event.preventDefault();"
    "      opencodeDesktopOpenPreferences();"
    "    });"
    "    document.body.appendChild(button);"
    "  }"
    "  function opencodeDesktopInstallShortcut() {"
    "    if (!opencodeDesktopHostedPage() || window.__opencodeDesktopPrefsShortcutInstalled) {"
    "      return;"
    "    }"
    "    window.__opencodeDesktopPrefsShortcutInstalled = true;"
    "    window.addEventListener('keydown', function (event) {"
    "      var key = String(event.key || '').toLowerCase();"
    "      if ((event.metaKey || event.ctrlKey) && !event.altKey && !event.shiftKey && key === ',') {"
    "        event.preventDefault();"
    "        opencodeDesktopOpenPreferences();"
    "      }"
    "    }, true);"
    "  }"
    "  function opencodeDesktopApplyInset() {"
    "    var root;"
    "    var button;"
    "    var wrapper;"
    "    var wrapperStyle;"
    "    var currentMargin;"
    "    var left;"
    "    var minLeft;"
    "    if (!opencodeDesktopHostedPage()) {"
    "      return;"
    "    }"
    "    root = document.documentElement;"
    "    button = document.querySelector('button[aria-label=\"Toggle sidebar\"], button[aria-label=\"Toggle menu\"], button[title=\"Toggle sidebar\"], button[title=\"Toggle menu\"]');"
    "    if (!button) {"
    "      button = document.querySelector('button[data-sidebar-trigger], button[data-testid=\"sidebar-toggle\"], button[data-testid=\"menu-toggle\"]');"
    "    }"
    "    if (!root || !button || !button.parentElement) {"
    "      return;"
    "    }"
    "    if (root.style && typeof root.style.setProperty === 'function') {"
    "      root.style.setProperty('--dialog-left-margin', '96px');"
    "      root.style.setProperty('--sidebar-left-offset', '96px');"
    "      root.style.setProperty('--safe-area-left', '96px');"
    "    }"
    "    wrapper = button.parentElement;"
    "    wrapperStyle = window.getComputedStyle ? window.getComputedStyle(wrapper) : null;"
    "    currentMargin = wrapperStyle ? parseFloat(wrapperStyle.marginLeft || '0') : 0;"
    "    if (!isFinite(currentMargin)) {"
    "      currentMargin = 0;"
    "    }"
    "    left = button.getBoundingClientRect ? button.getBoundingClientRect().left : 0;"
    "    minLeft = 96;"
    "    if (left < minLeft && wrapper.style) {"
    "      wrapper.style.marginLeft = String(Math.ceil(currentMargin + (minLeft - left))) + 'px';"
    "    }"
    "    if (button.style && left < minLeft) {"
    "      button.style.position = button.style.position || 'relative';"
    "      button.style.left = String(Math.ceil(minLeft - left)) + 'px';"
    "    }"
    "  }"
    "  function opencodeDesktopRefreshHostUi() {"
    "    opencodeDesktopInstallShortcut();"
    "    opencodeDesktopMountPreferencesButton();"
    "    opencodeDesktopApplyInset();"
    "  }"
    "  if (window.MutationObserver) {"
    "    var opencodeDesktopObserver;"
    "    var opencodeDesktopStartObserver;"
    "    var opencodeDesktopRefreshSafe = function () {"
    "      try {"
    "        opencodeDesktopRefreshHostUi();"
    "      } catch (error) {"
    "      }"
    "    };"
    "    if (document.readyState === 'loading') {"
    "      document.addEventListener('DOMContentLoaded', opencodeDesktopRefreshSafe, { once: true });"
    "    } else {"
    "      opencodeDesktopRefreshSafe();"
    "    }"
    "    opencodeDesktopObserver = new MutationObserver(opencodeDesktopRefreshSafe);"
    "    opencodeDesktopStartObserver = function () {"
    "      var attempts;"
    "      var timer;"
    "      if (!document.documentElement) {"
    "        return;"
    "      }"
    "      opencodeDesktopObserver.observe(document.documentElement, { childList: true, subtree: true });"
    "      attempts = 0;"
    "      timer = setInterval(function () {"
    "        opencodeDesktopRefreshSafe();"
    "        attempts += 1;"
    "        if (attempts >= 120) {"
    "          clearInterval(timer);"
    "        }"
    "      }, 250);"
    "    };"
    "    if (document.documentElement) {"
    "      opencodeDesktopStartObserver();"
    "    } else {"
    "      document.addEventListener('DOMContentLoaded', opencodeDesktopStartObserver, { once: true });"
    "    }"
    "  }"
    "})();";
REPLACEMENT

my $source = do { local $/; <> };
index($source, $needle) >= 0 or die "patch-linux-host.pl: bootstrap needle not found\n";
$source =~ s/\Q$needle\E/$replacement/ or die "patch-linux-host.pl: failed to replace bootstrap\n";
print $source;
EOF
  perl "$patch_script" "$host_source" > "$host_source.patched"
  mv "$host_source.patched" "$host_source"
}

mkdir -p "$OUT_DIR"

host_source="$tmpdir/main.c"
cp "$WIZARDRY_ROOT/apps/.host/linux/main.c" "$host_source"
patch_linux_host_source "$host_source"

cc -O2 \
  "$host_source" \
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
cp "$ROOT_DIR/assets/forge-icon.png" "$appdir/opencode-desktop.png"

cat > "$appdir/usr/share/applications/opencode-desktop.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=OpenCode
Exec=wizardry-host
Icon=opencode-desktop
Categories=Development;Utility;
DESKTOP
cp "$appdir/usr/share/applications/opencode-desktop.desktop" "$appdir/opencode-desktop.desktop"

cat > "$appdir/AppRun" <<'APP'
#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
exec "$HERE/usr/bin/wizardry-host" "$HERE/usr/share/opencode-desktop/app"
APP
chmod +x "$appdir/AppRun"

[ -f "$appdir/opencode-desktop.desktop" ] || {
  printf '%s\n' 'build-appimage.sh: missing top-level desktop entry in AppDir' >&2
  exit 1
}
[ -f "$appdir/opencode-desktop.png" ] || {
  printf '%s\n' 'build-appimage.sh: missing top-level icon in AppDir' >&2
  exit 1
}
[ -f "$appdir/usr/share/opencode-desktop/app/index.html" ] || {
  printf '%s\n' 'build-appimage.sh: missing app/index.html in AppDir payload' >&2
  exit 1
}
[ -f "$appdir/usr/share/opencode-desktop/app/.host/shared/wizardry-bridge.js" ] || {
  printf '%s\n' 'build-appimage.sh: missing wizardry bridge in AppDir payload' >&2
  exit 1
}

ARCH=x86_64 appimagetool "$appdir" "$OUT_DIR/OpenCode-x86_64.AppImage"
printf '%s\n' "$OUT_DIR/OpenCode-x86_64.AppImage"
