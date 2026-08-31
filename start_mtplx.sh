#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PI_X_ROOT="${SCRIPT_DIR}"

[[ -f "${SCRIPT_DIR}/config.env" ]] && source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/lib/preflight.sh"
[[ -z "${MODEL_PATH:-}" || -z "${MTPLX_BIN:-}" ]] && pi_x_preflight

PORT="${MTPLX_PORT:-8000}"
HOST="${MTPLX_HOST:-127.0.0.1}"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/mtplx.log"
PID_FILE="${LOG_DIR}/mtplx.pid"
MAX_LOG_MB="${PI_MAX_LOG_SIZE_MB:-50}"

mkdir -p "${LOG_DIR}"

# 1. Rotate logs if exceeding MAX_LOG_MB
if [[ -f "${LOG_FILE}" ]]; then
    size_bytes=$(stat -f%z "${LOG_FILE}" 2>/dev/null || stat -c%s "${LOG_FILE}" 2>/dev/null || echo 0)
    if (( size_bytes > MAX_LOG_MB * 1024 * 1024 )); then
        echo " [MTPLX] Rotating log file (> ${MAX_LOG_MB}MB)..."
        mv -f "${LOG_FILE}.1" "${LOG_FILE}.2" 2>/dev/null || true
        mv -f "${LOG_FILE}" "${LOG_FILE}.1" 2>/dev/null || true
        touch "${LOG_FILE}"
    fi
fi

# 2. Check if MTPLX is already healthy on target port
if curl -s "http://${HOST}:${PORT}/v1/models" 2>/dev/null | grep -qi "mtplx"; then
    echo " [MTPLX] Server is already running and healthy on http://${HOST}:${PORT}"
    exit 0
fi

# 3. Safe Port Conflict & Stale PID Resolution
if command -v lsof >/dev/null 2>&1 && lsof -i ":${PORT}" >/dev/null 2>&1; then
    OCCUPIER_PID="$(lsof -t -i ":${PORT}" | head -n 1)"
    SAVED_PID="$(cat "${PID_FILE}" 2>/dev/null || echo "")"

    # Check if the process occupying the port is an mtplx process
    if [[ "$OCCUPIER_PID" == "$SAVED_PID" ]] || ps -p "$OCCUPIER_PID" -o comm= 2>/dev/null | grep -qiE "mtplx|python"; then
        echo " [MTPLX] Cleaning up previous MTPLX process (PID ${OCCUPIER_PID}) on port ${PORT}..."
        kill -9 "$OCCUPIER_PID" 2>/dev/null || true
        sleep 1
    else
        # Port is occupied by an unrelated user process (e.g. Vite, Ollama). Find next available port.
        ORIG_PORT="$PORT"
        while command -v lsof >/dev/null 2>&1 && lsof -i ":${PORT}" >/dev/null 2>&1; do
            PORT=$((PORT + 1))
        done
        echo " [MTPLX] Notice: Port ${ORIG_PORT} is in use by another application. Binding to port ${PORT} instead."
        export MTPLX_PORT="$PORT"
    fi
fi

# Clean stale PID file if process no longer exists
if [[ -f "${PID_FILE}" ]]; then
    OLD_PID="$(cat "${PID_FILE}" 2>/dev/null || echo "")"
    if [[ -n "$OLD_PID" ]] && ! kill -0 "$OLD_PID" 2>/dev/null; then
        rm -f "${PID_FILE}"
    fi
fi

echo " [MTPLX] Launching ${MTPLX_MODEL_ID:-mtplx-flash-next-optimized-speed} on port ${PORT}..."
echo " [MTPLX] Context: ${MTPLX_CONTEXT_WINDOW:-65536} tok | MTP Depth: ${MTPLX_MTP_DEPTH:-3} | SSD Cache: ${MTPLX_SSD_SESSION_CACHE:-off}"

if [[ "${MTPLX_SOURCE:-}" == "python-module" ]]; then
    set -- python3 -m mtplx serve
else
    set -- "${MTPLX_BIN}" serve
fi

nohup "$@" \
    --model "${MODEL_PATH}" \
    --model-id "${MTPLX_MODEL_ID:-mtplx-flash-next-optimized-speed}" \
    --host "${HOST}" \
    --port "${PORT}" \
    --context-window "${MTPLX_CONTEXT_WINDOW:-65536}" \
    --profile "${MTPLX_PROFILE:-turbo}" \
    --depth "${MTPLX_MTP_DEPTH:-3}" \
    --reasoning "${MTPLX_REASONING:-on}" \
    --reasoning-parser "${MTPLX_REASONING_PARSER:-qwen3}" \
    --reasoning-effort "${MTPLX_REASONING_EFFORT:-high}" \
    --ssd-session-cache "${MTPLX_SSD_SESSION_CACHE:-off}" \
    --ssd-session-cache-min-prefix-tokens "${MTPLX_SSD_MIN_PREFIX_TOKENS:-512}" \
    --no-auth \
    --unsafe-force-unverified \
    --yes \
    </dev/null > "${LOG_FILE}" 2>&1 &

SERVER_PID=$!
disown ${SERVER_PID} 2>/dev/null || true
echo "${SERVER_PID}" > "${PID_FILE}"
echo " [MTPLX] Server started (PID ${SERVER_PID}). Waiting for health check..."

COUNT=0
until curl -s "http://${HOST}:${PORT}/health" >/dev/null 2>&1 || curl -s "http://${HOST}:${PORT}/v1/models" >/dev/null 2>&1; do
    sleep 1
    COUNT=$((COUNT + 1))
    if (( COUNT >= 45 )) || ! kill -0 "${SERVER_PID}" 2>/dev/null; then
        echo " [MTPLX] ERROR: Server failed to start. Last log lines:"
        tail -n 20 "${LOG_FILE}"
        exit 1
    fi
done

echo " [MTPLX] Server is ONLINE and READY at http://${HOST}:${PORT}/v1"
