#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# gate.sh — unified CI/developer verification entry point for deepspan.
#
# Commands:
#   build    — verify every layer builds (delegates to verify-build.sh)
#   lint     — go lint for all Go modules (platform + hwip)
#   test     — full-stack simulation test (delegates to run-sim.sh)
#   validate — 7-check generated artifact validation (hwip/scripts/validate.sh)
#   setup    — install toolchains + verify (setup-all.sh + verify-setup.sh)
#
# Usage:
#   ./scripts/gate.sh build    [--layers l4/server,l4/mgmt-daemon] [--skip firmware]
#   ./scripts/gate.sh lint     [--module l4/server] [--hwip]
#   ./scripts/gate.sh test     [--no-build]
#   ./scripts/gate.sh validate [--hwip accel] [--fix]
#   ./scripts/gate.sh setup    [--layers go] [--skip firmware]
#
# Exit code: 0 = all checks passed, 1 = failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
ds_setup_path
DS_LOG_PREFIX="[gate]"

COMMAND="${1:-}"
shift || true

# ── Helpers ───────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $0 <command> [options]

Commands:
  build    [--layers L1,L2] [--skip L1]          Build verification (verify-build.sh)
  lint     [--module <mod>] [--hwip]              Go lint (golangci-lint)
  test     [--no-build]                           Full-stack sim test (run-sim.sh)
  validate [--hwip <type>] [--fix]               HWIP artifact validation (validate.sh)
  setup    [--layers L1,L2] [--skip L1]          Dev env setup (setup-all.sh + verify-setup.sh)
EOF
    exit "${1:-0}"
}

[[ -z "$COMMAND" ]] && usage 1

# ── build ─────────────────────────────────────────────────────────────────────
cmd_build() {
    log "gate: build"
    exec "${SCRIPT_DIR}/verify-build.sh" "$@"
}

# ── lint ──────────────────────────────────────────────────────────────────────
cmd_lint() {
    local module=""
    local include_hwip=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --module) module="$2"; shift 2 ;;
            --hwip)   include_hwip=true; shift ;;
            *) die "Unknown lint option: $1" ;;
        esac
    done

    if ! command -v golangci-lint &>/dev/null; then
        warn "golangci-lint not found — installing via go install..."
        go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest
    fi

    local DEEPSPAN_ROOT
    DEEPSPAN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

    # Default: lint all Go modules
    local modules=()
    if [[ -n "$module" ]]; then
        modules=("$module")
    else
        modules=(l4/mgmt-daemon l4/server)
        if $include_hwip; then
            modules+=(hwip/accel/l4-plugin hwip/demo)
        fi
    fi

    local fail_count=0
    for mod in "${modules[@]}"; do
        local mod_path="${DEEPSPAN_ROOT}/${mod}"
        [[ -d "$mod_path" ]] || { warn "module not found: $mod_path"; continue; }
        section "lint: $mod"
        if ( cd "$mod_path" && golangci-lint run ./... ); then
            ok "$mod — lint passed"
        else
            fail_count=$((fail_count + 1))
        fi
    done

    [[ $fail_count -eq 0 ]] || { log "$fail_count module(s) failed lint"; exit 1; }
    ok "all modules passed lint"
}

# ── validate ──────────────────────────────────────────────────────────────────
cmd_validate() {
    log "gate: validate"
    exec "${SCRIPT_DIR}/../hwip/scripts/validate.sh" "$@"
}

# ── test ──────────────────────────────────────────────────────────────────────
cmd_test() {
    log "gate: test"
    exec "${SCRIPT_DIR}/run-sim.sh" "$@"
}

# ── setup ─────────────────────────────────────────────────────────────────────
cmd_setup() {
    log "gate: setup"
    "${SCRIPT_DIR}/setup-all.sh" "$@"
    "${SCRIPT_DIR}/verify-setup.sh" "$@"
    ok "setup complete and verified"
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "$COMMAND" in
    build)    cmd_build    "$@" ;;
    lint)     cmd_lint     "$@" ;;
    test)     cmd_test     "$@" ;;
    validate) cmd_validate "$@" ;;
    setup)    cmd_setup    "$@" ;;
    help|-h|--help) usage 0 ;;
    *) warn "Unknown command: $COMMAND"; usage 1 ;;
esac
