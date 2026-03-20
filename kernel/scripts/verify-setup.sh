#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# kernel: verify kernel headers and build tools
set -euo pipefail

FAILED=()
check_cmd() { command -v "$1" &>/dev/null || FAILED+=("command: $1"); }

echo "--- [kernel] ---"
check_cmd make
check_cmd gcc
check_cmd aarch64-linux-gnu-gcc

KVER=$(uname -r)
KBUILD="/lib/modules/${KVER}/build"
if [ ! -d "${KBUILD}" ]; then
    FAILED+=("linux-headers-${KVER} (${KBUILD} not found)")
else
    echo "    kernel headers: ${KBUILD}"
fi

# Check required headers exist
for hdr in linux/virtio.h linux/io_uring/cmd.h linux/xarray.h; do
    if [ ! -f "${KBUILD}/include/${hdr}" ] && \
       [ ! -f "/usr/src/linux-headers-${KVER}/include/${hdr}" ] && \
       [ ! -f "/usr/include/${hdr}" ]; then
        echo "    WARNING: ${hdr} not found in standard paths (may still be ok)"
    fi
done

echo "    gcc: $(gcc --version | head -1)"
echo "    aarch64-gcc: $(aarch64-linux-gnu-gcc --version | head -1)"

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "  MISSING: ${FAILED[*]}" >&2
    exit 1
fi
echo "  OK"
