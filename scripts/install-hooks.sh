#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Deepspan — install git hooks for local development
#
# Usage:
#   ./scripts/install-hooks.sh           # hooks only
#   ./scripts/install-hooks.sh --lint    # hooks + golangci-lint
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GOLANGCI_VERSION="v2.11.3"
INSTALL_LINT=false

for arg in "$@"; do
    case "$arg" in
        --lint) INSTALL_LINT=true ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

cd "$REPO_ROOT"

git config core.hooksPath .githooks
echo "Installed git hooks from .githooks/"

if command -v golangci-lint &>/dev/null; then
    echo "golangci-lint already installed: $(golangci-lint version 2>&1 | head -1)"
elif [ "$INSTALL_LINT" = true ]; then
    echo "Installing golangci-lint ${GOLANGCI_VERSION} ..."
    GOBIN="$(go env GOPATH)/bin"
    curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh \
        | sh -s -- -b "$GOBIN" "${GOLANGCI_VERSION}"
    echo "golangci-lint installed: $("$GOBIN/golangci-lint" version 2>&1 | head -1)"
else
    echo ""
    echo "Warning: golangci-lint not found. Pre-commit lint checks will be skipped."
    echo "To install automatically: ./scripts/install-hooks.sh --lint"
    echo "To install manually:      https://golangci-lint.run/welcome/install/"
fi
