#!/usr/bin/env bash
# Cruks via SGLang local tunnel (:30000).
# Usage:
#   cruks-sglang                    # interactive TUI
#   cruks-sglang exec "list *.rb"   # headless one-shot
#
# Bashrc (like pi-s / forge-s):
#   source /path/to/cruks/scripts/cruks-sglang.sh
#   alias cruks-s='cruks-sglang'
set -euo pipefail

_CRUKS_SGLANG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_cruks_sglang_run() {
  export CRUKS_ROOT="${CRUKS_ROOT:-$(cd "${_CRUKS_SGLANG_SCRIPT_DIR}/.." && pwd)}"
  export CRUKS_SGLANG_CFG="${CRUKS_SGLANG_CFG:-${CRUKS_ROOT}/config/cruks.sglang.toml}"
  export CRUKS_DATA_DIR="${CRUKS_DATA_DIR:-${TMPDIR:-/tmp}/cruks-runtime}"
  mkdir -p "${CRUKS_DATA_DIR}" || return 1
  export CRUKS_AUDIT_PATH="${CRUKS_AUDIT_PATH:-${CRUKS_DATA_DIR}/audit.log}"

  if [ -f "${HOME}/.sglang-tunnel.bash" ]; then
    # shellcheck disable=SC1091
    source "${HOME}/.sglang-tunnel.bash"
  elif ! declare -F _sglang_ensure_api >/dev/null 2>&1; then
    echo "SGLang helpers not found. Install ~/.sglang-tunnel.bash or run: sglang-up" >&2
    return 1
  fi

  if [[ "${CRUKS_DEBUG:-}" == "1" ]]; then _sglang_ensure_api || return 1; else _sglang_ensure_api >/dev/null 2>&1 || return 1; fi
  export SGLANG_HOST="http://127.0.0.1:${SGLANG_TUNNEL_LOCAL_PORT:-30000}"

  local model_id
  model_id=$(_sglang_model_id)
  model_id=$(basename "${model_id}")

  if [ ! -f "$CRUKS_SGLANG_CFG" ]; then
    echo "cruks sglang config not found: $CRUKS_SGLANG_CFG" >&2
    return 1
  fi

  [[ "${CRUKS_DEBUG:-}" == "1" ]] && echo "cruks-sglang: base=${SGLANG_HOST}/v1 model=${model_id} cfg=${CRUKS_SGLANG_CFG}"

  cd "${CRUKS_ROOT}"

  local -a launch
  if [ -f "${CRUKS_ROOT}/Gemfile" ]; then
    launch=(bundle exec ruby exe/cruks)
  elif command -v cruks >/dev/null 2>&1; then
    launch=(cruks)
  else
    echo "cruks not found. Build: cd ${CRUKS_ROOT} && bundle install" >&2
    return 1
  fi

  env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
    -u ALL_PROXY -u all_proxy \
    OPENAI_API_KEY=sglang \
    OPENAI_BASE_URL="${SGLANG_HOST}/v1" \
    OPENAI_API_BASE="${SGLANG_HOST}/v1" \
    no_proxy="localhost,127.0.0.1" \
    NO_PROXY="localhost,127.0.0.1" \
    CRUKS_DATA_DIR="${CRUKS_DATA_DIR}" \
    CRUKS_AUDIT_PATH="${CRUKS_AUDIT_PATH}" \
    "${launch[@]}" \
      --config "$CRUKS_SGLANG_CFG" \
      --model "$model_id" \
      --trust \
      "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _cruks_sglang_run "$@"
else
  cruks-sglang() { _cruks_sglang_run "$@"; }
  alias cruks-s='cruks-sglang'
fi
