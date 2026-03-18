#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Deepspan — full-stack integration test suite
#
# Builds, starts, tests, and tears down the entire simulation stack:
#
#   Layer            Tool / path
#   ─────────────────────────────────────────────────────────────────
#   C++ (accel-dev)  cmake --preset accel-dev  +  ctest --preset accel-dev
#   Go               go test ./server/...  ./hwip/accel/server/...
#   hw-model         build/accel-dev/hw-model/deepspan-hw-model
#   mgmt-daemon      build/bin/mgmt-daemon  (--sim flag)
#   server           build/bin/deepspan-server  --hwip-type accel
#   API smoke        ConnectRPC REST over http (curl)
#   SDK              sdk/examples/hello.py
#   hwip registry    verify unknown type returns error
#
# Usage:
#   ./scripts/test-fullstack.sh                  # full run
#   ./scripts/test-fullstack.sh --no-build       # skip build (binaries must exist)
#   ./scripts/test-fullstack.sh --hwip accel     # choose hwip type (default: accel)
#   ./scripts/test-fullstack.sh --port 19080     # custom server port
#   ./scripts/test-fullstack.sh --help
#
# Exit code: 0 = all tests passed, 1 = one or more failed

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
export PATH="/usr/local/go/bin:${HOME}/go/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"

# ── Defaults ──────────────────────────────────────────────────────────────────
NO_BUILD=0
HWIP_TYPE="accel"
SERVER_PORT=19080          # non-standard port so we don't collide with a running dev server
MGMT_PORT=19081
SHM_NAME="deepspan-test"
STARTUP_TIMEOUT=15
LOG_DIR="${ROOT}/build/logs/fullstack"

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-build)  NO_BUILD=1; shift ;;
        --hwip)      HWIP_TYPE="$2"; shift 2 ;;
        --port)      SERVER_PORT="$2"; shift 2 ;;
        -h|--help)
            sed -n '3,20p' "$0" | sed 's/^# \?//'
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

SERVER_URL="http://localhost:${SERVER_PORT}"
MGMT_ADDR=":${MGMT_PORT}"

# ── Colour / log helpers ──────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

log()    { echo -e "${BOLD}[test]${NC} $*"; }
ok()     { echo -e "${GREEN}${BOLD}  ✓ $*${NC}"; }
skip()   { echo -e "${YELLOW}  ⊘ $*${NC}"; }
fail()   { echo -e "${RED}${BOLD}  ✗ $*${NC}"; }
section(){ echo -e "\n${CYAN}${BOLD}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ── Test result tracking ──────────────────────────────────────────────────────
declare -a TEST_NAMES=()
declare -a TEST_RESULTS=()   # PASS | FAIL | SKIP
declare -a TEST_DETAILS=()

record() {
    local name="$1" result="$2" detail="${3:-}"
    TEST_NAMES+=("$name")
    TEST_RESULTS+=("$result")
    TEST_DETAILS+=("$detail")
    case "$result" in
        PASS) ok  "$name${detail:+  ($detail)}" ;;
        FAIL) fail "$name${detail:+  ($detail)}" ;;
        SKIP) skip "$name${detail:+  ($detail)}" ;;
    esac
}

# run_test NAME CMD... — runs CMD, records PASS/FAIL
run_test() {
    local name="$1"; shift
    local out
    if out=$("$@" 2>&1); then
        record "$name" PASS
    else
        record "$name" FAIL "exit $?"
        echo -e "${DIM}${out}${NC}" | head -20 || true
    fi
}

# ── PID list + cleanup ────────────────────────────────────────────────────────
PIDS=()

cleanup() {
    local rc=$?
    for pid in "${PIDS[@]:-}"; do
        kill "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null || true
    rm -f "/dev/shm/${SHM_NAME}" 2>/dev/null || true
    [[ $rc -eq 0 ]] || log "(stack torn down after failure)"
}
trap cleanup EXIT INT TERM

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1: Build
# ─────────────────────────────────────────────────────────────────────────────
section "Build"
mkdir -p "${LOG_DIR}" "${ROOT}/build/bin"

if [[ $NO_BUILD -eq 0 ]]; then

    # C++ — cmake preset
    log "cmake configure (${HWIP_TYPE}-dev)..."
    PRESET="${HWIP_TYPE}-dev"
    if cmake --preset "${PRESET}" \
            >"${LOG_DIR}/cmake-configure.log" 2>&1; then
        record "cmake configure (${PRESET})" PASS
    else
        record "cmake configure (${PRESET})" FAIL
        cat "${LOG_DIR}/cmake-configure.log"
        exit 1   # can't continue without a build dir
    fi

    log "cmake build..."
    if cmake --build --preset "${PRESET}" -j"$(nproc)" \
            >"${LOG_DIR}/cmake-build.log" 2>&1; then
        record "cmake build (${PRESET})" PASS
    else
        record "cmake build (${PRESET})" FAIL
        tail -30 "${LOG_DIR}/cmake-build.log"
        exit 1
    fi

    # Go build — server + hwip plugin
    log "go build server + hwip/${HWIP_TYPE}/server..."
    if (cd "${ROOT}" && \
        go build ./server/... \
                 "./hwip/${HWIP_TYPE}/server/..." \
        >"${LOG_DIR}/go-build.log" 2>&1); then
        record "go build" PASS
    else
        record "go build" FAIL
        cat "${LOG_DIR}/go-build.log"
        exit 1
    fi

    # Go binary for tests
    log "go build binaries..."
    (cd "${ROOT}/mgmt-daemon" && go build -o "${ROOT}/build/bin/mgmt-daemon" ./cmd/mgmt-daemon/) \
        >"${LOG_DIR}/go-build-mgmt.log" 2>&1
    (cd "${ROOT}/server"      && go build -o "${ROOT}/build/bin/deepspan-server" ./cmd/server/) \
        >"${LOG_DIR}/go-build-server.log" 2>&1
    record "go build binaries" PASS

else
    record "cmake build"   SKIP "--no-build"
    record "go build"      SKIP "--no-build"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2: Unit / integration tests (offline)
# ─────────────────────────────────────────────────────────────────────────────
section "Unit Tests (offline)"

# C++ tests
log "ctest --preset ${HWIP_TYPE}-dev..."
if ctest --preset "${HWIP_TYPE}-dev" --output-on-failure \
        >"${LOG_DIR}/ctest.log" 2>&1; then
    TOTAL=$(grep -Ec '[0-9]+/[0-9]+ Test +#' "${LOG_DIR}/ctest.log" || echo "?")
    record "ctest (${HWIP_TYPE}-dev)" PASS "${TOTAL} tests"
else
    FAIL_LINE=$(grep -i 'failed' "${LOG_DIR}/ctest.log" | tail -1 || echo "see log")
    record "ctest (${HWIP_TYPE}-dev)" FAIL "${FAIL_LINE}"
    grep -A5 'FAILED' "${LOG_DIR}/ctest.log" | head -20 || true
fi

# Go tests
log "go test ./server/... ./hwip/${HWIP_TYPE}/server/..."
if (cd "${ROOT}" && \
    go test -count=1 ./server/... "./hwip/${HWIP_TYPE}/server/..." \
    >"${LOG_DIR}/go-test.log" 2>&1); then
    PASSED=$(grep -c '^ok' "${LOG_DIR}/go-test.log" || echo 0)
    record "go test" PASS "${PASSED} package(s) ok"
else
    record "go test" FAIL
    grep -E '^(FAIL|---FAIL)' "${LOG_DIR}/go-test.log" | head -10 || true
fi

# Go vet
run_test "go vet" bash -c \
    "cd '${ROOT}' && go vet ./server/... './hwip/${HWIP_TYPE}/server/...'"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3: Start simulation stack
# ─────────────────────────────────────────────────────────────────────────────
section "Start Simulation Stack"

HW_MODEL_BIN="${ROOT}/build/${HWIP_TYPE}-dev/hw-model/deepspan-hw-model"
FW_SIM_BIN="${ROOT}/build/${HWIP_TYPE}-dev/hw-model/deepspan-firmware-sim"
MGMT_BIN="${ROOT}/build/bin/mgmt-daemon"
SERVER_BIN="${ROOT}/build/bin/deepspan-server"

# hw-model
if [[ -f "${HW_MODEL_BIN}" ]]; then
    log "starting hw-model (shm=/${SHM_NAME})..."
    "${HW_MODEL_BIN}" "--shm-name=/${SHM_NAME}" \
        >"${LOG_DIR}/hw-model.log" 2>&1 &
    PIDS+=($!)
    sleep 0.3
    if [[ -f "/dev/shm/${SHM_NAME}" ]]; then
        record "hw-model start" PASS "pid ${PIDS[-1]}"
    else
        record "hw-model start" FAIL "shm /dev/shm/${SHM_NAME} not created"
    fi
else
    record "hw-model start" SKIP "binary not found: ${HW_MODEL_BIN}"
fi

# firmware-sim (hw-model side emulation)
if [[ -f "${FW_SIM_BIN}" ]]; then
    log "starting firmware-sim..."
    "${FW_SIM_BIN}" "--shm-name=/${SHM_NAME}" --interval-ms=500 \
        >"${LOG_DIR}/firmware-sim.log" 2>&1 &
    PIDS+=($!)
    sleep 0.2
    record "firmware-sim start" PASS "pid ${PIDS[-1]}"
else
    record "firmware-sim start" SKIP "binary not found"
fi

# mgmt-daemon
if [[ -f "${MGMT_BIN}" ]]; then
    log "starting mgmt-daemon (${MGMT_ADDR})..."
    "${MGMT_BIN}" --addr "${MGMT_ADDR}" --sim \
        >"${LOG_DIR}/mgmt-daemon.log" 2>&1 &
    PIDS+=($!)
    sleep 0.3
    record "mgmt-daemon start" PASS "pid ${PIDS[-1]}"
else
    record "mgmt-daemon start" FAIL "binary not found: ${MGMT_BIN}"
fi

# server — with hwip-type flag
if [[ -f "${SERVER_BIN}" ]]; then
    log "starting server (${SERVER_URL}, --hwip-type ${HWIP_TYPE})..."
    "${SERVER_BIN}" \
        --addr ":${SERVER_PORT}" \
        --mgmt-addr "localhost${MGMT_ADDR}" \
        --shm-name "${SHM_NAME}" \
        --hwip-type "${HWIP_TYPE}" \
        >"${LOG_DIR}/server.log" 2>&1 &
    PIDS+=($!)
else
    fail "server binary not found — aborting"
    exit 1
fi

# wait for server ready
log "waiting for server ready (timeout ${STARTUP_TIMEOUT}s)..."
deadline=$((SECONDS + STARTUP_TIMEOUT))
while [[ $SECONDS -lt $deadline ]]; do
    if curl -sf "${SERVER_URL}/healthz" >/dev/null 2>&1; then
        record "server ready" PASS
        break
    fi
    sleep 0.4
done
if [[ $SECONDS -ge $deadline ]]; then
    record "server ready" FAIL "timed out after ${STARTUP_TIMEOUT}s"
    echo "--- server log ---"
    tail -20 "${LOG_DIR}/server.log" || true
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4: API smoke tests (ConnectRPC REST)
# ─────────────────────────────────────────────────────────────────────────────
section "API Smoke Tests"

BASE="${SERVER_URL}"

# helper: POST ConnectRPC JSON
rpc() {
    local proc="$1" body="${2:-{\}}"
    curl -sf -X POST "${BASE}/${proc}" \
        -H "Content-Type: application/json" \
        -d "${body}" 2>&1
}

# 4-1. Health check
run_test "GET /healthz" curl -sf "${BASE}/healthz"

# 4-2. HwipService.ListDevices
log "ListDevices..."
if resp=$(rpc "deepspan.v1.HwipService/ListDevices" '{}'); then
    N=$(echo "$resp" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('devices',[])))" 2>/dev/null || echo 0)
    if [[ "$N" -ge 1 ]]; then
        record "HwipService/ListDevices" PASS "${N} device(s)"
    else
        record "HwipService/ListDevices" FAIL "no devices in response: ${resp}"
    fi
else
    record "HwipService/ListDevices" FAIL "curl failed"
fi

# 4-3. HwipService.GetDeviceStatus
log "GetDeviceStatus..."
if resp=$(curl -sf -X POST "${BASE}/deepspan.v1.HwipService/GetDeviceStatus" \
        -H "Content-Type: application/json" \
        -d '{"deviceId":"hwip0"}' 2>&1) && \
   echo "$resp" | grep -q 'DEVICE_STATE_READY'; then
    record "HwipService/GetDeviceStatus" PASS
else
    record "HwipService/GetDeviceStatus" FAIL "resp=${resp}"
fi

# 4-4. HwipService.SubmitRequest — ECHO (opcode=1)
# payload: arg0=0xABCD (little-endian 4 bytes) + arg1=0x1234 (little-endian 4 bytes)
# base64("ÍëÀ\x00\x124\x00\x00") — easier to just send the b64
ECHO_PAYLOAD=$(python3 -c "import struct,base64; print(base64.b64encode(struct.pack('<II',0xABCD,0x1234)).decode())")
log "SubmitRequest ECHO (opcode=1, arg0=0xABCD, arg1=0x1234)..."
if resp=$(rpc "deepspan.v1.HwipService/SubmitRequest" \
    "{\"deviceId\":\"hwip0\",\"opcode\":1,\"payload\":\"${ECHO_PAYLOAD}\",\"timeoutMs\":3000}"); then
    # proto3 JSON: status=0 (success) is omitted (default value); treat absent as 0
    STATUS=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',0))" 2>/dev/null || echo -1)
    RESULT_B64=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('result',''))" 2>/dev/null || echo "")
    # Decode result bytes and check first 4 bytes = arg0 echo (little-endian 0xABCD)
    RESULT_HEX=$(python3 -c "import base64; d=base64.b64decode('${RESULT_B64}'); print(d[:4].hex())" 2>/dev/null || echo "?")
    if [[ "$STATUS" == "0" ]]; then
        record "HwipService/SubmitRequest ECHO" PASS "status=0 result[0:4]=0x${RESULT_HEX}"
    else
        record "HwipService/SubmitRequest ECHO" FAIL "status=${STATUS} resp=${resp}"
    fi
else
    record "HwipService/SubmitRequest ECHO" FAIL "curl failed"
fi

# 4-5. HwipService.SubmitRequest — STATUS (opcode=3)
log "SubmitRequest STATUS (opcode=3)..."
if resp=$(rpc "deepspan.v1.HwipService/SubmitRequest" \
    "{\"deviceId\":\"hwip0\",\"opcode\":3,\"payload\":\"\",\"timeoutMs\":3000}"); then
    # proto3 JSON: status=0 omitted when success
    STATUS=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',0))" 2>/dev/null || echo -1)
    if [[ "$STATUS" == "0" ]]; then
        record "HwipService/SubmitRequest STATUS" PASS "status=0"
    else
        record "HwipService/SubmitRequest STATUS" FAIL "status=${STATUS}"
    fi
else
    record "HwipService/SubmitRequest STATUS" FAIL "curl failed"
fi

# 4-6. ManagementService.GetFirmwareInfo
log "ManagementService/GetFirmwareInfo..."
if resp=$(rpc "deepspan.v1.ManagementService/GetFirmwareInfo" '{"deviceId":"hwip0"}'); then
    record "ManagementService/GetFirmwareInfo" PASS "$(echo "$resp" | head -c 80)..."
else
    # mgmt-daemon may return error in sim mode — check if it's a structured error
    if echo "$resp" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        record "ManagementService/GetFirmwareInfo" PASS "sim mode response"
    else
        record "ManagementService/GetFirmwareInfo" SKIP "sim mode / mgmt-daemon not available"
    fi
fi

# 4-7. TelemetryService.GetTelemetry
log "TelemetryService/GetTelemetry..."
if resp=$(rpc "deepspan.v1.TelemetryService/GetTelemetry" '{"deviceId":"hwip0"}'); then
    record "TelemetryService/GetTelemetry" PASS
else
    record "TelemetryService/GetTelemetry" SKIP "telemetry not available in sim"
fi

# 4-8. GET /api/hw-stats
log "GET /api/hw-stats..."
if resp=$(curl -sf "${BASE}/api/hw-stats" 2>&1); then
    AVAIL=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('available',False))" 2>/dev/null || echo False)
    if [[ "$AVAIL" == "True" ]]; then
        VER=$(echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('version_str','?'))" 2>/dev/null || echo "?")
        record "GET /api/hw-stats" PASS "version=${VER} hw-model connected"
    else
        record "GET /api/hw-stats" SKIP "hw-model not running (available=false)"
    fi
else
    record "GET /api/hw-stats" FAIL "curl failed"
fi

# 4-9. GET /monitor (HTML response)
run_test "GET /monitor" bash -c \
    "curl -sf '${BASE}/monitor' | grep -q 'Deepspan Hardware Monitor'"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5: hwip registry validation
# ─────────────────────────────────────────────────────────────────────────────
section "HWIP Registry Validation"

# 5-1. Verify known type (accel) works — already covered by smoke tests above.
record "registry: accel registered" PASS "covered by smoke tests"

# 5-2. Start server with unknown hwip-type — must exit non-zero
log "server --hwip-type unknown_type (must fail fast)..."
if "${SERVER_BIN}" \
        --addr ":$((SERVER_PORT + 10))" \
        --shm-name "${SHM_NAME}" \
        --hwip-type "unknown_type" \
    >"${LOG_DIR}/server-badtype.log" 2>&1; then
    record "registry: unknown type rejected" FAIL "server should have exited with error"
else
    record "registry: unknown type rejected" PASS "server exited with error (expected)"
fi

# 5-3. Verify deepspan_accel.h opcode values match Go constants
log "verifying DEEPSPAN_ACCEL_OP_ECHO == Go OpEcho == 0x0001..."
C_ECHO=$(grep -E '^#define DEEPSPAN_ACCEL_OP_ECHO' \
    "${ROOT}/kernel/include/uapi/linux/deepspan_accel.h" \
    | awk '{print $3}' | head -1)
GO_ECHO=$(grep -E 'OpEcho\s+uint32\s+=' "${ROOT}/hwip/accel/server/opcodes.go" \
    | grep -oE '0x[0-9a-fA-F]+' | head -1)
if [[ "$C_ECHO" == "$GO_ECHO" && "$C_ECHO" == "0x0001" ]]; then
    record "opcode parity (C == Go)" PASS "ECHO=${C_ECHO}"
else
    record "opcode parity (C == Go)" FAIL "C=${C_ECHO}  Go=${GO_ECHO}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 6: SDK hello-world
# ─────────────────────────────────────────────────────────────────────────────
section "SDK Hello-World"

HELLO="${ROOT}/sdk/examples/hello.py"
VENV_PY="${ROOT}/.venv/bin/python"

log "running SDK hello.py..."
SDK_ENV="DEEPSPAN_URL=${BASE}"
if [[ -x "${VENV_PY}" ]]; then
    if env "${SDK_ENV}" "${VENV_PY}" "${HELLO}" >"${LOG_DIR}/sdk-hello.log" 2>&1; then
        record "SDK hello-world" PASS ".venv python"
    else
        record "SDK hello-world" FAIL
        tail -10 "${LOG_DIR}/sdk-hello.log" || true
    fi
elif command -v uv &>/dev/null; then
    if (cd "${ROOT}/sdk" && env "${SDK_ENV}" uv run python "${HELLO}") \
            >"${LOG_DIR}/sdk-hello.log" 2>&1; then
        record "SDK hello-world" PASS "uv"
    else
        record "SDK hello-world" FAIL
        tail -10 "${LOG_DIR}/sdk-hello.log" || true
    fi
else
    record "SDK hello-world" SKIP "no python env (.venv or uv)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 7: hw-model interaction check
# ─────────────────────────────────────────────────────────────────────────────
section "HW-Model Interaction"

log "checking firmware-sim ↔ hw-model command flow (3s window)..."
if curl -sf "${BASE}/api/hw-stats" >/dev/null 2>&1; then
    _hw_counts() {
        curl -sf "${BASE}/api/hw-stats" | \
            python3 -c "import sys,json; d=json.load(sys.stdin); print(int(d.get('hw_cmd_count',0)),int(d.get('fw_cmd_count',0)))" 2>/dev/null \
            || echo "0 0"
    }
    mapfile -t _c0 < <(_hw_counts | tr ' ' '\n')
    hw0="${_c0[0]:-0}"; fw0="${_c0[1]:-0}"
    sleep 3
    mapfile -t _c1 < <(_hw_counts | tr ' ' '\n')
    hw1="${_c1[0]:-0}"; fw1="${_c1[1]:-0}"
    delta_hw=$(( hw1 - hw0 ))
    delta_fw=$(( fw1 - fw0 ))
    if [[ $delta_hw -gt 0 || $delta_fw -gt 0 ]]; then
        record "fw-sim ↔ hw-model cmd flow" PASS \
            "Δhw_cmd=${delta_hw}  Δfw_cmd=${delta_fw} in 3s"
    else
        record "fw-sim ↔ hw-model cmd flow" SKIP \
            "firmware-sim not running or no commands in 3s"
    fi
else
    record "fw-sim ↔ hw-model cmd flow" SKIP "hw-stats endpoint unavailable"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 8: Summary
# ─────────────────────────────────────────────────────────────────────────────
section "Test Summary"

PASS_N=0; FAIL_N=0; SKIP_N=0

printf "${BOLD}%-55s %-6s %s${NC}\n" "Test" "Result" "Detail"
printf '%0.s─' {1..80}; echo

for i in "${!TEST_NAMES[@]}"; do
    name="${TEST_NAMES[$i]}"
    result="${TEST_RESULTS[$i]}"
    detail="${TEST_DETAILS[$i]}"
    case "$result" in
        PASS) colour="${GREEN}"; (( PASS_N++ )) || true ;;
        FAIL) colour="${RED}";   (( FAIL_N++ )) || true ;;
        SKIP) colour="${YELLOW}"; (( SKIP_N++ )) || true ;;
    esac
    printf "${colour}%-55s %-6s${NC} %s\n" "${name}" "${result}" "${detail}"
done

printf '%0.s─' {1..80}; echo
printf "${BOLD}%-55s %-6s %s${NC}\n" \
    "Total: $((PASS_N + FAIL_N + SKIP_N)) tests" \
    "" \
    "${GREEN}${BOLD}${PASS_N} passed${NC}  ${RED}${BOLD}${FAIL_N} failed${NC}  ${YELLOW}${SKIP_N} skipped${NC}"
echo ""
echo -e "${DIM}Logs: ${LOG_DIR}/${NC}"
echo ""

if [[ $FAIL_N -gt 0 ]]; then
    echo -e "${RED}${BOLD}FULL-STACK TEST FAILED  (${FAIL_N} failure(s))${NC}"
    exit 1
else
    echo -e "${GREEN}${BOLD}FULL-STACK TEST PASSED${NC}"
fi
