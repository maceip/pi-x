#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
export PI_X_ROOT="${SCRIPT_DIR}"
[[ -f "${SCRIPT_DIR}/config.env" ]] && source "${SCRIPT_DIR}/config.env"

PORT="${MTPLX_PORT:-8000}"
HOST="${MTPLX_HOST:-127.0.0.1}"
PID_FILE="${SCRIPT_DIR}/logs/mtplx.pid"
LOCK_FILE="${SCRIPT_DIR}/logs/agent.lock"
mkdir -p "${SCRIPT_DIR}/logs"

case "${1:-}" in
    -h|--help)
        cat <<EOF
pi-x - High-Performance Pi Coding Agent for Apple Silicon & MTPLX
Usage: ./run_agent.sh [options] [-- <pi-options>]
Options:
  -c, --continue   Continue latest session
  -r, --resume     Interactive session picker
  --clean          Prune past session history in .pi/sessions
  --status         Show server/agent status & PID
  --restart        Restart background server
  --stop           Stop background server
  --no-skills      Launch without skills
  -h, --help       Show help
EOF
        exit 0 ;;
    --status)
        echo "=== pi-x System Status ==="
        if curl -s "http://${HOST}:${PORT}/v1/models" 2>/dev/null | grep -qi "mtplx"; then
            echo "  Server:   ONLINE (http://${HOST}:${PORT}/v1)"; [[ -f "${PID_FILE}" ]] && echo "  PID:      $(cat "${PID_FILE}")"
        else echo "  Server:   OFFLINE"; fi
        if [[ -f "${LOCK_FILE}" ]] && kill -0 "$(cat "${LOCK_FILE}" 2>/dev/null)" 2>/dev/null; then
            echo "  Agent:    ACTIVE (PID $(cat "${LOCK_FILE}"))"
        else echo "  Agent:    IDLE" && rm -f "${LOCK_FILE}"; fi
        exit 0 ;;
    --stop)    "${SCRIPT_DIR}/stop_mtplx.sh"; exit 0 ;;
    --restart) "${SCRIPT_DIR}/stop_mtplx.sh" || true; "${SCRIPT_DIR}/start_mtplx.sh"; exit 0 ;;
    --clean)
        sessions="${SCRIPT_DIR}/.pi/sessions"
        if [[ -d "$sessions" ]] && (( $(find "$sessions" -name "*.json" 2>/dev/null | wc -l) > 0 )); then
            read -r -p " [pi-x] Delete all past session history? [y/N] " r
            [[ "$r" =~ ^[Yy]$ ]] && rm -rf "${sessions:?}"/* && echo " [pi-x] Sessions pruned."
        else echo " [pi-x] No session history found."; fi
        exit 0 ;;
esac

source "${SCRIPT_DIR}/lib/preflight.sh"
pi_x_preflight

if ! curl -s "http://${HOST}:${PORT}/v1/models" 2>/dev/null | grep -qi "mtplx"; then
    echo " [Pi Launcher] Starting background MTPLX server..."; "${SCRIPT_DIR}/start_mtplx.sh"
fi

if [[ -f "${LOCK_FILE}" ]]; then
    old_pid="$(cat "${LOCK_FILE}" 2>/dev/null || true)"
    [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null && echo " [Pi Launcher] Notice: Another session active (PID ${old_pid})."
fi
echo "$$" > "${LOCK_FILE}"
trap 'rm -f "${LOCK_FILE}"' EXIT INT TERM

echo " [Pi Launcher] Launching Pi Coding Agent with MTPLX..."
echo " [Pi Launcher] Model: ${MODEL_PATH} | Thinking: ${PI_THINKING:-off}"

exec "${SCRIPT_DIR}/pi" \
    --provider mtplx \
    --model "${PI_MODEL:-mtplx-flash-next-optimized-speed}" \
    --thinking "${PI_THINKING:-off}" \
    --tui-mode "${PI_TUI_MODE:-fullscreen}" \
    "$@"
