#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# firmware layer: west build + twister tests (native_sim)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEEPSPAN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BOARD="${1:-native_sim/native/64}"

# west must be on PATH
if ! command -v west &>/dev/null; then
    echo "ERROR: 'west' not found. Run firmware/scripts/setup-dev.sh first." >&2
    exit 1
fi

# Find west workspace root by walking up (same algorithm as west itself)
find_west_root() {
    local dir="$1"
    while [[ "$dir" != "/" ]]; do
        [[ -d "$dir/.west" ]] && echo "$dir" && return 0
        dir="$(dirname "$dir")"
    done
    return 1
}

WEST_TOPDIR="$(find_west_root "${DEEPSPAN_ROOT}")" || {
    echo "ERROR: west workspace not initialised. Run:" >&2
    echo "  cd <workspace-parent> && west init -l deepspan && west update" >&2
    exit 1
}

cd "${DEEPSPAN_ROOT}"

# native_sim uses the host GCC toolchain — no Zephyr SDK needed.
# ARM targets override this by passing ZEPHYR_TOOLCHAIN_VARIANT=zephyr.
export ZEPHYR_TOOLCHAIN_VARIANT="${ZEPHYR_TOOLCHAIN_VARIANT:-host}"

echo "==> [firmware] Build app (board: ${BOARD}, toolchain: ${ZEPHYR_TOOLCHAIN_VARIANT})..."
west build -b "${BOARD}" firmware/app --build-dir build/firmware/app \
    -- -DZEPHYR_EXTRA_MODULES="${DEEPSPAN_ROOT}/firmware"

echo "==> [firmware] Run Ztest via twister..."
west twister \
    -T firmware/tests \
    --platform native_sim/native/64 \
    --inline-logs \
    -v \
    --outdir build/firmware/twister-out
