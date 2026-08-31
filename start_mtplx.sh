#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PI_X_ROOT="${SCRIPT_DIR}"

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

mkdir -p "${LOG_DIR}"

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
echo " [MTPLX] Configured Context Depth: 65,536 tokens"

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

if [[ "${MTPLX_SOURCE:-}" == "python-module" ]]; then
    set -- python3 -m mtplx serve
else
    set -- "${MTPLX_BIN}" serve
fi

nohup "$@" \
    --model "${MODEL_PATH}" \
    --host "${HOST}" \
    --port "${PORT}" \
    --context-window 65536 \
    --profile turbo \
    --reasoning on \
    --reasoning-parser qwen3 \
    --reasoning-effort high \
    --ssd-session-cache off \
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
