#!/usr/bin/env bash
# test-stack.sh — automated integration tests for the deepspan ACCEL stack.
#
# Starts hwsim + demo-server (or demo-server --stub), then runs curl-based
# ConnectRPC (JSON) assertions and the Go demo-client.
#
# Modes:
#   default  — starts hwsim (POSIX shm) + demo-server in sim mode.
#              demo-client runs full value-equality checks.
#   --stub   — starts demo-server in stub mode (no hw required).
#              demo-client is skipped (stub echoes opcode, not args).
#
# Usage:
#   ./scripts/test-stack.sh [--stub] [--port 8080]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${REPO_ROOT}/scripts/lib.sh"
hwip_setup_path
HWIP_LOG_PREFIX="[test-stack]"
GO="${GO:-/usr/local/go/bin/go}"
BIN_DIR="$REPO_ROOT/.demo-bin"
PORT=8080
SHM_NAME="deepspan_accel_0"
STUB_MODE=false

for arg in "$@"; do
  case "$arg" in
    --stub)    STUB_MODE=true ;;
    --port=*)  PORT="${arg#--port=}" ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

BASE="http://localhost:$PORT"

cleanup() {
  [[ -n "${HWSIM_PID:-}" ]]  && kill "$HWSIM_PID"  2>/dev/null || true
  [[ -n "${SERVER_PID:-}" ]] && kill "$SERVER_PID" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT

# rpc <procedure> <json-body> → stdout; returns 0 if HTTP 200, 1 otherwise.
rpc() {
  curl -sf \
    -H "Content-Type: application/json" \
    -d "$2" \
    "$BASE/$1"
}

# ── Build ─────────────────────────────────────────────────────────────────────
echo "[test-stack] building..."
mkdir -p "$BIN_DIR"
cd "$REPO_ROOT"
$GO build -o "$BIN_DIR/hwsim"       ./demo/cmd/hwsim
$GO build -o "$BIN_DIR/demo-server" ./demo/cmd/server
$GO build -o "$BIN_DIR/demo-client" ./demo/cmd/client
echo "[test-stack] build OK"

# ── Start infrastructure ──────────────────────────────────────────────────────
if ! $STUB_MODE; then
  "$BIN_DIR/hwsim" -name "$SHM_NAME" &
  HWSIM_PID=$!
  sleep 0.3
  [[ -e "/dev/shm/$SHM_NAME" ]] || die "hwsim shm not found at /dev/shm/$SHM_NAME"
fi

SERVER_ARGS=("-addr" ":$PORT" "-shm-name" "$SHM_NAME")
$STUB_MODE && SERVER_ARGS+=("-stub")
"$BIN_DIR/demo-server" "${SERVER_ARGS[@]}" >/dev/null 2>&1 &
SERVER_PID=$!
wait_port ":$PORT" 12
echo "[test-stack] up (port=$PORT, stub=$STUB_MODE)"

# ── Tests ─────────────────────────────────────────────────────────────────────
echo ""
echo "══ Test suite ════════════════════════════════════════════════════"

# T1: health ──────────────────────────────────────────────────────────────────
echo "T1: GET /healthz"
body="$(curl -sf "$BASE/healthz")"
[[ "$body" == "ok" ]] && pass "healthz = 'ok'" || fail "healthz: '$body'"

# T2: ListDevices ─────────────────────────────────────────────────────────────
echo "T2: Platform HwipService/ListDevices"
resp="$(rpc "deepspan.v1.HwipService/ListDevices" '{}')"
echo "$resp" | grep -q '"deviceId":"hwip0"' \
  && pass "ListDevices returns hwip0" \
  || fail "ListDevices: $resp"

# T3: SubmitRequest responds without error ────────────────────────────────────
echo "T3: Platform HwipService/SubmitRequest (Echo opcode=1)"
# payload = arg0:0xAA (LE 4B) + arg1:0xBB (LE 4B) → base64
resp="$(rpc "deepspan.v1.HwipService/SubmitRequest" \
  '{"deviceId":"hwip0","opcode":1,"payload":"qgAAAAC7AAAA","timeoutMs":1000}')"
# response has "requestId", "result" (no error field) means success
echo "$resp" | grep -q '"requestId"' \
  && pass "SubmitRequest/Echo: valid response" \
  || fail "SubmitRequest/Echo: $resp"

# T4: Accel Echo ──────────────────────────────────────────────────────────────
echo "T4: AccelHwipService/Echo"
resp="$(rpc "deepspan_accel.v1.AccelHwipService/Echo" \
  '{"deviceId":"hwip0","arg0":10,"arg1":20,"timeoutMs":1000}')"
if $STUB_MODE; then
  # Stub echoes opcode (ECHO=1) as data0; arg0/arg1 are ignored.
  echo "$resp" | grep -q '"data0":1' \
    && pass "Echo (stub): data0=opcode(1)" \
    || fail "Echo (stub): $resp"
else
  # hwsim echoes arg0/arg1.
  echo "$resp" | grep -q '"data0":10' && echo "$resp" | grep -q '"data1":20' \
    && pass "Echo (shm): data0=10 data1=20" \
    || fail "Echo (shm): $resp"
fi

# T5: Accel Process ───────────────────────────────────────────────────────────
echo "T5: AccelHwipService/Process (arg0=100, arg1=42)"
# data = struct.pack('<II', 100, 42) → base64(python): ZAAAACoAAAA=
resp="$(rpc "deepspan_accel.v1.AccelHwipService/Process" \
  '{"deviceId":"hwip0","data":"ZAAAACoAAAA=","timeoutMs":1000}')"
echo "$resp" | grep -q '"result"' \
  && pass "Process: got result bytes" \
  || fail "Process: $resp"

if ! $STUB_MODE; then
  # sum=142, xor=78 → struct.pack('<II', 142, 78) → base64: jgAAAE4AAAA=
  echo "$resp" | grep -q '"result":"jgAAAE4AAAA="' \
    && pass "Process (shm): sum=142 xor=78" \
    || fail "Process (shm): result mismatch: $resp"
fi

# T6: Accel Status ────────────────────────────────────────────────────────────
echo "T6: AccelHwipService/Status"
resp="$(rpc "deepspan_accel.v1.AccelHwipService/Status" \
  '{"deviceId":"hwip0","timeoutMs":1000}')"
if $STUB_MODE; then
  echo "$resp" | grep -q '"statusWord":3' \
    && pass "Status (stub): statusWord=opcode(3)" \
    || fail "Status (stub): $resp"
else
  # hwsim returns hwVersion=0x00010000 (65536) as statusWord.
  echo "$resp" | grep -q '"statusWord":65536' \
    && pass "Status (shm): statusWord=0x00010000" \
    || fail "Status (shm): $resp"
fi

# T7: Accel SubmitRequest (generic dispatch) ──────────────────────────────────
echo "T7: AccelHwipService/SubmitRequest (ACCEL_OP_ECHO=1)"
resp="$(rpc "deepspan_accel.v1.AccelHwipService/SubmitRequest" \
  '{"deviceId":"hwip0","op":"ACCEL_OP_ECHO","payload":"DQAAAB4AAAA=","timeoutMs":1000}')"
echo "$resp" | grep -q '"result"' \
  && pass "AccelHwipService/SubmitRequest: got result" \
  || fail "AccelHwipService/SubmitRequest: $resp"

# T8: demo-client end-to-end (hwsim mode only) ────────────────────────────────
echo "T8: demo-client end-to-end"
if $STUB_MODE; then
  skip "demo-client skipped in stub mode (stub echoes opcode, not args)"
else
  if "$BIN_DIR/demo-client" -addr "$BASE" >/tmp/demo-client.out 2>&1; then
    ok_count="$(grep -c '\[OK\]' /tmp/demo-client.out || true)"
    pass "demo-client: $ok_count value checks passed"
  else
    fail "demo-client failed:"
    cat /tmp/demo-client.out >&2
  fi
fi

# T9: Concurrent Echo ─────────────────────────────────────────────────────────
echo "T9: concurrent Echo x10"
pids=()
for i in $(seq 1 10); do
  rpc "deepspan_accel.v1.AccelHwipService/Echo" \
    "{\"deviceId\":\"hwip0\",\"arg0\":$i,\"arg1\":$((i*2)),\"timeoutMs\":500}" \
    >/dev/null &
  pids+=($!)
done
all_ok=true
for pid in "${pids[@]}"; do wait "$pid" || all_ok=false; done
$all_ok && pass "10 concurrent Echo calls all 200" || fail "some concurrent calls failed"

# ── Summary ───────────────────────────────────────────────────────────────────
hwip_summary || exit 1
