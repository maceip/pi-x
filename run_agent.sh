#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# 1. Ensure MTPLX Server is Running
if ! curl -s "http://127.0.0.1:8000/health" >/dev/null 2>&1 && ! curl -s "http://127.0.0.1:8000/v1/models" >/dev/null 2>&1; then
    echo " [Pi Launcher] MTPLX server is not running. Starting it now..."
    "${SCRIPT_DIR}/start_mtplx.sh"
else
    echo " [Pi Launcher] MTPLX server is active on http://127.0.0.1:8000/v1"
fi

# 2. Setup Node environment
export PATH="/Users/mac/.nvm/versions/node/v24.15.0/bin:${PATH}"

# 3. Launch Pi Agent in Interactive TUI Mode
echo " [Pi Launcher] Launching Pi Coding Agent with MTPLX Fast Model..."
echo " [Pi Launcher] Model: mtplx-flash-next-optimized-speed (Context: 65,536 tokens)"
echo " [Pi Launcher] Thinking: high | Single-row shaded status bar active"

exec "${SCRIPT_DIR}/pi" \
    --provider mtplx \
    --model mtplx-flash-next-optimized-speed \
    --thinking high \
    --tui-mode fullscreen \
    "$@"
