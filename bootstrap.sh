#!/usr/bin/env bash
# Copy-pasteable entrypoint. Works from a checkout OR via:
#   curl -fsSL https://raw.githubusercontent.com/maceip/pi-x/main/bootstrap.sh | bash
set -euo pipefail

REPO_URL="${PI_X_REPO:-https://github.com/maceip/pi-x.git}"
DEST="${PI_X_HOME:-${HOME}/pi-x}"

_self="${BASH_SOURCE[0]:-}"
if [[ -n "$_self" && "$_self" != "-" && "$_self" != "bash" && -f "$_self" ]]; then
    ROOT="$(cd "$(dirname "$_self")" && pwd)"
    if [[ -f "${ROOT}/run_agent.sh" ]]; then
        exec bash "${ROOT}/run_agent.sh" "$@"
    fi
fi

if [[ -f "${DEST}/run_agent.sh" ]]; then
    exec bash "${DEST}/run_agent.sh" "$@"
fi

echo " [pi-x] No local checkout found. Cloning ${REPO_URL} -> ${DEST}"
if ! command -v git >/dev/null 2>&1; then
    echo " [pi-x] git is required to fetch the harness. Install git and retry." >&2
    exit 1
fi
mkdir -p "$(dirname "${DEST}")"
git clone --depth 1 "${REPO_URL}" "${DEST}"
exec bash "${DEST}/run_agent.sh" "$@"
