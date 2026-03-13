#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# firmware layer dev tool setup (Ubuntu 24.04)
# Installs: West, Zephyr host tools, Zephyr SDK (x86_64 + aarch64 toolchains)
set -euo pipefail

ZEPHYR_SDK_VERSION="0.17.0"
ZEPHYR_SDK_INSTALL_DIR="${HOME}/.zephyr-sdk"
ZEPHYR_SDK_MINIMAL_BUNDLE="zephyr-sdk-${ZEPHYR_SDK_VERSION}_linux-x86_64_minimal.tar.xz"
ZEPHYR_SDK_URL="https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${ZEPHYR_SDK_VERSION}/${ZEPHYR_SDK_MINIMAL_BUNDLE}"

echo "==> [firmware] Installing host dependencies..."

sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    git \
    cmake \
    ninja-build \
    gperf \
    ccache \
    dfu-util \
    device-tree-compiler \
    wget \
    python3 \
    python3-pip \
    python3-setuptools \
    python3-wheel \
    python3-venv \
    xz-utils \
    file \
    make \
    gcc \
    gcc-multilib \
    g++-multilib \
    libsdl2-dev \
    libmagic1

echo "==> [firmware] Installing West and Zephyr Python requirements..."
pip3 install --user west

# Ensure ~/.local/bin is on PATH
export PATH="$HOME/.local/bin:$PATH"

echo "==> [firmware] Installing Zephyr SDK ${ZEPHYR_SDK_VERSION}..."
if [ -d "${ZEPHYR_SDK_INSTALL_DIR}" ]; then
    echo "  --> Zephyr SDK already present at ${ZEPHYR_SDK_INSTALL_DIR}, skipping."
else
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT
    echo "  --> Downloading ${ZEPHYR_SDK_MINIMAL_BUNDLE}..."
    wget -q --show-progress -P "$TMP_DIR" "${ZEPHYR_SDK_URL}"
    echo "  --> Extracting..."
    tar -xf "${TMP_DIR}/${ZEPHYR_SDK_MINIMAL_BUNDLE}" -C "${TMP_DIR}"
    SDK_DIR="${TMP_DIR}/zephyr-sdk-${ZEPHYR_SDK_VERSION}"
    echo "  --> Installing toolchains (x86_64, aarch64)..."
    "${SDK_DIR}/setup.sh" -t x86_64-zephyr-elf -t aarch64-zephyr-elf -c
    mv "${SDK_DIR}" "${ZEPHYR_SDK_INSTALL_DIR}"
    echo "  --> Zephyr SDK installed to ${ZEPHYR_SDK_INSTALL_DIR}"
fi

echo "==> [firmware] Hint: run 'west init -l . && west update' from the deepspan root"
echo "==>            then  'pip3 install --user -r zephyr/scripts/requirements.txt'"
echo "==> [firmware] Done."
