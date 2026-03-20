#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""
Deepspan hello-world example.
Connects to the server, lists devices, prints hw-model register state,
and shows the live firmware_sim ↔ hw-model interaction.
"""
import sys
import os
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import httpx
from deepspan.client import DeepspanClient

BASE_URL = os.environ.get("DEEPSPAN_URL", "http://localhost:8080")


def _get_hw_stats(http: httpx.Client) -> dict:
    try:
        r = http.get(BASE_URL + "/api/hw-stats", timeout=3.0)
        r.raise_for_status()
        return r.json()
    except Exception:
        return {"available": False}


def _print_hw_stats(stats: dict) -> None:
    if not stats.get("available"):
        print("[hello] hw-model: not available (run deepspan-hw-model first)")
        return
    print("[hello] hw-model register state:")
    print(f"  version       = {stats['version']}  (v{stats['version_str']})")
    print(f"  capabilities  = {stats['capabilities']}  {stats['capabilities_str']}")
    ready = "READY" if stats["status_ready"] else ("BUSY" if stats["status_busy"] else "ERROR")
    print(f"  status        = {stats['status_reg']}  [{ready}]")
    print(f"  uptime        = {stats['uptime_s']}s")
    print(f"  hw cmd_count  = {stats['hw_cmd_count']}")
    print(f"  fw cmd_count  = {stats['fw_cmd_count']}")
    if stats["hw_cmd_count"] > 0:
        print(f"  last opcode   = {stats['last_opcode']}")
        print(f"  last result   = {stats['last_result_status']}")
        print(f"  result_data0  = {stats['result_data0']}")
        print(f"  result_data1  = {stats['result_data1']}")


def main() -> None:
    print(f"[hello] connecting to {BASE_URL}")
    http = httpx.Client(http2=True, timeout=10.0,
                        headers={"Content-Type": "application/json"})

    with DeepspanClient(BASE_URL) as client:
        # ── Device list ──────────────────────────────────────────────────
        devices = client.list_devices()
        if not devices:
            print("[hello] no devices found")
            sys.exit(1)

        print(f"[hello] found {len(devices)} device(s):")
        for dev in devices:
            print(f"  device_id={dev.device_id}  state={dev.state.name}")

        # ── Firmware info (requires real Zephyr / OpenAMP) ───────────────
        dev_id = devices[0].device_id
        try:
            info = client.get_firmware_info(dev_id)
            print(f"[hello] firmware info for {dev_id}:")
            print(f"  fw_version={info.fw_version}")
            print(f"  build_date={info.build_date}")
            print(f"  protocol_version={info.protocol_version}")
        except Exception as exc:
            print(f"[hello] firmware info unavailable in sim mode: {exc}")

        # ── HW-model register state ──────────────────────────────────────
        print()
        stats_before = _get_hw_stats(http)
        _print_hw_stats(stats_before)

        # ── Watch firmware_sim ↔ hw-model interaction for 3s ────────────
        if stats_before.get("available"):
            print()
            print("[hello] watching firmware_sim ↔ hw-model interaction (3s)...")
            start_hw  = stats_before["hw_cmd_count"]
            start_fw  = stats_before["fw_cmd_count"]
            deadline  = time.monotonic() + 3.0
            prev_hw   = start_hw
            prev_fw   = start_fw
            while time.monotonic() < deadline:
                time.sleep(0.4)
                s = _get_hw_stats(http)
                if not s.get("available"):
                    break
                if s["hw_cmd_count"] != prev_hw or s["fw_cmd_count"] != prev_fw:
                    print(f"  hw_cmd_count={s['hw_cmd_count']}  fw_cmd_count={s['fw_cmd_count']}"
                          f"  result_data0={s['result_data0']}")
                    prev_hw = s["hw_cmd_count"]
                    prev_fw = s["fw_cmd_count"]

            stats_after = _get_hw_stats(http)
            delta_hw = stats_after["hw_cmd_count"] - start_hw
            delta_fw = stats_after["fw_cmd_count"] - start_fw
            print(f"[hello] interaction summary: hw processed={delta_hw}  fw sent={delta_fw}")

        print()
        print(f"[hello] web monitor: {BASE_URL}/monitor")
        print("[hello] OK")

    http.close()


if __name__ == "__main__":
    main()
