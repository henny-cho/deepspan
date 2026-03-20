#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# deepspan-hwip codegen — two-stage pipeline
#
# Stage 1: hwip.yaml → proto + all language artifacts (deepspan-codegen)
# Stage 2: proto → Go/Python gRPC stubs (buf generate)
#
# Usage:
#   ./scripts/codegen.sh                  # all HWIPs, all stages
#   ./scripts/codegen.sh --hwip accel     # one HWIP only
#   ./scripts/codegen.sh --stage 1        # Stage 1 only (no buf)
#   ./scripts/codegen.sh --stage 2        # Stage 2 only (buf generate)
#   ./scripts/codegen.sh --check          # dry-run, exit 1 if stale

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/usr/local/go/bin:${HOME}/go/bin:${HOME}/.local/bin:$PATH"

HWIP_FILTER=""
STAGE_FILTER=""
CHECK_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --hwip)    HWIP_FILTER="$2"; shift 2 ;;
        --stage)   STAGE_FILTER="$2"; shift 2 ;;
        --check)   CHECK_MODE=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--hwip <type>] [--stage 1|2] [--check]"
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ── Pre-flight ────────────────────────────────────────────────────────────────
if [[ "$STAGE_FILTER" != "2" ]]; then
    if ! command -v deepspan-codegen &>/dev/null; then
        echo "ERROR: deepspan-codegen not found." >&2
        echo "  Install: pip install deepspan/tools/deepspan-codegen/" >&2
        exit 1
    fi
fi

if [[ "$STAGE_FILTER" != "1" ]]; then
    if ! command -v buf &>/dev/null; then
        echo "ERROR: buf not found. Install from https://buf.build/docs/installation" >&2
        exit 1
    fi
fi

# ── Discover HWIPs ────────────────────────────────────────────────────────────
hwips=()
for hwip_dir in "$REPO_ROOT"/*/; do
    hwip_name="$(basename "$hwip_dir")"
    [[ -f "$hwip_dir/hwip.yaml" ]] || continue
    [[ -n "$HWIP_FILTER" && "$hwip_name" != "$HWIP_FILTER" ]] && continue
    hwips+=("$hwip_name")
done

if [[ ${#hwips[@]} -eq 0 ]]; then
    echo "ERROR: No HWIPs found${HWIP_FILTER:+ matching '$HWIP_FILTER'}" >&2
    exit 1
fi
echo "==> HWIPs: ${hwips[*]}"

# ── Stage 1: hwip.yaml → all artifacts ───────────────────────────────────────
if [[ "$STAGE_FILTER" != "2" ]]; then
    for hwip in "${hwips[@]}"; do
        echo "==> [Stage 1] $hwip: deepspan-codegen..."
        ARGS=(
            --descriptor "$REPO_ROOT/$hwip/hwip.yaml"
            --out        "$REPO_ROOT/$hwip/gen"
            --target     all
        )
        if $CHECK_MODE; then
            # Generate to temp dir and diff
            TMP_GEN="$(mktemp -d)"
            trap 'rm -rf "$TMP_GEN"' EXIT
            deepspan-codegen \
                --descriptor "$REPO_ROOT/$hwip/hwip.yaml" \
                --out        "$TMP_GEN" \
                --target     all
            # Compare only Stage 1 outputs (l*-prefixed dirs); skip gen/go, gen/python (Stage 2)
            STALE=false
            for layer_dir in "$TMP_GEN"/l*; do
                layer="$(basename "$layer_dir")"
                if ! diff -rq \
                        --exclude='__pycache__' --exclude='*.pyc' \
                        "$layer_dir" "$REPO_ROOT/$hwip/gen/$layer" &>/dev/null; then
                    STALE=true
                    echo "  STALE: $hwip/gen/$layer/" >&2
                    diff -r --exclude='__pycache__' --exclude='*.pyc' \
                        "$layer_dir" "$REPO_ROOT/$hwip/gen/$layer" 2>&1 | head -10 >&2 || true
                fi
            done
            if $STALE; then
                echo "ERROR: $hwip/gen/ is stale. Run: ./scripts/codegen.sh --hwip $hwip" >&2
                exit 1
            fi
            echo "  $hwip/gen/ is up-to-date."
        else
            deepspan-codegen "${ARGS[@]}"
        fi
    done
fi

# ── Stage 2: proto → Go/Python gRPC stubs (buf generate) ─────────────────────
if [[ "$STAGE_FILTER" != "1" ]] && ! $CHECK_MODE; then
    echo "==> [Stage 2] buf generate..."
    cd "$REPO_ROOT"
    buf generate
fi

echo ""
if $CHECK_MODE; then
    echo "✓ All generated files are up-to-date."
else
    echo "✓ Codegen complete."
    echo "  Commit: git add '*/gen/' && git commit -m 'chore: regenerate HWIP artifacts'"
fi
