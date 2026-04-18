#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# lib.sh — unified shared helpers for all deepspan scripts (platform + hwip).
#
# Source this file; do not execute directly.
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#
# Provides:
#   Colors     : GREEN RED YELLOW BOLD NC/RESET
#   setup_path : prepend standard tool dirs to PATH
#   should_skip : check layer against SKIP_LAYERS array
#   section / log / ok / warn / die : prefixed output helpers
#   info       : alias for ok
#   pass/fail/skip : test-result counters (PASS/FAIL/SKIP globals)
#   hwip_summary : print pass/fail/skip totals and return exit code
#   wait_port  : poll a TCP port or HTTP endpoint until ready

# Guard against double-sourcing.
[[ -n "${_DS_LIB_LOADED:-}" ]] && return 0
_DS_LIB_LOADED=1

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'
RESET='\033[0m'   # alias for NC

# ── PATH setup ────────────────────────────────────────────────────────────────
setup_path() {
    export PATH="/usr/local/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"
}
# Backward-compatible aliases
ds_setup_path()   { setup_path; }
hwip_setup_path() { setup_path; }

# ── Layer skip helper ─────────────────────────────────────────────────────────
# Usage: should_skip <layer>  — returns 0 if layer is in SKIP_LAYERS.
# SKIP_LAYERS must be declared as an array in the calling script.
should_skip() {
    local layer="$1" s
    [[ ${#SKIP_LAYERS[@]} -eq 0 ]] && return 1
    for s in "${SKIP_LAYERS[@]}"; do [[ "$s" == "$layer" ]] && return 0; done
    return 1
}

# ── Logging helpers ───────────────────────────────────────────────────────────
# DS_LOG_PREFIX or HWIP_LOG_PREFIX may be set for context; falls back to
# the calling script's basename.
_log_prefix() {
    echo "${DS_LOG_PREFIX:-${HWIP_LOG_PREFIX:-[$(basename "${BASH_SOURCE[2]:-lib.sh}" .sh)]}}"
}

section() { echo -e "\n${BOLD}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
log()     { echo -e "${BOLD}$(_log_prefix)${NC} $*"; }
ok()      { echo -e "${GREEN}${BOLD}$(_log_prefix) $*${NC}"; }
info()    { echo -e "${GREEN}$(_log_prefix)${NC} $*"; }   # alias for ok (lighter)
warn()    { echo -e "${YELLOW}$(_log_prefix) $*${NC}"; }
die()     { echo -e "${RED}${BOLD}$(_log_prefix) FATAL: $*${NC}" >&2; exit 1; }

# ── Test-result counters ──────────────────────────────────────────────────────
PASS=${PASS:-0}
FAIL=${FAIL:-0}
SKIP=${SKIP:-0}

pass() { PASS=$((PASS + 1)); echo -e "  ${GREEN}[PASS]${NC} $*"; }
fail() { FAIL=$((FAIL + 1)); echo -e "  ${RED}[FAIL]${NC} $*"; }
skip() { SKIP=$((SKIP + 1)); echo -e "  ${YELLOW}[SKIP]${NC} $*"; }

# ── Summary printer ───────────────────────────────────────────────────────────
# Usage: hwip_summary — prints results and returns 1 if FAIL > 0.
hwip_summary() {
    echo ""
    echo "══════════════════════════════════════════════════════════════════"
    printf "  Results: %d passed, %d failed, %d skipped\n" "$PASS" "$FAIL" "$SKIP"
    echo "══════════════════════════════════════════════════════════════════"
    if [[ $FAIL -gt 0 ]]; then
        echo "FAILED"
        return 1
    fi
    echo "OK"
}

# ── Layer argument parsing helper ────────────────────────────────────────────
# Usage: parse_layers_args "$@"
# Expects callers to declare LAYERS, SKIP_LAYERS arrays and ALL_LAYERS.
# Sets LAYERS from --layers, appends to SKIP_LAYERS from --skip.
parse_layers_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --layers) IFS=',' read -ra LAYERS <<< "$2"; shift 2 ;;
            --skip)   IFS=',' read -ra SKIP_LAYERS <<< "$2"; shift 2 ;;
            -h|--help)
                echo "Usage: $0 [--layers <l1,l2,...>] [--skip <l1,l2,...>]"
                echo "Layers: ${ALL_LAYERS[*]}"
                exit 0 ;;
            *) die "Unknown option: $1" ;;
        esac
    done
}

# ── Port readiness check ──────────────────────────────────────────────────────
# Usage: wait_port HOST PORT [TIMEOUT_S=30] [HTTP_PATH=/healthz]
#   or:  wait_port :PORT [TIMEOUT_S=30]        (localhost assumed)
# Checks /dev/tcp first (TCP accept is sufficient for gRPC and other
# non-HTTP services); falls back to HTTP /healthz for services that
# expose it. TCP-first avoids spawning a curl per poll iteration.
wait_port() {
    local arg1="$1"
    local timeout="${3:-30}"
    local http_path="${4:-/healthz}"
    local host port

    # Accept both "HOST PORT" and "HOST:PORT" or ":PORT" forms
    if [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]]; then
        host="$1"; port="$2"
    else
        host="${arg1%:*}"; host="${host:-127.0.0.1}"
        port="${arg1##*:}"
        timeout="${2:-30}"
        http_path="${3:-/healthz}"
    fi

    local deadline=$((SECONDS + timeout))
    while [[ $SECONDS -lt $deadline ]]; do
        if (</dev/tcp/"$host"/"$port") 2>/dev/null; then
            return 0
        fi
        if curl -sf "http://${host}:${port}${http_path}" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.3
    done
    die "port ${host}:${port} did not become ready within ${timeout}s"
}
