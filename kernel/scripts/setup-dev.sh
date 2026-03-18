#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# kernel layer dev tool setup (Ubuntu 24.04)
# Installs kernel build tools and KUnit runner dependencies
set -euo pipefail

echo "==> [kernel] Installing kernel build tools..."

sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    build-essential \
    flex \
    bison \
    bc \
    libelf-dev \
    libssl-dev \
    libdw-dev \
    pahole \
    python3 \
    python3-pip \
    dwarves \
    kmod

# Headers for the running kernel (out-of-tree module build)
KVER=$(uname -r)
if ! dpkg -l "linux-headers-${KVER}" &>/dev/null 2>&1; then
    echo "  --> Installing linux-headers-${KVER}..."
    sudo apt-get install -y --no-install-recommends "linux-headers-${KVER}"
fi

# Cross-compile toolchain for aarch64 target
sudo apt-get install -y --no-install-recommends \
    gcc-aarch64-linux-gnu \
    binutils-aarch64-linux-gnu

# kunit_tool (python wrapper for UML KUnit runs) — part of kernel tree
# For CI/local KUnit: install kernel-tests helper
pip3 install --user kernelci 2>/dev/null || true

echo "==> [kernel] To compile the out-of-tree module:"
echo "    make -C /lib/modules/\$(uname -r)/build M=\$(pwd)/drivers/deepspan modules"
echo "==> [kernel] Done."
