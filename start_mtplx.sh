#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PI_X_ROOT="${SCRIPT_DIR}"

# 1. Load Unified Configuration
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/config.env"
fi

# 2. Run Preflight Discovery
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight.sh"
if [[ -z "${MODEL_PATH:-}" || -z "${MTPLX_BIN:-}" ]]; then
    pi_x_preflight
fi

PORT="${MTPLX_PORT:-8000}"
HOST="${MTPLX_HOST:-127.0.0.1}"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/mtplx.log"
PID_FILE="${LOG_DIR}/mtplx.pid"
MAX_LOG_MB="${PI_MAX_LOG_SIZE_MB:-50}"

mkdir -p "${LOG_DIR}"

# Automated Log Rotation: Rotate log if larger than MAX_LOG_MB or if previous session log exists
rotate_logs() {
    if [[ -f "${LOG_FILE}" ]]; then
        local size_bytes=0
        if [[ "$(uname -s)" == "Darwin" ]]; then
            size_bytes="$(stat -f%z "${LOG_FILE}" 2>/dev/null || echo 0)"
        else
            size_bytes="$(stat -c%s "${LOG_FILE}" 2>/dev/null || echo 0)"
        fi
        local max_bytes=$((MAX_LOG_MB * 1024 * 1024))
        if (( size_bytes > max_bytes )); then
            echo " [MTPLX] Log file exceeds ${MAX_LOG_MB}MB (${size_bytes} bytes). Rotating logs..."
            mv -f "${LOG_FILE}.1" "${LOG_FILE}.2" 2>/dev/null || true
            mv -f "${LOG_FILE}" "${LOG_FILE}.1" 2>/dev/null || true
            touch "${LOG_FILE}"
        fi
    fi
}
rotate_logs

if curl -s "http://${HOST}:${PORT}/health" >/dev/null 2>&1 || curl -s "http://${HOST}:${PORT}/v1/models" >/dev/null 2>&1; then
    echo " [MTPLX] Server is already running and healthy on http://${HOST}:${PORT}"
    exit 0
fi

if command -v lsof >/dev/null 2>&1 && lsof -i ":${PORT}" >/dev/null 2>&1; then
    echo " [MTPLX] Cleaning up previous process on port ${PORT}..."
    kill -9 $(lsof -t -i ":${PORT}") 2>/dev/null || true
    sleep 1
fi

echo " [MTPLX] Launching model on port ${PORT}..."
echo " [MTPLX] Binary: ${MTPLX_BIN} (${MTPLX_SOURCE}, v${MTPLX_VERSION:-unknown})"
echo " [MTPLX] Model: ${MODEL_PATH}"
echo " [MTPLX] Context Window: ${MTPLX_CONTEXT_WINDOW:-65536} tokens | MTP Depth: ${MTPLX_MTP_DEPTH:-3}"
echo " [MTPLX] SSD Cache: ${MTPLX_SSD_SESSION_CACHE:-off} | Reasoning: ${MTPLX_REASONING:-on} (${MTPLX_REASONING_EFFORT:-high})"

export MTPLX_QWEN4EXP_COMPILE="${MTPLX_QWEN4EXP_COMPILE:-1}"
export MTPLX_COMPILED_GDN="${MTPLX_COMPILED_GDN:-1}"
export MTPLX_AR_PIPELINE="${MTPLX_AR_PIPELINE:-1}"
export MTPLX_FUSED_GATE_UP="${MTPLX_FUSED_GATE_UP:-1}"
export MTPLX_FUSED_GDN_INPROJ="${MTPLX_FUSED_GDN_INPROJ:-1}"
export MTPLX_FUSED_GDN_CONVNORM="${MTPLX_FUSED_GDN_CONVNORM:-1}"
export MTPLX_FUSED_GDN_STEP="${MTPLX_FUSED_GDN_STEP:-1}"
export MTPLX_FUSED_HC_V3="${MTPLX_FUSED_HC_V3:-1}"
export MTPLX_FUSED_QSA_INDEXER="${MTPLX_FUSED_QSA_INDEXER:-1}"
export MTPLX_QSA_GATHER="${MTPLX_QSA_GATHER:-1}"
export MTPLX_QSA_PREFILL="${MTPLX_QSA_PREFILL:-1}"
export MTPLX_QSA_PREFILL_MIN_CONTEXT="${MTPLX_QSA_PREFILL_MIN_CONTEXT:-16384}"
export MTPLX_QSA_PREFILL_FLASH_MIN_CONTEXT="${MTPLX_QSA_PREFILL_FLASH_MIN_CONTEXT:-32768}"
export MTPLX_SYNC_AR="${MTPLX_SYNC_AR:-0}"
export MTPLX_NGRAM_RESIDENT="${MTPLX_NGRAM_RESIDENT:-0}"
export MTPLX_ENGINE_RAM_FRACTION="${MTPLX_ENGINE_RAM_FRACTION:-0.90}"
export MTPLX_ALLOW_OVERCOMMITTED="${MTPLX_ALLOW_OVERCOMMITTED:-1}"
export MTPLX_MTP_HISTORY_POLICY="${MTPLX_MTP_HISTORY_POLICY:-committed}"

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
echo " [MTPLX] Server started with PID ${SERVER_PID}. Waiting for health check..."

MAX_RETRIES=45
COUNT=0
until curl -s "http://${HOST}:${PORT}/health" >/dev/null 2>&1 || curl -s "http://${HOST}:${PORT}/v1/models" >/dev/null 2>&1; do
    sleep 1
    COUNT=$((COUNT + 1))
    if [ "${COUNT}" -ge "${MAX_RETRIES}" ]; then
        echo " [MTPLX] ERROR: Server failed to start within ${MAX_RETRIES} seconds."
        echo " [MTPLX] Last 20 lines of log:"
        tail -n 20 "${LOG_FILE}"
        exit 1
    fi
    if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
        echo " [MTPLX] ERROR: Server process exited unexpectedly."
        tail -n 20 "${LOG_FILE}"
        exit 1
    fi
done

echo " [MTPLX] Server is ONLINE and READY at http://${HOST}:${PORT}/v1"
