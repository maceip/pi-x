#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${MTPLX_PORT:-8000}"
PID_FILE="${SCRIPT_DIR}/logs/mtplx.pid"

echo " [MTPLX] Stopping MTPLX server..."

if [ -f "${PID_FILE}" ]; then
    PID="$(cat "${PID_FILE}")"
    if kill -0 "${PID}" 2>/dev/null; then
        kill "${PID}" 2>/dev/null || true
        sleep 1
        kill -9 "${PID}" 2>/dev/null || true
    fi
    rm -f "${PID_FILE}"
fi

if command -v lsof >/dev/null 2>&1 && lsof -i ":${PORT}" >/dev/null 2>&1; then
    PIDS="$(lsof -t -i ":${PORT}")"
    echo " [MTPLX] Killing processes on port ${PORT}: ${PIDS}"
    kill -9 ${PIDS} 2>/dev/null || true
fi

pkill -f "mtplx serve" 2>/dev/null || true
pkill -f "mtplx --model" 2>/dev/null || true

echo " [MTPLX] Server stopped successfully."
