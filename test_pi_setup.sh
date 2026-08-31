#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "${SCRIPT_DIR}/config.env" ]] && source "${SCRIPT_DIR}/config.env"
[[ -f "${SCRIPT_DIR}/lib/preflight.sh" ]] && { source "${SCRIPT_DIR}/lib/preflight.sh"; pi_x_bootstrap_path; }

if command -v npx >/dev/null 2>&1; then exec npx --yes tsx "${SCRIPT_DIR}/test_pi_setup.ts" "$@"
else exec node --loader ts-node/esm "${SCRIPT_DIR}/test_pi_setup.ts" "$@"; fi
