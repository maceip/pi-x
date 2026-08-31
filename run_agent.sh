#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
export PI_X_ROOT="${SCRIPT_DIR}"

# 1. Load Unified Configuration
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/config.env"
fi

# 2. Parse Launcher Shortcut Flags
PORT="${MTPLX_PORT:-8000}"
HOST="${MTPLX_HOST:-127.0.0.1}"
PID_FILE="${SCRIPT_DIR}/logs/mtplx.pid"
LOCK_FILE="${SCRIPT_DIR}/logs/agent.lock"
mkdir -p "${SCRIPT_DIR}/logs"

show_help() {
    cat <<EOF
pi-x - High-Performance Pi Coding Agent for Apple Silicon & MTPLX

Usage:
  ./run_agent.sh [options] [-- <pi-options>]

Options:
  -c, --continue       Continue the most recent conversation session
  -r, --resume         Open interactive session history picker
  --clean              Prune old conversation session files in .pi/sessions
  --status             Show status of MTPLX server, active model, and memory
  --stop               Stop the background MTPLX server
  --restart            Restart the MTPLX background server
  --no-skills          Run agent without loading skills
  -h, --help           Show this help message

Environment overrides can be set in config.env or exported directly.
EOF
}

show_status() {
    echo "=== pi-x System Status ==="
    if curl -s "http://${HOST}:${PORT}/health" >/dev/null 2>&1 || curl -s "http://${HOST}:${PORT}/v1/models" >/dev/null 2>&1; then
        echo "  Server:   ONLINE (http://${HOST}:${PORT}/v1)"
        if [[ -f "${PID_FILE}" ]]; then
            echo "  PID:      $(cat "${PID_FILE}")"
        fi
        local models
        models="$(curl -s "http://${HOST}:${PORT}/v1/models" 2>/dev/null || true)"
        echo "  Endpoint: ${models}"
    else
        echo "  Server:   OFFLINE"
    fi
    if [[ -f "${LOCK_FILE}" ]]; then
        local lock_pid
        lock_pid="$(cat "${LOCK_FILE}" 2>/dev/null || echo "")"
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            echo "  Agent:    ACTIVE (PID ${lock_pid})"
        else
            echo "  Agent:    IDLE (stale lock cleaned)"
            rm -f "${LOCK_FILE}"
        fi
    else
        echo "  Agent:    IDLE"
    fi
    echo "  Config:   ${SCRIPT_DIR}/config.env"
}

clean_sessions() {
    local session_dir="${SCRIPT_DIR}/.pi/sessions"
    if [[ -d "${session_dir}" ]]; then
        local count
        count="$(find "${session_dir}" -name "*.json" 2>/dev/null | wc -l | xargs)"
        if (( count > 0 )); then
            echo " [pi-x] Found ${count} past session file(s) in ${session_dir}."
            read -r -p " [pi-x] Delete all past session history? [y/N] " reply
            if [[ "$reply" =~ ^[Yy]$ ]]; then
                rm -rf "${session_dir:?}"/*
                echo " [pi-x] Sessions pruned successfully."
            else
                echo " [pi-x] Pruning cancelled."
            fi
        else
            echo " [pi-x] No session files found to clean."
        fi
    else
        echo " [pi-x] No session directory found."
    fi
}

# Handle standalone actions
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    --status)
        show_status
        exit 0
        ;;
    --stop)
        "${SCRIPT_DIR}/stop_mtplx.sh"
        exit 0
        ;;
    --restart)
        "${SCRIPT_DIR}/stop_mtplx.sh" || true
        "${SCRIPT_DIR}/start_mtplx.sh"
        exit 0
        ;;
    --clean)
        clean_sessions
        exit 0
        ;;
esac

# 3. Discover RAM / mtplx / model
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight.sh"
pi_x_preflight

# 4. Ensure MTPLX server is running against discovered model
if ! curl -s "http://${HOST}:${PORT}/health" >/dev/null 2>&1 && ! curl -s "http://${HOST}:${PORT}/v1/models" >/dev/null 2>&1; then
    echo " [Pi Launcher] MTPLX server is not running. Starting it now..."
    "${SCRIPT_DIR}/start_mtplx.sh"
else
    echo " [Pi Launcher] MTPLX server is active on http://${HOST}:${PORT}/v1"
fi

# 5. Single-Instance Agent Lock
if [[ -f "${LOCK_FILE}" ]]; then
    EXISTING_PID="$(cat "${LOCK_FILE}" 2>/dev/null || true)"
    if [[ -n "${EXISTING_PID}" ]] && kill -0 "${EXISTING_PID}" 2>/dev/null; then
        echo " [Pi Launcher] Notice: Another active Pi Agent session detected (PID ${EXISTING_PID})."
        echo " [Pi Launcher] Starting in parallel session. Press Ctrl+C within 2s to abort if unintentional..."
        sleep 2 || true
    fi
fi
echo "$$" > "${LOCK_FILE}"
trap 'rm -f "${LOCK_FILE}"' EXIT INT TERM

# 6. Launch Pi Agent in Interactive TUI Mode
PI_MODEL="${PI_MODEL:-mtplx-flash-next-optimized-speed}"
PI_THINKING="${PI_THINKING:-high}"
PI_TUI_MODE="${PI_TUI_MODE:-fullscreen}"

echo " [Pi Launcher] Launching Pi Coding Agent with MTPLX..."
echo " [Pi Launcher] Model path: ${MODEL_PATH}"
echo " [Pi Launcher] Thinking: ${PI_THINKING} | TUI Mode: ${PI_TUI_MODE} | Single-row status rail active"

exec "${SCRIPT_DIR}/pi" \
    --provider mtplx \
    --model "${PI_MODEL}" \
    --thinking "${PI_THINKING}" \
    --tui-mode "${PI_TUI_MODE}" \
    "$@"
