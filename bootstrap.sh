#!/usr/bin/env bash
# Copy-pasteable entrypoint. Works from checkout OR curl -fsSL https://raw.githubusercontent.com/maceip/pi-x/main/bootstrap.sh | bash
set -euo pipefail

REPO_URL="${PI_X_REPO:-https://github.com/maceip/pi-x.git}"
DEST="${PI_X_HOME:-${HOME}/pi-x}"
_self="${BASH_SOURCE[0]:-}"

if [[ -n "$_self" && "$_self" != "-" && "$_self" != "bash" && -f "$_self" ]]; then
    ROOT="$(cd "$(dirname "$_self")" && pwd)"
    [[ -f "${ROOT}/run_agent.sh" ]] && exec bash "${ROOT}/run_agent.sh" "$@"
fi
[[ -f "${DEST}/run_agent.sh" ]] && exec bash "${DEST}/run_agent.sh" "$@"

echo " [pi-x] No local checkout found. Cloning ${REPO_URL} -> ${DEST}"
command -v git >/dev/null 2>&1 || { echo " [pi-x] git is required. Install git and retry." >&2; exit 1; }
mkdir -p "$(dirname "${DEST}")"
git clone --depth 1 "${REPO_URL}" "${DEST}"
exec bash "${DEST}/run_agent.sh" "$@"
