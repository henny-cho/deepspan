#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# lib.sh — shared helpers for deepspan scripts.
#
# Source this file; do not execute directly.
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#
# Provides:
#   Colors     : GREEN RED YELLOW BOLD NC (NC = no-colour / reset)
#   ds_setup_path  : prepend standard tool dirs to PATH
#   should_skip    : check layer against SKIP_LAYERS array
#   log / ok / warn / die / section : prefixed output helpers
#   wait_port HOST PORT [TIMEOUT_S] [PATH] : poll HTTP endpoint

# Guard against double-sourcing.
[[ -n "${_DS_LIB_LOADED:-}" ]] && return 0
_DS_LIB_LOADED=1

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'   # no colour / reset

# ── PATH setup ────────────────────────────────────────────────────────────────
# Call once near top of each script after sourcing lib.sh.
ds_setup_path() {
    export PATH="/usr/local/go/bin:${HOME}/go/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"
}

# ── Layer skip helper ─────────────────────────────────────────────────────────
# Usage: should_skip <layer>
# Returns 0 (true) if the layer is in SKIP_LAYERS array.
# SKIP_LAYERS must be declared as an array in the calling script.
should_skip() {
    local layer="$1"
    if [[ ${#SKIP_LAYERS[@]} -eq 0 ]]; then return 1; fi
    local s
    for s in "${SKIP_LAYERS[@]}"; do
        [[ "$s" == "$layer" ]] && return 0
    done
    return 1
}

# ── Logging helpers ───────────────────────────────────────────────────────────
# DS_LOG_PREFIX may be set by the caller for context (default: script basename).
_ds_prefix() { echo "${DS_LOG_PREFIX:-[$(basename "${BASH_SOURCE[2]:-lib.sh}" .sh)]}"; }

log()     { echo -e "${BOLD}$(_ds_prefix)${NC} $*"; }
ok()      { echo -e "${GREEN}${BOLD}$(_ds_prefix) $*${NC}"; }
warn()    { echo -e "${YELLOW}$(_ds_prefix) $*${NC}"; }
die()     { echo -e "${RED}${BOLD}$(_ds_prefix) FATAL: $*${NC}" >&2; exit 1; }
section() { echo -e "\n${BOLD}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ── Port readiness check ──────────────────────────────────────────────────────
# Usage: wait_port HOST PORT [TIMEOUT_S=30] [HTTP_PATH=/healthz]
# Polls http://HOST:PORT/HTTP_PATH with curl until HTTP 200 or timeout.
wait_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-30}"
    local path="${4:-/healthz}"
    local deadline=$((SECONDS + timeout))
    while [[ $SECONDS -lt $deadline ]]; do
        if curl -sf "http://${host}:${port}${path}" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.3
    done
    die "port ${host}:${port} did not become ready within ${timeout}s"
}
