#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# userlib: verify cmake, liburing, etl, gtest
set -euo pipefail

FAILED=()
check_cmd() { command -v "$1" &>/dev/null || FAILED+=("command: $1"); }
check_lib()  { pkg-config --exists "$1" 2>/dev/null || FAILED+=("pkg-config: $1"); }

echo "--- [userlib] ---"
check_cmd cmake
check_cmd ninja
check_cmd g++
check_lib liburing

# ETL: system package or submodule
SUBMODULE_ETL="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/deepspan/third_party/etl"
if ! pkg-config --exists etl 2>/dev/null && [ ! -d "${SUBMODULE_ETL}" ]; then
    FAILED+=("etl: neither system pkg-config nor third_party/etl submodule found")
else
    echo "    etl: OK"
fi

if ! dpkg -l libgtest-dev &>/dev/null 2>&1; then
    FAILED+=("package: libgtest-dev")
fi

echo "    liburing: $(pkg-config --modversion liburing 2>/dev/null || echo 'system')"

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "  MISSING: ${FAILED[*]}" >&2
    exit 1
fi
echo "  OK"
