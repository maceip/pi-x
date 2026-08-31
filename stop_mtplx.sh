#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "${SCRIPT_DIR}/config.env" ]] && source "${SCRIPT_DIR}/config.env"
PORT="${MTPLX_PORT:-8000}"
PID_FILE="${SCRIPT_DIR}/logs/mtplx.pid"

echo " [MTPLX] Stopping MTPLX server..."
if [[ -f "${PID_FILE}" ]]; then
    PID="$(cat "${PID_FILE}" 2>/dev/null || echo "")"
    if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null || true; sleep 1; kill -9 "$PID" 2>/dev/null || true
    fi
    rm -f "${PID_FILE}"
fi

if command -v lsof >/dev/null 2>&1 && lsof -i ":${PORT}" >/dev/null 2>&1; then
    OCCUPIER_PID="$(lsof -t -i ":${PORT}" | head -n 1)"
    if [[ -n "$OCCUPIER_PID" ]] && ps -p "$OCCUPIER_PID" -o comm= 2>/dev/null | grep -qiE "mtplx|python"; then
        kill -9 "$OCCUPIER_PID" 2>/dev/null || true
    fi
fi

pkill -f "mtplx serve" 2>/dev/null || true
echo " [MTPLX] Server stopped successfully."
