#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Multi-HWIP demo: exercises accel and codec devices simultaneously.

Prerequisites:
    # Build and start the server with both plugins loaded:
    cmake --preset dev-hwip && cmake --build build/dev-hwip
    build/dev-hwip/deepspan-server \\
        --hwip-plugin build/dev-hwip/hwip/accel/plugin/libhwip_accel.so \\
        --hwip-plugin build/dev-hwip/hwip/codec/plugin/libhwip_codec.so &

    # Install the Python SDK:
    cd sdk && uv pip install -e .

Usage:
    uv run python hwip/demo/demo.py [--addr localhost:8080]
"""

from __future__ import annotations

import argparse
import sys

from deepspan import DeepspanClient


def main() -> int:
    parser = argparse.ArgumentParser(description="deepspan multi-HWIP demo")
    parser.add_argument("--addr", default="localhost:8080",
                        help="deepspan-server address (default: localhost:8080)")
    args = parser.parse_args()

    print(f"Connecting to deepspan-server at {args.addr} ...")
    with DeepspanClient(args.addr) as client:
        devices = client.list_devices()
        if not devices:
            print("No devices found. Is deepspan-server running with HWIP plugins?")
            return 1

        print(f"Discovered {len(devices)} device(s):")
        for dev in devices:
            print(f"  {dev.device_id!r:20s}  state={dev.state.name}")

        # Submit a request to each device independently.
        for dev in devices:
            try:
                req_id = client.submit_request(dev.device_id, opcode=0x0001,
                                               data=b"\xDE\xAD\xBE\xEF")
                print(f"  submit_request({dev.device_id!r}) → request_id={req_id!r}")
            except Exception as exc:  # noqa: BLE001
                print(f"  submit_request({dev.device_id!r}) FAILED: {exc}")

    print("Demo complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
