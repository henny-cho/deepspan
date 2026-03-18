# Deepspan HWIP Plugin System

Each directory under `hwip/` is a self-contained plugin for a specific hardware IP type.

## Plugin structure

```
hwip/<type>/
├── kernel/               UAPI header: deepspan_<type>.h (opcodes)
├── firmware/
│   └── drivers/deepspan_<type>/  Zephyr driver (C only)
├── hw-model/
│   └── include/deepspan_<type>/reg_map.hpp  C++ register layout
├── server/
│   ├── shmclient.go      Submitter implementation (accel RegMap offsets)
│   ├── opcodes.go        Go opcode constants
│   └── go.mod            module github.com/myorg/deepspan/hwip/<type>/server
├── proto/deepspan_<type>/v1/
│   └── device.proto      HwipService RPC definition
├── sdk/
│   └── deepspan_<type>.py  Python client extension
├── tests/
├── buf.yaml              Buf module config
├── buf.gen.yaml          Per-plugin code generation config
└── CMakeLists.txt        CMake integration (included by root when DEEPSPAN_HWIP_TYPE=<type>)
```

## Adding a new HWIP type

```bash
# 1. Copy the accel skeleton
cp -r hwip/accel/ hwip/<type>/

# 2. Update the plugin files
#    - hwip/<type>/kernel/deepspan_<type>.h      → define DEEPSPAN_<TYPE>_OP_*
#    - hwip/<type>/firmware/drivers/deepspan_<type>/  → register layout + ISR
#    - hwip/<type>/proto/deepspan_<type>/v1/device.proto → RPC definition
#    - hwip/<type>/server/shmclient.go           → <Type>ShmClient with offsets
#    - hwip/<type>/server/opcodes.go             → Go Op* constants
#    - hwip/<type>/server/go.mod                 → module github.com/myorg/deepspan/hwip/<type>/server

# 3. Generate proto stubs
cd hwip/<type> && buf generate --template buf.gen.yaml

# 4. Register the plugin in the server
#    Edit server/cmd/server/backend_default.go:
#      import <type>server "github.com/myorg/deepspan/hwip/<type>/server"
#      hwip.Register("<type>", func(s string) hwip.Submitter { return <type>server.NewShmClient(s) })

# 5. Add to go.work
#    use ./hwip/<type>/server
#    use ./gen/hwip/<type>/go

# 6. Add to .release-please-config.json
#    "hwip/<type>": { "component": "hwip-<type>", "release-type": "simple" }

# 7. Add to CI matrix (if applicable)
#    .github/workflows/ci-cpp.yml: hwip: [accel, codec, <type>]
```

## Building firmware for a specific hwip type

```bash
# Accel firmware
west build -b native_sim firmware/app \
    -- -DZEPHYR_EXTRA_MODULES=$(pwd)/hwip/accel/firmware

# Codec firmware
west build -b native_sim firmware/app \
    -- -DZEPHYR_EXTRA_MODULES=$(pwd)/hwip/codec/firmware
```

## Building C++ code for a specific hwip type

```bash
# Using CMake presets
cmake --preset accel-dev   # DEEPSPAN_HWIP_TYPE=accel
cmake --preset codec-dev   # DEEPSPAN_HWIP_TYPE=codec

# Or explicitly
cmake -B build/my-accel -DDEEEPSPAN_HWIP_TYPE=accel
```

## Migration triggers

When any of these conditions are met, consider migrating hwip plugins to separate repositories:
- 5+ hwip types in simultaneous development
- IP confidentiality requirements for a specific hwip
- CI build time exceeds 30 minutes
- Teams need independent release cadences

## Available plugins

| Plugin | Status | Description |
|--------|--------|-------------|
| `accel` | stable | Generic acceleration (ECHO, PROCESS, STATUS) |
| `codec` | skeleton | Encoder/decoder (ENCODE, DECODE) |
