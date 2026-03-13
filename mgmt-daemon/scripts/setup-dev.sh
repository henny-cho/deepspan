#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# mgmt-daemon layer dev tool setup (Ubuntu 24.04)
# Installs: Go 1.23, golangci-lint, buf CLI
set -euo pipefail

GO_VERSION="1.23.5"
GO_TARBALL="go${GO_VERSION}.linux-amd64.tar.gz"
GO_URL="https://go.dev/dl/${GO_TARBALL}"
GO_INSTALL_DIR="/usr/local"

echo "==> [mgmt-daemon] Installing Go ${GO_VERSION}..."

if command -v go &>/dev/null && [[ "$(go version)" == *"go${GO_VERSION}"* ]]; then
    echo "  --> Go ${GO_VERSION} already installed."
else
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT
    wget -q --show-progress -P "$TMP_DIR" "${GO_URL}"
    sudo rm -rf "${GO_INSTALL_DIR}/go"
    sudo tar -C "${GO_INSTALL_DIR}" -xf "${TMP_DIR}/${GO_TARBALL}"
    echo "  --> Go installed to ${GO_INSTALL_DIR}/go"
fi

# Ensure Go is on PATH for this session
export PATH="${GO_INSTALL_DIR}/go/bin:${HOME}/go/bin:$PATH"

# Add to ~/.profile if not already there
if ! grep -q 'go/bin' "${HOME}/.profile" 2>/dev/null; then
    echo 'export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"' >> "${HOME}/.profile"
    echo "  --> Added Go to ~/.profile"
fi

echo "==> [mgmt-daemon] Installing golangci-lint..."
if ! command -v golangci-lint &>/dev/null; then
    curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh \
        | sh -s -- -b "$(go env GOPATH)/bin" v1.62.2
fi

echo "==> [mgmt-daemon] Done."
echo "    Reload shell or run: source ~/.profile"
