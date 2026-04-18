# deepspan-sdk

Python SDK for the Deepspan hardware-to-service stack.

## Installation

```bash
pip install deepspan-sdk
```

## Quick start

```python
from deepspan import DeepspanClient

with DeepspanClient("localhost:8080") as client:
    devices = client.list_devices()
    info    = client.get_firmware_info(devices[0].device_id)
    snap    = client.get_telemetry(devices[0].device_id)

    # Submit an HWIP command (opcode depends on plugin).
    rid = client.submit_request(devices[0].device_id, opcode=0x0001)
    print(rid)
```

The address is a plain `host:port` string — gRPC, not HTTP. Default server
address is `0.0.0.0:8080` (override with `--addr` on `deepspan-server`).

## Environment variables (test scripts)

| Variable | Default | Purpose |
|----------|---------|---------|
| `DEEPSPAN_ADDR`   | `localhost:8080` | SDK test target |
| `DEEPSPAN_DEVICE` | varies           | Device ID for E2E tests (`accel/0`, `crc32/0`, ...) |

## Development

```bash
# Generate gRPC stubs from api/proto/ (required once per schema change)
uv run --with grpcio-tools python scripts/gen_proto.py

# Run tests
uv run pytest
```

## License

Apache-2.0
