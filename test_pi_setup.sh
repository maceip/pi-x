#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/lib/preflight.sh" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/lib/preflight.sh"
    pi_x_bootstrap_path
fi

if command -v npx >/dev/null 2>&1; then
    exec npx --yes tsx "${SCRIPT_DIR}/test_pi_setup.ts" "$@"
fi

node --loader ts-node/esm "${SCRIPT_DIR}/test_pi_setup.ts" "$@"
