# SPDX-License-Identifier: Apache-2.0
"""Accel HWIP Python client extensions.

Extends the base deepspan SDK with acceleration-specific helpers.
"""

from __future__ import annotations

# Accel opcode constants — mirror deepspan_accel.h
ACCEL_OP_ECHO    = 0x0001  # Echo arg0/arg1 back as result (latency test)
ACCEL_OP_PROCESS = 0x0002  # Run data processing pipeline on payload
ACCEL_OP_STATUS  = 0x0003  # Return device status word in result_data0


class AccelClient:
    """High-level client for the acceleration HWIP.

    Wraps the generated HwipService stub with accel-specific helpers.

    Example::

        client = AccelClient("http://localhost:8080")
        result = client.echo(arg0=0xABCD, arg1=0x1234)
        assert result.status == 0
    """

    def __init__(self, base_url: str) -> None:
        self._base_url = base_url
        # TODO: import generated stub once device.proto is compiled
        # from deepspan_accel.v1 import device_pb2, device_connect

    def echo(self, arg0: int = 0, arg1: int = 0, timeout_ms: int = 5000) -> object:
        """Send ECHO command; returns the SubmitRequestResponse."""
        import struct
        payload = struct.pack("<II", arg0, arg1)
        return self._submit(ACCEL_OP_ECHO, payload, timeout_ms)

    def process(self, payload: bytes, timeout_ms: int = 5000) -> object:
        """Send PROCESS command with arbitrary payload."""
        return self._submit(ACCEL_OP_PROCESS, payload, timeout_ms)

    def device_status(self, timeout_ms: int = 5000) -> object:
        """Send STATUS command; result_data0 contains the status word."""
        return self._submit(ACCEL_OP_STATUS, b"", timeout_ms)

    def _submit(self, opcode: int, payload: bytes, timeout_ms: int) -> object:
        raise NotImplementedError(
            "AccelClient._submit: generate proto stubs first — "
            "run: buf generate --template hwip/accel/buf.gen.yaml"
        )
