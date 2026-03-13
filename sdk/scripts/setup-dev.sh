#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# sdk layer dev tool setup (Ubuntu 24.04)
# Installs: Python 3.12, uv
set -euo pipefail

echo "==> [sdk] Installing Python dev tools..."

sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    python3-pip \
    curl

# uv — fast Python package manager (replaces pip + venv + pip-tools)
if ! command -v uv &>/dev/null; then
    echo "  --> Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # uv installs to ~/.cargo/bin or ~/.local/bin
    export PATH="${HOME}/.cargo/bin:${HOME}/.local/bin:$PATH"
    # Add to ~/.profile
    if ! grep -q 'uv' "${HOME}/.profile" 2>/dev/null; then
        echo 'export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"' >> "${HOME}/.profile"
    fi
else
    echo "  --> uv already installed: $(uv --version)"
fi

echo "==> [sdk] Installing SDK dependencies..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."
uv sync --extra dev
echo "  --> uv sync complete. Run 'uv run pytest' to test."

echo "==> [sdk] Done."
echo "    To activate the venv: source .venv/bin/activate"
