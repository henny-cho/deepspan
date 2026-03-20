#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# lib.sh — shared helpers for deepspan-hwip scripts.
#
# Source this file; do not execute directly.
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#
# Provides:
#   Colors        : GREEN RED YELLOW RESET
#   hwip_setup_path : prepend standard tool dirs to PATH
#   PASS/FAIL/SKIP  : running counters (initialised to 0 on first source)
#   pass/fail/skip  : record a result and print coloured line
#   section / info / warn / die : output helpers
#   wait_port ADDR [TIMEOUT_S]  : poll /dev/tcp until port open

# Guard against double-sourcing.
[[ -n "${_HWIP_LIB_LOADED:-}" ]] && return 0
_HWIP_LIB_LOADED=1

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# ── PATH setup ────────────────────────────────────────────────────────────────
hwip_setup_path() {
    export PATH="/usr/local/go/bin:${HOME}/go/bin:${HOME}/.local/bin:${PATH}"
}

# ── Pass / fail / skip counters ───────────────────────────────────────────────
PASS=${PASS:-0}
FAIL=${FAIL:-0}
SKIP=${SKIP:-0}

pass() { PASS=$((PASS + 1)); echo -e "  ${GREEN}[PASS]${RESET} $*"; }
fail() { FAIL=$((FAIL + 1)); echo -e "  ${RED}[FAIL]${RESET} $*"; }
skip() { SKIP=$((SKIP + 1)); echo -e "  ${YELLOW}[SKIP]${RESET} $*"; }

# ── Generic output helpers ────────────────────────────────────────────────────
# HWIP_LOG_PREFIX may be set by the caller (default: script basename).
_hwip_prefix() { echo "${HWIP_LOG_PREFIX:-[$(basename "${BASH_SOURCE[2]:-lib.sh}" .sh)]}"; }

section() { echo -e "\n── $* ──────────────────────────────────────────"; }
info()    { echo -e "${GREEN}$(_hwip_prefix)${RESET} $*"; }
warn()    { echo -e "${YELLOW}$(_hwip_prefix)${RESET} $*"; }
die()     { echo -e "${RED}$(_hwip_prefix) FATAL${RESET}: $*" >&2; exit 1; }

# ── Port readiness check ──────────────────────────────────────────────────────
# Usage: wait_port ADDR [TIMEOUT_S=12]
# ADDR is host:port or :port (localhost assumed).
# Uses /dev/tcp (bash built-in, no curl needed).
wait_port() {
    local addr="$1"
    local timeout="${2:-12}"
    local port="${addr##*:}"
    local deadline=$((SECONDS + timeout))
    while ! (</dev/tcp/127.0.0.1/"$port") 2>/dev/null; do
        [[ $SECONDS -ge $deadline ]] && die "port ${addr} did not open within ${timeout}s"
        sleep 0.2
    done
}

# ── Summary printer ───────────────────────────────────────────────────────────
# Usage: hwip_summary
# Prints PASS/FAIL/SKIP counts and exits non-zero if FAIL > 0.
hwip_summary() {
    echo ""
    echo "══════════════════════════════════════════════════════════════════"
    printf "  Results: %d passed, %d failed, %d skipped\n" "$PASS" "$FAIL" "$SKIP"
    echo "══════════════════════════════════════════════════════════════════"
    if [[ $FAIL -gt 0 ]]; then
        echo "FAILED"
        return 1
    else
        echo "OK"
        return 0
    fi
}
