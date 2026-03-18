#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# appframework: verify tools (same requirements as userlib)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEEPSPAN_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)/deepspan"

echo "--- [appframework] ---"
# Delegates entirely to userlib verify — shared requirements
bash "${DEEPSPAN_ROOT}/userlib/scripts/verify-setup.sh" | sed 's/--- \[userlib\]/--- [appframework (via userlib)]/'
