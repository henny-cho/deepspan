#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# hw-model: verify required tools are installed
set -euo pipefail

FAILED=()

check_cmd() { command -v "$1" &>/dev/null || FAILED+=("command: $1"); }
check_lib()  { pkg-config --exists "$1" 2>/dev/null || FAILED+=("pkg-config: $1"); }
check_ver()  {
    local cmd="$1" want="$2" got
    got=$($cmd --version 2>&1 | head -1)
    echo "    $cmd: $got"
}

echo "--- [hw-model] ---"
check_cmd cmake;       check_ver cmake "3.25"
check_cmd ninja;       check_ver ninja ""
check_cmd g++;         check_ver g++ ""
check_cmd clang++;     check_ver clang++ ""
check_cmd clang-tidy
check_cmd clang-format
check_lib liburing

# GTest headers
if ! dpkg -l libgtest-dev &>/dev/null 2>&1; then
    FAILED+=("package: libgtest-dev")
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "  MISSING: ${FAILED[*]}" >&2
    exit 1
fi
echo "  OK"
