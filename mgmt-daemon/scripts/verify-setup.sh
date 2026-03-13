#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# mgmt-daemon: verify Go toolchain
set -euo pipefail

FAILED=()
MIN_GO="1.23"

echo "--- [mgmt-daemon] ---"

if ! command -v go &>/dev/null; then
    FAILED+=("command: go")
else
    GO_VER=$(go version | awk '{print $3}' | sed 's/go//')
    echo "    go: ${GO_VER}"
    # Compare major.minor
    MAJOR=$(echo "$GO_VER" | cut -d. -f1)
    MINOR=$(echo "$GO_VER" | cut -d. -f2)
    MIN_MINOR=$(echo "$MIN_GO" | cut -d. -f2)
    if [[ "$MAJOR" -lt 1 || ( "$MAJOR" -eq 1 && "$MINOR" -lt "$MIN_MINOR" ) ]]; then
        FAILED+=("go >= ${MIN_GO} required, found ${GO_VER}")
    fi
fi

if ! command -v golangci-lint &>/dev/null; then
    FAILED+=("command: golangci-lint")
else
    echo "    golangci-lint: $(golangci-lint --version | head -1)"
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "  MISSING: ${FAILED[*]}" >&2
    exit 1
fi
echo "  OK"
