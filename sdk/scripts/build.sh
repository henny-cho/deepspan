#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# sdk layer: uv sync + pytest
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="${SCRIPT_DIR}/.."

if ! command -v uv &>/dev/null; then
    echo "ERROR: 'uv' not found. Run sdk/scripts/setup-dev.sh first." >&2
    exit 1
fi

cd "${LAYER_DIR}"

echo "==> [sdk] uv sync..."
uv sync --extra dev

echo "==> [sdk] pytest..."
uv run pytest -v --tb=short
