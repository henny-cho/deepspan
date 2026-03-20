#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Generate Python gRPC stubs from deepspan proto files.

Usage:
    python sdk/scripts/gen_proto.py
    # or:
    uv run --with grpcio-tools python sdk/scripts/gen_proto.py

Output: sdk/src/deepspan/_proto/  (excluded from VCS)
"""
from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
PROTO_ROOT = REPO_ROOT / "api" / "proto"
# Stubs go into sdk/src/ so generated files land at deepspan/v1/*.py,
# making cross-imports like `from deepspan.v1 import device_pb2` work.
OUT_DIR = REPO_ROOT / "sdk" / "src"

PROTO_FILES = [
    "deepspan/v1/device.proto",
    "deepspan/v1/management.proto",
    "deepspan/v1/telemetry.proto",
]


def main() -> int:
    try:
        from grpc_tools import protoc  # type: ignore[import]
    except ImportError:
        print("grpcio-tools not installed. Run: pip install grpcio-tools", file=sys.stderr)
        return 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    # Ensure deepspan/v1/ __init__.py exists so generated stubs are importable.
    (OUT_DIR / "deepspan" / "v1").mkdir(parents=True, exist_ok=True)
    (OUT_DIR / "deepspan" / "v1" / "__init__.py").write_text("# auto-generated\n")

    for proto_rel in PROTO_FILES:
        ret = protoc.main([
            "grpc_tools.protoc",
            f"--proto_path={PROTO_ROOT}",
            # Well-known types bundled with grpcio-tools
            f"--proto_path={Path(protoc.__file__).parent / '_proto'}",
            f"--python_out={OUT_DIR}",
            f"--grpc_python_out={OUT_DIR}",
            str(PROTO_ROOT / proto_rel),
        ])
        if ret != 0:
            print(f"protoc failed for {proto_rel}", file=sys.stderr)
            return ret
        print(f"  generated: {proto_rel}")

    print(f"\nProto stubs written to: {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
