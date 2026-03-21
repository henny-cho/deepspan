# SPDX-License-Identifier: Apache-2.0
"""Unit tests for DeepspanClient using grpc mock stubs."""
from __future__ import annotations

import pytest
from unittest.mock import MagicMock, patch
from deepspan.models import DeviceInfo, DeviceState, FirmwareInfo


def _make_proto_device(device_id: str, state: int):
    d = MagicMock()
    d.device_id = device_id
    d.state = state
    return d


@pytest.fixture
def mock_stubs(monkeypatch):
    """Patch the proto stub imports and return mock stub instances."""
    # Build mock pb2 modules with lightweight stand-ins
    device_pb2 = MagicMock()
    device_pb2_grpc = MagicMock()
    management_pb2 = MagicMock()
    management_pb2_grpc = MagicMock()
    telemetry_pb2 = MagicMock()
    telemetry_pb2_grpc = MagicMock()

    stub_modules = {
        "deepspan._proto": MagicMock(),
        "deepspan._proto.deepspan": MagicMock(),
        "deepspan._proto.deepspan.v1": MagicMock(),
        "deepspan._proto.deepspan.v1.device_pb2": device_pb2,
        "deepspan._proto.deepspan.v1.device_pb2_grpc": device_pb2_grpc,
        "deepspan._proto.deepspan.v1.management_pb2": management_pb2,
        "deepspan._proto.deepspan.v1.management_pb2_grpc": management_pb2_grpc,
        "deepspan._proto.deepspan.v1.telemetry_pb2": telemetry_pb2,
        "deepspan._proto.deepspan.v1.telemetry_pb2_grpc": telemetry_pb2_grpc,
    }

    with patch.dict("sys.modules", stub_modules):
        # Reimport client with patched modules
        import importlib
        import deepspan.client as client_mod
        importlib.reload(client_mod)

        # Create stub mock instances
        hwip_stub = MagicMock()
        mgmt_stub = MagicMock()
        tel_stub = MagicMock()

        device_pb2_grpc.HwipServiceStub.return_value = hwip_stub
        management_pb2_grpc.ManagementServiceStub.return_value = mgmt_stub
        telemetry_pb2_grpc.TelemetryServiceStub.return_value = tel_stub

        with patch("grpc.insecure_channel"):
            client = client_mod.DeepspanClient("localhost:8080")
            client._hwip = hwip_stub
            client._mgmt = mgmt_stub
            client._tel = tel_stub
            yield client, hwip_stub, mgmt_stub, tel_stub, device_pb2, management_pb2, telemetry_pb2


def test_list_devices(mock_stubs):
    client, hwip_stub, *_ = mock_stubs
    dev0 = _make_proto_device("accel/0", 2)
    resp = MagicMock()
    resp.devices = [dev0]
    hwip_stub.ListDevices.return_value = resp

    devices = client.list_devices()
    assert len(devices) == 1
    assert devices[0].device_id == "accel/0"
    assert devices[0].state == DeviceState.READY


def test_list_devices_empty(mock_stubs):
    client, hwip_stub, *_ = mock_stubs
    resp = MagicMock()
    resp.devices = []
    hwip_stub.ListDevices.return_value = resp

    devices = client.list_devices()
    assert devices == []


def test_submit_request_returns_result_bytes(mock_stubs):
    client, hwip_stub, *_ = mock_stubs
    resp = MagicMock()
    resp.result = b"\xef\xbe\xad\xde\xbe\xba\xfe\xca"
    hwip_stub.SubmitRequest.return_value = resp

    raw = client.submit_request("accel/0", opcode=0x0001)
    assert raw == b"\xef\xbe\xad\xde\xbe\xba\xfe\xca"


def test_get_device_status(mock_stubs):
    client, hwip_stub, *_ = mock_stubs
    proto_info = _make_proto_device("accel/0", 2)
    resp = MagicMock()
    resp.info = proto_info
    hwip_stub.GetDeviceStatus.return_value = resp

    info = client.get_device_status("accel/0")
    assert info.device_id == "accel/0"
    assert info.state == DeviceState.READY


def test_context_manager(mock_stubs):
    client, *_ = mock_stubs
    with client as c:
        assert c is client
