#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# appframework layer dev tool setup (Ubuntu 24.04)
# Depends on userlib — run userlib/scripts/setup-dev.sh first
set -euo pipefail

echo "==> [appframework] Installing dev tools..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEEPSPAN_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)/deepspan"

# Reuse userlib setup (shared deps: cmake, liburing, etl, gtest)
if [ -f "${DEEPSPAN_ROOT}/userlib/scripts/setup-dev.sh" ]; then
    echo "  --> Running userlib setup (shared deps)..."
    bash "${DEEPSPAN_ROOT}/userlib/scripts/setup-dev.sh"
else
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends \
        cmake ninja-build pkg-config liburing-dev libgtest-dev g++
fi

echo "==> [appframework] Done."
