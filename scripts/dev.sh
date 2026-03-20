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
deepspan developer CLI

Usage:
  dev.sh <command> [options]

Lifecycle commands:
  setup     [--layers L1,L2] [--skip L1] [--hooks] [--lint-tools] [--verify-only]
              Install dev toolchains and verify the environment.
              --hooks        Also install git pre-commit hooks
              --lint-tools   Also install golangci-lint
              --verify-only  Skip install; only verify existing toolchains

  gen       [--go-only] [--install] [--skip-hwip] [--hwip TYPE] [--check]
              Generate Go/Python proto stubs and HWIP layer artifacts.
              --go-only      Skip Python stub generation
              --install      Install buf CLI and Go/Python plugins first
              --skip-hwip    Skip HWIP codegen stage
              --hwip TYPE    Run HWIP codegen for one type only
              --check        Dry-run: exit 1 if generated files are stale

  build     [--layers L1,L2] [--skip L1]
              Build every layer and print a pass/fail/time summary.

  lint      [--module MOD] [--strict]
              Run golangci-lint on all Go workspace modules.
              --module MOD   Lint a single module (e.g. l4/server)
              --strict       Exit 1 on any lint failure (default: warn only)

  test      [--no-build] [--hwip [--stub] [--port N]]
              Full-stack simulation: hw-model → mgmt-daemon → server → SDK hello-world.
              --no-build     Skip build; use existing binaries
              --hwip         Route to HWIP integration tests instead
              --stub         (hwip) Use stub mode (no hardware)
              --port N       (hwip) Server port (default: 8080)

  validate  [--hwip TYPE] [--fix] [--skip-syntax]
              Run 7-check validation on generated HWIP artifacts.
              --hwip TYPE    Validate a single HWIP type
              --fix          Auto-fix gofmt and stale codegen issues
              --skip-syntax  Skip C / C++ / Go syntax checks

  check     [--layers L1,L2] [--skip L1]
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
    local GOLANGCI_VERSION="v2.11.3"
    ALL_LAYERS=(l3/hw-model l2/firmware l2/kernel l3/userlib l3/appframework l4/mgmt-daemon l4/server l6/sdk)
    LAYERS=("${ALL_LAYERS[@]}")
    SKIP_LAYERS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --layers)      IFS=',' read -ra LAYERS <<< "$2"; shift 2 ;;
            --skip)        IFS=',' read -ra SKIP_LAYERS <<< "$2"; shift 2 ;;
            --hooks)       install_hooks=1; shift ;;
            --lint-tools)  install_lint=1; shift ;;
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
        if [[ " ${LAYERS[*]} " == *"l2/firmware"* ]] && ! should_skip l2/firmware; then
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

    # ── Optional: golangci-lint ────────────────────────────────────────────────
    if [[ $install_lint -eq 1 ]]; then
        section "setup: golangci-lint"
        if command -v golangci-lint &>/dev/null; then
            ok "golangci-lint already installed: $(golangci-lint version 2>&1 | head -1)"
        else
            log "Installing golangci-lint ${GOLANGCI_VERSION}..."
            local GOBIN
            GOBIN="$(go env GOPATH)/bin"
            curl -sSfL \
                https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh \
                | sh -s -- -b "$GOBIN" "${GOLANGCI_VERSION}"
            ok "golangci-lint installed: $("$GOBIN/golangci-lint" version 2>&1 | head -1)"
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
    local go_only=false do_install=false skip_hwip=false
    local hwip_filter="" check_mode=false
    local PROTO_DIR="${DEEPSPAN_ROOT}/l5/proto"
    local GEN_GO_DIR="${DEEPSPAN_ROOT}/l5/gen/go"
    local GEN_PY_DIR="${DEEPSPAN_ROOT}/l5/gen/python"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --go-only)   go_only=true; shift ;;
            --install)   do_install=true; shift ;;
            --skip-hwip) skip_hwip=true; shift ;;
            --hwip)      hwip_filter="$2"; shift 2 ;;
            --check)     check_mode=true; shift ;;
            -h|--help)
                echo "Usage: $0 gen [--go-only] [--install] [--skip-hwip] [--hwip TYPE] [--check]"
                exit 0 ;;
            *) die "Unknown gen option: $1" ;;
        esac
    done

    # ── Optional: install tools ────────────────────────────────────────────────
    if $do_install; then
        section "gen: install tools"
        if ! command -v buf &>/dev/null; then
            local BUF_VERSION="1.34.0"
            log "Installing buf ${BUF_VERSION}..."
            sudo wget -q -O /usr/local/bin/buf \
                "https://github.com/bufbuild/buf/releases/download/v${BUF_VERSION}/buf-Linux-x86_64"
            sudo chmod +x /usr/local/bin/buf
            ok "buf installed"
        else
            ok "buf: $(buf --version) (already installed)"
        fi
        log "Installing Go proto plugins..."
        go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.34.2
        go install connectrpc.com/connect/cmd/protoc-gen-connect-go@v1.16.2
        log "Installing Python proto plugin..."
        pipx install grpcio-tools 2>/dev/null \
            || pip3 install --break-system-packages grpcio-tools mypy-protobuf
    fi

    # ── Pre-flight ─────────────────────────────────────────────────────────────
    if ! command -v buf &>/dev/null; then
        die "buf not found — run: ./scripts/dev.sh gen --install"
    fi
    section "gen: platform proto (buf $(buf --version))"

    # ── Stage 1: platform proto → Go + Python stubs ───────────────────────────
    mkdir -p "${GEN_GO_DIR}"
    $go_only || mkdir -p "${GEN_PY_DIR}"

    cd "${PROTO_DIR}"
    if $go_only; then
        local TMP_GEN
        TMP_GEN="$(mktemp --suffix=.yaml)"
        trap 'rm -f "$TMP_GEN"' EXIT
        cat > "$TMP_GEN" <<'YAML'
version: v2
managed:
  enabled: true
  override:
    - file_option: go_package_prefix
      value: github.com/myorg/deepspan/l5/gen
plugins:
  - remote: buf.build/protocolbuffers/go
    out: ../gen/go
    opt:
      - paths=source_relative
  - remote: buf.build/connectrpc/go
    out: ../gen/go
    opt:
      - paths=source_relative
YAML
        log "Generating Go stubs..."
        buf generate --template "$TMP_GEN"
    else
        log "Generating Go + Python stubs..."
        buf generate
    fi

    log "go mod tidy: l5/gen/go..."
    (cd "${GEN_GO_DIR}" && go mod tidy)
    log "go mod tidy: l4/server..."
    (cd "${DEEPSPAN_ROOT}/l4/server" && go mod tidy)
    log "go mod tidy: l4/mgmt-daemon..."
    (cd "${DEEPSPAN_ROOT}/l4/mgmt-daemon" && go mod tidy)

    if ! $go_only && [[ -d "${GEN_PY_DIR}" ]]; then
        log "Ensuring Python __init__.py files..."
        find "${GEN_PY_DIR}" -type d | while read -r d; do
            touch "${d}/__init__.py"
        done
    fi
    ok "platform proto generation complete"

    # ── Stage 2: HWIP codegen ─────────────────────────────────────────────────
    if $skip_hwip; then
        log "Skipping HWIP codegen (--skip-hwip)"
        return 0
    fi

    section "gen: HWIP codegen"
    if ! command -v deepspan-codegen &>/dev/null; then
        die "deepspan-codegen not found — run: pip install tools/deepspan-codegen/"
    fi

    _run_hwip_codegen() {
        local hwip_type="$1"
        local hwip_dir="${DEEPSPAN_ROOT}/hwip/${hwip_type}"

        if $check_mode; then
            local TMP_GEN
            TMP_GEN="$(mktemp -d)"
            trap 'rm -rf "$TMP_GEN"' EXIT
            deepspan-codegen \
                --descriptor "${hwip_dir}/hwip.yaml" \
                --out "$TMP_GEN" --target all
            local stale=false
            for layer_dir in "$TMP_GEN"/l*; do
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
            log "[Stage 1] ${hwip_type}: deepspan-codegen..."
            deepspan-codegen \
                --descriptor "${hwip_dir}/hwip.yaml" \
                --out "${hwip_dir}/gen" --target all
            log "[Stage 2] ${hwip_type}: buf generate..."
            (cd "${DEEPSPAN_ROOT}/hwip" && buf generate \
                --config "${DEEPSPAN_ROOT}/hwip/buf.yaml" \
                --template "${DEEPSPAN_ROOT}/hwip/buf.gen.yaml")
            go mod tidy -C "${hwip_dir}/gen/go"
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
        echo "  Go stubs:     ${GEN_GO_DIR}"
        $go_only || echo "  Python stubs: ${GEN_PY_DIR}"
        echo ""
        echo "Next: git add l5/gen/ hwip/*/gen/ && git commit -m 'chore: regenerate proto stubs'"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# build
# ══════════════════════════════════════════════════════════════════════════════
cmd_build() {
    declare -A LAYER_SCRIPT=(
        [l3/hw-model]="l3/hw-model/scripts/build.sh"
        [l3/userlib]="l3/userlib/scripts/build.sh"
        [l3/appframework]="l3/appframework/scripts/build.sh"
        [l2/kernel]="l2/kernel/scripts/build.sh"
        [l2/firmware]="l2/firmware/scripts/build.sh"
        [l4/mgmt-daemon]="l4/mgmt-daemon/scripts/build.sh"
        [l4/server]="l4/server/scripts/build.sh"
        [l6/sdk]="l6/sdk/scripts/build.sh"
    )
    ALL_LAYERS=(l3/hw-model l2/kernel l3/userlib l3/appframework l2/firmware l4/mgmt-daemon l4/server l6/sdk)
    LAYERS=("${ALL_LAYERS[@]}")
    SKIP_LAYERS=()
    parse_layers_args "$@"

    declare -A RESULTS=()
    declare -A DURATIONS=()

    for layer in "${LAYERS[@]}"; do
        local script="${DEEPSPAN_ROOT}/${LAYER_SCRIPT[$layer]}"
        if should_skip "$layer"; then
            RESULTS[$layer]="SKIP"; continue
        fi
        if [[ ! -f "$script" ]]; then
            echo -e "${RED}[${layer}] build script not found${NC}"
            RESULTS[$layer]="FAIL"; continue
        fi
        local log_file="${DEEPSPAN_ROOT}/build/logs/${layer//\//-}-build.log"
        mkdir -p "$(dirname "$log_file")"
        section "build: $layer"
        local t_start t_end
        t_start=$(date +%s)
        if bash "$script" 2>&1 | tee "$log_file"; then
            t_end=$(date +%s)
            RESULTS[$layer]="PASS"
            DURATIONS[$layer]="$((t_end - t_start))s"
        else
            t_end=$(date +%s)
            RESULTS[$layer]="FAIL"
            DURATIONS[$layer]="$((t_end - t_start))s"
            echo -e "${RED}[${layer}] FAILED — see ${log_file}${NC}"
        fi
    done

    echo ""
    echo -e "${BOLD}┌──────────────────────────────────────┐${NC}"
    echo -e "${BOLD}│  Build summary                       │${NC}"
    echo -e "${BOLD}├──────────────────────┬───────┬───────┤${NC}"
    printf "${BOLD}│ %-20s │ %-5s │ %-5s │${NC}\n" "Layer" "Result" "Time"
    echo -e "${BOLD}├──────────────────────┼───────┼───────┤${NC}"
    local FAIL_COUNT=0
    for layer in "${LAYERS[@]}"; do
        local result="${RESULTS[$layer]:-SKIP}"
        local duration="${DURATIONS[$layer]:--}"
        local colour
        case "$result" in
            PASS) colour="${GREEN}" ;;
            FAIL) colour="${RED}";  ((FAIL_COUNT++)) || true ;;
            SKIP) colour="${YELLOW}" ;;
            *)    colour="${NC}" ;;
        esac
        printf "│ %-20s │ ${colour}%-5s${NC} │ %-5s │\n" "$layer" "$result" "$duration"
    done
    echo -e "${BOLD}└──────────────────────┴───────┴───────┘${NC}"
    echo ""

    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo -e "${RED}${BOLD}${FAIL_COUNT} layer(s) failed. Fix errors before committing.${NC}"
        exit 1
    fi
    ok "all layers passed"
}

# ══════════════════════════════════════════════════════════════════════════════
# lint
# ══════════════════════════════════════════════════════════════════════════════
cmd_lint() {
    local module="" strict=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --module) module="$2"; shift 2 ;;
            --strict) strict=1; shift ;;
            -h|--help)
                echo "Usage: $0 lint [--module MOD] [--strict]"
                exit 0 ;;
            *) die "Unknown lint option: $1" ;;
        esac
    done

    if ! command -v golangci-lint &>/dev/null; then
        warn "golangci-lint not found — installing via go install..."
        go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest
    fi

    local modules=()
    if [[ -n "$module" ]]; then
        modules=("$module")
    else
        modules=("${DS_GO_MODULES[@]}")
    fi

    local fail_count=0
    for mod in "${modules[@]}"; do
        local mod_path="${DEEPSPAN_ROOT}/${mod}"
        [[ -d "$mod_path" ]] || { warn "module not found: $mod_path"; continue; }
        section "lint: $mod"
        if (cd "$mod_path" && golangci-lint run --timeout 5m ./...); then
            ok "$mod — passed"
        else
            fail_count=$((fail_count + 1))
            warn "$mod — failed"
        fi
    done

    if [[ $fail_count -gt 0 ]]; then
        if [[ $strict -eq 1 ]]; then
            die "$fail_count module(s) failed lint"
        else
            warn "$fail_count module(s) failed lint (use --strict to exit 1)"
        fi
    else
        ok "all modules passed lint"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# test
# ══════════════════════════════════════════════════════════════════════════════
cmd_test() {
    # Route to HWIP integration tests if --hwip flag is present
    if [[ "${1:-}" == "--hwip" ]]; then
        shift
        log "test: routing to hwip integration tests"
        exec "${SCRIPT_DIR}/../hwip/scripts/hwip.sh" test "$@"
    fi

    local no_build=0
    local SERVER_ADDR="${SERVER_ADDR:-:8080}"
    local MGMT_ADDR="${MGMT_ADDR:-:8081}"
    local HW_MODEL_SHM="${HW_MODEL_SHM:-deepspan-sim}"
    local STARTUP_TIMEOUT=15

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-build) no_build=1; shift ;;
            -h|--help)
                echo "Usage: $0 test [--no-build] [--hwip [--stub] [--port N]]"
                echo ""
                echo "Environment overrides:"
                echo "  SERVER_ADDR   server listen address  (default: :8080)"
                echo "  MGMT_ADDR     mgmt-daemon address    (default: :8081)"
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

    local BIN_DIR="${DEEPSPAN_ROOT}/build/bin"
    local HW_MODEL_BIN="${DEEPSPAN_ROOT}/l3/hw-model/build/deepspan-hw-model"
    local FW_SIM_BIN="${DEEPSPAN_ROOT}/l3/hw-model/build/deepspan-firmware-sim"
    local MGMT_BIN="${BIN_DIR}/mgmt-daemon"
    local SERVER_BIN="${BIN_DIR}/deepspan-accel-server"
    local ZEPHYR_BIN="${DEEPSPAN_ROOT}/build/l2/firmware/app/zephyr/zephyr.exe"

    if [[ $no_build -eq 0 ]]; then
        mkdir -p "${BIN_DIR}"
        if command -v cmake &>/dev/null && command -v ninja &>/dev/null; then
            section "test: build hw-model"
            cmake -S "${DEEPSPAN_ROOT}/l3/hw-model" \
                  -B "${DEEPSPAN_ROOT}/l3/hw-model/build" \
                  -G Ninja -DCMAKE_BUILD_TYPE=Release \
                  -DDEEPSPAN_BUILD_TESTS=OFF >/dev/null
            cmake --build "${DEEPSPAN_ROOT}/l3/hw-model/build" -j"$(nproc)" >/dev/null
            ok "hw-model built"
        else
            warn "cmake/ninja not found — skipping hw-model build"
        fi
        section "test: build Go services"
        command -v go &>/dev/null || die "go not found — cannot build services"
        (cd "${DEEPSPAN_ROOT}/l4/mgmt-daemon" && \
            go build -o "${MGMT_BIN}" ./cmd/mgmt-daemon/)
        (cd "${DEEPSPAN_ROOT}/hwip/demo" && \
            go build -o "${SERVER_BIN}" ./cmd/server/)
        ok "Go services built"
    fi

    [[ -f "${MGMT_BIN}"   ]] || die "mgmt-daemon binary not found: ${MGMT_BIN}"
    [[ -f "${SERVER_BIN}" ]] || die "server binary not found: ${SERVER_BIN}"

    mkdir -p "${DEEPSPAN_ROOT}/build/logs"
    section "test: start simulation stack"

    if [[ -f "${HW_MODEL_BIN}" ]]; then
        log "starting hw-model (shm: ${HW_MODEL_SHM})..."
        "${HW_MODEL_BIN}" "--shm-name=/${HW_MODEL_SHM}" \
            >"${DEEPSPAN_ROOT}/build/logs/hw-model.log" 2>&1 &
        PIDS+=($!)
        sleep 0.3
        ok "hw-model started (pid ${PIDS[-1]})"
    else
        warn "hw-model binary not found — skipping"
    fi

    if [[ -f "${FW_SIM_BIN}" ]]; then
        log "starting firmware_sim (shm: ${HW_MODEL_SHM})..."
        "${FW_SIM_BIN}" "--shm-name=/${HW_MODEL_SHM}" --interval-ms=1000 \
            >"${DEEPSPAN_ROOT}/build/logs/firmware-sim.log" 2>&1 &
        PIDS+=($!)
        sleep 0.2
        ok "firmware_sim started (pid ${PIDS[-1]})"
    fi

    if [[ -f "${ZEPHYR_BIN}" ]]; then
        log "starting Zephyr native_sim firmware..."
        "${ZEPHYR_BIN}" \
            >"${DEEPSPAN_ROOT}/build/logs/zephyr.log" 2>&1 &
        PIDS+=($!)
        sleep 0.3
        ok "Zephyr firmware started (pid ${PIDS[-1]})"
    fi

    log "starting mgmt-daemon (addr ${MGMT_ADDR}, sim mode)..."
    "${MGMT_BIN}" --addr "${MGMT_ADDR}" --sim \
        >"${DEEPSPAN_ROOT}/build/logs/mgmt-daemon.log" 2>&1 &
    PIDS+=($!)
    sleep 0.3
    ok "mgmt-daemon started (pid ${PIDS[-1]})"

    log "starting server (addr ${SERVER_ADDR})..."
    "${SERVER_BIN}" --addr "${SERVER_ADDR}" --shm-name "${HW_MODEL_SHM}" \
        >"${DEEPSPAN_ROOT}/build/logs/server.log" 2>&1 &
    PIDS+=($!)
    ok "server started (pid ${PIDS[-1]})"

    local SERVER_PORT="${SERVER_ADDR#:}"
    log "waiting for server (port ${SERVER_PORT})..."
    local deadline=$((SECONDS + STARTUP_TIMEOUT))
    while [[ $SECONDS -lt $deadline ]]; do
        if curl -sf "http://localhost:${SERVER_PORT}/healthz" >/dev/null 2>&1; then
            ok "server is ready"
            break
        fi
        sleep 0.5
    done
    if [[ $SECONDS -ge $deadline ]]; then
        echo "--- server log ---"
        cat "${DEEPSPAN_ROOT}/build/logs/server.log" || true
        die "server did not become ready within ${STARTUP_TIMEOUT}s"
    fi

    section "test: SDK hello-world"
    export DEEPSPAN_URL="http://localhost:${SERVER_PORT}"
    local HELLO_SCRIPT="${DEEPSPAN_ROOT}/l6/sdk/examples/hello.py"
    local VENV_PYTHON="${DEEPSPAN_ROOT}/.venv/bin/python"

    if [[ -x "${VENV_PYTHON}" ]]; then
        "${VENV_PYTHON}" "${HELLO_SCRIPT}"
    elif command -v uv &>/dev/null; then
        (cd "${DEEPSPAN_ROOT}/l6/sdk" && uv run python "${HELLO_SCRIPT}")
    elif command -v python3 &>/dev/null; then
        python3 "${HELLO_SCRIPT}"
    else
        die "python not found (tried .venv, uv, python3)"
    fi

    echo ""
    ok "=== Full-stack simulation test PASSED ==="
    echo ""
    echo -e "  ${BOLD}Processes running:${NC}"
    for pid in "${PIDS[@]}"; do
        local name
        name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "(exited)")
        echo "    pid ${pid}: ${name}"
    done
    echo ""
    echo -e "  ${BOLD}Logs:${NC} ${DEEPSPAN_ROOT}/build/logs/"
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
    local LAYER_ARGS=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --layers|--skip) LAYER_ARGS+=("$1" "$2"); shift 2 ;;
            -h|--help)
                echo "Usage: $0 check [--layers L1,L2] [--skip L1]"
                exit 0 ;;
            *) die "Unknown check option: $1" ;;
        esac
    done

    section "check: build"
    cmd_build "${LAYER_ARGS[@]}"

    section "check: lint"
    cmd_lint --strict

    section "check: test"
    cmd_test --no-build

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
