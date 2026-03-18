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
# Use pipx to avoid PEP 668 "externally-managed-environment" restriction on Ubuntu 24.04+
if ! command -v conan &>/dev/null; then
    echo "  --> Installing Conan v2 via pipx..."
    sudo apt-get install -y --no-install-recommends pipx
    pipx install "conan>=2,<3"
    pipx ensurepath
    export PATH="${HOME}/.local/bin:$PATH"
    conan profile detect --force
fi

echo "==> [hw-model] Done."
