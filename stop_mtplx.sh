#!/usr/bin/env bash
set -euo pipefail

PORT=8000
PID_FILE="/Users/mac/pi/logs/mtplx.pid"

echo " [MTPLX] Stopping MTPLX server..."

if [ -f "${PID_FILE}" ]; then
    PID=$(cat "${PID_FILE}")
    if kill -0 "${PID}" 2>/dev/null; then
        kill "${PID}" 2>/dev/null || true
        sleep 1
        kill -9 "${PID}" 2>/dev/null || true
    fi
    rm -f "${PID_FILE}"
fi

if lsof -i :${PORT} >/dev/null 2>&1; then
    PIDS=$(lsof -t -i :${PORT})
    echo " [MTPLX] Killing processes on port ${PORT}: ${PIDS}"
    kill -9 ${PIDS} 2>/dev/null || true
fi

pkill -f "mtplx --model" 2>/dev/null || true

echo " [MTPLX] Server stopped successfully."
