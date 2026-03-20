#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Deepspan — proto code generation
#
# Stage 1 (platform proto): Generates Go + Python stubs from l5/proto using buf.
# Stage 2 (hwip codegen):   hwip.yaml → multi-layer artifacts (deepspan-codegen + buf).
#
# Output:
#   l5/gen/go/deepspan/v1/          Go protobuf + connect-go stubs
#   l5/gen/python/deepspan/v1/      Python protobuf stubs
#   hwip/<type>/gen/                HWIP layer artifacts
#
# Usage:
#   ./scripts/codegen.sh                  # generate all
#   ./scripts/codegen.sh --go-only        # skip Python output
#   ./scripts/codegen.sh --install        # install buf + plugins, then generate
#   ./scripts/codegen.sh --hwip accel     # run hwip codegen for specific type
#   ./scripts/codegen.sh --skip-hwip      # skip hwip codegen stage
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEEPSPAN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROTO_DIR="${DEEPSPAN_ROOT}/l5/proto"
GEN_GO_DIR="${DEEPSPAN_ROOT}/l5/gen/go"
GEN_PY_DIR="${DEEPSPAN_ROOT}/l5/gen/python"
export PATH="/usr/local/go/bin:${HOME}/go/bin:${HOME}/.local/bin:$PATH"

GO_ONLY=false
DO_INSTALL=false
SKIP_HWIP=false
HWIP_FILTER=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --go-only)   GO_ONLY=true; shift ;;
        --install)   DO_INSTALL=true; shift ;;
        --skip-hwip) SKIP_HWIP=true; shift ;;
        --hwip)      HWIP_FILTER="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--go-only] [--install] [--skip-hwip] [--hwip <type>]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Optional: install buf CLI and Go plugins ──────────────────────────────────
install_tools() {
    echo "==> Installing buf CLI..."
    if ! command -v buf &>/dev/null; then
        BUF_VERSION="1.34.0"
        sudo wget -q -O /usr/local/bin/buf \
            "https://github.com/bufbuild/buf/releases/download/v${BUF_VERSION}/buf-Linux-x86_64"
        sudo chmod +x /usr/local/bin/buf
        echo "    buf ${BUF_VERSION} installed."
    else
        echo "    buf: $(buf --version) (already installed)"
    fi

    echo "==> Installing Go proto plugins..."
    go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.34.2
    go install connectrpc.com/connect/cmd/protoc-gen-connect-go@v1.16.2

    echo "==> Installing Python proto plugin..."
    pipx install grpcio-tools 2>/dev/null || pip3 install --break-system-packages grpcio-tools mypy-protobuf
}

if $DO_INSTALL; then
    install_tools
fi

# ── Pre-flight checks ─────────────────────────────────────────────────────────
if ! command -v buf &>/dev/null; then
    echo "ERROR: buf not found. Run: $0 --install" >&2
    exit 1
fi

echo "==> buf: $(buf --version)"

# ── Prepare output directories ────────────────────────────────────────────────
mkdir -p "${GEN_GO_DIR}"
if ! $GO_ONLY; then
    mkdir -p "${GEN_PY_DIR}"
fi

# ── Generate ──────────────────────────────────────────────────────────────────
cd "${PROTO_DIR}"

# Build buf.gen.yaml dynamically based on --go-only flag
if $GO_ONLY; then
    # Temporarily use a go-only config
    TMP_GEN=$(mktemp --suffix=.yaml)
    trap 'rm -f "$TMP_GEN"' EXIT
    cat > "$TMP_GEN" <<'YAML'
version: v2
managed:
  enabled: true
  override:
    - file_option: go_package_prefix
      value: github.com/myorg/deepspan/l5-gen/go
plugins:
  - remote: buf.build/protocolbuffers/go
    out: ../l5-gen/go
    opt:
      - paths=source_relative
  - remote: buf.build/connectrpc/go
    out: ../l5-gen/go
    opt:
      - paths=source_relative
YAML
    echo "==> Generating Go stubs..."
    buf generate --template "$TMP_GEN"
else
    echo "==> Generating Go + Python stubs..."
    buf generate
fi

# ── Post-generation: go mod tidy ──────────────────────────────────────────────
echo "==> Running go mod tidy for l5/gen/go..."
(cd "${GEN_GO_DIR}" && go mod tidy)

echo "==> Running go mod tidy for l4/server (depends on l5/gen)..."
(cd "${DEEPSPAN_ROOT}/l4/server" && go mod tidy)

echo "==> Running go mod tidy for l4/mgmt-daemon (depends on l5/gen)..."
(cd "${DEEPSPAN_ROOT}/l4/mgmt-daemon" && go mod tidy)

# ── Python post-processing: ensure __init__.py files ─────────────────────────
if ! $GO_ONLY && [ -d "${GEN_PY_DIR}" ]; then
    echo "==> Ensuring Python package __init__.py files..."
    find "${GEN_PY_DIR}" -type d | while read -r d; do
        touch "${d}/__init__.py"
    done
fi

# ── Stage 3: HWIP codegen ─────────────────────────────────────────────────────
if ! $SKIP_HWIP; then
    run_hwip_codegen() {
        local hwip_type="${1}"
        local hwip_dir="${DEEPSPAN_ROOT}/hwip/${hwip_type}"

        if [[ ! -f "${hwip_dir}/hwip.yaml" ]]; then
            echo "  skipping ${hwip_type}: no hwip.yaml found"
            return
        fi

        echo "==> [HWIP Stage 1] ${hwip_type}: deepspan-codegen..."
        if ! command -v deepspan-codegen &>/dev/null; then
            echo "  ERROR: deepspan-codegen not found. Install: pip install tools/deepspan-codegen/" >&2
            return 1
        fi
        deepspan-codegen \
            --descriptor "${hwip_dir}/hwip.yaml" \
            --out        "${hwip_dir}/gen" \
            --target     all

        echo "==> [HWIP Stage 2] ${hwip_type}: buf generate..."
        if ! command -v buf &>/dev/null; then
            echo "  ERROR: buf not found." >&2
            return 1
        fi
        (cd "${DEEPSPAN_ROOT}/hwip" && buf generate \
            --config "${DEEPSPAN_ROOT}/hwip/buf.yaml" \
            --template "${DEEPSPAN_ROOT}/hwip/buf.gen.yaml")

        go mod tidy -C "${hwip_dir}/gen/go"
    }

    if [[ -n "${HWIP_FILTER}" ]]; then
        run_hwip_codegen "${HWIP_FILTER}"
    else
        for hwip_dir in "${DEEPSPAN_ROOT}/hwip"/*/; do
            [[ -f "${hwip_dir}/hwip.yaml" ]] || continue
            run_hwip_codegen "$(basename "${hwip_dir}")"
        done
    fi
fi

echo ""
echo "Codegen complete."
echo "  Go stubs:     ${GEN_GO_DIR}"
if ! $GO_ONLY; then
    echo "  Python stubs: ${GEN_PY_DIR}"
fi
echo ""
echo "Next: git add l5/gen/ hwip/*/gen/ && git commit -m 'chore: regenerate proto stubs'"
