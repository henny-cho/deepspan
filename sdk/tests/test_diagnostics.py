# SPDX-License-Identifier: Apache-2.0
import json
import pytest
from unittest.mock import MagicMock, patch
from deepspan import AIDiagnostics
from deepspan.models import DeviceInfo, DeviceState, FirmwareInfo, TelemetrySnapshot


@pytest.fixture
def mock_anthropic():
    with patch("deepspan.diagnostics.anthropic.Anthropic") as mock_cls:
        mock_instance = MagicMock()
        mock_cls.return_value = mock_instance
        yield mock_instance


def test_diagnose_device_calls_claude(mock_anthropic):
    mock_anthropic.messages.create.return_value = MagicMock(
        content=[MagicMock(text="**Assessment**: Device healthy")]
    )
    diag = AIDiagnostics(api_key="test-key")
    report = diag.diagnose_device(
        device=DeviceInfo("hwip0", DeviceState.ERROR),
        firmware=FirmwareInfo("v1.0.0", "2026-01-01", 1, ["echo"]),
    )
    assert "Assessment" in report
    mock_anthropic.messages.create.assert_called_once()


def test_suggest_config_parses_json(mock_anthropic):
    mock_anthropic.messages.create.return_value = MagicMock(
        content=[MagicMock(text='{"log_level": "debug", "watchdog_ms": "5000"}')]
    )
    diag = AIDiagnostics(api_key="test-key")
    config = diag.suggest_config(
        device=DeviceInfo("hwip0", DeviceState.READY),
        goal="enable verbose logging",
    )
    assert config["log_level"] == "debug"
    assert config["watchdog_ms"] == "5000"


def test_suggest_config_strips_code_fences(mock_anthropic):
    mock_anthropic.messages.create.return_value = MagicMock(
        content=[MagicMock(text='```json\n{"key": "value"}\n```')]
    )
    diag = AIDiagnostics(api_key="test-key")
    config = diag.suggest_config(
        device=DeviceInfo("hwip0", DeviceState.READY),
        goal="test",
    )
    assert config == {"key": "value"}
