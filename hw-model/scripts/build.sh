#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# hw-model layer: configure, build, and test
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="${SCRIPT_DIR}/.."
BUILD_DIR="${LAYER_DIR}/build"
PRESET="${1:-dev-submodule}"   # accepts: dev, dev-submodule

echo "==> [hw-model] Configure (preset: ${PRESET})..."
cmake --preset "${PRESET}" -S "${LAYER_DIR}" -B "${BUILD_DIR}"

echo "==> [hw-model] Build..."
cmake --build "${BUILD_DIR}" -j"$(nproc)"

echo "==> [hw-model] Test..."
ctest --test-dir "${BUILD_DIR}" --output-on-failure
