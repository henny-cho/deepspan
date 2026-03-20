#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# setup-dev.sh — one-shot developer setup for deepspan-hwip.
#
# Lessons learned:
#   1. West workspace topdir = PARENT of manifest repo (ih-scratch/), not
#      deepspan-hwip itself — even with self: path: . in west.yml.
#      deepspan lives at <topdir>/deepspan (sibling of deepspan-hwip).
#   2. go.work uses ../deepspan/l4-server (sibling path), not ./deepspan/server.
#   3. Install deepspan-codegen AFTER deepspan is confirmed available
#      (the tool lives inside deepspan/tools/deepspan-codegen/).
#   4. west update for deepspan fails when west.yml uses a placeholder org
#      (myorg/). Local dev: detect existing deepspan and skip clone.
#      west update is only needed for Zephyr firmware deps (etl, openamp, …),
#      and those are only importable AFTER deepspan is fetched — so skip
#      west update entirely when deepspan is already present locally.
#   5. deepspan-codegen CLI: no subcommands; flags are --descriptor, --out,
#      --target (not `deepspan-codegen generate …`).
#
# Usage:
#   ./scripts/setup-dev.sh [--deepspan-path <path>]
#                          [--source-build]
#                          [--west-update]      # attempt west update (firmware)
#                          [--skip-codegen]
#                          [--skip-platform]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# West workspace topdir = parent of manifest repo (always).
WORKSPACE_ROOT="$(cd "$REPO_ROOT/.." && pwd)"

PLATFORM_DIR="${DEEPSPAN_PLATFORM_DIR:-/opt/deepspan-platform}"
SOURCE_BUILD=false
WEST_UPDATE=false
SKIP_CODEGEN=false
SKIP_PLATFORM=false
DEEPSPAN_PATH=""   # default: <workspace>/deepspan

while [[ $# -gt 0 ]]; do
    case "$1" in
        --deepspan-path)  DEEPSPAN_PATH="$2"; shift 2 ;;
        --source-build)   SOURCE_BUILD=true; shift ;;
        --west-update)    WEST_UPDATE=true; shift ;;
        --skip-codegen)   SKIP_CODEGEN=true; shift ;;
        --skip-platform)  SKIP_PLATFORM=true; shift ;;
        *)                echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Resolve deepspan directory.
# West places deepspan at <workspace>/deepspan (sibling of deepspan-hwip).
if [[ -z "$DEEPSPAN_PATH" ]]; then
    DEEPSPAN_PATH="$WORKSPACE_ROOT/deepspan"
fi

echo "==> deepspan-hwip dev setup"
echo "    repo-root      : $REPO_ROOT"
echo "    workspace-root : $WORKSPACE_ROOT"
echo "    deepspan-path  : $DEEPSPAN_PATH"
echo "    platform-dir   : $PLATFORM_DIR"
echo ""

# ── Prerequisite check ────────────────────────────────────────────────────────
PREREQ_OK=true
check_required() {
    if ! command -v "$1" &>/dev/null; then
        echo "  [MISSING] $1${2:+ — $2}"
        PREREQ_OK=false
    else
        echo "  [OK]      $1"
    fi
}
check_optional() {
    if ! command -v "$1" &>/dev/null; then
        echo "  [WARN]    $1 not found (optional for ${2:-$1} steps)"
    else
        echo "  [OK]      $1"
    fi
}
echo "==> Checking prerequisites..."
check_required python3 "Python 3.11+ required"
check_required gcc     "needed for C syntax check in validate.sh"
check_required g++     "needed for C++ syntax check in validate.sh"
check_optional west    "pip install west  (needed for firmware dep setup)"
check_optional go      "https://go.dev/dl/ (needed for Go tests)"
check_optional buf     "https://buf.build/docs/installation (needed for proto lint)"
if [[ "$PREREQ_OK" != "true" ]]; then
    echo ""
    echo "ERROR: missing required tools above. Install them and re-run." >&2
    exit 1
fi
echo ""

# ── Step 1: Resolve deepspan ──────────────────────────────────────────────────
echo "==> Resolving deepspan source..."
if [[ ! -d "$DEEPSPAN_PATH" ]]; then
    echo ""
    echo "ERROR: deepspan not found at: $DEEPSPAN_PATH"
    echo ""
    echo "Clone it first:"
    echo "  git clone git@github.com:<org>/deepspan.git $DEEPSPAN_PATH"
    echo ""
    echo "Or specify an existing clone:"
    echo "  $0 --deepspan-path /path/to/deepspan"
    exit 1
fi
echo "  deepspan found at: $DEEPSPAN_PATH"
echo ""

# ── Step 2: West init ─────────────────────────────────────────────────────────
# west init -l deepspan-hwip creates .west at WORKSPACE_ROOT (the topdir).
# This is correct; west always places .west at parent of the manifest repo.
if command -v west &>/dev/null; then
    echo "==> West workspace (topdir: $WORKSPACE_ROOT)..."
    if [[ ! -f "$WORKSPACE_ROOT/.west/config" ]]; then
        (cd "$WORKSPACE_ROOT" && west init -l deepspan-hwip 2>&1) || true
        echo "  west init done"
    else
        echo "  .west already initialized"
    fi

    if [[ "$WEST_UPDATE" == "true" ]]; then
        # west update tries to clone deepspan from the placeholder remote
        # (myorg/deepspan). This fails in local dev unless deepspan's actual
        # remote is reachable. The firmware deps (etl, openamp, …) are imported
        # from deepspan's west.yml and require deepspan to be fetched first.
        # Only attempt this when explicitly requested with --west-update.
        echo "==> Running west update (may fail for deepspan if remote unreachable)..."
        (cd "$WORKSPACE_ROOT" && west update --narrow 2>&1) || \
            echo "  west update failed (deepspan remote unreachable in local dev)"
    else
        echo "  Skipping west update (use --west-update for Zephyr firmware deps)"
    fi
else
    echo "==> west not found — skipping workspace init"
    echo "    Firmware builds require: pip install west && $0 --west-update"
fi
echo ""

# ── Step 3: Install deepspan-codegen ─────────────────────────────────────────
# The tool lives inside deepspan/. Must run after deepspan is confirmed present.
CODEGEN_SRC="$DEEPSPAN_PATH/tools/deepspan-codegen"
if [[ ! -d "$CODEGEN_SRC" ]]; then
    echo "ERROR: deepspan-codegen not found at $CODEGEN_SRC" >&2
    exit 1
fi

echo "==> Installing deepspan-codegen..."
if command -v deepspan-codegen &>/dev/null; then
    echo "  already installed: $(deepspan-codegen --version 2>/dev/null || echo 'ok')"
else
    if command -v uv &>/dev/null; then
        uv tool install "$CODEGEN_SRC"
    else
        pip install --quiet "$CODEGEN_SRC"
    fi
    echo "  installed from $CODEGEN_SRC"
fi
echo ""

# ── Step 4: Run codegen for each HWIP ────────────────────────────────────────
# CLI: deepspan-codegen --descriptor <hwip.yaml> --out <gen_dir>
# (no subcommands — flags are direct top-level options)
if [[ "$SKIP_CODEGEN" == "true" ]]; then
    echo "==> Skipping codegen (--skip-codegen)"
else
    echo "==> Generating artifacts for all HWIPs..."
    FOUND_HWIP=false
    for hwip_dir in "$REPO_ROOT"/*/; do
        hwip_yaml="$hwip_dir/hwip.yaml"
        if [[ -f "$hwip_yaml" ]]; then
            hwip_name="$(basename "$hwip_dir")"
            echo "  -> $hwip_name"
            deepspan-codegen \
                --descriptor "$hwip_yaml" \
                --out "$hwip_dir/gen"
            FOUND_HWIP=true
        fi
    done
    if [[ "$FOUND_HWIP" == "false" ]]; then
        echo "  (no hwip.yaml found under $REPO_ROOT)"
    fi
fi
echo ""

# ── Step 5: Platform (C++ libraries) ─────────────────────────────────────────
if [[ "$SKIP_PLATFORM" == "true" ]]; then
    echo "==> Skipping platform setup (--skip-platform)"
elif [[ "$SOURCE_BUILD" == "true" ]]; then
    echo "==> Source build: building deepspan C++ platform from $DEEPSPAN_PATH..."
    cmake --preset release \
        -S "$DEEPSPAN_PATH" \
        -B "$DEEPSPAN_PATH/build/release" \
        -DCMAKE_INSTALL_PREFIX="$PLATFORM_DIR" \
        -DDEESPAN_BUILD_TESTS=OFF
    cmake --build "$DEEPSPAN_PATH/build/release" -j"$(nproc)"
    cmake --install "$DEEPSPAN_PATH/build/release"
    echo "  installed to $PLATFORM_DIR"
else
    echo "==> Platform C++ libraries: not set up (only needed for hw-model C++ builds)."
    echo "    To build with source: $0 --source-build"
fi
echo ""

# ── Done ──────────────────────────────────────────────────────────────────────
echo "✓ Setup complete!"
echo ""
echo "Verify with:"
echo "  ./scripts/validate.sh"
echo ""
echo "Next steps:"
echo "  go test ./accel/l4-plugin/...                       # Go unit tests"
echo "  ./scripts/validate.sh                              # 7-check artifact validation"
echo "  cmake --preset accel-dev && cmake --build ...      # C++ hw-model (needs platform)"
