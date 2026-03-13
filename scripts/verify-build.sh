#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Deepspan — build verification script
#
# Runs each layer's build.sh and reports pass/fail.
# Intended to be run before the initial git commit and in CI.
#
# Usage:
#   ./scripts/verify-build.sh                          # all layers
#   ./scripts/verify-build.sh --layers go,python       # subset
#   ./scripts/verify-build.sh --skip firmware,kernel   # skip slow layers
#
# Exit code: 0 = all passed, 1 = one or more failed
set -euo pipefail

DEEPSPAN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/usr/local/go/bin:${HOME}/go/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:$PATH"

# ── Layer definitions: name → build script path ──────────────────────────────
declare -A LAYER_SCRIPT=(
    [hw-model]="hw-model/scripts/build.sh"
    [userlib]="userlib/scripts/build.sh"
    [appframework]="appframework/scripts/build.sh"
    [kernel]="kernel/scripts/build.sh"
    [firmware]="firmware/scripts/build.sh"
    [mgmt-daemon]="mgmt-daemon/scripts/build.sh"
    [server]="server/scripts/build.sh"
    [sdk]="sdk/scripts/build.sh"
)

# Default order (dependencies first)
ALL_LAYERS=(hw-model kernel userlib appframework firmware mgmt-daemon server sdk)
LAYERS=("${ALL_LAYERS[@]}")
SKIP_LAYERS=()

# ── Argument parsing ──────────────────────────────────────────────────────────
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

# ── Colour helpers ────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; NC='\033[0m'

PASS="${GREEN}PASS${NC}"; FAIL="${RED}FAIL${NC}"; SKIP="${YELLOW}SKIP${NC}"

should_skip() { local l="$1"; for s in "${SKIP_LAYERS[@]:-}"; do [[ "$s" == "$l" ]] && return 0; done; return 1; }

# ── Per-layer runner ──────────────────────────────────────────────────────────
declare -A RESULTS=()
declare -A DURATIONS=()

run_layer() {
    local layer="$1"
    local script="${DEEPSPAN_ROOT}/${LAYER_SCRIPT[$layer]}"

    if should_skip "$layer"; then
        RESULTS[$layer]="SKIP"
        return 0
    fi
    if [ ! -f "$script" ]; then
        echo -e "${RED}[${layer}] build script not found: ${script}${NC}"
        RESULTS[$layer]="FAIL"
        return 1
    fi

    local log="${DEEPSPAN_ROOT}/build/logs/${layer}-build.log"
    mkdir -p "$(dirname "$log")"

    echo -e "${BOLD}━━━ ${layer} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    local t_start t_end
    t_start=$(date +%s)

    if bash "$script" 2>&1 | tee "$log"; then
        t_end=$(date +%s)
        RESULTS[$layer]="PASS"
        DURATIONS[$layer]="$((t_end - t_start))s"
    else
        t_end=$(date +%s)
        RESULTS[$layer]="FAIL"
        DURATIONS[$layer]="$((t_end - t_start))s"
        echo -e "${RED}[${layer}] FAILED — see ${log}${NC}"
    fi
}

# ── Run all layers ────────────────────────────────────────────────────────────
for layer in "${LAYERS[@]}"; do
    run_layer "$layer" || true   # collect all results; don't abort early
done

# ── Summary table ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}┌────────────────────────────────────┐${NC}"
echo -e "${BOLD}│  Deepspan build verification       │${NC}"
echo -e "${BOLD}├──────────────────┬────────┬────────┤${NC}"
printf "${BOLD}│ %-16s │ %-6s │ %-6s │${NC}\n" "Layer" "Result" "Time"
echo -e "${BOLD}├──────────────────┼────────┼────────┤${NC}"

FAIL_COUNT=0
for layer in "${LAYERS[@]}"; do
    result="${RESULTS[$layer]:-SKIP}"
    duration="${DURATIONS[$layer]:--}"
    case "$result" in
        PASS) colour="${GREEN}" ;;
        FAIL) colour="${RED}"; ((FAIL_COUNT++)) ;;
        SKIP) colour="${YELLOW}" ;;
        *)    colour="${NC}" ;;
    esac
    printf "│ %-16s │ ${colour}%-6s${NC} │ %-6s │\n" "$layer" "$result" "$duration"
done
echo -e "${BOLD}└──────────────────┴────────┴────────┘${NC}"
echo ""

if [[ $FAIL_COUNT -gt 0 ]]; then
    echo -e "${RED}${BOLD}${FAIL_COUNT} layer(s) failed. Fix errors before committing.${NC}"
    exit 1
else
    echo -e "${GREEN}${BOLD}All layers passed. Safe to commit.${NC}"
fi
