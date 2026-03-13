# deepspan-sdk

Python SDK for the Deepspan hardware-to-service stack.

## Installation

```bash
pip install deepspan-sdk
```

## Quick start

```python
from deepspan import DeepspanClient, AIDiagnostics

with DeepspanClient("http://localhost:8080") as client:
    devices = client.list_devices()
    info = client.get_firmware_info(devices[0].device_id)
    snap = client.get_telemetry(devices[0].device_id)

# AI-powered diagnostics
diag = AIDiagnostics()
report = diag.diagnose_device(devices[0], firmware=info, telemetry=snap)
print(report)
```

## License

Apache-2.0
