# SPDX-License-Identifier: Apache-2.0
"""DeepspanClient: synchronous ConnectRPC client for deepspan server."""

from __future__ import annotations

import json
from typing import AsyncIterator, Iterator
import httpx

from .models import DeviceInfo, DeviceState, FirmwareInfo, TelemetrySnapshot


class DeepspanClient:
    """Synchronous client for the deepspan gRPC/ConnectRPC server.

    Example:
        client = DeepspanClient("http://localhost:8080")
        devices = client.list_devices()
        info = client.get_firmware_info("hwip0")
    """

    def __init__(self, base_url: str, timeout: float = 10.0) -> None:
        self._base = base_url.rstrip("/")
        self._http = httpx.Client(
            http2=True,
            timeout=timeout,
            headers={"Content-Type": "application/json"},
        )

    def close(self) -> None:
        self._http.close()

    def __enter__(self) -> "DeepspanClient":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    # ── HwipService ─────────────────────────────────────────────────────────

    def list_devices(self) -> list[DeviceInfo]:
        """Return all known HWIP devices."""
        resp = self._post("/deepspan.v1.HwipService/ListDevices", {})
        return [
            DeviceInfo(
                device_id=d.get("deviceId", ""),
                state=self._parse_state(d.get("state", 0)),
            )
            for d in resp.get("devices", [])
        ]

    def get_device_status(self, device_id: str) -> DeviceInfo:
        """Return current state of a device."""
        resp = self._post(
            "/deepspan.v1.HwipService/GetDeviceStatus",
            {"deviceId": device_id},
        )
        return DeviceInfo(
            device_id=device_id,
            state=self._parse_state(resp.get("state", 0)),
        )

    def submit_request(self, device_id: str, opcode: int, data: bytes = b"") -> str:
        """Submit a synchronous request. Returns request_id."""
        resp = self._post(
            "/deepspan.v1.HwipService/SubmitRequest",
            {"deviceId": device_id, "opcode": opcode, "data": list(data)},
        )
        return resp.get("requestId", "")

    # ── ManagementService ────────────────────────────────────────────────────

    def get_firmware_info(self, device_id: str) -> FirmwareInfo:
        """Return firmware version/features for a device."""
        resp = self._post(
            "/deepspan.v1.ManagementService/GetFirmwareInfo",
            {"deviceId": device_id},
        )
        return FirmwareInfo(
            fw_version=resp.get("fwVersion", ""),
            build_date=resp.get("buildDate", ""),
            protocol_version=int(resp.get("protocolVersion", 0)),
            features=resp.get("features", []),
        )

    def reset_device(self, device_id: str, force: bool = False) -> bool:
        """Trigger firmware reset. Returns True on success."""
        resp = self._post(
            "/deepspan.v1.ManagementService/ResetDevice",
            {"deviceId": device_id, "force": force},
        )
        return bool(resp.get("success", False))

    def push_config(self, device_id: str, config: dict[str, str]) -> list[str]:
        """Push runtime config to firmware. Returns list of rejected keys."""
        resp = self._post(
            "/deepspan.v1.ManagementService/PushConfig",
            {"deviceId": device_id, "config": config},
        )
        return resp.get("rejectedKeys", [])

    def get_console_path(self, device_id: str) -> str:
        """Return PTY path for direct console access."""
        resp = self._post(
            "/deepspan.v1.ManagementService/GetConsolePath",
            {"deviceId": device_id},
        )
        return resp.get("ptyPath", "")

    # ── TelemetryService ─────────────────────────────────────────────────────

    def get_telemetry(self, device_id: str) -> TelemetrySnapshot:
        """Return a single telemetry snapshot."""
        resp = self._post(
            "/deepspan.v1.TelemetryService/GetTelemetry",
            {"deviceId": device_id},
        )
        snap = resp.get("snapshot", {})
        return TelemetrySnapshot(
            device_id=snap.get("deviceId", device_id),
            timestamp_ms=int(snap.get("timestampMs", 0)),
            cpu_usage=float(snap.get("cpuUsage", 0.0)),
            mem_usage=float(snap.get("memUsage", 0.0)),
        )

    # ── Internal ──────────────────────────────────────────────────────────────

    @staticmethod
    def _parse_state(raw: object) -> DeviceState:
        """Parse a proto DeviceState value (int or proto-JSON string) into DeviceState."""
        if isinstance(raw, int):
            return DeviceState(raw)
        # Proto JSON encodes enums as "DEVICE_STATE_<NAME>" strings
        if isinstance(raw, str):
            suffix = raw.removeprefix("DEVICE_STATE_")
            try:
                return DeviceState[suffix]
            except KeyError:
                return DeviceState.UNSPECIFIED
        return DeviceState.UNSPECIFIED

    def _post(self, procedure: str, body: dict) -> dict:
        """Send a ConnectRPC unary request (JSON wire format)."""
        r = self._http.post(self._base + procedure, json=body)
        r.raise_for_status()
        return r.json()
