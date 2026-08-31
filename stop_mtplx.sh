#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "${SCRIPT_DIR}/config.env" ]] && source "${SCRIPT_DIR}/config.env"

PORT="${MTPLX_PORT:-8000}"
PID_FILE="${SCRIPT_DIR}/logs/mtplx.pid"

echo " [MTPLX] Stopping server on port ${PORT}..."
[[ -f "${PID_FILE}" ]] && { kill -9 "$(cat "${PID_FILE}")" 2>/dev/null || true; rm -f "${PID_FILE}"; }
command -v lsof >/dev/null 2>&1 && lsof -i ":${PORT}" >/dev/null 2>&1 && kill -9 $(lsof -t -i ":${PORT}") 2>/dev/null || true
pkill -f "mtplx serve" 2>/dev/null || true
echo " [MTPLX] Server stopped successfully."
