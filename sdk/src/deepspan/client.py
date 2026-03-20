# SPDX-License-Identifier: Apache-2.0
"""DeepspanClient: synchronous gRPC client for the deepspan server."""

from __future__ import annotations

from typing import ClassVar, Protocol, runtime_checkable

import grpc

from .models import DeviceInfo, DeviceState, FirmwareInfo, TelemetrySnapshot

try:
    from deepspan.v1 import (  # type: ignore[import]
        device_pb2,
        device_pb2_grpc,
        management_pb2,
        management_pb2_grpc,
        telemetry_pb2,
        telemetry_pb2_grpc,
    )
    _STUBS_AVAILABLE = True
except ImportError:
    _STUBS_AVAILABLE = False


def _require_stubs() -> None:
    if not _STUBS_AVAILABLE:
        raise ImportError(
            "gRPC Python stubs not found. Generate them first:\n"
            "  python sdk/scripts/gen_proto.py\n"
            "or:\n"
            "  uv run --with grpcio-tools python sdk/scripts/gen_proto.py"
        )


@runtime_checkable
class HwipExtension(Protocol):
    """Protocol that HWIP-specific extension objects must satisfy.

    Example usage::

        class AccelExtension:
            hwip_type: ClassVar[str] = "accel"

            def attach(self, client: "DeepspanClient") -> None:
                client._accel = self

            def echo(self, device_id: str, opcode: int) -> str:
                return client.submit_request(device_id, opcode)

        client.register_extension(AccelExtension())
    """

    hwip_type: ClassVar[str]

    def attach(self, client: "DeepspanClient") -> None: ...


class DeepspanClient:
    """Synchronous gRPC client for the deepspan server.

    Example::

        with DeepspanClient("localhost:8080") as client:
            devices = client.list_devices()
            req_id = client.submit_request(devices[0].device_id, opcode=0x0001)
    """

    def __init__(self, addr: str, timeout: float = 10.0) -> None:
        """
        Args:
            addr: Server address, e.g. "localhost:8080" or "[::1]:8080".
            timeout: Default RPC timeout in seconds.
        """
        _require_stubs()
        self._addr = addr
        self._timeout = timeout
        self._channel: grpc.Channel = grpc.insecure_channel(addr)
        self._hwip = device_pb2_grpc.HwipServiceStub(self._channel)
        self._mgmt = management_pb2_grpc.ManagementServiceStub(self._channel)
        self._tel = telemetry_pb2_grpc.TelemetryServiceStub(self._channel)
        self._extensions: dict[str, HwipExtension] = {}

    def close(self) -> None:
        """Close the gRPC channel."""
        self._channel.close()

    def __enter__(self) -> "DeepspanClient":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def register_extension(self, ext: HwipExtension) -> None:
        """Register a HWIP-specific extension and attach it to this client."""
        self._extensions[ext.hwip_type] = ext
        ext.attach(self)

    def get_extension(self, hwip_type: str) -> HwipExtension | None:
        """Return a registered extension by HWIP type, or None."""
        return self._extensions.get(hwip_type)

    # ── HwipService ─────────────────────────────────────────────────────────

    def list_devices(self) -> list[DeviceInfo]:
        """Return all known HWIP devices."""
        resp = self._hwip.ListDevices(
            device_pb2.ListDevicesRequest(), timeout=self._timeout
        )
        return [
            DeviceInfo(
                device_id=d.device_id,
                state=DeviceState(d.state),
            )
            for d in resp.devices
        ]

    def get_device_status(self, device_id: str) -> DeviceInfo:
        """Return current state of a device."""
        resp = self._hwip.GetDeviceStatus(
            device_pb2.GetDeviceStatusRequest(device_id=device_id),
            timeout=self._timeout,
        )
        return DeviceInfo(
            device_id=resp.info.device_id,
            state=DeviceState(resp.info.state),
        )

    def submit_request(self, device_id: str, opcode: int, data: bytes = b"") -> str:
        """Submit a synchronous request. Returns request_id as a string."""
        resp = self._hwip.SubmitRequest(
            device_pb2.SubmitRequestRequest(
                device_id=device_id,
                opcode=opcode,
                payload=data,
            ),
            timeout=self._timeout,
        )
        return str(resp.request_id)

    # ── ManagementService ────────────────────────────────────────────────────

    def get_firmware_info(self, device_id: str) -> FirmwareInfo:
        """Return firmware version/features for a device."""
        resp = self._mgmt.GetFirmwareInfo(
            management_pb2.GetFirmwareInfoRequest(device_id=device_id),
            timeout=self._timeout,
        )
        return FirmwareInfo(
            fw_version=resp.fw_version,
            build_date=resp.build_date,
            protocol_version=resp.protocol_version,
            features=list(resp.features),
        )

    def reset_device(self, device_id: str, force: bool = False) -> bool:
        """Trigger firmware reset. Returns True on success."""
        resp = self._mgmt.ResetDevice(
            management_pb2.ResetDeviceRequest(device_id=device_id, force=force),
            timeout=self._timeout,
        )
        return resp.success

    def push_config(self, device_id: str, config: dict[str, str]) -> list[str]:
        """Push runtime config to firmware. Returns list of rejected keys."""
        resp = self._mgmt.PushConfig(
            management_pb2.PushConfigRequest(device_id=device_id, config=config),
            timeout=self._timeout,
        )
        return list(resp.rejected_keys)

    def get_console_path(self, device_id: str) -> str:
        """Return PTY path for direct console access."""
        resp = self._mgmt.GetConsolePath(
            management_pb2.GetConsolePathRequest(device_id=device_id),
            timeout=self._timeout,
        )
        return resp.pty_path

    # ── TelemetryService ─────────────────────────────────────────────────────

    def get_telemetry(self, device_id: str) -> TelemetrySnapshot:
        """Return a single telemetry snapshot."""
        resp = self._tel.GetTelemetry(
            telemetry_pb2.GetTelemetryRequest(device_id=device_id),
            timeout=self._timeout,
        )
        snap = resp.snapshot
        return TelemetrySnapshot(
            device_id=snap.device_id,
            uptime_ms=snap.firmware.uptime_ms,
            irq_count=snap.kernel.irq_count,
        )
