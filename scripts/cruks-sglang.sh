#!/usr/bin/env bash
# Cruks (Ruby Forge agent) via SGLang local tunnel (:30000).
# Usage:
#   cruks-sglang                    # interactive TUI
#   cruks-sglang exec "list *.rb"   # headless one-shot
#   cruks-s                         # alias (add to bashrc)
#
# Env:
#   CRUKS_ROOT         repo path (auto-detected from script location)
#   CRUKS_SGLANG_CFG   config file (default: $CRUKS_ROOT/config/cruks.sglang.toml)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CRUKS_ROOT="${CRUKS_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
export CRUKS_SGLANG_CFG="${CRUKS_SGLANG_CFG:-${CRUKS_ROOT}/config/cruks.sglang.toml}"

if [ -f "${HOME}/.sglang-tunnel.bash" ]; then
  # shellcheck disable=SC1091
  source "${HOME}/.sglang-tunnel.bash"
elif ! declare -F _sglang_ensure_api >/dev/null 2>&1; then
  echo "SGLang helpers not found. Install ~/.sglang-tunnel.bash or run: sglang-up" >&2
  exit 1
fi

_sglang_ensure_api || exit 1
export SGLANG_HOST="http://127.0.0.1:${SGLANG_TUNNEL_LOCAL_PORT:-30000}"

model_id=$(_sglang_model_id)
model_id=$(basename "${model_id}")

if [ ! -f "$CRUKS_SGLANG_CFG" ]; then
  echo "cruks sglang config not found: $CRUKS_SGLANG_CFG" >&2
  exit 1
fi

echo "cruks-sglang: base=${SGLANG_HOST}/v1 model=${model_id} cfg=${CRUKS_SGLANG_CFG}"

cd "${CRUKS_ROOT}"

if [ -f "${CRUKS_ROOT}/Gemfile" ]; then
  CRUKS_LAUNCH=(bundle exec ruby exe/forge)
elif command -v forge >/dev/null 2>&1; then
  CRUKS_LAUNCH=(forge)
else
  echo "cruks/forge not found. Build: cd ${CRUKS_ROOT} && bundle install" >&2
  exit 1
fi

exec env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
  -u ALL_PROXY -u all_proxy \
  OPENAI_API_KEY=sglang \
  OPENAI_BASE_URL="${SGLANG_HOST}/v1" \
  OPENAI_API_BASE="${SGLANG_HOST}/v1" \
  no_proxy="localhost,127.0.0.1" \
  NO_PROXY="localhost,127.0.0.1" \
  "${CRUKS_LAUNCH[@]}" \
    --config "$CRUKS_SGLANG_CFG" \
    --model "$model_id" \
    --trust \
    "$@"
