#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# hwip.sh — deepspan HWIP developer CLI
#
# Follows the HWIP development lifecycle:
#   setup     Install deepspan-codegen and generate initial artifacts
#   gen       Generate layer artifacts from hwip.yaml (two-stage pipeline)
#   build     Build hwsim, demo-server, demo-client, and Go plugin
#   lint      Go static analysis (golangci-lint)
#   validate  7-check validation of generated artifacts
#   demo      Run full-stack HWIP demo (hwsim + server + client)
#   test      Automated integration tests (curl-based ConnectRPC assertions)
#   check     Full CI gate: build → lint → validate → test
#
# Usage:
#   ./hwip/scripts/hwip.sh <command> [options]
#   ./hwip/scripts/hwip.sh help
#
# Exit code: 0 = success, 1 = failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HWIP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEEPSPAN_ROOT="$(cd "${HWIP_ROOT}/.." && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
hwip_setup_path
HWIP_LOG_PREFIX="[hwip]"

COMMAND="${1:-}"
shift || true

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
deepspan HWIP developer CLI (C++20)

Usage:
  hwip.sh <command> [options]

Lifecycle commands:
  setup     [--skip-codegen]
              Install deepspan-codegen and generate all HWIP artifacts.
              --skip-codegen   Skip codegen after installing the tool

  gen       [--hwip TYPE] [--check] [--all-hwip]
              HWIP codegen pipeline:
                hwip.yaml → gen/{kernel,firmware,sim,rpc,proto,sdk}/
              --hwip TYPE    Run for a single HWIP type only
              --all-hwip     Regenerate all HWIP types
              --check        Dry-run: exit 1 if generated files are stale

  build     [--preset PRESET] [--target TARGET]
              Build HWIP plugin(s) via CMake.
              --preset PRESET   CMake preset (default: dev-hwip)
              --target TARGET   CMake target (default: all)

  validate  [--hwip TYPE] [--fix] [--skip-syntax]
              5-check validation of generated artifacts:
                1. Codegen stale check
                2. C kernel header syntax (gcc -fsyntax-only)
                3. C++ sim header syntax (g++ -std=c++20 -fsyntax-only)
                4. Python syntax (py_compile)
                5. Proto lint (buf lint)
              --hwip TYPE    Validate a single HWIP type
              --fix          Auto-fix stale codegen
              --skip-syntax  Skip C / C++ syntax checks

  demo      [--addr ADDR] [--preset PRESET]
              Run the multi-HWIP Python demo (requires server to be running).
              --addr ADDR    Server address (default: localhost:8080)

  test      [--preset PRESET] [--port N]
              Automated integration tests (ctest + Python smoke test).
              --preset PRESET  CMake preset (default: dev-hwip)
              --port N         Server port (default: 8080)

  check     [--preset PRESET]
              Full CI gate: build → validate → test.

  help      Show this help and exit.
EOF
    exit "${1:-0}"
}

[[ -z "$COMMAND" ]] && usage 1

# ══════════════════════════════════════════════════════════════════════════════
# setup
# ══════════════════════════════════════════════════════════════════════════════
cmd_setup() {
    local skip_codegen=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-codegen) skip_codegen=true; shift ;;
            -h|--help)
                echo "Usage: $0 setup [--skip-codegen]"
                exit 0 ;;
            *) die "Unknown setup option: $1" ;;
        esac
    done

    section "setup: prerequisites"
    local prereq_ok=true
    _check_required() {
        if ! command -v "$1" &>/dev/null; then
            echo -e "  ${RED}[MISSING]${NC} $1${2:+ — $2}"
            prereq_ok=false
        else
            echo -e "  ${GREEN}[OK]${NC}      $1"
        fi
    }
    _check_optional() {
        if ! command -v "$1" &>/dev/null; then
            echo -e "  ${YELLOW}[WARN]${NC}    $1 not found (optional: ${2:-$1})"
        else
            echo -e "  ${GREEN}[OK]${NC}      $1"
        fi
    }
    _check_required python3 "Python 3.11+ required"
    _check_required cmake   "needed for build"
    _check_required gcc     "needed for C syntax check in validate"
    _check_required g++     "needed for C++ syntax check in validate"
    _check_optional uv      "https://docs.astral.sh/uv (needed for Python smoke tests)"
    _check_optional buf     "https://buf.build/docs/installation (needed for proto lint)"
    if [[ "$prereq_ok" != "true" ]]; then
        die "Missing required tools. Install them and re-run."
    fi

    section "setup: deepspan-codegen"
    local CODEGEN_SRC="${DEEPSPAN_ROOT}/codegen"
    [[ -d "$CODEGEN_SRC" ]] || die "deepspan-codegen not found at ${CODEGEN_SRC}"

    if command -v deepspan-codegen &>/dev/null; then
        ok "already installed: $(deepspan-codegen --version 2>/dev/null || echo 'ok')"
    else
        if command -v uv &>/dev/null; then
            uv tool install "$CODEGEN_SRC"
        else
            pip install --quiet "$CODEGEN_SRC"
        fi
        ok "installed from ${CODEGEN_SRC}"
    fi

    if $skip_codegen; then
        log "Skipping codegen (--skip-codegen)"
    else
        section "setup: generate HWIP artifacts"
        local found_hwip=false
        for hwip_dir in "${HWIP_ROOT}"/*/; do
            local hwip_yaml="${hwip_dir}/hwip.yaml"
            if [[ -f "$hwip_yaml" ]]; then
                local hwip_name
                hwip_name="$(basename "${hwip_dir}")"
                log "  -> ${hwip_name}"
                deepspan-codegen --descriptor "$hwip_yaml" --out "${hwip_dir}/gen"
                found_hwip=true
            fi
        done
        $found_hwip || warn "No hwip.yaml found under ${HWIP_ROOT}"
        ok "HWIP artifacts generated"

        section "setup: Python gRPC proto stubs"
        local GEN_PROTO="${DEEPSPAN_ROOT}/sdk/scripts/gen_proto.py"
        if command -v uv &>/dev/null; then
            (cd "${DEEPSPAN_ROOT}/sdk" && \
                uv run --with grpcio-tools python "${GEN_PROTO}") \
                && ok "Python proto stubs generated → sdk/src/deepspan/_proto/" \
                || warn "Python proto stub generation failed (grpcio-tools not available?)"
        else
            python3 "${GEN_PROTO}" \
                && ok "Python proto stubs generated" \
                || warn "Python proto stub generation failed"
        fi
    fi

    echo ""
    echo "Next steps:"
    echo "  ./hwip/scripts/hwip.sh validate    # artifact validation"
    echo "  ./hwip/scripts/hwip.sh build       # build HWIP plugins"
    echo "  ./hwip/scripts/hwip.sh test        # integration tests"
}

# ══════════════════════════════════════════════════════════════════════════════
# gen
# ══════════════════════════════════════════════════════════════════════════════
cmd_gen() {
    local hwip_filter="" check_mode=false all_hwip=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --hwip)     hwip_filter="$2"; shift 2 ;;
            --all-hwip) all_hwip=true; shift ;;
            --check)    check_mode=true; shift ;;
            -h|--help)
                echo "Usage: $0 gen [--hwip TYPE] [--all-hwip] [--check]"
                exit 0 ;;
            *) die "Unknown gen option: $1" ;;
        esac
    done

    command -v deepspan-codegen &>/dev/null \
        || die "deepspan-codegen not found — run: ./hwip/scripts/hwip.sh setup"

    # Discover HWIPs (skip _template and non-hwip dirs)
    local hwips=()
    for hwip_dir in "${HWIP_ROOT}"/*/; do
        local hwip_name
        hwip_name="$(basename "$hwip_dir")"
        [[ "$hwip_name" == "_template" ]] && continue
        [[ -f "$hwip_dir/hwip.yaml" ]] || continue
        [[ -n "$hwip_filter" && "$hwip_name" != "$hwip_filter" ]] && continue
        hwips+=("$hwip_name")
    done
    [[ ${#hwips[@]} -gt 0 ]] \
        || die "No HWIPs found${hwip_filter:+ matching '${hwip_filter}'}"
    log "HWIPs: ${hwips[*]}"

    # hwip.yaml → gen/{kernel,firmware,sim,rpc,proto,sdk}/
    for hwip in "${hwips[@]}"; do
        local hwip_dir="${HWIP_ROOT}/${hwip}"
        if $check_mode; then
            section "gen check: $hwip"
            local TMP_GEN
            TMP_GEN="$(mktemp -d)"
            trap 'rm -rf "$TMP_GEN"' EXIT
            deepspan-codegen --descriptor "${hwip_dir}/hwip.yaml" \
                --out "$TMP_GEN" --target all
            local stale=false
            for layer_dir in "$TMP_GEN"/*/; do
                local layer
                layer="$(basename "$layer_dir")"
                if ! diff -rq \
                        --exclude='__pycache__' --exclude='*.pyc' \
                        "$layer_dir" "${hwip_dir}/gen/${layer}" &>/dev/null; then
                    stale=true
                    warn "STALE: ${hwip}/gen/${layer}/"
                    diff -r --exclude='__pycache__' --exclude='*.pyc' \
                        "$layer_dir" "${hwip_dir}/gen/${layer}" 2>&1 | head -10 >&2 || true
                fi
            done
            if $stale; then
                die "${hwip}/gen/ is stale — run: ./hwip/scripts/hwip.sh gen --hwip ${hwip}"
            fi
            ok "${hwip}/gen/ is up-to-date"
        else
            section "gen: $hwip"
            deepspan-codegen --descriptor "${hwip_dir}/hwip.yaml" \
                --out "${hwip_dir}/gen" --target all
            ok "${hwip} codegen complete → gen/{kernel,firmware,sim,rpc,proto,sdk}/"
        fi
    done

    echo ""
    if $check_mode; then
        ok "All generated files are up-to-date."
    else
        ok "Codegen complete."
        echo "  Commit: git add '*/gen/' && git commit -m 'chore: regenerate HWIP artifacts'"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# build
# ══════════════════════════════════════════════════════════════════════════════
cmd_build() {
    local preset="dev-hwip" target="all"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --preset) preset="$2"; shift 2 ;;
            --target) target="$2"; shift 2 ;;
            -h|--help)
                echo "Usage: $0 build [--preset PRESET] [--target TARGET]"
                exit 0 ;;
            *) die "Unknown build option: $1" ;;
        esac
    done

    section "build: cmake --preset ${preset} --target ${target}"
    cd "${DEEPSPAN_ROOT}"
    cmake --preset "${preset}"
    if [[ "$target" == "all" ]]; then
        cmake --build "build/${preset}" -j"$(nproc)"
    else
        cmake --build "build/${preset}" --target "${target}" -j"$(nproc)"
    fi
    ok "HWIP build complete (preset=${preset})"
}

# ══════════════════════════════════════════════════════════════════════════════
# lint  — delegate to platform dev.sh (clang-tidy)
# ══════════════════════════════════════════════════════════════════════════════
cmd_lint() {
    exec "${DEEPSPAN_ROOT}/scripts/dev.sh" lint "$@"
}

# ══════════════════════════════════════════════════════════════════════════════
# validate
# ══════════════════════════════════════════════════════════════════════════════
cmd_validate() {
    local hwip_filter="" skip_syntax=false fix_mode=false
    local CODEGEN_BIN="${CODEGEN_BIN:-deepspan-codegen}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --hwip)        hwip_filter="$2"; shift 2 ;;
            --skip-syntax) skip_syntax=true; shift ;;
            --fix)         fix_mode=true; shift ;;
            -h|--help)
                echo "Usage: $0 validate [--hwip TYPE] [--fix] [--skip-syntax]"
                exit 0 ;;
            *) die "Unknown validate option: $1" ;;
        esac
    done

    # Discover HWIPs (skip _template — no gen/ directory by design)
    local hwips=()
    for hwip_dir in "${HWIP_ROOT}"/*/; do
        local hwip_name
        hwip_name="$(basename "$hwip_dir")"
        [[ "$hwip_name" == "_template" ]] && continue
        [[ -f "$hwip_dir/hwip.yaml" ]] || continue
        [[ -n "$hwip_filter" && "$hwip_name" != "$hwip_filter" ]] && continue
        hwips+=("$hwip_name")
    done
    [[ ${#hwips[@]} -gt 0 ]] \
        || die "No HWIPs found${hwip_filter:+ matching '${hwip_filter}'}"
    log "Validating HWIPs: ${hwips[*]}"

    # ── Check 1: Codegen stale ─────────────────────────────────────────────────
    section "validate: Check 1 — codegen stale"
    if ! command -v "$CODEGEN_BIN" &>/dev/null; then
        skip "deepspan-codegen not found (set CODEGEN_BIN or run: hwip.sh setup)"
    else
        for hwip in "${hwips[@]}"; do
            local TMP_GEN
            TMP_GEN="$(mktemp -d)"
            "$CODEGEN_BIN" \
                --descriptor "${HWIP_ROOT}/${hwip}/hwip.yaml" \
                --out "$TMP_GEN" --target all >/dev/null 2>&1
            local stale=false
            for layer_dir in "$TMP_GEN"/*/; do
                [[ -d "$layer_dir" ]] || continue
                local layer
                layer="$(basename "$layer_dir")"
                if ! diff -rq \
                        --exclude='__pycache__' --exclude='*.pyc' \
                        "$layer_dir" "${HWIP_ROOT}/${hwip}/gen/${layer}" &>/dev/null; then
                    stale=true
                fi
            done
            if ! $stale; then
                pass "${hwip}/gen/ is up-to-date"
            elif $fix_mode; then
                "$CODEGEN_BIN" \
                    --descriptor "${HWIP_ROOT}/${hwip}/hwip.yaml" \
                    --out "${HWIP_ROOT}/${hwip}/gen" --target all >/dev/null
                pass "${hwip}/gen/ regenerated"
            else
                fail "${hwip}/gen/ is stale — run: hwip.sh gen --hwip ${hwip}"
            fi
            rm -rf "$TMP_GEN"
        done
    fi

    # ── Check 2: C kernel header syntax ───────────────────────────────────────
    section "validate: Check 2 — C kernel header syntax (gen/kernel/)"
    if $skip_syntax; then
        skip "skipped via --skip-syntax"
    elif ! command -v gcc &>/dev/null; then
        skip "gcc not found"
    else
        for hwip in "${hwips[@]}"; do
            local gen_dir="${HWIP_ROOT}/${hwip}/gen"
            while IFS= read -r -d '' hfile; do
                local rel="${hfile#"${HWIP_ROOT}"/}"
                if gcc -fsyntax-only -x c -std=gnu11 \
                    -isystem /usr/include \
                    -Wno-unused-macros -Wno-redundant-decls \
                    "$hfile" 2>/dev/null; then
                    pass "$rel"
                else
                    local errs
                    errs="$(gcc -fsyntax-only -x c -std=gnu11 \
                        -isystem /usr/include "$hfile" 2>&1 | grep ': error:' | head -5)"
                    if [[ -n "$errs" ]]; then
                        fail "$rel — C syntax error"; echo "$errs" >&2
                    else
                        pass "$rel (warnings only)"
                    fi
                fi
            done < <(find "${gen_dir}/kernel" -name "*.h" -print0 2>/dev/null)
        done
    fi

    # ── Check 3: C++20 gen/sim + gen/rpc header syntax ────────────────────────
    section "validate: Check 3 — C++20 header syntax (gen/sim/ + gen/rpc/)"
    if $skip_syntax; then
        skip "skipped via --skip-syntax"
    elif ! command -v g++ &>/dev/null; then
        skip "g++ not found"
    else
        for hwip in "${hwips[@]}"; do
            local gen_dir="${HWIP_ROOT}/${hwip}/gen"
            while IFS= read -r -d '' hfile; do
                local rel="${hfile#"${HWIP_ROOT}"/}"
                if g++ -fsyntax-only -x c++ -std=c++20 \
                    -Wno-unused-variable "$hfile" 2>/dev/null; then
                    pass "$rel"
                else
                    local errs
                    errs="$(g++ -fsyntax-only -x c++ -std=c++20 \
                        "$hfile" 2>&1 | grep ': error:' | head -5)"
                    if [[ -n "$errs" ]]; then
                        fail "$rel — C++ syntax error"; echo "$errs" >&2
                    else
                        pass "$rel (warnings only)"
                    fi
                fi
            done < <(find "${gen_dir}/sim" "${gen_dir}/rpc" -name "*.hpp" -print0 2>/dev/null)
        done
    fi

    # ── Check 4: Python syntax ─────────────────────────────────────────────────
    section "validate: Check 4 — Python syntax (gen/sdk/)"
    if ! command -v python3 &>/dev/null; then
        skip "python3 not found"
    else
        for hwip in "${hwips[@]}"; do
            local gen_dir="${HWIP_ROOT}/${hwip}/gen"
            while IFS= read -r -d '' pyfile; do
                local rel="${pyfile#"${HWIP_ROOT}"/}"
                if python3 -m py_compile "$pyfile" 2>/dev/null; then
                    pass "$rel"
                else
                    fail "$rel — Python syntax error"
                    python3 -m py_compile "$pyfile" 2>&1 >&2 || true
                fi
            done < <(find "${gen_dir}/sdk" -name "*.py" -print0 2>/dev/null)
        done
    fi

    # ── Check 5: Proto lint ────────────────────────────────────────────────────
    section "validate: Check 5 — Proto lint (gen/proto/)"
    if ! command -v buf &>/dev/null; then
        skip "buf not found"
    else
        for hwip in "${hwips[@]}"; do
            local proto_dir="${HWIP_ROOT}/${hwip}/gen/proto"
            if [[ ! -d "$proto_dir" ]]; then
                skip "${hwip}/gen/proto/ not found"; continue
            fi
            local CFG='{"version":"v2","lint":{"use":["DEFAULT"],"except":["PACKAGE_VERSION_SUFFIX"]}}'
            if buf lint --config "$CFG" "$proto_dir" 2>/dev/null; then
                pass "${hwip}/gen/proto/ — lint OK"
            else
                local lint_out
                lint_out="$(buf lint --config "$CFG" "$proto_dir" 2>&1 | head -20)"
                if [[ -n "$lint_out" ]]; then
                    fail "${hwip}/gen/proto/ — lint failed"; echo "$lint_out" >&2
                else
                    pass "${hwip}/gen/proto/ — lint OK"
                fi
            fi
        done
    fi

    # ── Summary ────────────────────────────────────────────────────────────────
    [[ $FAIL -gt 0 ]] && echo ""
    hwip_summary || {
        echo "Fix issues above, or run with --fix for auto-fixable checks."
        exit 1
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# demo
# ══════════════════════════════════════════════════════════════════════════════
cmd_demo() {
    local addr="localhost:8080" preset="dev-hwip"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --addr)   addr="$2"; shift 2 ;;
            --preset) preset="$2"; shift 2 ;;
            -h|--help)
                echo "Usage: $0 demo [--addr ADDR] [--preset PRESET]"
                exit 0 ;;
            *) die "Unknown demo option: $1" ;;
        esac
    done

    section "demo: Python multi-HWIP demo"
    info "Connecting to deepspan-server at ${addr}"
    info "(Start server first: build/dev-hwip/server/deepspan-server --hwip-plugin ...)"

    if command -v uv &>/dev/null; then
        (cd "${DEEPSPAN_ROOT}/sdk" && \
            uv run python "${HWIP_ROOT}/demo/demo.py" --addr "${addr}")
    else
        python3 "${HWIP_ROOT}/demo/demo.py" --addr "${addr}"
    fi
    ok "demo complete"
}

# ══════════════════════════════════════════════════════════════════════════════
# test
# ══════════════════════════════════════════════════════════════════════════════
cmd_test() {
    local preset="dev-hwip" port=8080

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --preset) preset="$2"; shift 2 ;;
            --port)   port="$2"; shift 2 ;;
            -h|--help)
                echo "Usage: $0 test [--preset PRESET] [--port N]"
                exit 0 ;;
            *) die "Unknown test option: $1" ;;
        esac
    done

    section "test: ctest (preset=${preset})"
    cd "${DEEPSPAN_ROOT}"
    ctest --preset "${preset}" --output-on-failure -j"$(nproc)"
    ok "ctest passed"

    section "test: Python smoke test"
    local SERVER_BIN="${DEEPSPAN_ROOT}/build/${preset}/server/deepspan-server"
    local ACCEL_SO="${DEEPSPAN_ROOT}/build/${preset}/hwip/accel/plugin/libhwip_accel.so"
    local SERVER_PID=""
    cleanup_test() {
        [[ -n "${SERVER_PID}" ]] && kill "$SERVER_PID" 2>/dev/null || true
        wait 2>/dev/null || true
    }
    trap cleanup_test EXIT

    if [[ ! -f "$SERVER_BIN" ]]; then
        warn "server binary not found — skipping Python smoke test"
        return 0
    fi

    "${SERVER_BIN}" --addr ":${port}" \
        ${ACCEL_SO:+--hwip-plugin "${ACCEL_SO}"} \
        >/dev/null 2>&1 &
    SERVER_PID=$!
    wait_port "localhost" "${port}" 10

    section "test: suite"

    # T1: Python SDK — list_devices returns at least one device
    log "T1: SDK list_devices"
    if command -v uv &>/dev/null; then
        (cd "${DEEPSPAN_ROOT}/sdk" && uv run python3 -c "
from deepspan import DeepspanClient
c = DeepspanClient('localhost:${port}')
devs = c.list_devices()
assert len(devs) > 0, 'no devices returned'
print('  devices:', [d.device_id for d in devs])
c.close()
") && pass "T1: list_devices returned devices" \
       || fail "T1: list_devices failed"
    else
        skip "T1: uv not found (skipping Python SDK smoke test)"
    fi

    # T2: Python SDK — submit_request to first device
    log "T2: SDK submit_request (opcode=0x0001)"
    if command -v uv &>/dev/null; then
        (cd "${DEEPSPAN_ROOT}/sdk" && uv run python3 -c "
from deepspan import DeepspanClient
c = DeepspanClient('localhost:${port}')
devs = c.list_devices()
if devs:
    req_id = c.submit_request(devs[0].device_id, opcode=0x0001)
    assert req_id, 'empty request_id'
    print('  request_id:', req_id)
c.close()
") && pass "T2: submit_request returned request_id" \
       || fail "T2: submit_request failed"
    else
        skip "T2: uv not found"
    fi

    hwip_summary || exit 1
}

# ══════════════════════════════════════════════════════════════════════════════
# check  (full CI gate)
# ══════════════════════════════════════════════════════════════════════════════
cmd_check() {
    local preset="dev-hwip"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --preset) preset="$2"; shift 2 ;;
            -h|--help)
                echo "Usage: $0 check [--preset PRESET]"
                exit 0 ;;
            *) die "Unknown check option: $1" ;;
        esac
    done

    section "check: build"
    cmd_build --preset "${preset}"

    section "check: validate"
    cmd_validate

    section "check: lint"
    cmd_lint

    section "check: test"
    cmd_test --preset "${preset}"

    echo ""
    ok "=== All HWIP checks passed ==="
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "$COMMAND" in
    setup)    cmd_setup    "$@" ;;
    gen)      cmd_gen      "$@" ;;
    build)    cmd_build    "$@" ;;
    lint)     cmd_lint     "$@" ;;
    validate) cmd_validate "$@" ;;
    demo)     cmd_demo     "$@" ;;
    test)     cmd_test     "$@" ;;
    check)    cmd_check    "$@" ;;
    help|-h|--help) usage 0 ;;
    *) warn "Unknown command: ${COMMAND}"; usage 1 ;;
esac
