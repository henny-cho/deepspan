#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""
Deepspan CRC32 HWIP full-stack E2E smoke test (gRPC).

Flow:
  1. list_devices()          → expects crc32/0 in READY state
  2. GET_POLY (0x0002)       → polynomial must equal 0xEDB88320 (IEEE 802.3)
  3. COMPUTE (0x0001)        → compare against Python binascii.crc32
  4. COMPUTE empty input     → CRC32 of b"" = 0x00000000
  5. COMPUTE max-size input  → 3072 bytes, cross-check with binascii
  6. get_firmware_info()     → version must be non-empty
  7. get_telemetry()         → irq_count must be > 0 after submits

Exit code: 0 = all assertions passed, 1 = any failure.
"""
import binascii
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from deepspan.client import DeepspanClient

ADDR      = os.environ.get("DEEPSPAN_ADDR",   "localhost:8080")
DEVICE_ID = os.environ.get("DEEPSPAN_DEVICE", "crc32/0")

CRC32_COMPUTE  = 0x0001
CRC32_GET_POLY = 0x0002

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


def crc32_ref(data: bytes) -> int:
    return binascii.crc32(data) & 0xFFFFFFFF


def submit_u32(client: DeepspanClient, opcode: int, data: bytes = b"") -> int:
    raw = client.submit_request(DEVICE_ID, opcode=opcode, data=data)
    check(f"response is 4 bytes (opcode=0x{opcode:04X})",
          len(raw) >= 4, f"len={len(raw)}")
    return struct.unpack_from("<I", raw)[0] if len(raw) >= 4 else 0


def main() -> int:
    print(f"[crc32_test] deepspan CRC32 HWIP full-stack E2E test")
    print(f"[crc32_test] server : {ADDR}")
    print(f"[crc32_test] device : {DEVICE_ID}")
    print()

    try:
        with DeepspanClient(ADDR, timeout=10.0) as client:

            # ── 1. ListDevices ──────────────────────────────────────────────
            print("── 1. ListDevices")
            devices = client.list_devices()
            check("at least one device returned",
                  len(devices) > 0, f"got {len(devices)}")
            ids = [d.device_id for d in devices]
            check(f"{DEVICE_ID} in device list", DEVICE_ID in ids, str(ids))
            target = next((d for d in devices if d.device_id == DEVICE_ID), None)
            if target:
                check(f"{DEVICE_ID} state is READY",
                      target.state.value == 2,
                      f"got state={target.state.name}")
            print()

            # ── 2. GET_POLY ─────────────────────────────────────────────────
            print("── 2. GET_POLY (opcode=0x0002)")
            poly = submit_u32(client, CRC32_GET_POLY)
            check("polynomial == 0xEDB88320 (IEEE 802.3)",
                  poly == 0xEDB88320, f"got 0x{poly:08X}")
            print(f"       polynomial = 0x{poly:08X}")
            print()

            # ── 3. COMPUTE — known string ───────────────────────────────────
            print("── 3. COMPUTE known string")
            data = b"Hello, deepspan!"
            got  = submit_u32(client, CRC32_COMPUTE, data)
            exp  = crc32_ref(data)
            check(f"CRC32({data!r}) matches binascii reference",
                  got == exp,
                  f"got 0x{got:08X}, want 0x{exp:08X}")
            print(f"       0x{got:08X}")
            print()

            # ── 4. COMPUTE — empty input ────────────────────────────────────
            print("── 4. COMPUTE empty input")
            got = submit_u32(client, CRC32_COMPUTE, b"")
            exp = crc32_ref(b"")
            check("CRC32(b\"\") matches reference",
                  got == exp, f"got 0x{got:08X}, want 0x{exp:08X}")
            print(f"       0x{got:08X}")
            print()

            # ── 5. COMPUTE — max-size input (3072 bytes) ────────────────────
            print("── 5. COMPUTE max-size input (3072 bytes)")
            data = bytes(range(256)) * 12   # 3072 bytes, deterministic
            got  = submit_u32(client, CRC32_COMPUTE, data)
            exp  = crc32_ref(data)
            check("CRC32(3072 bytes) matches reference",
                  got == exp, f"got 0x{got:08X}, want 0x{exp:08X}")
            print(f"       0x{got:08X}")
            print()

            # ── 6. GetFirmwareInfo ──────────────────────────────────────────
            print("── 6. GetFirmwareInfo")
            try:
                info = client.get_firmware_info(DEVICE_ID)
                check("fw_version non-empty", bool(info.fw_version),
                      repr(info.fw_version))
                check("protocol_version >= 1", info.protocol_version >= 1,
                      str(info.protocol_version))
                print(f"       fw_version={info.fw_version!r}  "
                      f"protocol={info.protocol_version}")
            except Exception as exc:
                check("GetFirmwareInfo succeeded", False, str(exc))
            print()

            # ── 7. GetTelemetry ─────────────────────────────────────────────
            print("── 7. GetTelemetry")
            try:
                tel = client.get_telemetry(DEVICE_ID)
                check("telemetry device_id matches",
                      tel.device_id == DEVICE_ID, repr(tel.device_id))
                check("irq_count > 0 (hw-model processed commands)",
                      tel.irq_count > 0, f"irq_count={tel.irq_count}")
                print(f"       uptime_ms={tel.uptime_ms}  "
                      f"irq_count={tel.irq_count}")
            except Exception as exc:
                check("GetTelemetry succeeded", False, str(exc))
            print()

    except Exception as exc:
        print(f"[crc32_test] FATAL: {exc}", file=sys.stderr)
        return 1

    print("══════════════════════════════════════════════════════════")
    print(f"  Results: {PASS} passed, {FAIL} failed")
    print("══════════════════════════════════════════════════════════")
    if FAIL > 0:
        print("[crc32_test] FAILED")
        return 1
    print("[crc32_test] OK — all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
