# SPDX-License-Identifier: Apache-2.0
import pytest
import respx
import httpx
from deepspan import DeepspanClient
from deepspan.models import DeviceState


@pytest.fixture
def client():
    c = DeepspanClient("http://localhost:8080")
    yield c
    c.close()


@respx.mock
def test_list_devices(client):
    respx.post("http://localhost:8080/deepspan.v1.HwipService/ListDevices").mock(
        return_value=httpx.Response(200, json={
            "devices": [{"deviceId": "hwip0", "state": 2}]
        })
    )
    devices = client.list_devices()
    assert len(devices) == 1
    assert devices[0].device_id == "hwip0"
    assert devices[0].state == DeviceState.READY


@respx.mock
def test_get_firmware_info(client):
    respx.post("http://localhost:8080/deepspan.v1.ManagementService/GetFirmwareInfo").mock(
        return_value=httpx.Response(200, json={
            "fwVersion": "v2.1.0",
            "buildDate": "2026-01-01T00:00:00Z",
            "protocolVersion": 1,
            "features": ["echo", "process"],
        })
    )
    info = client.get_firmware_info("hwip0")
    assert info.fw_version == "v2.1.0"
    assert info.protocol_version == 1
    assert "echo" in info.features


@respx.mock
def test_push_config_no_rejections(client):
    respx.post("http://localhost:8080/deepspan.v1.ManagementService/PushConfig").mock(
        return_value=httpx.Response(200, json={"success": True, "rejectedKeys": []})
    )
    rejected = client.push_config("hwip0", {"log_level": "debug"})
    assert rejected == []


@respx.mock
def test_get_telemetry(client):
    respx.post("http://localhost:8080/deepspan.v1.TelemetryService/GetTelemetry").mock(
        return_value=httpx.Response(200, json={
            "snapshot": {
                "deviceId": "hwip0",
                "timestampMs": 1700000000000,
                "cpuUsage": 12.5,
                "memUsage": 34.2,
            }
        })
    )
    snap = client.get_telemetry("hwip0")
    assert snap.device_id == "hwip0"
    assert snap.cpu_usage == pytest.approx(12.5)


def test_client_context_manager():
    """Verify __enter__/__exit__ work without errors."""
    with DeepspanClient("http://localhost:8080") as c:
        assert c is not None
