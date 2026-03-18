#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Deepspan — full-stack simulation runner
#
# Builds and starts every runnable layer in simulation mode:
#   hw-model       POSIX shm MMIO simulator
#   mgmt-daemon    OpenAMP management daemon (--sim: /dev/null transport)
#   server         ConnectRPC server (gRPC + REST)
#   sdk            Python hello-world client
#
# Firmware (native_sim Zephyr binary) is started automatically if the binary
# exists at build/firmware/app/zephyr/zephyr.exe; otherwise it is skipped.
#
# Usage:
#   ./scripts/run-sim.sh             # build all + run
#   ./scripts/run-sim.sh --no-build  # skip build step (binaries must exist)
#   ./scripts/run-sim.sh --help
#
# Exit code: 0 = hello-world passed, 1 = failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEEPSPAN_ROOT="${SCRIPT_DIR}/.."
export PATH="/usr/local/go/bin:${HOME}/go/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:$PATH"

# ── Defaults ─────────────────────────────────────────────────────────────────
NO_BUILD=0
SERVER_ADDR="${SERVER_ADDR:-:8080}"
MGMT_ADDR="${MGMT_ADDR:-:8081}"
HW_MODEL_SHM="${HW_MODEL_SHM:-deepspan-sim}"
STARTUP_TIMEOUT=15  # seconds to wait for server ready

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-build) NO_BUILD=1; shift ;;
        -h|--help)
            echo "Usage: $0 [--no-build]"
            echo ""
            echo "Starts the full Deepspan simulation stack and runs a hello-world SDK test."
            echo ""
            echo "Environment overrides:"
            echo "  SERVER_ADDR      server listen address  (default: :8080)"
            echo "  MGMT_ADDR        mgmt-daemon address    (default: :8081)"
            echo "  HW_MODEL_SHM     POSIX shm name         (default: deepspan-sim)"
            echo "  DEEPSPAN_URL     SDK base URL           (default: http://localhost:8080)"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${BOLD}[run-sim]${NC} $*"; }
ok()   { echo -e "${GREEN}${BOLD}[run-sim] $*${NC}"; }
warn() { echo -e "${YELLOW}[run-sim] $*${NC}"; }
fail() { echo -e "${RED}${BOLD}[run-sim] $*${NC}"; exit 1; }

# ── PID tracking for cleanup ─────────────────────────────────────────────────
PIDS=()

cleanup() {
    log "shutting down..."
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null || true
    # Remove POSIX shm segment if it exists
    rm -f "/dev/shm/${HW_MODEL_SHM}" 2>/dev/null || true
    log "done"
}
trap cleanup EXIT INT TERM

# ── Build step ────────────────────────────────────────────────────────────────
build_hw_model() {
    log "building hw-model..."
    cmake -S "${DEEPSPAN_ROOT}/hw-model" \
          -B "${DEEPSPAN_ROOT}/hw-model/build" \
          -G Ninja -DCMAKE_BUILD_TYPE=Release \
          -DDEEPSPAN_BUILD_TESTS=OFF \
          >/dev/null
    cmake --build "${DEEPSPAN_ROOT}/hw-model/build" -j"$(nproc)" >/dev/null
    ok "hw-model built"
}

build_go_services() {
    log "building Go services (mgmt-daemon, server)..."
    local gen_go="${DEEPSPAN_ROOT}/gen/go"
    if [ -f "${gen_go}/go.mod" ]; then
        (cd "${gen_go}" && go mod tidy 2>/dev/null)
    fi
    (cd "${DEEPSPAN_ROOT}/mgmt-daemon" && go build -o "${DEEPSPAN_ROOT}/build/bin/mgmt-daemon" ./cmd/mgmt-daemon/)
    (cd "${DEEPSPAN_ROOT}/server"      && go build -o "${DEEPSPAN_ROOT}/build/bin/deepspan-server" ./cmd/server/)
    ok "Go services built"
}

if [[ $NO_BUILD -eq 0 ]]; then
    mkdir -p "${DEEPSPAN_ROOT}/build/bin"

    if command -v cmake &>/dev/null && command -v ninja &>/dev/null; then
        build_hw_model
    else
        warn "cmake/ninja not found — skipping hw-model build"
    fi

    if command -v go &>/dev/null; then
        build_go_services
    else
        fail "go not found — cannot build services"
    fi
fi

# ── Verify binaries exist ─────────────────────────────────────────────────────
BIN_DIR="${DEEPSPAN_ROOT}/build/bin"
HW_MODEL_BIN="${DEEPSPAN_ROOT}/hw-model/build/deepspan-hw-model"
FW_SIM_BIN="${DEEPSPAN_ROOT}/hw-model/build/deepspan-firmware-sim"
MGMT_BIN="${BIN_DIR}/mgmt-daemon"
SERVER_BIN="${BIN_DIR}/deepspan-server"
ZEPHYR_BIN="${DEEPSPAN_ROOT}/build/firmware/app/zephyr/zephyr.exe"

[[ -f "${MGMT_BIN}"   ]] || fail "mgmt-daemon binary not found: ${MGMT_BIN}"
[[ -f "${SERVER_BIN}" ]] || fail "server binary not found: ${SERVER_BIN}"

# ── Start hw-model ────────────────────────────────────────────────────────────
if [[ -f "${HW_MODEL_BIN}" ]]; then
    log "starting hw-model (shm: ${HW_MODEL_SHM})..."
    "${HW_MODEL_BIN}" "--shm-name=/${HW_MODEL_SHM}" \
        >"${DEEPSPAN_ROOT}/build/logs/hw-model.log" 2>&1 &
    PIDS+=($!)
    sleep 0.3
    ok "hw-model started (pid ${PIDS[-1]})"
else
    warn "hw-model binary not found — skipping"
fi

# ── Start firmware_sim (hw-model ↔ firmware interaction demo) ─────────────────
if [[ -f "${FW_SIM_BIN}" ]]; then
    log "starting firmware_sim (shm: ${HW_MODEL_SHM})..."
    "${FW_SIM_BIN}" "--shm-name=/${HW_MODEL_SHM}" --interval-ms=1000 \
        >"${DEEPSPAN_ROOT}/build/logs/firmware-sim.log" 2>&1 &
    PIDS+=($!)
    sleep 0.2
    ok "firmware_sim started (pid ${PIDS[-1]})"
else
    warn "firmware_sim binary not found — skipping hw-model interaction demo"
    warn "  (run: cmake --build hw-model/build to build deepspan-firmware-sim)"
fi

# ── Start Zephyr native_sim firmware (optional, requires west build) ──────────
if [[ -f "${ZEPHYR_BIN}" ]]; then
    log "starting Zephyr native_sim firmware..."
    "${ZEPHYR_BIN}" \
        >"${DEEPSPAN_ROOT}/build/logs/zephyr.log" 2>&1 &
    PIDS+=($!)
    sleep 0.3
    ok "Zephyr firmware started (pid ${PIDS[-1]})"
fi

# ── Start mgmt-daemon ─────────────────────────────────────────────────────────
log "starting mgmt-daemon (addr ${MGMT_ADDR}, sim mode)..."
mkdir -p "${DEEPSPAN_ROOT}/build/logs"
"${MGMT_BIN}" --addr "${MGMT_ADDR}" --sim \
    >"${DEEPSPAN_ROOT}/build/logs/mgmt-daemon.log" 2>&1 &
PIDS+=($!)
sleep 0.3
ok "mgmt-daemon started (pid ${PIDS[-1]})"

# ── Start server ──────────────────────────────────────────────────────────────
log "starting server (addr ${SERVER_ADDR})..."
"${SERVER_BIN}" --addr "${SERVER_ADDR}" --mgmt-addr "localhost${MGMT_ADDR}" --shm-name "${HW_MODEL_SHM}" \
    >"${DEEPSPAN_ROOT}/build/logs/server.log" 2>&1 &
PIDS+=($!)
ok "server started (pid ${PIDS[-1]})"

# ── Wait for server ready ─────────────────────────────────────────────────────
log "waiting for server to be ready..."
SERVER_PORT="${SERVER_ADDR#:}"
deadline=$((SECONDS + STARTUP_TIMEOUT))
while [[ $SECONDS -lt $deadline ]]; do
    if curl -sf "http://localhost:${SERVER_PORT}/healthz" >/dev/null 2>&1; then
        ok "server is ready"
        break
    fi
    sleep 0.5
done
if [[ $SECONDS -ge $deadline ]]; then
    echo "--- server log ---"
    cat "${DEEPSPAN_ROOT}/build/logs/server.log" || true
    fail "server did not become ready within ${STARTUP_TIMEOUT}s"
fi

# ── Run SDK hello-world ───────────────────────────────────────────────────────
log "running SDK hello-world..."
DEEPSPAN_URL="http://localhost:${SERVER_PORT}"
export DEEPSPAN_URL

HELLO_SCRIPT="${DEEPSPAN_ROOT}/sdk/examples/hello.py"

if command -v uv &>/dev/null; then
    (cd "${DEEPSPAN_ROOT}/sdk" && uv run python "${HELLO_SCRIPT}")
elif command -v python3 &>/dev/null; then
    # Fallback: use system python (requires httpx installed)
    python3 "${HELLO_SCRIPT}"
else
    fail "neither 'uv' nor 'python3' found"
fi

echo ""
ok "=== Full-stack simulation hello-world PASSED ==="
echo ""
echo -e "  ${BOLD}Processes running:${NC}"
for pid in "${PIDS[@]}"; do
    name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "(exited)")
    echo "    pid ${pid}: ${name}"
done
echo ""
echo -e "  ${BOLD}Logs:${NC} ${DEEPSPAN_ROOT}/build/logs/"
echo ""
echo "  Press Ctrl-C to stop all services."

# ── Keep alive until Ctrl-C ───────────────────────────────────────────────────
wait
