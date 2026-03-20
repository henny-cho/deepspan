#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# kernel layer: out-of-tree module compile check
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVER_DIR="${SCRIPT_DIR}/../drivers/deepspan"
KVER="${1:-$(uname -r)}"
KBUILD="/lib/modules/${KVER}/build"

if [ ! -d "${KBUILD}" ]; then
    echo "ERROR: kernel headers not found at ${KBUILD}." >&2
    echo "  Install with: sudo apt-get install linux-headers-${KVER}" >&2
    exit 1
fi

echo "==> [kernel] Compile check (kernel ${KVER})..."
make -C "${KBUILD}" M="${DRIVER_DIR}" modules 2>&1 | tee "${DRIVER_DIR}/build.log"

# Fail if any error line exists
if grep -qiE '^\s*error:' "${DRIVER_DIR}/build.log"; then
    echo "ERROR: kernel module build failed. See ${DRIVER_DIR}/build.log" >&2
    exit 1
fi

echo "==> [kernel] Build OK."
echo "==> [kernel] Cleaning up..."
make -C "${KBUILD}" M="${DRIVER_DIR}" clean
