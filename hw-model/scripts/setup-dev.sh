#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# hw-model layer dev tool setup (Ubuntu 24.04)
set -euo pipefail

echo "==> [hw-model] Installing dev tools..."

sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    cmake \
    ninja-build \
    pkg-config \
    libgtest-dev \
    libgmock-dev \
    clang \
    clang-tidy \
    clang-format \
    g++ \
    ccache

# liburing (io_uring — also needed by userlib, install here for early dev)
sudo apt-get install -y --no-install-recommends liburing-dev

# Conan v2 (optional — only needed for DEEPSPAN_USE_SYSTEM_DEPS=ON)
if ! command -v conan &>/dev/null; then
    echo "  --> Installing Conan v2..."
    pip3 install --user "conan>=2,<3"
    conan profile detect --force
fi

echo "==> [hw-model] Done."
