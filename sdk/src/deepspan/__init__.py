# SPDX-License-Identifier: Apache-2.0
"""Deepspan Python SDK — hardware-to-service stack client library."""

from .client import DeepspanClient
from .models import DeviceInfo, DeviceState, TelemetrySnapshot, FirmwareInfo

try:
    from .diagnostics import AIDiagnostics
    _HAS_DIAGNOSTICS = True
except ImportError:
    _HAS_DIAGNOSTICS = False

__all__ = [
    "DeepspanClient",
    "DeviceInfo",
    "DeviceState",
    "TelemetrySnapshot",
    "FirmwareInfo",
]
if _HAS_DIAGNOSTICS:
    __all__.append("AIDiagnostics")
