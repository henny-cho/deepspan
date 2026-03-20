#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# gate.sh — unified CI/developer verification entry point for deepspan-hwip.
#
# Commands:
#   build     — build hwsim, demo-server, demo-client, and Go plugin
#   lint      — gofmt + go vet + golangci-lint on all Go modules
#   validate  — 7-check generated artifact validation (delegates to validate.sh)
#   test      — full-stack integration test (delegates to test-stack.sh)
#
# Usage:
#   ./scripts/gate.sh build
#   ./scripts/gate.sh lint   [--module accel/l4-plugin]
#   ./scripts/gate.sh validate [--hwip accel] [--fix]
#   ./scripts/gate.sh test   [--stub] [--port=8080]
#
# Exit code: 0 = all checks passed, 1 = failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
hwip_setup_path
HWIP_LOG_PREFIX="[gate]"
GO="${GO:-/usr/local/go/bin/go}"

COMMAND="${1:-}"
shift || true

# ── Helpers ───────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $0 <command> [options]

Commands:
  build                              Build all demo + plugin binaries
  lint     [--module <mod>]          gofmt + vet + golangci-lint
  validate [--hwip <type>] [--fix]   Generated artifact validation (validate.sh)
  test     [--stub] [--port=N]       Full-stack integration tests (test-stack.sh)
EOF
    exit "${1:-0}"
}

[[ -z "$COMMAND" ]] && usage 1

# ── build ─────────────────────────────────────────────────────────────────────
cmd_build() {
    local BIN_DIR="${REPO_ROOT}/.demo-bin"
    mkdir -p "$BIN_DIR"
    section "build: demo binaries"
    (cd "${REPO_ROOT}" && \
        "$GO" build -o "$BIN_DIR/hwsim"       ./demo/cmd/hwsim && \
        "$GO" build -o "$BIN_DIR/demo-server" ./demo/cmd/server && \
        "$GO" build -o "$BIN_DIR/demo-client" ./demo/cmd/client)
    info "demo binaries built"

    section "build: accel l4-plugin"
    (cd "${REPO_ROOT}/accel/l4-plugin" && "$GO" build ./...)
    info "accel l4-plugin built"
}

# ── lint ──────────────────────────────────────────────────────────────────────
cmd_lint() {
    local module=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --module) module="$2"; shift 2 ;;
            *) die "Unknown lint option: $1" ;;
        esac
    done

    # Default: all Go modules in workspace
    local modules=()
    if [[ -n "$module" ]]; then
        modules=("${REPO_ROOT}/${module}")
    else
        # Hwip Go modules (go.work lives at monorepo root, not here)
        modules=(
            "${REPO_ROOT}/accel/gen/go"
            "${REPO_ROOT}/accel/l4-plugin"
            "${REPO_ROOT}/shared/testutils"
            "${REPO_ROOT}/demo"
        )
    fi

    local fail_count=0
    for mod_path in "${modules[@]}"; do
        [[ -d "$mod_path" ]] || continue
        local mod_name
        mod_name="$(basename "$mod_path")"
        section "lint: $mod_name"

        # gofmt check
        local unformatted
        unformatted=$(gofmt -l "${mod_path}" 2>/dev/null | grep -v vendor || true)
        if [[ -n "$unformatted" ]]; then
            fail "$mod_name: unformatted files (run gofmt -w):"
            echo "$unformatted" >&2
            fail_count=$((fail_count + 1))
        else
            pass "$mod_name: gofmt clean"
        fi

        # go vet
        if (cd "$mod_path" && "$GO" vet ./... 2>/dev/null); then
            pass "$mod_name: go vet"
        else
            fail "$mod_name: go vet failed"
            fail_count=$((fail_count + 1))
        fi

        # golangci-lint (optional)
        if command -v golangci-lint &>/dev/null; then
            if (cd "$mod_path" && golangci-lint run ./...); then
                pass "$mod_name: golangci-lint"
            else
                fail "$mod_name: golangci-lint failed"
                fail_count=$((fail_count + 1))
            fi
        else
            skip "$mod_name: golangci-lint not installed"
        fi
    done

    [[ $fail_count -eq 0 ]] || { info "$fail_count check(s) failed lint"; exit 1; }
    info "all modules passed lint"
}

# ── validate ──────────────────────────────────────────────────────────────────
cmd_validate() {
    info "gate: validate"
    exec "${SCRIPT_DIR}/validate.sh" "$@"
}

# ── test ──────────────────────────────────────────────────────────────────────
cmd_test() {
    info "gate: test"
    exec "${SCRIPT_DIR}/test-stack.sh" "$@"
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "$COMMAND" in
    build)    cmd_build    "$@" ;;
    lint)     cmd_lint     "$@" ;;
    validate) cmd_validate "$@" ;;
    test)     cmd_test     "$@" ;;
    help|-h|--help) usage 0 ;;
    *) warn "Unknown command: $COMMAND"; usage 1 ;;
esac
