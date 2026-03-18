#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# mgmt-daemon layer: go build + test
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="${SCRIPT_DIR}/.."

if ! command -v go &>/dev/null; then
    echo "ERROR: 'go' not found. Run mgmt-daemon/scripts/setup-dev.sh first." >&2
    exit 1
fi

cd "${MODULE_DIR}"

echo "==> [mgmt-daemon] go mod tidy..."
go mod tidy

echo "==> [mgmt-daemon] go build..."
go build ./...

echo "==> [mgmt-daemon] go test..."
go test -race ./...
