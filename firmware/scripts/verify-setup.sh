#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# firmware: verify west, Zephyr SDK, and host tools
set -euo pipefail

FAILED=()
check_cmd() { command -v "$1" &>/dev/null || FAILED+=("command: $1"); }

echo "--- [firmware] ---"
check_cmd west
check_cmd cmake
check_cmd ninja
check_cmd dtc          # device-tree-compiler
check_cmd python3

# West version
if command -v west &>/dev/null; then
    echo "    west: $(west --version)"
fi

# Zephyr SDK
SDK_DIR="${HOME}/.zephyr-sdk"
if [ ! -d "${SDK_DIR}" ]; then
    FAILED+=("Zephyr SDK not found at ${SDK_DIR}")
else
    echo "    Zephyr SDK: ${SDK_DIR}"
    # Verify at least one toolchain is present
    if ! ls "${SDK_DIR}"/x86_64-zephyr-elf/bin/x86_64-zephyr-elf-gcc &>/dev/null 2>&1; then
        FAILED+=("Zephyr SDK toolchain x86_64-zephyr-elf not found")
    fi
fi

# West workspace
DEEPSPAN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/deepspan"
if [ ! -d "${DEEPSPAN_ROOT}/.west" ]; then
    FAILED+=("west workspace not initialised (run: west init -l . && west update)")
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "  MISSING: ${FAILED[*]}" >&2
    exit 1
fi
echo "  OK"
