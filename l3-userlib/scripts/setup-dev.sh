#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# userlib layer dev tool setup (Ubuntu 24.04)
set -euo pipefail

echo "==> [userlib] Installing dev tools..."

sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    cmake \
    ninja-build \
    pkg-config \
    liburing-dev \
    libgtest-dev \
    libgmock-dev \
    clang \
    clang-tidy \
    clang-format \
    g++

# ETL (Embedded Template Library) — system install via apt
# Ubuntu 24.04 ships etl-dev via universe; fallback to git submodule otherwise
if apt-cache show libetl-dev &>/dev/null 2>&1; then
    sudo apt-get install -y --no-install-recommends libetl-dev
else
    echo "  --> libetl-dev not found in apt; will use third_party/etl submodule."
    echo "      Run: git submodule update --init third_party/etl"
fi

echo "==> [userlib] Done."
