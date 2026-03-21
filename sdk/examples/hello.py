#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""
Deepspan full-stack E2E smoke test (gRPC).

Flow:
  1. list_devices()         → expects accel/0 in READY state
  2. submit_request()       → ECHO opcode, decodes and verifies arg0/arg1 round-trip
  3. get_firmware_info()    → shows version (sim: reads SHM)
  4. get_telemetry()        → shows uptime_ms and irq_count from SHM stats

Exit code: 0 = all assertions passed, 1 = any failure.
"""
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from deepspan.client import DeepspanClient

ADDR = os.environ.get("DEEPSPAN_ADDR", "localhost:8080")
DEVICE_ID = os.environ.get("DEEPSPAN_DEVICE", "accel/0")
ECHO_OPCODE = 0x0001  # AccelOp::ECHO

PASS = 0
FAIL = 0


def check(label: str, ok: bool, detail: str = "") -> None:
    global PASS, FAIL
    if ok:
        PASS += 1
        print(f"  [PASS] {label}")
    else:
        FAIL += 1
        print(f"  [FAIL] {label}" + (f" — {detail}" if detail else ""))


def main() -> int:
    print(f"[hello] deepspan full-stack E2E test")
    print(f"[hello] server : {ADDR}")
    print(f"[hello] device : {DEVICE_ID}")
    print()

    try:
        with DeepspanClient(ADDR, timeout=10.0) as client:

            # ── 1. ListDevices ──────────────────────────────────────────────
            print("── 1. ListDevices")
            devices = client.list_devices()
            check("at least one device returned", len(devices) > 0,
                  f"got {len(devices)}")

            ids = [d.device_id for d in devices]
            check(f"{DEVICE_ID} in device list", DEVICE_ID in ids, str(ids))

            target = next((d for d in devices if d.device_id == DEVICE_ID), None)
            if target:
                # DeviceState.READY == 2
                check(f"{DEVICE_ID} state is READY",
                      target.state.value == 2,
                      f"got state={target.state.name}")
            print()

            # ── 2. SubmitRequest — ECHO ────────────────────────────────────
            print("── 2. SubmitRequest (ECHO opcode=0x0001)")
            arg0 = 0xDEADBEEF
            arg1 = 0xCAFEBABE
            payload = struct.pack("<II", arg0, arg1)   # 8 bytes little-endian

            raw = client.submit_request(DEVICE_ID, opcode=ECHO_OPCODE,
                                        data=payload)
            check("submit_request returned 8 response bytes",
                  len(raw) == 8,
                  f"len={len(raw)}")
            if len(raw) == 8:
                r0, r1 = struct.unpack_from("<II", raw)
                check("ECHO data0 round-trips arg0", r0 == arg0,
                      f"got 0x{r0:08X}, want 0x{arg0:08X}")
                check("ECHO data1 round-trips arg1", r1 == arg1,
                      f"got 0x{r1:08X}, want 0x{arg1:08X}")
                print(f"       data0=0x{r0:08X}  data1=0x{r1:08X}")
            print()

            # ── 3. GetFirmwareInfo ─────────────────────────────────────────
            print("── 3. GetFirmwareInfo")
            try:
                info = client.get_firmware_info(DEVICE_ID)
                check("fw_version non-empty", bool(info.fw_version),
                      repr(info.fw_version))
                check("protocol_version >= 1", info.protocol_version >= 1,
                      str(info.protocol_version))
                print(f"       fw_version={info.fw_version!r}  "
                      f"build_date={info.build_date!r}  "
                      f"protocol={info.protocol_version}")
            except Exception as exc:
                check("GetFirmwareInfo succeeded", False, str(exc))
            print()

            # ── 4. GetTelemetry ───────────────────────────────────────────
            print("── 4. GetTelemetry")
            try:
                tel = client.get_telemetry(DEVICE_ID)
                check("telemetry device_id matches", tel.device_id == DEVICE_ID,
                      repr(tel.device_id))
                # After at least one submit, irq_count should be > 0
                check("irq_count > 0 (hw-model processed commands)",
                      tel.irq_count > 0,
                      f"irq_count={tel.irq_count}")
                print(f"       uptime_ms={tel.uptime_ms}  "
                      f"irq_count={tel.irq_count}")
            except Exception as exc:
                check("GetTelemetry succeeded", False, str(exc))
            print()

    except Exception as exc:
        print(f"[hello] FATAL: {exc}", file=sys.stderr)
        return 1

    # ── Summary ────────────────────────────────────────────────────────────
    print("══════════════════════════════════════════════════════════")
    print(f"  Results: {PASS} passed, {FAIL} failed")
    print("══════════════════════════════════════════════════════════")
    if FAIL > 0:
        print("[hello] FAILED")
        return 1
    print("[hello] OK — all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
