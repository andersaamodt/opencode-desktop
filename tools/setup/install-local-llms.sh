#!/bin/sh

set -eu

PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:${HOME}/.local/bin:${HOME}/bin
export PATH

wizardry_install_url='https://raw.githubusercontent.com/andersaamodt/wizardry/main/install'

usage() {
  cat <<'EOF'
Usage: install-local-llms.sh [--list]

Bootstraps Wizardry if needed, prints the curated local-model recommendations,
and opens the Wizardry menu used to install and manage local LLMs for OpenCode.

Options:
  --list   Print the curated model recommendations without opening a menu
  -h       Show this help text
EOF
}

say() {
  printf '%s\n' "$*"
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

wizardry_dir=${WIZARDRY_DIR-${HOME}/.wizardry}
ai_dev_dir=
list_only=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --list)
      list_only=1
      ;;
    --help|--usage|-h)
      usage
      exit 0
      ;;
    *)
      die "install-local-llms.sh: unknown argument: $1"
      ;;
  esac
  shift
done

download_to() {
  target=$1
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$wizardry_install_url" -o "$target"
    return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO "$target" "$wizardry_install_url"
    return 0
  fi
  return 1
}

ensure_wizardry() {
  if [ -d "$wizardry_dir" ] && [ -f "$wizardry_dir/install" ]; then
    return 0
  fi

  scratch_root=${TMPDIR:-/tmp}
  if [ -d /var/tmp ]; then
    scratch_root=/var/tmp
  fi
  tmpdir=$(mktemp -d "$scratch_root/opencode-desktop-wizardry-install.XXXXXX")
  trap 'rm -rf "$tmpdir"' EXIT INT TERM HUP
  installer="$tmpdir/wizardry-install"

  say "Wizardry is not installed yet."
  say "Installing Wizardry via the official installer..."

  if ! download_to "$installer"; then
    die "install-local-llms.sh: curl or wget is required to install Wizardry"
  fi

  sh "$installer"

  if [ ! -d "$wizardry_dir" ] || [ ! -f "$wizardry_dir/install" ]; then
    die "install-local-llms.sh: Wizardry installer finished, but $wizardry_dir was not created"
  fi
}

locate_ai_dev_dir() {
  if [ -d "$wizardry_dir/spells/.arcana/ai-dev" ]; then
    ai_dev_dir=$wizardry_dir/spells/.arcana/ai-dev
    return 0
  fi
  die "install-local-llms.sh: could not find Wizardry ai-dev scripts under $wizardry_dir"
}

export_wizardry_environment() {
  wizardry_path=
  for dir in $(find "$wizardry_dir/spells" -mindepth 1 -maxdepth 2 -type d | sort); do
    wizardry_path=${wizardry_path}:${dir}
  done
  PATH=${wizardry_dir}/spells${wizardry_path}:$PATH
  export PATH WIZARDRY_DIR="$wizardry_dir"
}

print_recommended_llms() {
  say
  say "Recommended local LLMs for OpenCode:"
  "$ai_dev_dir/list-available-llms" | while IFS='|' read -r model description size_gb context_k; do
    [ -n "$model" ] || continue
    printf '  %-24s %s (%s GB, %sk context)\n' "$model" "$description" "$size_gb" "$context_k"
  done
}

open_menu() {
  if "$ai_dev_dir/is-ai-component-installed" ollama >/dev/null 2>&1; then
    say
    say "Opening Wizardry's LLM manager..."
    exec "$ai_dev_dir/manage-llms"
  fi

  say
  say "Ollama is not installed yet, so OpenCode cannot use local models yet."
  say "Opening Wizardry's AI development menu so you can install Ollama first."
  exec "$ai_dev_dir/ai-dev-menu"
}

ensure_wizardry
locate_ai_dev_dir
export_wizardry_environment
print_recommended_llms

if [ "$list_only" -eq 1 ]; then
  exit 0
fi

open_menu
