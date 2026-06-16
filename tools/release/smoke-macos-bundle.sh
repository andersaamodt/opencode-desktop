#!/bin/sh

set -eu

bundle=${1-}
[ -n "$bundle" ] || {
  printf '%s\n' 'smoke-macos-bundle.sh: bundle path required' >&2
  exit 2
}

plist="$bundle/Contents/Info.plist"
[ -d "$bundle" ] || {
  printf '%s\n' "smoke-macos-bundle.sh: bundle not found: $bundle" >&2
  exit 1
}
[ -f "$plist" ] || {
  printf '%s\n' "smoke-macos-bundle.sh: missing Info.plist in $bundle" >&2
  exit 1
}

name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$plist")
display_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$plist")
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")
app_entry=$(/usr/libexec/PlistBuddy -c 'Print :WizardryAppEntry' "$plist")

[ "$name" = "OpenCode" ] || {
  printf '%s\n' "smoke-macos-bundle.sh: unexpected CFBundleName: $name" >&2
  exit 1
}
[ "$display_name" = "OpenCode" ] || {
  printf '%s\n' "smoke-macos-bundle.sh: unexpected CFBundleDisplayName: $display_name" >&2
  exit 1
}
[ "$executable" = "wizardry-host" ] || {
  printf '%s\n' "smoke-macos-bundle.sh: unexpected CFBundleExecutable: $executable" >&2
  exit 1
}
[ "$app_entry" = "Resources/app" ] || {
  printf '%s\n' "smoke-macos-bundle.sh: unexpected WizardryAppEntry: $app_entry" >&2
  exit 1
}
[ -x "$bundle/Contents/MacOS/wizardry-host" ] || {
  printf '%s\n' 'smoke-macos-bundle.sh: missing executable host binary' >&2
  exit 1
}
[ -f "$bundle/Contents/Resources/app/index.html" ] || {
  printf '%s\n' 'smoke-macos-bundle.sh: missing app/index.html in bundle resources' >&2
  exit 1
}
[ -f "$bundle/Contents/Resources/app/.host/shared/wizardry-bridge.js" ] || {
  printf '%s\n' 'smoke-macos-bundle.sh: missing bundled wizardry bridge in bundle resources' >&2
  exit 1
}

printf '%s\n' "$bundle"
