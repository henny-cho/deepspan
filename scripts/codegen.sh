#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Deepspan — proto code generation
#
# Generates Go + Python stubs from proto/deepspan/v1/*.proto using buf.
# Output:
#   gen/go/deepspan/v1/          Go protobuf + connect-go stubs
#   gen/python/deepspan/v1/      Python protobuf stubs
#
# Usage:
#   ./scripts/codegen.sh            # generate all
#   ./scripts/codegen.sh --go-only  # skip Python output
#   ./scripts/codegen.sh --install  # install buf + plugins, then generate
set -euo pipefail

DEEPSPAN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROTO_DIR="${DEEPSPAN_ROOT}/proto"
GEN_GO_DIR="${DEEPSPAN_ROOT}/gen/go"
GEN_PY_DIR="${DEEPSPAN_ROOT}/gen/python"
export PATH="/usr/local/go/bin:${HOME}/go/bin:${HOME}/.local/bin:$PATH"

GO_ONLY=false
DO_INSTALL=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --go-only)  GO_ONLY=true; shift ;;
        --install)  DO_INSTALL=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--go-only] [--install]"
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
      value: github.com/myorg/deepspan/gen/go
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
    echo "==> Generating Go stubs..."
    buf generate --template "$TMP_GEN"
else
    echo "==> Generating Go + Python stubs..."
    buf generate
fi

# ── Post-generation: go mod tidy ──────────────────────────────────────────────
echo "==> Running go mod tidy for gen/go..."
(cd "${GEN_GO_DIR}" && go mod tidy)

echo "==> Running go mod tidy for server (depends on gen/go)..."
(cd "${DEEPSPAN_ROOT}/server" && go mod tidy)

echo "==> Running go mod tidy for mgmt-daemon (depends on gen/go)..."
(cd "${DEEPSPAN_ROOT}/mgmt-daemon" && go mod tidy)

# ── Python post-processing: ensure __init__.py files ─────────────────────────
if ! $GO_ONLY && [ -d "${GEN_PY_DIR}" ]; then
    echo "==> Ensuring Python package __init__.py files..."
    find "${GEN_PY_DIR}" -type d | while read -r d; do
        touch "${d}/__init__.py"
    done
fi

echo ""
echo "Codegen complete."
echo "  Go stubs:     ${GEN_GO_DIR}"
if ! $GO_ONLY; then
    echo "  Python stubs: ${GEN_PY_DIR}"
fi
echo ""
echo "Next: git add gen/ && git commit -m 'chore: regenerate proto stubs'"
