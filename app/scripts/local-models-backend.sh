#!/bin/sh

set -eu

PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:${HOME}/.local/bin:${HOME}/bin
export PATH

wizardry_install_url='https://raw.githubusercontent.com/andersaamodt/wizardry/main/install'
wizardry_dir=${WIZARDRY_DIR-${HOME}/.wizardry}
ai_dev_dir=

say() {
  printf '%s\n' "$*"
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

wizardry_available() {
  [ -d "$wizardry_dir/spells/.arcana/ai-dev" ] && [ -f "$wizardry_dir/install" ]
}

export_wizardry_environment() {
  wizardry_path=
  for dir in $(find "$wizardry_dir/spells" -mindepth 1 -maxdepth 2 -type d | sort); do
    wizardry_path=${wizardry_path}:$dir
  done
  PATH=${wizardry_dir}/spells${wizardry_path}:$PATH
  export PATH WIZARDRY_DIR="$wizardry_dir"
}

locate_ai_dev_dir() {
  if [ -d "$wizardry_dir/spells/.arcana/ai-dev" ]; then
    ai_dev_dir=$wizardry_dir/spells/.arcana/ai-dev
    return 0
  fi
  die "local-models-backend: Wizardry ai-dev scripts are unavailable"
}

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

install_wizardry() {
  if wizardry_available; then
    return 0
  fi

  scratch_root=${TMPDIR:-/tmp}
  if [ -d /var/tmp ]; then
    scratch_root=/var/tmp
  fi
  tmpdir=$(mktemp -d "$scratch_root/opencode-desktop-wizardry-install.XXXXXX")
  trap 'rm -rf "$tmpdir"' EXIT INT TERM HUP
  installer=$tmpdir/wizardry-install

  if ! download_to "$installer"; then
    die "local-models-backend: curl or wget is required to install Wizardry"
  fi

  sh "$installer"

  if ! wizardry_available; then
    die "local-models-backend: Wizardry installer finished, but $wizardry_dir is unavailable"
  fi
}

ensure_wizardry() {
  if ! wizardry_available; then
    install_wizardry
  fi
  export_wizardry_environment
  locate_ai_dev_dir
}

curated_models() {
  printf '%s\n' "phi3:mini|lightweight local helper|2.2|128"
  printf '%s\n' "qwen3:4b|best small all-around coding generalist|2.5|256"
  printf '%s\n' "qwen2.5-coder:7b|everyday code writer|4.7|32"
  printf '%s\n' "deepseek-r1:8b|reasoning-heavy bug reviewer|5.2|128"
  printf '%s\n' "llama3.1:8b|big-context general fallback|4.9|128"
  printf '%s\n' "devstral:24b|agentic power user pick|14|128"
}

resolve_ollama_bin() {
  if command -v ollama >/dev/null 2>&1; then
    command -v ollama
    return 0
  fi
  if [ -x "$HOME/.local/bin/ollama" ]; then
    printf '%s\n' "$HOME/.local/bin/ollama"
    return 0
  fi
  if [ -x "/usr/local/bin/ollama" ]; then
    printf '%s\n' "/usr/local/bin/ollama"
    return 0
  fi
  return 1
}

ollama_installed() {
  if wizardry_available; then
    ensure_wizardry
    "$ai_dev_dir/is-ai-component-installed" ollama >/dev/null 2>&1
    return $?
  fi
  resolve_ollama_bin >/dev/null 2>&1
}

ollama_running() {
  if command -v curl >/dev/null 2>&1; then
    if curl -fsS --max-time 1 "http://127.0.0.1:11434/api/tags" >/dev/null 2>&1; then
      return 0
    fi
  elif command -v wget >/dev/null 2>&1; then
    if wget -q -T 1 -O - "http://127.0.0.1:11434/api/tags" >/dev/null 2>&1; then
      return 0
    fi
  fi
  pgrep -f "ollama serve" >/dev/null 2>&1
}

ensure_ollama_identity() {
  ollama_home=$HOME/.ollama
  ollama_key=$ollama_home/id_ed25519
  if [ -f "$ollama_key" ]; then
    return 0
  fi
  mkdir -p "$ollama_home"
  if ! command -v ssh-keygen >/dev/null 2>&1; then
    die "local-models-backend: ssh-keygen is required to initialize Ollama pulls"
  fi
  ssh-keygen -q -t ed25519 -N "" -f "$ollama_key" >/dev/null 2>&1 \
    || die "local-models-backend: failed to generate $ollama_key"
}

start_ollama_session() {
  if ollama_running; then
    return 0
  fi

  ollama_bin=$(resolve_ollama_bin) || die "local-models-backend: Ollama is not installed"
  ensure_ollama_identity

  state_root=${XDG_STATE_HOME:-$HOME/.local/state}
  log_root=$state_root/opencode-desktop
  mkdir -p "$log_root"

  nohup "$ollama_bin" serve >"$log_root/ollama.log" 2>"$log_root/ollama.err" &

  tries=0
  while [ "$tries" -lt 120 ]; do
    if ollama_running; then
      return 0
    fi
    tries=$((tries + 1))
    sleep 0.25
  done

  if [ -f "$log_root/ollama.err" ]; then
    tail -n 40 "$log_root/ollama.err" >&2 || :
  fi
  die "local-models-backend: Ollama did not become ready"
}

installed_models() {
  if ! ollama_installed; then
    return 0
  fi
  if ! ollama_running; then
    return 0
  fi
  ollama_bin=$(resolve_ollama_bin) || return 0
  "$ollama_bin" list 2>/dev/null | tail -n +2 | awk '{print $1}' || return 0
}

list_models_action() {
  available_models=$(curated_models)
  installed_now=$(installed_models 2>/dev/null || printf '')
  printf '%s\n' "$available_models" | while IFS='|' read -r model description size_gb context_k; do
    [ -n "$model" ] || continue
    installed=0
    for current in $installed_now; do
      if [ "$current" = "$model" ]; then
        installed=1
        break
      fi
    done
    printf '%s|%s|%s|%s|%s\n' "$model" "$description" "$size_gb" "$context_k" "$installed"
  done
}

status_action() {
  wizardry_flag=0
  ollama_flag=0
  running_flag=0

  if wizardry_available; then
    wizardry_flag=1
  fi
  if ollama_installed; then
    ollama_flag=1
  fi
  if ollama_running; then
    running_flag=1
  fi

  printf 'wizardry_installed=%s\n' "$wizardry_flag"
  printf 'ollama_installed=%s\n' "$ollama_flag"
  printf 'ollama_running=%s\n' "$running_flag"
}

install_ollama_action() {
  ensure_wizardry
  "$ai_dev_dir/install-ollama"
  start_ollama_session
  status_action
}

install_model_action() {
  model=${1-}
  [ -n "$model" ] || die "local-models-backend: MODEL is required"
  ensure_wizardry
  if ! ollama_installed; then
    die "local-models-backend: install Ollama before installing models"
  fi
  start_ollama_session
  "$ai_dev_dir/install-llm" "$model"
  list_models_action
}

remove_model_action() {
  model=${1-}
  [ -n "$model" ] || die "local-models-backend: MODEL is required"
  ensure_wizardry
  if ! ollama_installed; then
    die "local-models-backend: Ollama is not installed"
  fi
  start_ollama_session
  "$ai_dev_dir/uninstall-llm" "$model"
  list_models_action
}

action=${1-}
[ -n "$action" ] || die "local-models-backend: action required"
shift || true

case "$action" in
  status)
    status_action
    ;;
  list-models)
    list_models_action
    ;;
  install-wizardry)
    install_wizardry
    status_action
    ;;
  install-ollama)
    install_ollama_action
    ;;
  start-ollama)
    if ! ollama_installed; then
      die "local-models-backend: install Ollama before starting it"
    fi
    start_ollama_session
    status_action
    ;;
  install-model)
    install_model_action "$@"
    ;;
  remove-model)
    remove_model_action "$@"
    ;;
  *)
    die "local-models-backend: unknown action: $action"
    ;;
esac
