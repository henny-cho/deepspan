# SPDX-License-Identifier: Apache-2.0
"""AIDiagnostics: AI-powered device diagnostics using Claude API."""

from __future__ import annotations

import json
from typing import Optional

import anthropic

from .models import DeviceInfo, DeviceState, FirmwareInfo, TelemetrySnapshot


# System prompt — gives Claude context about the deepspan stack
_SYSTEM_PROMPT = """\
You are an expert embedded systems diagnostics assistant for the Deepspan hardware stack.
The stack consists of:
- Zephyr RTOS firmware running on a custom HWIP (Hardware IP) device
- Linux kernel virtio/RPMsg driver for communication
- io_uring-based userspace library
- gRPC management and telemetry services

When diagnosing issues, consider:
1. Firmware state machine transitions (INITIALIZING → READY → RUNNING → ERROR)
2. virtio/RPMsg channel health
3. io_uring queue depth and submission/completion ratios
4. CPU/memory pressure on both Linux and Zephyr sides

Provide concise, actionable diagnostics. Format as:
- **Assessment**: one-line summary
- **Root cause**: most likely explanation
- **Actions**: numbered steps to resolve
"""


class AIDiagnostics:
    """Claude-powered diagnostics for deepspan devices.

    Example:
        diag = AIDiagnostics()  # uses ANTHROPIC_API_KEY env var
        report = diag.diagnose_device(
            device=DeviceInfo("hwip0", DeviceState.ERROR),
            firmware=firmware_info,
            telemetry=telemetry_snapshot,
        )
        print(report)
    """

    def __init__(
        self,
        api_key: Optional[str] = None,
        model: str = "claude-sonnet-4-6",
    ) -> None:
        self._client = anthropic.Anthropic(api_key=api_key)  # None → uses env var
        self._model = model

    def diagnose_device(
        self,
        device: DeviceInfo,
        firmware: Optional[FirmwareInfo] = None,
        telemetry: Optional[TelemetrySnapshot] = None,
        error_log: Optional[str] = None,
    ) -> str:
        """Run AI diagnostics on a device and return a markdown report."""
        context = self._build_context(device, firmware, telemetry, error_log)
        message = self._client.messages.create(
            model=self._model,
            max_tokens=1024,
            system=_SYSTEM_PROMPT,
            messages=[{"role": "user", "content": context}],
        )
        return message.content[0].text

    def suggest_config(
        self,
        device: DeviceInfo,
        goal: str,
        current_config: Optional[dict[str, str]] = None,
    ) -> dict[str, str]:
        """Ask Claude to suggest runtime config key-value pairs for a given goal.

        Returns: dict[str, str] with suggested config (ready to pass to push_config).
        """
        prompt = (
            f"Device: {device.device_id} (state: {device.state.name})\n"
            f"Goal: {goal}\n"
        )
        if current_config:
            prompt += f"Current config: {json.dumps(current_config, indent=2)}\n"
        prompt += (
            "\nRespond with ONLY a JSON object of key-value string pairs "
            "representing the suggested config changes. No explanation."
        )
        message = self._client.messages.create(
            model=self._model,
            max_tokens=512,
            system=_SYSTEM_PROMPT,
            messages=[{"role": "user", "content": prompt}],
        )
        text = message.content[0].text.strip()
        # Strip markdown code fences if present
        if text.startswith("```"):
            lines = text.splitlines()
            text = "\n".join(lines[1:-1])
        return json.loads(text)

    @staticmethod
    def _build_context(
        device: DeviceInfo,
        firmware: Optional[FirmwareInfo],
        telemetry: Optional[TelemetrySnapshot],
        error_log: Optional[str],
    ) -> str:
        parts = [
            f"## Device: {device.device_id}",
            f"State: {device.state.name}",
        ]
        if firmware:
            parts += [
                "",
                "## Firmware",
                f"Version: {firmware.fw_version}",
                f"Build date: {firmware.build_date}",
                f"Protocol: v{firmware.protocol_version}",
                f"Features: {', '.join(firmware.features) or 'none'}",
            ]
        if telemetry:
            parts += [
                "",
                "## Telemetry",
                f"CPU usage: {telemetry.cpu_usage:.1f}%",
                f"Memory usage: {telemetry.mem_usage:.1f}%",
                f"Timestamp: {telemetry.timestamp_ms} ms",
            ]
        if error_log:
            parts += [
                "",
                "## Error log",
                "```",
                error_log,
                "```",
            ]
        parts.append("\nPlease diagnose this device.")
        return "\n".join(parts)
