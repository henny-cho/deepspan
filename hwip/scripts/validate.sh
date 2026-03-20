#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# validate.sh — runtime validation for deepspan-hwip generated artifacts.
#
# Checks:
#   1. codegen stale check  — gen/ matches hwip.yaml
#   2. C kernel header      — gcc -fsyntax-only
#   3. C++ l3-cpp header    — g++ -fsyntax-only -std=c++17
#   4. Go format            — gofmt -l (must produce no output)
#   5. Go vet               — go vet on generated opcodes.go
#   6. Python syntax        — python3 -m py_compile
#   7. Proto lint           — buf lint (if buf available)
#
# Usage:
#   ./scripts/validate.sh [--hwip accel] [--skip-syntax] [--fix]
#
# Environment:
#   CODEGEN_BIN  path to deepspan-codegen (default: deepspan-codegen in PATH)
#
# Exit code:
#   0  all checks passed (or skipped)
#   1  one or more checks failed

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${REPO_ROOT}/scripts/lib.sh"
hwip_setup_path
HWIP_LOG_PREFIX="[validate]"

HWIP_FILTER=""
SKIP_SYNTAX=false
FIX_MODE=false
CODEGEN_BIN="${CODEGEN_BIN:-deepspan-codegen}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --hwip)         HWIP_FILTER="$2"; shift 2 ;;
        --skip-syntax)  SKIP_SYNTAX=true; shift ;;
        --fix)          FIX_MODE=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--hwip <type>] [--skip-syntax] [--fix]"
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

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

echo "deepspan-hwip validate — HWIPs: ${hwips[*]}"

# ── Check 1: Codegen stale check ─────────────────────────────────────────────
section "Check 1: Codegen stale check"
if ! command -v "$CODEGEN_BIN" &>/dev/null; then
    skip "deepspan-codegen not found (set CODEGEN_BIN or install)"
else
    for hwip in "${hwips[@]}"; do
        TMP_GEN="$(mktemp -d)"

        "$CODEGEN_BIN" \
            --descriptor "$REPO_ROOT/$hwip/hwip.yaml" \
            --out "$TMP_GEN" \
            --target all \
            >/dev/null 2>&1

        # Only compare Stage-1 outputs (l*-prefixed dirs); skip gen/go/ and gen/python/ (Stage-2).
        STALE=false
        for layer_dir in "$TMP_GEN"/l*; do
            [ -d "$layer_dir" ] || continue
            layer="$(basename "$layer_dir")"
            if ! diff -rq \
                    --exclude='__pycache__' --exclude='*.pyc' \
                    "$layer_dir" "$REPO_ROOT/$hwip/gen/$layer" &>/dev/null; then
                STALE=true
                diff -r --exclude='__pycache__' --exclude='*.pyc' \
                    "$layer_dir" "$REPO_ROOT/$hwip/gen/$layer" 2>&1 | head -20 >&2 || true
            fi
        done

        if ! $STALE; then
            pass "$hwip/gen/ is up-to-date"
        else
            if $FIX_MODE; then
                echo "  [FIX]  Regenerating $hwip/gen/..."
                "$CODEGEN_BIN" \
                    --descriptor "$REPO_ROOT/$hwip/hwip.yaml" \
                    --out "$REPO_ROOT/$hwip/gen" \
                    --target all >/dev/null
                pass "$hwip/gen/ regenerated"
            else
                fail "$hwip/gen/ is stale — run: deepspan-codegen --descriptor $hwip/hwip.yaml --out $hwip/gen"
            fi
        fi
        rm -rf "$TMP_GEN"
    done
fi

# ── Check 2: C kernel header syntax ──────────────────────────────────────────
section "Check 2: C kernel header syntax (gcc -fsyntax-only)"
if $SKIP_SYNTAX; then
    skip "skipped via --skip-syntax"
elif ! command -v gcc &>/dev/null; then
    skip "gcc not found"
else
    for hwip in "${hwips[@]}"; do
        gen_dir="$REPO_ROOT/$hwip/gen"
        while IFS= read -r -d '' hfile; do
            rel="${hfile#"$REPO_ROOT"/}"
            # Use system linux/types.h; suppress warnings from host/kernel header mix
            if gcc -fsyntax-only -x c -std=gnu11 \
                -isystem /usr/include \
                -Wno-unused-macros -Wno-redundant-decls \
                "$hfile" 2>/dev/null; then
                pass "$rel"
            else
                errs="$(gcc -fsyntax-only -x c -std=gnu11 \
                    -isystem /usr/include \
                    "$hfile" 2>&1 | grep ': error:' | head -5)"
                if [[ -n "$errs" ]]; then
                    fail "$rel — C syntax error"
                    echo "$errs" >&2
                else
                    pass "$rel (warnings only)"
                fi
            fi
        done < <(find "$gen_dir/l1-kernel" -name "*.h" -print0 2>/dev/null)
    done
fi

# ── Check 3: C++ hw_model header syntax ──────────────────────────────────────
section "Check 3: C++ l3-cpp header syntax (g++ -std=c++17)"
if $SKIP_SYNTAX; then
    skip "skipped via --skip-syntax"
elif ! command -v g++ &>/dev/null; then
    skip "g++ not found"
else
    for hwip in "${hwips[@]}"; do
        gen_dir="$REPO_ROOT/$hwip/gen"
        while IFS= read -r -d '' hfile; do
            rel="${hfile#"$REPO_ROOT"/}"
            if g++ -fsyntax-only -x c++ -std=c++17 \
                -Wno-unused-variable \
                "$hfile" 2>/dev/null; then
                pass "$rel"
            else
                errs="$(g++ -fsyntax-only -x c++ -std=c++17 "$hfile" 2>&1 \
                    | grep ': error:' | head -5)"
                if [[ -n "$errs" ]]; then
                    fail "$rel — C++ syntax error"
                    echo "$errs" >&2
                else
                    pass "$rel (warnings only)"
                fi
            fi
        done < <(find "$gen_dir/l3-cpp" -name "*.hpp" -print0 2>/dev/null)
    done
fi

# Note: firmware dispatch headers (gen/firmware/) require Zephyr toolchain
# and are excluded from host syntax checks.

# ── Check 4: Go format ────────────────────────────────────────────────────────
section "Check 4: Go format (gofmt -l)"
if ! command -v gofmt &>/dev/null; then
    skip "gofmt not found"
else
    for hwip in "${hwips[@]}"; do
        gen_dir="$REPO_ROOT/$hwip/gen"
        while IFS= read -r -d '' gofile; do
            rel="${gofile#"$REPO_ROOT"/}"
            unformatted="$(gofmt -l "$gofile")"
            if [[ -z "$unformatted" ]]; then
                pass "$rel"
            else
                if $FIX_MODE; then
                    gofmt -w "$gofile"
                    pass "$rel (reformatted)"
                else
                    fail "$rel — not gofmt-formatted"
                    gofmt -d "$gofile" 2>&1 | head -20 >&2 || true
                fi
            fi
        done < <(find "$gen_dir/l4-rpc" -name "*.go" -print0 2>/dev/null)
    done
fi

# ── Check 5: Go vet ───────────────────────────────────────────────────────────
section "Check 5: Go vet"
if ! command -v go &>/dev/null; then
    skip "go not found"
else
    for hwip in "${hwips[@]}"; do
        gen_dir="$REPO_ROOT/$hwip/gen/l4-rpc"
        [[ -d "$gen_dir" ]] || { skip "$hwip/gen/l4-rpc/ not found"; continue; }

        while IFS= read -r -d '' gofile; do
            rel="${gofile#"$REPO_ROOT"/}"
            # Isolated module to allow go vet without workspace context
            TMP_MOD="$(mktemp -d)"
            cp "$gofile" "$TMP_MOD/"
            printf 'module gen_validate\ngo 1.21\n' > "$TMP_MOD/go.mod"
            if ( cd "$TMP_MOD" && GOWORK=off go vet . ) 2>/dev/null; then
                pass "$rel"
            else
                fail "$rel — go vet failed"
                ( cd "$TMP_MOD" && GOWORK=off go vet . ) 2>&1 | head -10 >&2 || true
            fi
            rm -rf "$TMP_MOD"
        done < <(find "$gen_dir" -name "*.go" -print0 2>/dev/null)
    done
fi

# ── Check 6: Python syntax ────────────────────────────────────────────────────
section "Check 6: Python syntax (py_compile)"
if ! command -v python3 &>/dev/null; then
    skip "python3 not found"
else
    for hwip in "${hwips[@]}"; do
        gen_dir="$REPO_ROOT/$hwip/gen"
        while IFS= read -r -d '' pyfile; do
            rel="${pyfile#"$REPO_ROOT"/}"
            if python3 -m py_compile "$pyfile" 2>/dev/null; then
                pass "$rel"
            else
                fail "$rel — Python syntax error"
                python3 -m py_compile "$pyfile" 2>&1 >&2 || true
            fi
        done < <(find "$gen_dir/l6-sdk" -name "*.py" -print0 2>/dev/null)
    done
fi

# ── Check 7: Proto lint ───────────────────────────────────────────────────────
section "Check 7: Proto lint (buf lint)"
if ! command -v buf &>/dev/null; then
    skip "buf not found"
else
    for hwip in "${hwips[@]}"; do
        proto_dir="$REPO_ROOT/$hwip/gen/l5-proto"
        if [[ ! -d "$proto_dir" ]]; then
            skip "$hwip/gen/l5-proto/ not found"
            continue
        fi
        # Inline buf config to avoid workspace dependency
        CFG='{"version":"v2","lint":{"use":["DEFAULT"],"except":["PACKAGE_VERSION_SUFFIX"]}}'
        if buf lint --config "$CFG" "$proto_dir" 2>/dev/null; then
            pass "$hwip/gen/l5-proto/ lint"
        else
            lint_out="$(buf lint --config "$CFG" "$proto_dir" 2>&1 | head -20)"
            if [[ -n "$lint_out" ]]; then
                fail "$hwip/gen/l5-proto/ lint"
                echo "$lint_out" >&2
            else
                pass "$hwip/gen/l5-proto/ lint"
            fi
        fi
    done
fi

# ── Summary ───────────────────────────────────────────────────────────────────
if [[ $FAIL -gt 0 ]]; then
    echo ""
fi
hwip_summary || { echo "Fix issues above or run with --fix for auto-fixable checks."; exit 1; }
