#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# server: verify Go toolchain + buf CLI
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEEPSPAN_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)/deepspan"
FAILED=()

echo "--- [server] ---"

# Go — delegate to mgmt-daemon verify (shared toolchain)
bash "${DEEPSPAN_ROOT}/mgmt-daemon/scripts/verify-setup.sh" | grep -v '^---' | sed 's/^/  /'

# buf CLI
if ! command -v buf &>/dev/null; then
    FAILED+=("command: buf (install via server/scripts/setup-dev.sh)")
else
    echo "    buf: $(buf --version)"
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "  MISSING: ${FAILED[*]}" >&2
    exit 1
fi
echo "  OK"
