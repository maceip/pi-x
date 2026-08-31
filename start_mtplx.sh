#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "${SCRIPT_DIR}/config.env" ]] && source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/lib/preflight.sh"
[[ -z "${MODEL_PATH:-}" || -z "${MTPLX_BIN:-}" ]] && pi_x_preflight

PORT="${MTPLX_PORT:-8000}"
HOST="${MTPLX_HOST:-127.0.0.1}"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/mtplx.log"
PID_FILE="${LOG_DIR}/mtplx.pid"
mkdir -p "${LOG_DIR}"

# 1. Rotate logs if exceeding threshold
if [[ -f "${LOG_FILE}" ]]; then
    size=$(stat -f%z "${LOG_FILE}" 2>/dev/null || stat -c%s "${LOG_FILE}" 2>/dev/null || echo 0)
    if (( size > ${PI_MAX_LOG_SIZE_MB:-50} * 1048576 )); then
        echo " [MTPLX] Rotating log file (> ${PI_MAX_LOG_SIZE_MB:-50}MB)..."
        mv -f "${LOG_FILE}.1" "${LOG_FILE}.2" 2>/dev/null || true
        mv -f "${LOG_FILE}" "${LOG_FILE}.1" 2>/dev/null || true
        touch "${LOG_FILE}"
    fi
fi

# 2. Check if already healthy
if curl -s "http://${HOST}:${PORT}/v1/models" 2>/dev/null | grep -qi "mtplx"; then
    echo " [MTPLX] Server is already running and healthy on http://${HOST}:${PORT}"; exit 0
fi

# 3. Safe port resolution & stale PID cleanup
if command -v lsof >/dev/null 2>&1 && lsof -i ":${PORT}" >/dev/null 2>&1; then
    OCCUPIER_PID="$(lsof -t -i ":${PORT}" | head -n 1)"
    SAVED_PID="$(cat "${PID_FILE}" 2>/dev/null || echo "")"
    if [[ "$OCCUPIER_PID" == "$SAVED_PID" ]] || ps -p "$OCCUPIER_PID" -o comm= 2>/dev/null | grep -qiE "mtplx|python"; then
        echo " [MTPLX] Cleaning up previous MTPLX (PID ${OCCUPIER_PID}) on port ${PORT}..."
        kill -9 "$OCCUPIER_PID" 2>/dev/null || true; sleep 1
    else
        ORIG_PORT="$PORT"
        while command -v lsof >/dev/null 2>&1 && lsof -i ":${PORT}" >/dev/null 2>&1; do PORT=$((PORT + 1)); done
        echo " [MTPLX] Port ${ORIG_PORT} busy; binding to port ${PORT} instead."
        export MTPLX_PORT="$PORT"
    fi
fi
[[ -f "${PID_FILE}" ]] && ! kill -0 "$(cat "${PID_FILE}" 2>/dev/null)" 2>/dev/null && rm -f "${PID_FILE}"

echo " [MTPLX] Launching ${MTPLX_MODEL_ID:-mtplx-flash-next-optimized-speed} on port ${PORT} (Ctx: ${MTPLX_CONTEXT_WINDOW:-65536})..."
CMD=("${MTPLX_BIN}" serve)
[[ "${MTPLX_SOURCE:-}" == "python-module" ]] && CMD=(python3 -m mtplx serve)

nohup "${CMD[@]}" \
    --model "${MODEL_PATH}" \
    --model-id "${MTPLX_MODEL_ID:-mtplx-flash-next-optimized-speed}" \
    --host "${HOST}" --port "${PORT}" \
    --context-window "${MTPLX_CONTEXT_WINDOW:-65536}" \
    --profile "${MTPLX_PROFILE:-turbo}" \
    --depth "${MTPLX_MTP_DEPTH:-3}" \
    --reasoning "${MTPLX_REASONING:-off}" \
    --reasoning-parser "${MTPLX_REASONING_PARSER:-qwen3}" \
    --reasoning-effort "${MTPLX_REASONING_EFFORT:-low}" \
    --ssd-session-cache "${MTPLX_SSD_SESSION_CACHE:-on}" \
    --ssd-session-cache-min-prefix-tokens "${MTPLX_SSD_MIN_PREFIX_TOKENS:-512}" \
    --no-auth --unsafe-force-unverified --yes \
    </dev/null > "${LOG_FILE}" 2>&1 &

SERVER_PID=$!
disown ${SERVER_PID} 2>/dev/null || true
echo "${SERVER_PID}" > "${PID_FILE}"
echo " [MTPLX] Server started (PID ${SERVER_PID}). Waiting for health check..."

COUNT=0
until curl -s "http://${HOST}:${PORT}/health" >/dev/null 2>&1 || curl -s "http://${HOST}:${PORT}/v1/models" >/dev/null 2>&1; do
    sleep 1; COUNT=$((COUNT + 1))
    if (( COUNT >= 45 )) || ! kill -0 "${SERVER_PID}" 2>/dev/null; then
        echo " [MTPLX] ERROR: Server failed to start. Last log lines:"; tail -n 20 "${LOG_FILE}"; exit 1
    fi
done

echo " [MTPLX] Server is ONLINE and READY at http://${HOST}:${PORT}/v1"
