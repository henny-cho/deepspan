# CRC32 HWIP User Manual

Full-stack guide: build → run simulation → GDB debugging → operational tests.

---

## Stack Overview

```
Python SDK  ──gRPC──►  deepspan-server  ──dlopen──►  libhwip_crc32.so
                                                            │
                                                      POSIX SHM mmio
                                                      /deepspan_hwip_0
                                                            │
                                                    deepspan-hw-model
                                                    (CRC32 engine sim)
                                           [optional: deepspan-firmware-sim]
```

**Device ID**: `crc32/0`
**SHM name**: `/deepspan_hwip_0`
**gRPC address**: `localhost:8080`

---

## Prerequisites

```bash
# Build tools
sudo apt install cmake ninja-build clang clang-tidy python3-pip gdb

# Python tools (SDK)
pip install uv          # or: pip install grpcio grpcio-tools

# Optional — Zephyr firmware sim
pip install west        # then run: west init -l . && west update
```

---

## 1. Build

```bash
cd /path/to/deepspan

# Configure + build the CRC32 stack
./scripts/dev.sh build --preset dev-crc32
```

This configures with `DEEPSPAN_BUILD_HWIP=ON HWIP_TYPES=crc32` and builds to `build/dev-crc32/`.

**Output binaries**:

| Binary | Path |
|--------|------|
| HW model (FPGA sim) | `build/dev-crc32/sim/hw-model/deepspan-hw-model` |
| gRPC server | `build/dev-crc32/server/deepspan-server` |
| CRC32 plugin | `build/dev-crc32/hwip/crc32/plugin/libhwip_crc32.so` |
| Zephyr firmware sim | `build/dev-crc32/sim/hw-model/deepspan-firmware-sim` |

---

## 2. tmux Development Session (Recommended)

`scripts/tmux-crc32.sh` creates a four-pane tmux session that starts all processes automatically.

### Layout

```
┌──────────────────────┬──────────────────────┐
│  pane 0              │  pane 1              │
│  hw-model            │  deepspan-server     │
│  (FPGA sim)          │  + crc32 plugin      │
├──────────────────────┼──────────────────────┤
│  pane 2              │  pane 3              │
│  logs  (tail -f)     │  shell  (interactive)│
└──────────────────────┴──────────────────────┘
```

### Quickstart

```bash
# Build first (required once)
./scripts/dev.sh build --preset dev-crc32

# Launch session (auto-attaches in interactive terminals)
./scripts/tmux-crc32.sh
```

On launch the script:
1. Verifies that `deepspan-hw-model`, `deepspan-server`, and `libhwip_crc32.so` exist
2. Creates the session `deepspan-crc32`
3. Starts hw-model (pane 0) and server (pane 1), tee-ing their output to `build/dev-crc32/logs/`
4. Opens a live log tail (pane 2) and an interactive shell (pane 3)
5. Activates `.venv` in the shell pane if it exists

### Options

```bash
./scripts/tmux-crc32.sh [OPTIONS]

  --preset PRESET     CMake preset          (default: dev-crc32)
  --addr ADDR         gRPC listen address   (default: 0.0.0.0:8080)
  --shm NAME          POSIX SHM name        (default: /deepspan_hwip_0)
  --latency-us N      hw-model latency in μs (default: 0)
  --firmware          Also start deepspan-firmware-sim alongside server
  --attach            Attach after creation  (default: yes in interactive)
  --no-attach         Print attach command and exit
  --kill              Kill existing session
```

### Examples

```bash
# Standard session
./scripts/tmux-crc32.sh

# Non-interactive (CI or script): start without attaching
./scripts/tmux-crc32.sh --no-attach
# ... run tests ...
./scripts/tmux-crc32.sh --kill

# Inject 200 μs latency to simulate real HW timing
./scripts/tmux-crc32.sh --latency-us 200

# Include Zephyr firmware sim
./scripts/tmux-crc32.sh --firmware

# Attach to an already-running session
tmux attach -t deepspan-crc32
```

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Ctrl-b d` | Detach (session keeps running) |
| `Ctrl-b 0–3` | Jump to pane by number |
| `Ctrl-b ←→↑↓` | Navigate between panes |
| `Ctrl-b z` | Zoom/unzoom focused pane |
| `Ctrl-b [` | Scroll mode (q to exit) |

### Session Lifecycle

```bash
# Check if session is alive
tmux has-session -t deepspan-crc32 && echo running || echo not running

# Re-attach after detach
tmux attach -t deepspan-crc32

# Kill all processes and remove session
./scripts/tmux-crc32.sh --kill
```

---

## 3. Run the Simulation Stack (Manual)

Launch three processes in separate terminals (or background):

### Terminal 1 — HW Model

```bash
./build/dev-crc32/sim/hw-model/deepspan-hw-model \
    --shm-name=/deepspan_hwip_0
```

Options:

| Flag | Default | Description |
|------|---------|-------------|
| `--shm-name=NAME` | `/deepspan_hwip_0` | POSIX shared memory object name |
| `--latency-us=N` | `0` | Artificial response latency (μs) |
| `--no-auto-irq` | off | Disable automatic IRQ after each command |

The hw-model creates `/deepspan_hwip_0` and polls for commands from the plugin.

### Terminal 2 — gRPC Server

```bash
./build/dev-crc32/server/deepspan-server \
    --addr 0.0.0.0:8080 \
    --hwip-plugin ./build/dev-crc32/hwip/crc32/plugin/libhwip_crc32.so
```

The server scans the SHM for `crc32/0` through `crc32/N` on startup and registers devices found.

### Terminal 3 — Zephyr Firmware Sim (optional)

The firmware sim exercises the Zephyr ETL FSM path; the gRPC path does not require it.

```bash
# Build first (one-time):
west build -b native_sim/native/64 deepspan/firmware/app

# Run:
./build/firmware/app/zephyr/zephyr.exe
# or via dev.sh firmware sim binary:
./build/dev-crc32/sim/hw-model/deepspan-firmware-sim \
    --shm-name=/deepspan_hwip_0 \
    --interval-ms=100
```

### One-command stack start (dev.sh)

```bash
./scripts/dev.sh test --preset dev-crc32 --no-build
```

This starts hw-model → (optional Zephyr) → server, runs the SDK E2E test, then shuts everything down.

---

## 4. Verify Stack is Running

```bash
# Check SHM exists
ls -la /dev/shm/deepspan_hwip_0

# Check server is listening
ss -tlnp | grep 8080

# Check logs
tail -f build/dev-crc32/logs/hw-model.log
tail -f build/dev-crc32/logs/server.log
```

---

## 5. CRC32 Operations

**Opcodes**:

| Name | Value | Encoding | Input | Output |
|------|-------|----------|-------|--------|
| `COMPUTE` | `0x0001` | `dma_bytes` | byte stream (max 3072 B) | `checksum: u32` |
| `GET_POLY` | `0x0002` | `fixed_args` | none | `polynomial: u32` |

**Polynomial**: IEEE 802.3 = `0xEDB88320`

---

## 6. Operational Tests

### 6.1 dev.sh automated test

`dev.sh test` starts the full simulation stack, runs the E2E test, then shuts everything down cleanly. It auto-selects the test script based on the loaded plugin:

| Plugin path contains | Test script | Device |
|----------------------|-------------|--------|
| `/crc32/` | `sdk/examples/crc32_test.py` | `crc32/0` |
| other | `sdk/examples/hello.py` | `accel/0` |

```bash
# Build + full stack test
./scripts/dev.sh check --preset dev-crc32

# Stack test only (skip build)
./scripts/dev.sh test --preset dev-crc32 --no-build
```

Press `Ctrl-C` once to stop all processes. The cleanup handler resets the trap on entry so repeated `Ctrl-C` does not loop; any process that does not exit within 5 seconds is `SIGKILL`ed.

### 6.2 CTest unit tests

```bash
# C++ unit tests only (no stack required)
ctest --preset dev-crc32 --output-on-failure -j$(nproc)
```

### 6.3 Manual Python SDK test

`sdk/examples/crc32_test.py` runs 7 checks against a live stack:

| Check | Description |
|-------|-------------|
| 1. ListDevices | `crc32/0` present and in READY state |
| 2. GET_POLY | polynomial == `0xEDB88320` (IEEE 802.3) |
| 3. COMPUTE known string | `b"Hello, deepspan!"` vs `binascii.crc32` |
| 4. COMPUTE empty input | `b""` → `0x00000000` |
| 5. COMPUTE max-size | 3072 bytes vs `binascii.crc32` |
| 6. GetFirmwareInfo | fw_version non-empty, protocol_version ≥ 1 |
| 7. GetTelemetry | irq_count > 0 after submits |

Start the stack first (tmux session or manually), then:

```bash
# Generate stubs once
cd sdk && uv run --with grpcio-tools python scripts/gen_proto.py && cd ..

# Run test (env vars optional — these are the defaults)
DEEPSPAN_ADDR=localhost:8080 DEEPSPAN_DEVICE=crc32/0 \
    uv run python sdk/examples/crc32_test.py
```

### 6.4 Kernel AF_ALG Test (requires kernel module)

The `deepspan_crc32_shash` kernel module registers `"crc32-deepspan"` with the Linux Crypto API.

**Build and load the module**:
```bash
make -C kernel/drivers/deepspan
sudo insmod kernel/drivers/deepspan/deepspan_crc32_shash.ko

# Confirm registration
grep -A5 "crc32-deepspan" /proc/crypto
```

**Test via Python AF_ALG socket**:
```python
import socket, struct, binascii

ALG_TYPE = "hash"
ALG_NAME = b"crc32-deepspan"
data     = b"Hello, deepspan!"

# Open AF_ALG socket
alg = socket.socket(socket.AF_ALG, socket.SOCK_SEQPACKET, 0)
alg.bind((ALG_TYPE, "", 0, 0, ALG_NAME))
op, _ = alg.accept()
op.sendall(data)
hw_crc = struct.unpack("<I", op.recv(4))[0]
sw_crc = binascii.crc32(data) & 0xFFFFFFFF

print(f"AF_ALG result : 0x{hw_crc:08X}")
print(f"Python crc32  : 0x{sw_crc:08X}")
assert hw_crc == sw_crc, "MISMATCH"
op.close()
alg.close()
print("AF_ALG path OK")
```

---

## 7. GDB Debugging

### 7.1 Debug the HW Model

```bash
gdb --args ./build/dev-crc32/sim/hw-model/deepspan-hw-model \
    --shm-name=/deepspan_hwip_0

(gdb) set follow-fork-mode child
(gdb) break deepspan::hw_model::HwModel::poll_once   # poll loop entry
(gdb) run
```

Useful breakpoints in the hw-model:

| Breakpoint | Purpose |
|------------|---------|
| `deepspan::hw_model::HwModel::poll_once` | Triggered each SHM poll cycle |
| `deepspan::hw_model::CRC32Handler::handle` | CRC32 opcode dispatch |
| `deepspan::hw_model::RegMap::write` | Any register write |

### 7.2 Attach to Running Server

```bash
# Start server normally (Terminal 2), then:
gdb -p $(pgrep deepspan-server)

(gdb) sharedlibrary libhwip_crc32     # load symbols from plugin
(gdb) break deepspan::hwip::crc32::Crc32Plugin::submit
(gdb) continue
```

**Inspect SHM from GDB** (while server is running):

```gdb
(gdb) call (int)shm_open("/deepspan_hwip_0", 2, 0)
# use returned fd to inspect via x/32xw or call mmap
```

### 7.3 Debug the Plugin (.so loaded via dlopen)

The server `dlopen`s `libhwip_crc32.so` at runtime. GDB does not load symbols until dlopen completes.

```bash
gdb ./build/dev-crc32/server/deepspan-server
(gdb) set args --addr 0.0.0.0:8080 \
               --hwip-plugin ./build/dev-crc32/hwip/crc32/plugin/libhwip_crc32.so
(gdb) catch load libhwip_crc32       # break when .so is loaded
(gdb) run
# GDB stops at dlopen — now add plugin breakpoints:
(gdb) break deepspan::hwip::crc32::Crc32Plugin::submit
(gdb) continue
```

### 7.4 Debug the Firmware Sim

```bash
gdb --args ./build/dev-crc32/sim/hw-model/deepspan-firmware-sim \
    --shm-name=/deepspan_hwip_0

(gdb) break deepspan_hwip_dispatch    # Zephyr ETL FSM entry
(gdb) run
```

### 7.5 GDB TUI Multi-window Layout

```bash
gdb -tui --args ./build/dev-crc32/sim/hw-model/deepspan-hw-model \
    --shm-name=/deepspan_hwip_0
```

Inside GDB TUI:
```
(gdb) layout split    # source + assembly
(gdb) layout regs     # show registers
(gdb) focus cmd       # return keyboard focus to command window
```

---

## 8. Inspecting SHM Directly

The POSIX SHM layout at `/deepspan_hwip_0` (4096 bytes):

| Offset | Region | Description |
|--------|--------|-------------|
| `0x000` | `RegMap` (512 B) | MMIO register bank |
| `0x200` | `ShmStats` | uptime_ms, irq_count, submit_count |
| `0x300` | DMA buffer | Raw data for `dma_bytes` operations |

**Dump with Python**:
```python
import mmap, struct, posixipc

shm = posixipc.SharedMemory("/deepspan_hwip_0")
mm  = mmap.mmap(shm.fd, 512, mmap.MAP_SHARED, mmap.PROT_READ)

RESULT_STATUS = 0x110
RESULT_DATA0  = 0x114

result_status = struct.unpack_from("<I", mm, RESULT_STATUS)[0]
result_data0  = struct.unpack_from("<I", mm, RESULT_DATA0)[0]
print(f"result_status = 0x{result_status:08X}")
print(f"result_data0  = 0x{result_data0:08X}")
mm.close()
shm.close_fd()
```

---

## 9. Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DEEPSPAN_SHM_NAME` | `/deepspan_hwip_0` | Override SHM name for all components |
| `SERVER_ADDR` | `0.0.0.0:8080` | gRPC server listen address |
| `DEEPSPAN_ADDR` | `localhost:8080` | gRPC address for SDK/tests |
| `DEEPSPAN_DEVICE` | `crc32/0` | Device ID for SDK tests |

---

## 10. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Server starts but no `crc32/0` device | hw-model not running or SHM not found | Start hw-model first; confirm `/dev/shm/deepspan_hwip_0` exists |
| `submit_request` returns error | Plugin can't find SHM | Check `--shm-name` matches between hw-model and plugin |
| CRC mismatch | Endianness or polynomial mismatch | Expected `0xEDB88320` (IEEE 802.3); verify `GET_POLY` returns correct value |
| GDB can't find plugin symbols | .so not yet loaded | Use `catch load libhwip_crc32` before `run` |
| AF_ALG: `bind: No such device` | Kernel module not loaded | `sudo insmod deepspan_crc32_shash.ko` and check `/proc/crypto` |
| Build fails on codegen check | Generated files out of date | Run `./hwip/scripts/hwip.sh gen --hwip crc32` then rebuild |
| `dev.sh test` hangs on Ctrl-C, loops "shutting down" | Old cleanup trap was re-entrant | Fixed: trap is reset on entry; processes are SIGKILL'd after 5 s if still alive |
| `deepspan-server` ignores Ctrl-C, keeps logging "received signal 2" | Signal handler set `g_shutdown` but never called `server->Shutdown()` | Fixed: handler now calls `g_server->Shutdown()` to unblock `Wait()` |
| `[FAIL] accel/0 in device list` when using `dev-crc32` | `hello.py` hardcoded to `accel/0`; crc32 preset has only `crc32/0` | Fixed: `dev.sh test` now auto-selects `crc32_test.py` for crc32 plugin |

---

## 11. Quick Reference

```bash
# Full build
./scripts/dev.sh build --preset dev-crc32

# Run all automated tests
./scripts/dev.sh check --preset dev-crc32

# ── tmux session (recommended) ──────────────────────────────────────────────
./scripts/tmux-crc32.sh              # build required; auto-attaches
./scripts/tmux-crc32.sh --no-attach  # start without attaching
tmux attach -t deepspan-crc32        # re-attach
./scripts/tmux-crc32.sh --kill       # stop all processes

# ── Manual stack startup ─────────────────────────────────────────────────────
./build/dev-crc32/sim/hw-model/deepspan-hw-model --shm-name=/deepspan_hwip_0 &
./build/dev-crc32/server/deepspan-server \
    --addr 0.0.0.0:8080 \
    --hwip-plugin ./build/dev-crc32/hwip/crc32/plugin/libhwip_crc32.so &

# ── Tests ────────────────────────────────────────────────────────────────────
# SDK smoke test (run from shell pane 3)
DEEPSPAN_DEVICE=crc32/0 uv run python sdk/examples/crc32_test.py

# Full E2E via dev.sh (starts its own stack, no tmux needed)
./scripts/dev.sh test --preset dev-crc32

# ── Logs ─────────────────────────────────────────────────────────────────────
tail -f build/dev-crc32/logs/{hw-model,server}.log
```
