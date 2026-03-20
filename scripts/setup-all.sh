#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Deepspan — full dev environment setup (Ubuntu 24.04)
#
# Usage:
#   ./scripts/setup-all.sh                    # all layers
#   ./scripts/setup-all.sh --layers l3-hw-model,l3-userlib,l6-sdk
#   ./scripts/setup-all.sh --skip firmware    # skip Zephyr SDK download
#
# Each layer's script is idempotent — safe to re-run.
set -euo pipefail

DEEPSPAN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${DEEPSPAN_ROOT}/scripts/lib.sh"

# ── Argument parsing ─────────────────────────────────────────────────────────
ALL_LAYERS=(l3-hw-model l2-firmware l2-kernel l3-userlib l3-appframework l4-mgmt-daemon l4-server l6-sdk)
LAYERS=("${ALL_LAYERS[@]}")
SKIP_LAYERS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --layers)
            IFS=',' read -ra LAYERS <<< "$2"; shift 2 ;;
        --skip)
            IFS=',' read -ra SKIP_LAYERS <<< "$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--layers <l1,l2,...>] [--skip <l1,l2,...>]"
            echo "Available layers: ${ALL_LAYERS[*]}"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

run_layer() {
    local layer="$1"
    local script="${DEEPSPAN_ROOT}/${layer}/scripts/setup-dev.sh"
    if should_skip "$layer"; then
        echo -e "${YELLOW}  [SKIP] ${layer}${NC}"
        return 0
    fi
    if [ ! -f "$script" ]; then
        echo -e "${RED}  [MISSING] ${layer}/scripts/setup-dev.sh${NC}"
        return 1
    fi
    echo -e "${GREEN}━━━ ${layer} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    bash "$script"
}

# ── Common system packages (apt once, shared across layers) ───────────────────
echo -e "${GREEN}━━━ common ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    python3 \
    python3-pip \
    python3-venv \
    pipx

# ── Per-layer setup ───────────────────────────────────────────────────────────
FAILED=()
for layer in "${LAYERS[@]}"; do
    if ! run_layer "$layer"; then
        FAILED+=("$layer")
    fi
done

# ── West workspace init (after firmware tools are ready) ─────────────────────
if [[ " ${LAYERS[*]} " == *" firmware "* ]] && ! should_skip firmware; then
    echo -e "${GREEN}━━━ west workspace ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    export PATH="${HOME}/.local/bin:/usr/local/go/bin:${HOME}/go/bin:$PATH"
    cd "${DEEPSPAN_ROOT}"
    if [ ! -d .west ]; then
        echo "  --> west init..."
        west init -l .
    fi
    echo "  --> west update (this may take a while)..."
    west update --narrow -o=--depth=1
    echo "  --> Installing Zephyr Python requirements in venv..."
    python3 -m venv "${DEEPSPAN_ROOT}/.venv-zephyr"
    "${DEEPSPAN_ROOT}/.venv-zephyr/bin/pip" install -r zephyr/scripts/requirements.txt
    echo "  --> Activate with: source ${DEEPSPAN_ROOT}/.venv-zephyr/bin/activate"
fi

# ── Git submodules (for dev-submodule CMake preset) ───────────────────────────
echo -e "${GREEN}━━━ git submodules ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
cd "${DEEPSPAN_ROOT}"
git submodule update --init --recursive

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}┌─────────────────────────────────────────────────┐${NC}"
echo -e "${GREEN}│  Deepspan dev environment setup complete        │${NC}"
echo -e "${GREEN}└─────────────────────────────────────────────────┘${NC}"

if [ ${#FAILED[@]} -gt 0 ]; then
    echo -e "${RED}Failed layers: ${FAILED[*]}${NC}"
    exit 1
fi

echo ""
echo "Next steps:"
echo "  1. Reload shell:  source ~/.profile"
echo "  2. Build C++:     cmake --preset dev-submodule && cmake --build build -j\$(nproc)"
echo "  3. Build firmware: west build -b native_sim/native/64 l2-firmware/app"
echo "  4. Build Go:      cd server && go mod tidy && go build ./cmd/server"
echo "  5. Test Python:   cd sdk && uv run pytest"
