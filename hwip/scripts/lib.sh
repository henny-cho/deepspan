#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# hwip/scripts/lib.sh — thin shim; all logic lives in scripts/lib.sh.
#
# Source this file; do not execute directly.
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Guard against double-sourcing.
[[ -n "${_DS_LIB_LOADED:-}" ]] && return 0

_HWIP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/lib.sh
source "${_HWIP_SCRIPT_DIR}/../../scripts/lib.sh"
