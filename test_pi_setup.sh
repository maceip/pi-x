#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="/Users/mac/.nvm/versions/node/v24.15.0/bin:${PATH}"

node --loader ts-node/esm "${SCRIPT_DIR}/test_pi_setup.ts" 2>/dev/null || node "${SCRIPT_DIR}/test_pi_setup.ts" 2>/dev/null || npx -y tsx "${SCRIPT_DIR}/test_pi_setup.ts"
