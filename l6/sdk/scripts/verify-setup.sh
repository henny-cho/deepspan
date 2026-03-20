#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# sdk: verify Python and uv
set -euo pipefail

FAILED=()
MIN_PY_MINOR=11

echo "--- [sdk] ---"

# python3
if ! command -v python3 &>/dev/null; then
    FAILED+=("command: python3")
else
    PY_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)
    echo "    python3: ${PY_VER}"
    if [[ "$PY_MINOR" -lt "$MIN_PY_MINOR" ]]; then
        FAILED+=("python3 >= 3.${MIN_PY_MINOR} required, found ${PY_VER}")
    fi
fi

# uv
if ! command -v uv &>/dev/null; then
    FAILED+=("command: uv (install via sdk/scripts/setup-dev.sh)")
else
    echo "    uv: $(uv --version)"
fi

# venv / lockfile — uv workspace root is one level above sdk/
LAYER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ROOT="$(cd "${LAYER_DIR}/.." && pwd)"
if [ ! -d "${LAYER_DIR}/.venv" ] && [ ! -d "${WORKSPACE_ROOT}/.venv" ]; then
    echo "    WARNING: .venv not found — run 'uv sync --extra dev' in sdk/"
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "  MISSING: ${FAILED[*]}" >&2
    exit 1
fi
echo "  OK"
