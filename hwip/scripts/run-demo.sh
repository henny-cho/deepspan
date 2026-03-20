#!/usr/bin/env bash
# run-demo.sh — deepspan ACCEL full-stack demo
#
# Builds and runs:
#   1. hwsim    — Go POSIX shm hardware simulator
#   2. demo-server — ConnectRPC server (platform + accel services)
#   3. demo-client — exercises all RPCs and verifies results
#
# Options:
#   --stub      skip hwsim; use stub (no-hardware) mode
#   --addr A    server listen address (default :8080)
#   --shm N     shm basename (default deepspan_accel_0)
#   --verbose   enable hwsim verbose logging
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${REPO_ROOT}/scripts/lib.sh"
hwip_setup_path
HWIP_LOG_PREFIX="[run-demo]"
GO="${GO:-/usr/local/go/bin/go}"
BIN_DIR="$REPO_ROOT/.demo-bin"
SHM_NAME="deepspan_accel_0"
ADDR=":8080"
STUB_MODE=false
VERBOSE=false

for arg in "$@"; do
  case "$arg" in
    --stub)    STUB_MODE=true ;;
    --verbose) VERBOSE=true ;;
    --addr=*)  ADDR="${arg#--addr=}" ;;
    --shm=*)   SHM_NAME="${arg#--shm=}" ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

cleanup() {
  info "cleanup..."
  [[ -n "${HWSIM_PID:-}" ]]  && kill "$HWSIM_PID"  2>/dev/null || true
  [[ -n "${SERVER_PID:-}" ]] && kill "$SERVER_PID" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT

# ── Build ─────────────────────────────────────────────────────────────────────
info "building binaries..."
mkdir -p "$BIN_DIR"
cd "$REPO_ROOT"
$GO build -o "$BIN_DIR/hwsim"       ./demo/cmd/hwsim
$GO build -o "$BIN_DIR/demo-server" ./demo/cmd/server
$GO build -o "$BIN_DIR/demo-client" ./demo/cmd/client
info "build OK — binaries in $BIN_DIR"

# ── hwsim ─────────────────────────────────────────────────────────────────────
if $STUB_MODE; then
  warn "stub mode — skipping hwsim"
else
  HWSIM_ARGS=("-name" "$SHM_NAME")
  $VERBOSE && HWSIM_ARGS+=("-verbose")
  info "starting hwsim (shm=/dev/shm/$SHM_NAME)..."
  "$BIN_DIR/hwsim" "${HWSIM_ARGS[@]}" &
  HWSIM_PID=$!
  sleep 0.3
  [[ -e "/dev/shm/$SHM_NAME" ]] || die "hwsim did not create /dev/shm/$SHM_NAME"
  info "hwsim PID=$HWSIM_PID"
fi

# ── demo-server ───────────────────────────────────────────────────────────────
SERVER_ARGS=("-addr" "$ADDR" "-shm-name" "$SHM_NAME")
$STUB_MODE && SERVER_ARGS+=("-stub")
info "starting demo-server (addr=$ADDR)..."
"$BIN_DIR/demo-server" "${SERVER_ARGS[@]}" &
SERVER_PID=$!
wait_port "$ADDR"
info "demo-server PID=$SERVER_PID"

# ── demo-client ───────────────────────────────────────────────────────────────
BASE_URL="http://localhost${ADDR}"
[[ "$ADDR" == :* ]] || BASE_URL="http://$ADDR"
info "running demo-client (target=$BASE_URL)..."
echo ""
"$BIN_DIR/demo-client" -addr "$BASE_URL"
echo ""
info "demo complete"
