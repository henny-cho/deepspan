#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Deepspan — toolchain setup verification
#
# Checks that every layer's required tools are present and at the minimum
# required version.  Run this after setup-all.sh and before verify-build.sh.
#
# Usage:
#   ./scripts/verify-setup.sh                       # all layers
#   ./scripts/verify-setup.sh --layers go,python    # subset
#   ./scripts/verify-setup.sh --skip firmware       # skip layers with long downloads
#
# Exit code: 0 = all OK, 1 = one or more missing
set -euo pipefail

DEEPSPAN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/usr/local/go/bin:${HOME}/go/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:$PATH"

declare -A LAYER_SCRIPT=(
    [hw-model]="hw-model/scripts/verify-setup.sh"
    [userlib]="userlib/scripts/verify-setup.sh"
    [appframework]="appframework/scripts/verify-setup.sh"
    [kernel]="kernel/scripts/verify-setup.sh"
    [firmware]="firmware/scripts/verify-setup.sh"
    [mgmt-daemon]="mgmt-daemon/scripts/verify-setup.sh"
    [server]="server/scripts/verify-setup.sh"
    [sdk]="sdk/scripts/verify-setup.sh"
)

ALL_LAYERS=(hw-model kernel userlib appframework firmware mgmt-daemon server sdk)
LAYERS=("${ALL_LAYERS[@]}")
SKIP_LAYERS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --layers) IFS=',' read -ra LAYERS <<< "$2"; shift 2 ;;
        --skip)   IFS=',' read -ra SKIP_LAYERS <<< "$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--layers <l1,l2,...>] [--skip <l1,l2,...>]"
            echo "Layers: ${ALL_LAYERS[*]}"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

should_skip() { for s in "${SKIP_LAYERS[@]:-}"; do [[ "$s" == "$1" ]] && return 0; done; return 1; }

declare -A RESULTS=()

run_layer() {
    local layer="$1"
    local script="${DEEPSPAN_ROOT}/${LAYER_SCRIPT[$layer]}"

    if should_skip "$layer"; then
        RESULTS[$layer]="SKIP"; return 0
    fi
    if [ ! -f "$script" ]; then
        echo -e "${RED}[${layer}] verify-setup.sh not found${NC}"
        RESULTS[$layer]="FAIL"; return 1
    fi

    if bash "$script" 2>/tmp/deepspan-verify-${layer}.err; then
        RESULTS[$layer]="OK"
    else
        RESULTS[$layer]="FAIL"
        echo -e "${RED}  Errors:${NC}"
        cat /tmp/deepspan-verify-${layer}.err | sed 's/^/    /'
    fi
    rm -f /tmp/deepspan-verify-${layer}.err
}

for layer in "${LAYERS[@]}"; do
    run_layer "$layer" || true
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}┌──────────────────────────────────────────────────┐${NC}"
echo -e "${BOLD}│  Toolchain setup verification                    │${NC}"
echo -e "${BOLD}├──────────────────────┬───────────────────────────┤${NC}"
printf "${BOLD}│ %-20s │ %-25s │${NC}\n" "Layer" "Status"
echo -e "${BOLD}├──────────────────────┼───────────────────────────┤${NC}"

FAIL_COUNT=0
for layer in "${LAYERS[@]}"; do
    result="${RESULTS[$layer]:-SKIP}"
    case "$result" in
        OK)   colour="${GREEN}";  label="OK" ;;
        FAIL) colour="${RED}";    label="MISSING — run setup-dev.sh"; ((FAIL_COUNT++)) ;;
        SKIP) colour="${YELLOW}"; label="skipped" ;;
        *)    colour="${NC}";     label="$result" ;;
    esac
    printf "│ %-20s │ ${colour}%-25s${NC} │\n" "$layer" "$label"
done
echo -e "${BOLD}└──────────────────────┴───────────────────────────┘${NC}"
echo ""

if [[ $FAIL_COUNT -gt 0 ]]; then
    echo -e "${RED}${BOLD}${FAIL_COUNT} layer(s) missing tools.${NC}"
    echo "  Run:  ./scripts/setup-all.sh --layers <failed-layers>"
    exit 1
else
    echo -e "${GREEN}${BOLD}All toolchains verified. Ready to build.${NC}"
fi
