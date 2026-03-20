#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# server layer dev tool setup (Ubuntu 24.04)
# Go and golangci-lint are shared with mgmt-daemon — delegate to it
set -euo pipefail

echo "==> [server] Installing dev tools..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEEPSPAN_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)/deepspan"

# Go + golangci-lint are the same as mgmt-daemon
if [ -f "${DEEPSPAN_ROOT}/mgmt-daemon/scripts/setup-dev.sh" ]; then
    echo "  --> Running mgmt-daemon setup (shared Go toolchain)..."
    bash "${DEEPSPAN_ROOT}/mgmt-daemon/scripts/setup-dev.sh"
fi

# buf CLI for proto codegen (server often re-generates stubs)
echo "==> [server] Installing buf CLI..."
if ! command -v buf &>/dev/null; then
    BUF_VERSION="1.34.0"
    BUF_URL="https://github.com/bufbuild/buf/releases/download/v${BUF_VERSION}/buf-Linux-x86_64"
    sudo wget -q -O /usr/local/bin/buf "${BUF_URL}"
    sudo chmod +x /usr/local/bin/buf
    echo "  --> buf ${BUF_VERSION} installed."
fi

echo "==> [server] Done."
