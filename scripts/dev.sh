#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# dev.sh — deepspan developer CLI
#
# Follows the development lifecycle:
#   setup     Install toolchains, git hooks, and lint tools
#   gen       Generate code from proto / hwip.yaml specs
#   build     Compile all layers and report results
#   lint      Go static analysis (golangci-lint)
#   test      Full-stack simulation test (or HWIP integration tests)
#   validate  Validate generated HWIP artifacts (7-check)
#   check     Full CI gate: build → lint → test → validate
#
# Usage:
#   ./scripts/dev.sh <command> [options]
#   ./scripts/dev.sh help
#
# Exit code: 0 = success, 1 = failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEEPSPAN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
ds_setup_path
DS_LOG_PREFIX="[dev]"

COMMAND="${1:-}"
shift || true

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
deepspan developer CLI (C++20 platform)

Usage:
  dev.sh <command> [options]

Lifecycle commands:
  setup     [--layers L1,L2] [--skip L1] [--hooks] [--lint-tools] [--verify-only]
              Install dev toolchains and verify the environment.
              --hooks        Also install git pre-commit hooks
              --lint-tools   Also install clang-tidy
              --verify-only  Skip install; only verify existing toolchains

  gen       [--skip-hwip] [--hwip TYPE] [--check]
              Generate HWIP layer artifacts from hwip.yaml.
              --skip-hwip    Skip HWIP codegen stage
              --hwip TYPE    Run HWIP codegen for one type only
              --check        Dry-run: exit 1 if generated files are stale

  build     [--preset PRESET]
              Build via CMake (single command: cmake --preset + cmake --build).
              --preset PRESET  CMake preset (default: dev)

  build clean  [--preset PRESET] [--all]
              Remove CMake build directory.
              --preset PRESET  CMake preset (default: dev)
              --all            Remove all build/ subdirectories

  lint      [--strict]
              Run clang-tidy on all C++ source files.
              --strict       Exit 1 on any lint warning (default: warn only)

  test      [--no-build] [--preset PRESET]
              Full-stack simulation: hw-model → server → SDK hello-world.
              --no-build     Skip build; use existing binaries
              --preset PRESET  CMake preset (default: dev)

  validate  [--hwip TYPE] [--fix] [--skip-syntax]
              Run validation checks on generated HWIP artifacts.
              --hwip TYPE    Validate a single HWIP type
              --fix          Auto-fix stale codegen issues
              --skip-syntax  Skip C / C++ syntax checks

  check     [--preset PRESET]
              Full CI gate: build → lint → test → validate.

  help      Show this help and exit.
EOF
    exit "${1:-0}"
}

[[ -z "$COMMAND" ]] && usage 1

# ══════════════════════════════════════════════════════════════════════════════
# setup
# ══════════════════════════════════════════════════════════════════════════════
cmd_setup() {
    local verify_only=0 install_hooks=0 install_lint=0
    ALL_LAYERS=(sim/hw-model firmware kernel runtime/userlib runtime/appframework sdk)
    LAYERS=("${ALL_LAYERS[@]}")
    SKIP_LAYERS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --layers)      IFS=',' read -ra LAYERS <<< "$2"; shift 2 ;;
            --skip)        IFS=',' read -ra SKIP_LAYERS <<< "$2"; shift 2 ;;
            --hooks)       install_hooks=1; shift ;;
            --lint-tools)  install_lint=1;  shift ;;
            --verify-only) verify_only=1; shift ;;
            -h|--help)
                echo "Usage: $0 setup [--layers L1,L2] [--skip L1] [--hooks] [--lint-tools] [--verify-only]"
                exit 0 ;;
            *) die "Unknown setup option: $1" ;;
        esac
    done

    # ── Install stage ──────────────────────────────────────────────────────────
    if [[ $verify_only -eq 0 ]]; then
        section "setup: common packages"
        sudo apt-get update -qq
        sudo apt-get install -y --no-install-recommends \
            git curl wget ca-certificates gnupg lsb-release \
            software-properties-common python3 python3-pip python3-venv pipx

        local FAILED=()
        for layer in "${LAYERS[@]}"; do
            if should_skip "$layer"; then
                echo -e "${YELLOW}  [SKIP] ${layer}${NC}"
                continue
            fi
            local script="${DEEPSPAN_ROOT}/${layer}/scripts/setup-dev.sh"
            if [[ ! -f "$script" ]]; then
                echo -e "${RED}  [MISSING] ${layer}/scripts/setup-dev.sh${NC}"
                FAILED+=("$layer")
                continue
            fi
            section "setup: $layer"
            bash "$script" || FAILED+=("$layer")
        done

        # West workspace init (after firmware tools are ready)
        if [[ " ${LAYERS[*]} " == *"firmware"* ]] && ! should_skip firmware; then
            section "setup: west workspace"
            cd "${DEEPSPAN_ROOT}"
            if [[ ! -d .west ]]; then
                log "west init..."
                west init -l .
            fi
            log "west update (this may take a while)..."
            west update --narrow -o=--depth=1
            log "Installing Zephyr Python requirements in venv..."
            python3 -m venv "${DEEPSPAN_ROOT}/.venv-zephyr"
            "${DEEPSPAN_ROOT}/.venv-zephyr/bin/pip" install \
                -r zephyr/scripts/requirements.txt
        fi

        # Git submodules
        section "setup: git submodules"
        cd "${DEEPSPAN_ROOT}"
        git submodule update --init --recursive

        if [[ ${#FAILED[@]} -gt 0 ]]; then
            die "Failed layers: ${FAILED[*]}"
        fi
    fi

    # ── Optional: git hooks ────────────────────────────────────────────────────
    if [[ $install_hooks -eq 1 ]]; then
        section "setup: git hooks"
        cd "${DEEPSPAN_ROOT}"
        git config core.hooksPath .githooks
        ok "git hooks installed from .githooks/"
    fi

    # ── Optional: clang-tidy ───────────────────────────────────────────────────
    if [[ $install_lint -eq 1 ]]; then
        section "setup: clang-tidy"
        if command -v clang-tidy &>/dev/null; then
            ok "clang-tidy already installed: $(clang-tidy --version | head -1)"
        else
            log "Installing clang-tidy..."
            sudo apt-get install -y --no-install-recommends clang-tidy
            ok "clang-tidy installed: $(clang-tidy --version | head -1)"
        fi
    fi

    # ── Verify stage ───────────────────────────────────────────────────────────
    section "setup: verify toolchains"
    declare -A VERIFY_RESULTS=()
    for layer in "${LAYERS[@]}"; do
        local vscript="${DEEPSPAN_ROOT}/${layer}/scripts/verify-setup.sh"
        if should_skip "$layer"; then
            VERIFY_RESULTS[$layer]="SKIP"
        elif [[ ! -f "$vscript" ]]; then
            VERIFY_RESULTS[$layer]="FAIL"
        elif bash "$vscript" \
                2>/tmp/ds-verify-${layer//\//-}.err; then
            VERIFY_RESULTS[$layer]="OK"
        else
            VERIFY_RESULTS[$layer]="FAIL"
        fi
    done

    echo ""
    echo -e "${BOLD}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}│  Toolchain verification                          │${NC}"
    echo -e "${BOLD}├──────────────────────┬───────────────────────────┤${NC}"
    printf "${BOLD}│ %-20s │ %-25s │${NC}\n" "Layer" "Status"
    echo -e "${BOLD}├──────────────────────┼───────────────────────────┤${NC}"
    local FAIL_COUNT=0
    for layer in "${LAYERS[@]}"; do
        local result="${VERIFY_RESULTS[$layer]:-SKIP}"
        local colour label
        case "$result" in
            OK)   colour="${GREEN}";  label="OK" ;;
            FAIL) colour="${RED}";    label="MISSING — run setup first"; ((FAIL_COUNT++)) ;;
            SKIP) colour="${YELLOW}"; label="skipped" ;;
            *)    colour="${NC}";     label="$result" ;;
        esac
        printf "│ %-20s │ ${colour}%-25s${NC} │\n" "$layer" "$label"
    done
    echo -e "${BOLD}└──────────────────────┴───────────────────────────┘${NC}"
    echo ""

    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo -e "${RED}${BOLD}${FAIL_COUNT} layer(s) missing tools.${NC}"
        echo "  Re-run:  ./scripts/dev.sh setup --layers <failed-layers>"
        exit 1
    fi
    ok "all toolchains verified"

    if [[ $verify_only -eq 0 ]]; then
        echo ""
        echo "Next steps:"
        echo "  1. Reload shell:     source ~/.profile"
        echo "  2. Generate code:    ./scripts/dev.sh gen"
        echo "  3. Build all:        ./scripts/dev.sh build"
        echo "  4. Run tests:        ./scripts/dev.sh test"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# gen
# ══════════════════════════════════════════════════════════════════════════════
cmd_gen() {
    local skip_hwip=false hwip_filter="" check_mode=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-hwip) skip_hwip=true; shift ;;
            --hwip)      hwip_filter="$2"; shift 2 ;;
            --check)     check_mode=true; shift ;;
            -h|--help)
                echo "Usage: $0 gen [--skip-hwip] [--hwip TYPE] [--check]"
                exit 0 ;;
            *) die "Unknown gen option: $1" ;;
        esac
    done

    # ── HWIP codegen (deepspan-codegen → gen/{kernel,firmware,sim,rpc,proto,sdk}/) ──
    if $skip_hwip; then
        log "Skipping HWIP codegen (--skip-hwip)"
        return 0
    fi

    section "gen: HWIP codegen"
    if ! command -v deepspan-codegen &>/dev/null; then
        die "deepspan-codegen not found — run: uv tool install codegen/"
    fi

    _run_hwip_codegen() {
        local hwip_type="$1"
        local hwip_dir="${DEEPSPAN_ROOT}/hwip/${hwip_type}"

        if $check_mode; then
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
                        "$layer_dir" "${hwip_dir}/gen/$layer" &>/dev/null; then
                    stale=true
                    warn "STALE: ${hwip_type}/gen/${layer}/"
                fi
            done
            if $stale; then
                die "${hwip_type}/gen/ is stale — run: ./scripts/dev.sh gen --hwip ${hwip_type}"
            fi
            ok "${hwip_type}/gen/ is up-to-date"
        else
            log "${hwip_type}: deepspan-codegen..."
            deepspan-codegen --descriptor "${hwip_dir}/hwip.yaml" \
                --out "${hwip_dir}/gen" --target all
            ok "${hwip_type} codegen complete"
        fi
    }

    if [[ -n "$hwip_filter" ]]; then
        _run_hwip_codegen "$hwip_filter"
    else
        for hwip_dir in "${DEEPSPAN_ROOT}/hwip"/*/; do
            [[ -f "${hwip_dir}/hwip.yaml" ]] || continue
            _run_hwip_codegen "$(basename "${hwip_dir}")"
        done
    fi

    if ! $check_mode; then
        echo ""
        ok "Codegen complete."
        echo "  Generated:  hwip/*/gen/{kernel,firmware,sim,rpc,proto,sdk}/"
        echo ""
        echo "Next: git add hwip/*/gen/ && git commit -m 'chore: regenerate HWIP artifacts'"
    fi

    # ── Python gRPC proto stubs (api/proto/ → sdk/src/deepspan/_proto/) ──────
    if ! $check_mode && ! $skip_hwip; then
        section "gen: Python gRPC proto stubs"
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
}

# ══════════════════════════════════════════════════════════════════════════════
# build clean
# ══════════════════════════════════════════════════════════════════════════════
cmd_build_clean() {
    local preset="dev" clean_all=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --preset) preset="$2"; shift 2 ;;
            --all)    clean_all=1; shift ;;
            -h|--help)
                echo "Usage: $0 build clean [--preset PRESET] [--all]"
                exit 0 ;;
            *) die "Unknown clean option: $1" ;;
        esac
    done

    if [[ $clean_all -eq 1 ]]; then
        section "clean: all build/ directories"
        rm -rf "${DEEPSPAN_ROOT}/build"
        ok "build/ removed"
    else
        local build_dir="${DEEPSPAN_ROOT}/build/${preset}"
        section "clean: build/${preset}"
        if [[ -d "$build_dir" ]]; then
            rm -rf "$build_dir"
            ok "build/${preset}/ removed"
        else
            log "nothing to clean (build/${preset}/ not found)"
        fi
    fi

    ok "clean complete"
}

# ══════════════════════════════════════════════════════════════════════════════
# build
# ══════════════════════════════════════════════════════════════════════════════
cmd_build() {
    # Sub-command: clean
    if [[ "${1:-}" == "clean" ]]; then
        shift
        cmd_build_clean "$@"
        return
    fi

    local preset="dev"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --preset) preset="$2"; shift 2 ;;
            -h|--help)
                echo "Usage: $0 build [--preset PRESET]"
                exit 0 ;;
            *) die "Unknown build option: $1" ;;
        esac
    done

    section "build: cmake --preset ${preset}"
    cd "${DEEPSPAN_ROOT}"
    local t_start t_end
    t_start=$(date +%s)
    cmake --preset "${preset}"
    cmake --build "build/${preset}" -j"$(nproc)"
    t_end=$(date +%s)
    ok "build complete in $((t_end - t_start))s (preset=${preset})"
}

# ══════════════════════════════════════════════════════════════════════════════
# lint
# ══════════════════════════════════════════════════════════════════════════════
cmd_lint() {
    local strict=0 preset="dev"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --strict) strict=1; shift ;;
            --preset) preset="$2"; shift 2 ;;
            -h|--help)
                echo "Usage: $0 lint [--strict] [--preset PRESET]"
                exit 0 ;;
            *) die "Unknown lint option: $1" ;;
        esac
    done

    if ! command -v clang-tidy &>/dev/null; then
        die "clang-tidy not found — run: ./scripts/dev.sh setup --lint-tools"
    fi

    local compile_db="${DEEPSPAN_ROOT}/build/${preset}/compile_commands.json"
    if [[ ! -f "$compile_db" ]]; then
        die "compile_commands.json not found — run: ./scripts/dev.sh build --preset ${preset}"
    fi

    section "lint: clang-tidy (preset=${preset})"
    local fail_count=0
    while IFS= read -r -d '' src; do
        local rel="${src#"${DEEPSPAN_ROOT}"/}"
        if ! clang-tidy -p "${compile_db}" "${src}" --quiet 2>/dev/null; then
            fail_count=$((fail_count + 1))
            warn "${rel} — clang-tidy issues found"
        fi
    done < <(find "${DEEPSPAN_ROOT}/server" "${DEEPSPAN_ROOT}/runtime" "${DEEPSPAN_ROOT}/sim" \
                  -name "*.cpp" -o -name "*.hpp" -print0 2>/dev/null)

    if [[ $fail_count -gt 0 ]]; then
        if [[ $strict -eq 1 ]]; then
            die "${fail_count} file(s) failed clang-tidy"
        else
            warn "${fail_count} file(s) had clang-tidy issues (use --strict to exit 1)"
        fi
    else
        ok "all C++ files passed clang-tidy"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# test
# ══════════════════════════════════════════════════════════════════════════════
cmd_test() {
    local no_build=0 preset="dev"
    local SERVER_ADDR="${SERVER_ADDR:-:8080}"
    local HW_MODEL_SHM="${HW_MODEL_SHM:-deepspan-sim}"
    local STARTUP_TIMEOUT=15

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-build) no_build=1; shift ;;
            --preset)   preset="$2"; shift 2 ;;
            -h|--help)
                echo "Usage: $0 test [--no-build] [--preset PRESET]"
                echo ""
                echo "Environment overrides:"
                echo "  SERVER_ADDR   server listen address  (default: :8080)"
                echo "  HW_MODEL_SHM  POSIX shm name         (default: deepspan-sim)"
                exit 0 ;;
            *) die "Unknown test option: $1" ;;
        esac
    done

    local PIDS=()
    cleanup_test() {
        log "shutting down simulation..."
        for pid in "${PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
        wait 2>/dev/null || true
        rm -f "/dev/shm/${HW_MODEL_SHM}" 2>/dev/null || true
        log "done"
    }
    trap cleanup_test EXIT INT TERM

    local BUILD_DIR="${DEEPSPAN_ROOT}/build/${preset}"
    local HW_MODEL_BIN="${BUILD_DIR}/sim/hw-model/deepspan-hw-model"
    local SERVER_BIN="${BUILD_DIR}/server/deepspan-server"
    local ZEPHYR_BIN="${DEEPSPAN_ROOT}/build/firmware/app/zephyr/zephyr.exe"

    if [[ $no_build -eq 0 ]]; then
        section "test: cmake build (preset=${preset})"
        cd "${DEEPSPAN_ROOT}"
        cmake --preset "${preset}"
        cmake --build "${BUILD_DIR}" -j"$(nproc)"
        ok "build complete"
    fi

    [[ -f "${SERVER_BIN}" ]] || die "server binary not found: ${SERVER_BIN}"

    mkdir -p "${BUILD_DIR}/logs"
    section "test: start simulation stack"

    if [[ -f "${HW_MODEL_BIN}" ]]; then
        log "starting hw-model (shm: ${HW_MODEL_SHM})..."
        "${HW_MODEL_BIN}" "--shm-name=/${HW_MODEL_SHM}" \
            >"${BUILD_DIR}/logs/hw-model.log" 2>&1 &
        PIDS+=($!)
        sleep 0.3
        ok "hw-model started (pid ${PIDS[-1]})"
    else
        warn "hw-model binary not found — skipping"
    fi

    if [[ -f "${ZEPHYR_BIN}" ]]; then
        log "starting Zephyr native_sim firmware..."
        "${ZEPHYR_BIN}" >"${BUILD_DIR}/logs/zephyr.log" 2>&1 &
        PIDS+=($!)
        sleep 0.3
        ok "Zephyr firmware started (pid ${PIDS[-1]})"
    fi

    log "starting deepspan-server (addr ${SERVER_ADDR})..."
    "${SERVER_BIN}" --addr "${SERVER_ADDR}" \
        >"${BUILD_DIR}/logs/server.log" 2>&1 &
    PIDS+=($!)
    ok "deepspan-server started (pid ${PIDS[-1]})"

    local SERVER_PORT="${SERVER_ADDR#:}"
    wait_port "localhost" "${SERVER_PORT}" "${STARTUP_TIMEOUT}"

    section "test: SDK hello-world"
    local HELLO_SCRIPT="${DEEPSPAN_ROOT}/sdk/examples/hello.py"
    if command -v uv &>/dev/null; then
        (cd "${DEEPSPAN_ROOT}/sdk" && uv run python "${HELLO_SCRIPT}")
    else
        python3 "${HELLO_SCRIPT}"
    fi

    echo ""
    ok "=== Full-stack simulation test PASSED ==="
    echo ""
    echo -e "  ${BOLD}Logs:${NC} ${BUILD_DIR}/logs/"
    echo ""
    echo "  Press Ctrl-C to stop all services."
    wait
}

# ══════════════════════════════════════════════════════════════════════════════
# validate
# ══════════════════════════════════════════════════════════════════════════════
cmd_validate() {
    log "validate: delegating to hwip/scripts/hwip.sh validate"
    exec "${SCRIPT_DIR}/../hwip/scripts/hwip.sh" validate "$@"
}

# ══════════════════════════════════════════════════════════════════════════════
# check  (full CI gate)
# ══════════════════════════════════════════════════════════════════════════════
cmd_check() {
    local preset="dev"
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

    section "check: ctest"
    ctest --preset "${preset}" --output-on-failure

    section "check: lint"
    cmd_lint --strict --preset "${preset}"

    section "check: validate"
    cmd_validate

    echo ""
    ok "=== All checks passed ==="
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "$COMMAND" in
    setup)    cmd_setup    "$@" ;;
    gen)      cmd_gen      "$@" ;;
    build)    cmd_build    "$@" ;;
    lint)     cmd_lint     "$@" ;;
    test)     cmd_test     "$@" ;;
    validate) cmd_validate "$@" ;;
    check)    cmd_check    "$@" ;;
    help|-h|--help) usage 0 ;;
    *) warn "Unknown command: ${COMMAND}"; usage 1 ;;
esac
