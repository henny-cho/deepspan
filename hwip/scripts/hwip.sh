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
GO="${GO:-/usr/local/go/bin/go}"

COMMAND="${1:-}"
shift || true

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
deepspan HWIP developer CLI

Usage:
  hwip.sh <command> [options]

Lifecycle commands:
  setup     [--skip-codegen]
              Install deepspan-codegen and generate all HWIP artifacts.
              --skip-codegen   Skip codegen after installing the tool

  gen       [--hwip TYPE] [--stage 1|2] [--check]
              Two-stage HWIP codegen pipeline:
                Stage 1: hwip.yaml → proto + language artifacts (deepspan-codegen)
                Stage 2: proto → Go/Python gRPC stubs (buf generate)
              --hwip TYPE    Run for a single HWIP type only
              --stage 1|2   Run only the specified stage
              --check        Dry-run: exit 1 if generated files are stale

  build
              Build hwsim, demo-server, demo-client, and the accel l4-plugin.

  lint      [--module MOD]
              Run gofmt + go vet + golangci-lint on all HWIP Go modules.
              --module MOD   Lint a single module (e.g. accel/l4-plugin)

  validate  [--hwip TYPE] [--fix] [--skip-syntax]
              7-check validation of generated artifacts:
                1. Codegen stale check
                2. C kernel header syntax (gcc -fsyntax-only)
                3. C++ hw_model header syntax (g++ -fsyntax-only)
                4. Go format (gofmt -l)
                5. Go vet
                6. Python syntax (py_compile)
                7. Proto lint (buf lint)
              --hwip TYPE    Validate a single HWIP type
              --fix          Auto-fix gofmt and stale codegen
              --skip-syntax  Skip C / C++ / Go syntax checks

  demo      [--stub] [--addr ADDR] [--shm NAME] [--verbose]
              Build and run the full HWIP demo stack:
                hwsim → demo-server → demo-client
              --stub         Skip hwsim; use stub (no-hardware) mode
              --addr ADDR    Server listen address (default: :8080)
              --shm NAME     POSIX shm basename (default: deepspan_accel_0)
              --verbose      Enable hwsim verbose logging

  test      [--stub] [--port N]
              Automated integration tests (9 curl-based test cases).
              --stub         Start demo-server in stub mode (no hardware)
              --port N       Server port (default: 8080)

  check
              Full CI gate: build → lint → validate → test (stub mode).

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
    _check_required gcc     "needed for C syntax check in validate"
    _check_required g++     "needed for C++ syntax check in validate"
    _check_optional go      "https://go.dev/dl/ (needed for Go tests)"
    _check_optional buf     "https://buf.build/docs/installation (needed for proto lint)"
    if [[ "$prereq_ok" != "true" ]]; then
        die "Missing required tools. Install them and re-run."
    fi

    section "setup: deepspan-codegen"
    local CODEGEN_SRC="${DEEPSPAN_ROOT}/tools/deepspan-codegen"
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
    fi

    echo ""
    echo "Next steps:"
    echo "  ./hwip/scripts/hwip.sh validate    # artifact validation"
    echo "  ./hwip/scripts/hwip.sh build       # build demo binaries"
    echo "  ./hwip/scripts/hwip.sh test --stub # integration tests"
}

# ══════════════════════════════════════════════════════════════════════════════
# gen
# ══════════════════════════════════════════════════════════════════════════════
cmd_gen() {
    local hwip_filter="" stage_filter="" check_mode=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --hwip)  hwip_filter="$2"; shift 2 ;;
            --stage) stage_filter="$2"; shift 2 ;;
            --check) check_mode=true; shift ;;
            -h|--help)
                echo "Usage: $0 gen [--hwip TYPE] [--stage 1|2] [--check]"
                exit 0 ;;
            *) die "Unknown gen option: $1" ;;
        esac
    done

    # Pre-flight
    if [[ "$stage_filter" != "2" ]]; then
        command -v deepspan-codegen &>/dev/null \
            || die "deepspan-codegen not found — run: ./hwip/scripts/hwip.sh setup"
    fi
    if [[ "$stage_filter" != "1" ]]; then
        command -v buf &>/dev/null \
            || die "buf not found — see https://buf.build/docs/installation"
    fi

    # Discover HWIPs
    local hwips=()
    for hwip_dir in "${HWIP_ROOT}"/*/; do
        local hwip_name
        hwip_name="$(basename "$hwip_dir")"
        [[ -f "$hwip_dir/hwip.yaml" ]] || continue
        [[ -n "$hwip_filter" && "$hwip_name" != "$hwip_filter" ]] && continue
        hwips+=("$hwip_name")
    done
    [[ ${#hwips[@]} -gt 0 ]] \
        || die "No HWIPs found${hwip_filter:+ matching '${hwip_filter}'}"
    log "HWIPs: ${hwips[*]}"

    # Stage 1: hwip.yaml → language artifacts
    if [[ "$stage_filter" != "2" ]]; then
        for hwip in "${hwips[@]}"; do
            local hwip_dir="${HWIP_ROOT}/${hwip}"
            if $check_mode; then
                section "gen check: $hwip"
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
                section "gen stage1: $hwip"
                deepspan-codegen \
                    --descriptor "${hwip_dir}/hwip.yaml" \
                    --out "${hwip_dir}/gen" --target all
                ok "${hwip} stage 1 complete"
            fi
        done
    fi

    # Stage 2: proto → Go/Python gRPC stubs
    if [[ "$stage_filter" != "1" ]] && ! $check_mode; then
        section "gen stage2: buf generate"
        cd "${HWIP_ROOT}"
        buf generate
        ok "buf generate complete"
    fi

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
    local BIN_DIR="${HWIP_ROOT}/.demo-bin"
    mkdir -p "$BIN_DIR"

    section "build: demo binaries"
    (cd "${HWIP_ROOT}" && \
        "$GO" build -o "$BIN_DIR/hwsim"       ./demo/cmd/hwsim && \
        "$GO" build -o "$BIN_DIR/demo-server" ./demo/cmd/server && \
        "$GO" build -o "$BIN_DIR/demo-client" ./demo/cmd/client)
    ok "demo binaries built → ${BIN_DIR}"

    section "build: accel l4-plugin"
    (cd "${HWIP_ROOT}/accel/l4-plugin" && "$GO" build ./...)
    ok "accel l4-plugin built"
}

# ══════════════════════════════════════════════════════════════════════════════
# lint
# ══════════════════════════════════════════════════════════════════════════════
cmd_lint() {
    # Delegate to platform dev.sh to keep golangci-lint version in sync
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

    # Discover HWIPs
    local hwips=()
    for hwip_dir in "${HWIP_ROOT}"/*/; do
        local hwip_name
        hwip_name="$(basename "$hwip_dir")"
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
            for layer_dir in "$TMP_GEN"/l*; do
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
    section "validate: Check 2 — C kernel header syntax"
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
            done < <(find "${gen_dir}/l1-kernel" -name "*.h" -print0 2>/dev/null)
        done
    fi

    # ── Check 3: C++ hw_model header syntax ───────────────────────────────────
    section "validate: Check 3 — C++ l3-cpp header syntax"
    if $skip_syntax; then
        skip "skipped via --skip-syntax"
    elif ! command -v g++ &>/dev/null; then
        skip "g++ not found"
    else
        for hwip in "${hwips[@]}"; do
            local gen_dir="${HWIP_ROOT}/${hwip}/gen"
            while IFS= read -r -d '' hfile; do
                local rel="${hfile#"${HWIP_ROOT}"/}"
                if g++ -fsyntax-only -x c++ -std=c++17 \
                    -Wno-unused-variable "$hfile" 2>/dev/null; then
                    pass "$rel"
                else
                    local errs
                    errs="$(g++ -fsyntax-only -x c++ -std=c++17 \
                        "$hfile" 2>&1 | grep ': error:' | head -5)"
                    if [[ -n "$errs" ]]; then
                        fail "$rel — C++ syntax error"; echo "$errs" >&2
                    else
                        pass "$rel (warnings only)"
                    fi
                fi
            done < <(find "${gen_dir}/l3-cpp" -name "*.hpp" -print0 2>/dev/null)
        done
    fi

    # ── Check 4: Go format ─────────────────────────────────────────────────────
    section "validate: Check 4 — Go format"
    if ! command -v gofmt &>/dev/null; then
        skip "gofmt not found"
    else
        for hwip in "${hwips[@]}"; do
            local gen_dir="${HWIP_ROOT}/${hwip}/gen"
            while IFS= read -r -d '' gofile; do
                local rel="${gofile#"${HWIP_ROOT}"/}"
                local unformatted
                unformatted="$(gofmt -l "$gofile")"
                if [[ -z "$unformatted" ]]; then
                    pass "$rel"
                elif $fix_mode; then
                    gofmt -w "$gofile"
                    pass "$rel (reformatted)"
                else
                    fail "$rel — not gofmt-formatted"
                    gofmt -d "$gofile" 2>&1 | head -20 >&2 || true
                fi
            done < <(find "${gen_dir}/l4-rpc" -name "*.go" -print0 2>/dev/null)
        done
    fi

    # ── Check 5: Go vet ────────────────────────────────────────────────────────
    section "validate: Check 5 — Go vet"
    if ! command -v go &>/dev/null; then
        skip "go not found"
    else
        for hwip in "${hwips[@]}"; do
            local gen_dir="${HWIP_ROOT}/${hwip}/gen/l4-rpc"
            [[ -d "$gen_dir" ]] || { skip "${hwip}/gen/l4-rpc/ not found"; continue; }
            while IFS= read -r -d '' gofile; do
                local rel="${gofile#"${HWIP_ROOT}"/}"
                local TMP_MOD
                TMP_MOD="$(mktemp -d)"
                cp "$gofile" "$TMP_MOD/"
                printf 'module gen_validate\ngo 1.21\n' > "$TMP_MOD/go.mod"
                if (cd "$TMP_MOD" && GOWORK=off go vet .) 2>/dev/null; then
                    pass "$rel"
                else
                    fail "$rel — go vet failed"
                    (cd "$TMP_MOD" && GOWORK=off go vet .) 2>&1 | head -10 >&2 || true
                fi
                rm -rf "$TMP_MOD"
            done < <(find "$gen_dir" -name "*.go" -print0 2>/dev/null)
        done
    fi

    # ── Check 6: Python syntax ─────────────────────────────────────────────────
    section "validate: Check 6 — Python syntax"
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
            done < <(find "${gen_dir}/l6-sdk" -name "*.py" -print0 2>/dev/null)
        done
    fi

    # ── Check 7: Proto lint ────────────────────────────────────────────────────
    section "validate: Check 7 — Proto lint"
    if ! command -v buf &>/dev/null; then
        skip "buf not found"
    else
        for hwip in "${hwips[@]}"; do
            local proto_dir="${HWIP_ROOT}/${hwip}/gen/l5-proto"
            if [[ ! -d "$proto_dir" ]]; then
                skip "${hwip}/gen/l5-proto/ not found"; continue
            fi
            local CFG='{"version":"v2","lint":{"use":["DEFAULT"],"except":["PACKAGE_VERSION_SUFFIX"]}}'
            if buf lint --config "$CFG" "$proto_dir" 2>/dev/null; then
                pass "${hwip}/gen/l5-proto/ — lint OK"
            else
                local lint_out
                lint_out="$(buf lint --config "$CFG" "$proto_dir" 2>&1 | head -20)"
                if [[ -n "$lint_out" ]]; then
                    fail "${hwip}/gen/l5-proto/ — lint failed"; echo "$lint_out" >&2
                else
                    pass "${hwip}/gen/l5-proto/ — lint OK"
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
    local stub_mode=false verbose=false
    local addr=":8080" shm_name="deepspan_accel_0"
    local BIN_DIR="${HWIP_ROOT}/.demo-bin"

    for arg in "$@"; do
        case "$arg" in
            --stub)    stub_mode=true ;;
            --verbose) verbose=true ;;
            --addr=*)  addr="${arg#--addr=}" ;;
            --shm=*)   shm_name="${arg#--shm=}" ;;
            -h|--help)
                echo "Usage: $0 demo [--stub] [--addr ADDR] [--shm NAME] [--verbose]"
                exit 0 ;;
            *) die "Unknown demo option: $arg" ;;
        esac
    done

    local HWSIM_PID="" SERVER_PID=""
    cleanup_demo() {
        info "cleanup..."
        [[ -n "${HWSIM_PID}"  ]] && kill "$HWSIM_PID"  2>/dev/null || true
        [[ -n "${SERVER_PID}" ]] && kill "$SERVER_PID" 2>/dev/null || true
        wait 2>/dev/null || true
    }
    trap cleanup_demo EXIT

    section "demo: build"
    mkdir -p "$BIN_DIR"
    cd "${HWIP_ROOT}"
    $GO build -o "$BIN_DIR/hwsim"       ./demo/cmd/hwsim
    $GO build -o "$BIN_DIR/demo-server" ./demo/cmd/server
    $GO build -o "$BIN_DIR/demo-client" ./demo/cmd/client
    ok "binaries ready → ${BIN_DIR}"

    section "demo: start hwsim + server"
    if $stub_mode; then
        warn "stub mode — skipping hwsim"
    else
        local hwsim_args=("-name" "$shm_name")
        $verbose && hwsim_args+=("-verbose")
        info "starting hwsim (shm=/dev/shm/${shm_name})..."
        "$BIN_DIR/hwsim" "${hwsim_args[@]}" &
        HWSIM_PID=$!
        sleep 0.3
        [[ -e "/dev/shm/$shm_name" ]] \
            || die "hwsim did not create /dev/shm/${shm_name}"
        info "hwsim PID=${HWSIM_PID}"
    fi

    local server_args=("-addr" "$addr" "-shm-name" "$shm_name")
    $stub_mode && server_args+=("-stub")
    info "starting demo-server (addr=${addr})..."
    "$BIN_DIR/demo-server" "${server_args[@]}" &
    SERVER_PID=$!
    wait_port "$addr"
    info "demo-server PID=${SERVER_PID}"

    section "demo: run client"
    local base_url="http://localhost${addr}"
    [[ "$addr" == :* ]] || base_url="http://$addr"
    info "demo-client (target=${base_url})..."
    echo ""
    "$BIN_DIR/demo-client" -addr "$base_url"
    echo ""
    ok "demo complete"
}

# ══════════════════════════════════════════════════════════════════════════════
# test
# ══════════════════════════════════════════════════════════════════════════════
cmd_test() {
    local stub_mode=false port=8080
    local BIN_DIR="${HWIP_ROOT}/.demo-bin"
    local SHM_NAME="deepspan_accel_0"

    for arg in "$@"; do
        case "$arg" in
            --stub)   stub_mode=true ;;
            --port=*) port="${arg#--port=}" ;;
            -h|--help)
                echo "Usage: $0 test [--stub] [--port N]"
                exit 0 ;;
            *) die "Unknown test option: $arg" ;;
        esac
    done

    local BASE="http://localhost:${port}"
    local HWSIM_PID="" SERVER_PID=""

    cleanup_test() {
        [[ -n "${HWSIM_PID}"  ]] && kill "$HWSIM_PID"  2>/dev/null || true
        [[ -n "${SERVER_PID}" ]] && kill "$SERVER_PID" 2>/dev/null || true
        wait 2>/dev/null || true
    }
    trap cleanup_test EXIT

    rpc() {
        curl -sf -H "Content-Type: application/json" -d "$2" "${BASE}/$1"
    }

    section "test: build"
    mkdir -p "$BIN_DIR"
    cd "${HWIP_ROOT}"
    $GO build -o "$BIN_DIR/hwsim"       ./demo/cmd/hwsim
    $GO build -o "$BIN_DIR/demo-server" ./demo/cmd/server
    $GO build -o "$BIN_DIR/demo-client" ./demo/cmd/client
    ok "build complete"

    section "test: start infrastructure"
    if ! $stub_mode; then
        "$BIN_DIR/hwsim" -name "$SHM_NAME" &
        HWSIM_PID=$!
        sleep 0.3
        [[ -e "/dev/shm/$SHM_NAME" ]] \
            || die "hwsim shm not found at /dev/shm/${SHM_NAME}"
    fi

    local server_args=("-addr" ":${port}" "-shm-name" "$SHM_NAME")
    $stub_mode && server_args+=("-stub")
    "$BIN_DIR/demo-server" "${server_args[@]}" >/dev/null 2>&1 &
    SERVER_PID=$!
    wait_port ":${port}" 12
    log "server up (port=${port}, stub=${stub_mode})"

    section "test: suite"

    # T1: health
    log "T1: GET /healthz"
    local body
    body="$(curl -sf "${BASE}/healthz")"
    [[ "$body" == "ok" ]] \
        && pass "healthz = 'ok'" \
        || fail "healthz: '${body}'"

    # T2: ListDevices
    log "T2: HwipService/ListDevices"
    local resp
    resp="$(rpc "deepspan.v1.HwipService/ListDevices" '{}')"
    echo "$resp" | grep -q '"deviceId":"hwip0"' \
        && pass "ListDevices returns hwip0" \
        || fail "ListDevices: ${resp}"

    # T3: SubmitRequest (Echo opcode=1)
    log "T3: HwipService/SubmitRequest (Echo opcode=1)"
    resp="$(rpc "deepspan.v1.HwipService/SubmitRequest" \
        '{"deviceId":"hwip0","opcode":1,"payload":"qgAAAAC7AAAA","timeoutMs":1000}')"
    echo "$resp" | grep -q '"requestId"' \
        && pass "SubmitRequest/Echo: valid response" \
        || fail "SubmitRequest/Echo: ${resp}"

    # T4: Accel Echo
    log "T4: AccelHwipService/Echo"
    resp="$(rpc "deepspan_accel.v1.AccelHwipService/Echo" \
        '{"deviceId":"hwip0","arg0":10,"arg1":20,"timeoutMs":1000}')"
    if $stub_mode; then
        echo "$resp" | grep -q '"data0":1' \
            && pass "Echo (stub): data0=opcode(1)" \
            || fail "Echo (stub): ${resp}"
    else
        echo "$resp" | grep -q '"data0":10' && echo "$resp" | grep -q '"data1":20' \
            && pass "Echo (shm): data0=10 data1=20" \
            || fail "Echo (shm): ${resp}"
    fi

    # T5: Accel Process
    log "T5: AccelHwipService/Process (arg0=100, arg1=42)"
    resp="$(rpc "deepspan_accel.v1.AccelHwipService/Process" \
        '{"deviceId":"hwip0","data":"ZAAAACoAAAA=","timeoutMs":1000}')"
    echo "$resp" | grep -q '"result"' \
        && pass "Process: got result bytes" \
        || fail "Process: ${resp}"
    if ! $stub_mode; then
        echo "$resp" | grep -q '"result":"jgAAAE4AAAA="' \
            && pass "Process (shm): sum=142 xor=78" \
            || fail "Process (shm): result mismatch: ${resp}"
    fi

    # T6: Accel Status
    log "T6: AccelHwipService/Status"
    resp="$(rpc "deepspan_accel.v1.AccelHwipService/Status" \
        '{"deviceId":"hwip0","timeoutMs":1000}')"
    if $stub_mode; then
        echo "$resp" | grep -q '"statusWord":3' \
            && pass "Status (stub): statusWord=opcode(3)" \
            || fail "Status (stub): ${resp}"
    else
        echo "$resp" | grep -q '"statusWord":65536' \
            && pass "Status (shm): statusWord=0x00010000" \
            || fail "Status (shm): ${resp}"
    fi

    # T7: AccelHwipService/SubmitRequest (generic dispatch)
    log "T7: AccelHwipService/SubmitRequest (ACCEL_OP_ECHO=1)"
    resp="$(rpc "deepspan_accel.v1.AccelHwipService/SubmitRequest" \
        '{"deviceId":"hwip0","op":"ACCEL_OP_ECHO","payload":"DQAAAB4AAAA=","timeoutMs":1000}')"
    echo "$resp" | grep -q '"result"' \
        && pass "AccelHwipService/SubmitRequest: got result" \
        || fail "AccelHwipService/SubmitRequest: ${resp}"

    # T8: demo-client end-to-end (hwsim mode only)
    log "T8: demo-client end-to-end"
    if $stub_mode; then
        skip "demo-client skipped in stub mode"
    else
        if "$BIN_DIR/demo-client" -addr "$BASE" >/tmp/hwip-demo-client.out 2>&1; then
            local ok_count
            ok_count="$(grep -c '\[OK\]' /tmp/hwip-demo-client.out || true)"
            pass "demo-client: ${ok_count} value checks passed"
        else
            fail "demo-client failed:"; cat /tmp/hwip-demo-client.out >&2
        fi
    fi

    # T9: Concurrent Echo x10
    log "T9: concurrent Echo x10"
    local pids=()
    for i in $(seq 1 10); do
        rpc "deepspan_accel.v1.AccelHwipService/Echo" \
            "{\"deviceId\":\"hwip0\",\"arg0\":${i},\"arg1\":$((i*2)),\"timeoutMs\":500}" \
            >/dev/null &
        pids+=($!)
    done
    local all_ok=true
    for pid in "${pids[@]}"; do wait "$pid" || all_ok=false; done
    $all_ok \
        && pass "10 concurrent Echo calls all 200" \
        || fail "some concurrent calls failed"

    hwip_summary || exit 1
}

# ══════════════════════════════════════════════════════════════════════════════
# check  (full CI gate)
# ══════════════════════════════════════════════════════════════════════════════
cmd_check() {
    section "check: build"
    cmd_build

    section "check: lint"
    cmd_lint --strict

    section "check: validate"
    cmd_validate

    section "check: test (stub mode)"
    cmd_test --stub

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
