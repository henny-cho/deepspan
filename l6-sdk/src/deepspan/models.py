# SPDX-License-Identifier: Apache-2.0
"""Pure Python data models corresponding to deepspan proto types."""

from dataclasses import dataclass, field
from enum import IntEnum
from typing import Optional


class DeviceState(IntEnum):
    UNSPECIFIED  = 0
    INITIALIZING = 1
    READY        = 2
    RUNNING      = 3
    ERROR        = 4
    RESETTING    = 5


@dataclass
class DeviceInfo:
    device_id: str
    state: DeviceState = DeviceState.UNSPECIFIED


@dataclass
class FirmwareInfo:
    fw_version: str
    build_date: str
    protocol_version: int
    features: list[str] = field(default_factory=list)


@dataclass
class TelemetrySnapshot:
    device_id: str
    timestamp_ms: int
    cpu_usage: float = 0.0
    mem_usage: float = 0.0
