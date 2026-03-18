#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Deepspan — install git hooks for local development
#
# Usage:
#   ./scripts/install-hooks.sh
#
# Configures git to use .githooks/ as the hooks directory.
# After this, golangci-lint runs automatically before every push.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$REPO_ROOT"

git config core.hooksPath .githooks
echo "Installed git hooks from .githooks/"

if ! command -v golangci-lint &>/dev/null; then
    echo ""
    echo "Warning: golangci-lint not found."
    echo "Install it to enable pre-push lint checks:"
    echo "  https://golangci-lint.run/welcome/install/"
fi
