#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# userlib layer: configure, build, and test
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="${SCRIPT_DIR}/.."
BUILD_DIR="${LAYER_DIR}/build"
PRESET="${1:-dev-submodule}"

echo "==> [userlib] Configure (preset: ${PRESET})..."
cmake -S "${LAYER_DIR}" -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Debug \
    -DDEEPSPAN_BUILD_TESTS=ON \
    -DDEEPSPAN_USE_SYSTEM_DEPS=OFF

echo "==> [userlib] Build..."
cmake --build "${BUILD_DIR}" -j"$(nproc)"

echo "==> [userlib] Test..."
ctest --test-dir "${BUILD_DIR}" --output-on-failure
