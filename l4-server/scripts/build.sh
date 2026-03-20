#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# server layer: go build + test (also tidies gen/go dependency)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="${SCRIPT_DIR}/.."
GEN_GO_DIR="${MODULE_DIR}/../gen/go"

if ! command -v go &>/dev/null; then
    echo "ERROR: 'go' not found. Run server/scripts/setup-dev.sh first." >&2
    exit 1
fi

# gen/go must be tidied first (server depends on it via replace directive)
if [ -f "${GEN_GO_DIR}/go.mod" ]; then
    echo "==> [gen/go] go mod tidy..."
    (cd "${GEN_GO_DIR}" && go mod tidy)
fi

cd "${MODULE_DIR}"

echo "==> [server] go mod tidy..."
go mod tidy

echo "==> [server] go build..."
go build ./...

echo "==> [server] go test..."
go test -race ./...
