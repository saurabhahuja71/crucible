#!/usr/bin/env bash
# Cruks via Ollama local server.
# Usage:
#   cruks-ollama                    # interactive TUI (via OpenAI-compatible API)
#   cruks-ollama exec "list *.rb"   # headless one-shot
#
# Add to your bashrc/zshrc:
#   source /path/to/cruks/scripts/cruks-ollama.sh
#   alias cruks-s1='cruks-ollama'

_CRUKS_OLLAMA_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_cruks_ollama_run() {
  # When loaded from the user's shell, use the canonical S1 tunnel setup
  # before reading config so Ollama never falls back to bare localhost:11434.
  if declare -F _ollama1_ensure >/dev/null 2>&1; then
    _ollama1_ensure || return 1
  fi
  export CRUKS_ROOT="${CRUKS_ROOT:-$(cd "${_CRUKS_OLLAMA_SCRIPT_DIR}/.." && pwd)}"
  export CRUKS_OLLAMA_CFG="${CRUKS_OLLAMA_CFG:-${CRUKS_ROOT}/config/cruks.ollama.toml}"

  # Ollama default: http://localhost:11434, uses OpenAI-compatible API via ollama/openai endpoint
  local ollama_host="${OLLAMA_HOST:-http://localhost:11434}"
  
  # Create config if it doesn't exist (with sane defaults)
  if [ ! -f "$CRUKS_OLLAMA_CFG" ]; then
    cat > "$CRUKS_OLLAMA_CFG" <<'EOF'
# Cruks + Ollama local server
# Use with: cruks-s1

[workspace]
trust = true
auto_approve = false

[agent]
max_turns = 16
summarize_after_messages = 40
max_tokens = 4096
system_prompt = "You are Cruks, a precise coding agent. Use tools to inspect and verify work. For shell aliases such as podman9, use ssh_execute with the alias host after inspecting bashrc; never fall back to shell_execute SSH. After a tool failure, do not repeat the same command; diagnose the exact error and make one evidence-based correction. For a request to start Podman containers on podman9, run one ssh_execute call with sudo podman ps -a --format first; if every container is Up, report that no start action is needed and do not inspect systemd units. Use add_todo, complete_todo, update_todo, and list_todos for multi-step work."

[providers]
primary = "ollama"
failover = []

[providers.ollama]
type = "openai_compatible"
api_key = ""
base_url = "${OLLAMA_HOST:-http://localhost:11434}/v1"
model = "darwin-35b-a3b-opus:q4_k_m"  # S1 canonical model; launcher overrides this when configured
temperature = 0.2
max_tokens = 4096
timeout = 300

[safety]
sandbox_shell = true
confirm_destructive = true

[ssh]
config_path = "~/.config/cruks/ssh_hosts.toml"
default_timeout = 30

[parallel]
max_workers = 4

[logging]
level = "warn"
audit_path = "~/.local/share/cruks/audit.log"

[mcp]
servers = []
EOF
    # Replace ${OLLAMA_HOST} placeholder with actual value
    sed -i "s|\\\${OLLAMA_HOST:-http://localhost:11434}|${ollama_host}|g" "$CRUKS_OLLAMA_CFG"
    echo "Created Ollama config at $CRUKS_OLLAMA_CFG"
  fi

  cd "${CRUKS_ROOT}"

  # Build launch command
  local -a launch
  if [ -f "${CRUKS_ROOT}/Gemfile" ]; then
    launch=(bundle exec ruby exe/cruks)
  elif command -v cruks >/dev/null 2>&1; then
    launch=(cruks)
  else
    echo "cruks not found. Build: cd ${CRUKS_ROOT} && bundle install" >&2
    return 1
  fi

  # Match the canonical S1 wrappers (forge-s1/pi-s1): _ollama1_ensure sets
  # OLLAMA1_MODEL to Darwin-35B. Do not let a stale generated config switch
  # Cruks back to an unrelated Qwen model.
  local model_id="${CRUKS_OLLAMA_MODEL:-${OLLAMA1_MODEL:-}}"
  if [ -z "$model_id" ] && grep -q "^model = " "$CRUKS_OLLAMA_CFG"; then
    model_id=$(grep "^model = " "$CRUKS_OLLAMA_CFG" | cut -d'"' -f2)
  fi
  model_id="${model_id:-darwin-35b-a3b-opus:q4_k_m}"

  echo "cruks-ollama: base=${ollama_host}/v1 model=${model_id} cfg=${CRUKS_OLLAMA_CFG}"

  env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
    -u ALL_PROXY -u all_proxy \
    no_proxy="localhost,127.0.0.1" \
    NO_PROXY="localhost,127.0.0.1" \
    "${launch[@]}" \
      --config "$CRUKS_OLLAMA_CFG" \
      --model "$model_id" \
      --trust \
      "$@"
}

# If sourced from a different file (like bashrc), create shell functions. Do
# not install an alias to a function name that does not exist: aliases expand
# before function dispatch and made cruks-s1 report command-not-found.
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  cruks-ollama() { _cruks_ollama_run "$@"; }
  cruks-s1() { _cruks_ollama_run "$@"; }
else
  # If called directly, run the command
  _cruks_ollama_run "$@"
fi
