#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""
Deepspan hello-world example.
Connects to the server, lists devices, and prints firmware info.
"""
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from deepspan.client import DeepspanClient

BASE_URL = os.environ.get("DEEPSPAN_URL", "http://localhost:8080")


def main() -> None:
    print(f"[hello] connecting to {BASE_URL}")
    with DeepspanClient(BASE_URL) as client:
        devices = client.list_devices()
        if not devices:
            print("[hello] no devices found")
            sys.exit(1)

        print(f"[hello] found {len(devices)} device(s):")
        for dev in devices:
            print(f"  device_id={dev.device_id}  state={dev.state.name}")

        # Fetch firmware info for first device
        dev_id = devices[0].device_id
        try:
            info = client.get_firmware_info(dev_id)
            print(f"[hello] firmware info for {dev_id}:")
            print(f"  fw_version={info.fw_version}")
            print(f"  build_date={info.build_date}")
            print(f"  protocol_version={info.protocol_version}")
            print(f"  features={info.features}")
        except Exception as exc:
            # In simulation mode the mgmt-daemon transport is /dev/null;
            # firmware info is not available without a real Zephyr connection.
            print(f"[hello] firmware info unavailable in sim mode: {exc}")

        print("[hello] OK")


if __name__ == "__main__":
    main()
