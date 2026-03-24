#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# tmux-crc32.sh — launch a CRC32 HWIP development session in tmux
#
# Creates a named tmux session with four panes:
#
#   ┌──────────────────────┬──────────────────────┐
#   │  hw-model            │  deepspan-server      │
#   │  (FPGA sim)          │  + crc32 plugin       │
#   ├──────────────────────┼──────────────────────┤
#   │  logs  (tail -f)     │  shell  (sdk / gdb)  │
#   └──────────────────────┴──────────────────────┘
#
# Usage:
#   ./scripts/tmux-crc32.sh [OPTIONS]
#
# Options:
#   --preset PRESET   CMake preset (default: dev-crc32)
#   --addr ADDR       gRPC listen address (default: 0.0.0.0:8080)
#   --shm NAME        POSIX SHM name (default: /deepspan_hwip_0)
#   --firmware        Also start deepspan-firmware-sim in server pane
#   --latency-us N    hw-model artificial response latency (default: 0)
#   --attach          Attach to session after creation (default: yes if interactive)
#   --no-attach       Do not attach to session
#   --kill            Kill existing session and exit
#   -h, --help        Show this help
#
# Keyboard shortcuts inside the session:
#   Ctrl-b d          Detach (session keeps running)
#   Ctrl-b [0-3]      Jump to pane by number
#   Ctrl-b arrow      Navigate between panes
#   Ctrl-b z          Zoom/unzoom a pane

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEEPSPAN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Defaults ──────────────────────────────────────────────────────────────────
SESSION="deepspan-crc32"
PRESET="dev-crc32"
ADDR="0.0.0.0:8080"
SHM_NAME="/deepspan_hwip_0"
LATENCY_US=0
START_FIRMWARE=0
DO_KILL=0

# Auto-attach if we are in an interactive terminal and not already inside tmux
if [[ -t 1 && -z "${TMUX:-}" ]]; then
    DO_ATTACH=1
else
    DO_ATTACH=0
fi

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --preset)     PRESET="$2";      shift 2 ;;
        --addr)       ADDR="$2";        shift 2 ;;
        --shm)        SHM_NAME="$2";    shift 2 ;;
        --latency-us) LATENCY_US="$2";  shift 2 ;;
        --firmware)   START_FIRMWARE=1; shift   ;;
        --attach)     DO_ATTACH=1;      shift   ;;
        --no-attach)  DO_ATTACH=0;      shift   ;;
        --kill)       DO_KILL=1;        shift   ;;
        -h|--help)
            sed -n '4,30p' "$0" | sed 's/^# \?//'
            exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Run with --help for usage." >&2
            exit 1 ;;
    esac
done

# ── Kill existing session ──────────────────────────────────────────────────────
if tmux has-session -t "$SESSION" 2>/dev/null; then
    if [[ $DO_KILL -eq 1 ]]; then
        tmux kill-session -t "$SESSION"
        echo "Session '$SESSION' killed."
        exit 0
    fi
    echo "Session '$SESSION' already exists."
    echo "  Attach:  tmux attach -t $SESSION"
    echo "  Kill:    $0 --kill"
    exit 0
fi

if [[ $DO_KILL -eq 1 ]]; then
    echo "No session '$SESSION' to kill."
    exit 0
fi

# ── Derived paths ─────────────────────────────────────────────────────────────
BUILD_DIR="${DEEPSPAN_ROOT}/build/${PRESET}"
HW_MODEL_BIN="${BUILD_DIR}/sim/hw-model/deepspan-hw-model"
FIRMWARE_SIM_BIN="${BUILD_DIR}/sim/hw-model/deepspan-firmware-sim"
SERVER_BIN="${BUILD_DIR}/server/deepspan-server"
PLUGIN_SO="${BUILD_DIR}/hwip/crc32/plugin/libhwip_crc32.so"
LOG_DIR="${BUILD_DIR}/logs"

# ── Verify binaries exist ─────────────────────────────────────────────────────
missing=()
[[ -f "$HW_MODEL_BIN" ]] || missing+=("$HW_MODEL_BIN")
[[ -f "$SERVER_BIN"   ]] || missing+=("$SERVER_BIN")
[[ -f "$PLUGIN_SO"    ]] || missing+=("$PLUGIN_SO")

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: build artifacts not found. Run first:" >&2
    echo "  ./scripts/dev.sh build --preset ${PRESET}" >&2
    echo "" >&2
    echo "Missing:" >&2
    for f in "${missing[@]}"; do echo "  $f" >&2; done
    exit 1
fi

mkdir -p "$LOG_DIR"

# ── Commands for each pane ────────────────────────────────────────────────────

# Pane 0 (top-left): hw-model
CMD_HW_MODEL=(
    "$HW_MODEL_BIN"
    "--shm-name=${SHM_NAME}"
    "--latency-us=${LATENCY_US}"
)

# Pane 1 (top-right): server [+ optional firmware-sim]
if [[ $START_FIRMWARE -eq 1 && -f "$FIRMWARE_SIM_BIN" ]]; then
    CMD_SERVER="\"${FIRMWARE_SIM_BIN}\" --shm-name=${SHM_NAME} &
\"${SERVER_BIN}\" --addr ${ADDR} --hwip-plugin \"${PLUGIN_SO}\""
else
    CMD_SERVER="\"${SERVER_BIN}\" --addr ${ADDR} --hwip-plugin \"${PLUGIN_SO}\""
fi

# Pane 2 (bottom-left): combined log tail
CMD_LOGS="mkdir -p '${LOG_DIR}' && touch '${LOG_DIR}/hw-model.log' '${LOG_DIR}/server.log' && tail -f '${LOG_DIR}/hw-model.log' '${LOG_DIR}/server.log'"

# Pane 3 (bottom-right): interactive shell in repo root, venv active if present
VENV_ACTIVATE=""
if [[ -f "${DEEPSPAN_ROOT}/.venv/bin/activate" ]]; then
    VENV_ACTIVATE="source '${DEEPSPAN_ROOT}/.venv/bin/activate' && "
fi
CMD_SHELL="${VENV_ACTIVATE}cd '${DEEPSPAN_ROOT}' && exec \$SHELL"

# ── Build the session ─────────────────────────────────────────────────────────

# Window 0: hw-model (top-left, pane 0)
tmux new-session  -d -s "$SESSION" -x 220 -y 50 \
    -n "crc32-stack" \
    -- bash -c "${CMD_HW_MODEL[*]} 2>&1 | tee '${LOG_DIR}/hw-model.log'; exec bash"

# Split right → server (pane 1, top-right)
tmux split-window -t "${SESSION}:0" -h \
    -- bash -c "${CMD_SERVER} 2>&1 | tee '${LOG_DIR}/server.log'; exec bash"

# Select pane 0 → split down → logs (pane 2, bottom-left)
tmux select-pane  -t "${SESSION}:0.0"
tmux split-window -t "${SESSION}:0.0" -v \
    -- bash -c "${CMD_LOGS}; exec bash"

# Select pane 1 → split down → interactive shell (pane 3, bottom-right)
tmux select-pane  -t "${SESSION}:0.1"
tmux split-window -t "${SESSION}:0.1" -v \
    -- bash -c "${CMD_SHELL}"

# Even out the layout
tmux select-layout -t "${SESSION}:0" tiled

# Rename panes via titles (tmux 3.0+)
tmux select-pane  -t "${SESSION}:0.0" -T "hw-model"
tmux select-pane  -t "${SESSION}:0.1" -T "server"
tmux select-pane  -t "${SESSION}:0.2" -T "logs"
tmux select-pane  -t "${SESSION}:0.3" -T "shell"

# Focus the interactive shell pane on attach
tmux select-pane  -t "${SESSION}:0.3"

# ── Status bar hint ───────────────────────────────────────────────────────────
tmux set-option   -t "$SESSION" status-right \
    " [deepspan-crc32 | ${PRESET}] | Ctrl-b d = detach "

# ── Done ──────────────────────────────────────────────────────────────────────
echo "Session '$SESSION' created."
echo ""
echo "  Pane layout:"
echo "    0 (top-left)     hw-model   → ${SHM_NAME}"
echo "    1 (top-right)    server     → ${ADDR}"
echo "    2 (bottom-left)  logs       → tail -f hw-model.log server.log"
echo "    3 (bottom-right) shell      → interactive (sdk / gdb / tests)"
echo ""
echo "  Attach : tmux attach -t ${SESSION}"
echo "  Kill   : $0 --kill"
echo ""

if [[ $DO_ATTACH -eq 1 ]]; then
    tmux attach -t "$SESSION"
fi
