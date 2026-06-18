#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
OUT_DIR=${1-}
WIZARDRY_ROOT=${2-${OPENCODE_DESKTOP_WIZARDRY_APPS_ROOT:-}}

[ -n "$OUT_DIR" ] || {
  printf '%s\n' 'build-macos-bundle.sh: OUT_DIR is required' >&2
  exit 2
}
[ -n "$WIZARDRY_ROOT" ] || {
  printf '%s\n' 'build-macos-bundle.sh: wizardry-apps root is required via arg 2 or OPENCODE_DESKTOP_WIZARDRY_APPS_ROOT' >&2
  exit 2
}
[ -f "$WIZARDRY_ROOT/apps/.host/macos/main.m" ] || {
  printf '%s\n' "build-macos-bundle.sh: missing macOS host source under $WIZARDRY_ROOT" >&2
  exit 1
}
[ -f "$WIZARDRY_ROOT/apps/.host/shared/wizardry-bridge.js" ] || {
  printf '%s\n' "build-macos-bundle.sh: missing shared bridge under $WIZARDRY_ROOT" >&2
  exit 1
}

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/opencode-desktop-macos-build.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT INT TERM

macos_codesign_identity() {
  if [ -n "${WIZARDRY_CODESIGN_IDENTITY-}" ]; then
    printf '%s\n' "$WIZARDRY_CODESIGN_IDENTITY"
    return 0
  fi
  default_identity="Artificer Local Development Code Signing"
  if command -v security >/dev/null 2>&1 \
      && security find-certificate -c "$default_identity" >/dev/null 2>&1; then
    printf '%s\n' "$default_identity"
    return 0
  fi
  printf '%s\n' "-"
}

patch_macos_host_source() {
  host_source=$1
  patch_script="$tmpdir/patch-macos-host.pl"
  cat > "$patch_script" <<'EOF'
use strict;
use warnings;

my $needle = <<'NEEDLE';
           @"  if (typeof window.wizardry.rpc !== 'function') {"
           @"    window.wizardry.rpc = rpcBridge;"
           @"  }"
           @"})();";
NEEDLE

my $replacement = <<'REPLACEMENT';
           @"  if (typeof window.wizardry.rpc !== 'function') {"
           @"    window.wizardry.rpc = rpcBridge;"
           @"  }"
           @"  function opencodeDesktopApplyInset() {"
           @"    var host = (window.location && window.location.hostname) ? window.location.hostname : '';"
           @"    if (host !== '127.0.0.1' && host !== 'localhost' && host !== 'opencode.local') {"
           @"      return;"
           @"    }"
           @"    var root = document.documentElement;"
           @"    var button = document.querySelector('button[aria-label=\"Toggle sidebar\"]');"
           @"    if (!root || !button || !button.parentElement) {"
           @"      return;"
           @"    }"
           @"    var rootStyle = root.style;"
           @"    if (rootStyle && typeof rootStyle.setProperty === 'function') {"
           @"      rootStyle.setProperty('--dialog-left-margin', '96px');"
           @"    }"
           @"    var wrapper = button.parentElement;"
           @"    var wrapperStyle = window.getComputedStyle ? window.getComputedStyle(wrapper) : null;"
           @"    var currentMargin = wrapperStyle ? parseFloat(wrapperStyle.marginLeft || '0') : 0;"
           @"    if (!isFinite(currentMargin)) {"
           @"      currentMargin = 0;"
           @"    }"
           @"    var left = button.getBoundingClientRect ? button.getBoundingClientRect().left : 0;"
           @"    var minLeft = 96;"
           @"    if (left < minLeft && wrapper.style) {"
           @"      wrapper.style.marginLeft = String(Math.ceil(currentMargin + (minLeft - left))) + 'px';"
           @"    }"
           @"  }"
           @"  if (window.MutationObserver) {"
           @"    var opencodeDesktopReapply = function () {"
           @"      try {"
           @"        opencodeDesktopApplyInset();"
           @"      } catch (error) {"
           @"      }"
           @"    };"
           @"    if (document.readyState === 'loading') {"
           @"      document.addEventListener('DOMContentLoaded', opencodeDesktopReapply, { once: true });"
           @"    } else {"
           @"      opencodeDesktopReapply();"
           @"    }"
           @"    var opencodeDesktopObserver = new MutationObserver(opencodeDesktopReapply);"
           @"    var opencodeDesktopStartObserver = function () {"
           @"      if (!document.documentElement) {"
           @"        return;"
           @"      }"
           @"      opencodeDesktopObserver.observe(document.documentElement, { childList: true, subtree: true });"
           @"      var attempts = 0;"
           @"      var timer = setInterval(function () {"
           @"        opencodeDesktopReapply();"
           @"        attempts += 1;"
           @"        if (attempts >= 120) {"
           @"          clearInterval(timer);"
           @"        }"
           @"      }, 250);"
           @"    };"
           @"    if (document.documentElement) {"
           @"      opencodeDesktopStartObserver();"
           @"    } else {"
           @"      document.addEventListener('DOMContentLoaded', opencodeDesktopStartObserver, { once: true });"
           @"    }"
           @"  }"
           @"})();";
REPLACEMENT

my $source = do { local $/; <> };
index($source, $needle) >= 0 or die "patch-macos-host.pl: bootstrap needle not found\n";
$source =~ s/\Q$needle\E/$replacement/ or die "patch-macos-host.pl: failed to replace bootstrap\n";
print $source;
EOF
  perl "$patch_script" "$host_source" > "$host_source.patched"
  mv "$host_source.patched" "$host_source"
}

mkdir -p "$OUT_DIR"
bundle="$OUT_DIR/OpenCode.app"
bundle_resources_root="$bundle/Contents/Resources/opencode-desktop"
bundle_app_path="$bundle_resources_root/app"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"

host_source="$tmpdir/main.m"
cp "$WIZARDRY_ROOT/apps/.host/macos/main.m" "$host_source"
patch_macos_host_source "$host_source"

clang -O2 -fobjc-arc -fmodules \
  "$host_source" \
  -o "$tmpdir/wizardry-host" \
  -framework Cocoa \
  -framework WebKit \
  -framework Carbon \
  -framework QuartzCore

cp "$tmpdir/wizardry-host" "$bundle/Contents/MacOS/wizardry-host"
chmod +x "$bundle/Contents/MacOS/wizardry-host"
mkdir -p "$bundle_resources_root"
cp -R "$ROOT_DIR/app" "$bundle_app_path"
mkdir -p "$bundle_app_path/.host/shared"
cp "$WIZARDRY_ROOT/apps/.host/shared/wizardry-bridge.js" "$bundle_app_path/.host/shared/wizardry-bridge.js"
cp "$ROOT_DIR/assets/forge-icon.png" "$bundle/Contents/Resources/forge-icon.png"

cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>OpenCode</string>
  <key>CFBundleDisplayName</key>
  <string>OpenCode</string>
  <key>CFBundleIdentifier</key>
  <string>io.github.andersaamodt.opencode-desktop</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleExecutable</key>
  <string>wizardry-host</string>
  <key>WizardryAppEntry</key>
  <string>Resources/opencode-desktop/app</string>
  <key>CFBundleIconFile</key>
  <string>forge-icon.png</string>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  signing_identity=$(macos_codesign_identity)
  [ -n "$signing_identity" ] || signing_identity=-
  codesign --force --deep --sign "$signing_identity" "$bundle" >/dev/null 2>&1 || {
    printf '%s\n' "build-macos-bundle.sh: failed to codesign $bundle" >&2
    exit 1
  }
fi

printf '%s\n' "$bundle"
