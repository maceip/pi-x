#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
export PI_X_ROOT="${SCRIPT_DIR}"

# 0. Discover RAM / mtplx / model (prompts on /dev/tty so curl|bash works)
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight.sh"
pi_x_preflight

# 1. Ensure MTPLX server is running against the discovered model
if ! curl -s "http://127.0.0.1:8000/health" >/dev/null 2>&1 && ! curl -s "http://127.0.0.1:8000/v1/models" >/dev/null 2>&1; then
    echo " [Pi Launcher] MTPLX server is not running. Starting it now..."
    "${SCRIPT_DIR}/start_mtplx.sh"
else
    echo " [Pi Launcher] MTPLX server is active on http://127.0.0.1:8000/v1"
fi

# 2. Launch Pi Agent in Interactive TUI Mode
echo " [Pi Launcher] Launching Pi Coding Agent with MTPLX..."
echo " [Pi Launcher] Model path: ${MODEL_PATH}"
echo " [Pi Launcher] Thinking: high | Single-row shaded status bar active"

exec "${SCRIPT_DIR}/pi" \
    --provider mtplx \
    --model mtplx-flash-next-optimized-speed \
    --thinking high \
    --tui-mode fullscreen \
    "$@"
