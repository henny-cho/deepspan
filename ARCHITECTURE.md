# Deepspan Architecture

멀티레이어 SW 스택의 레이어 간 의존 관계, 실행 경로, 인터페이스 경계를 설명한다.

---

## 레이어 의존 관계

```
  [Python SDK]              sdk/
       │ gRPC (binary, port 8080)
  [C++20 gRPC Server]       server/
       │ dlopen
  [HWIP plugin]             hwip/accel/plugin/  · Submitter 인터페이스
       │
  [C++ appframework]        runtime/appframework/
       │
  [C++ userlib]             runtime/userlib/
       │
    ┌──┴──────────────────────────────────────────────────┐
    │  HW 경로 (실제 하드웨어)      Sim 경로 (시뮬레이션)  │
    │  kernel/ (Linux virtio)       sim/hw-model/ (C++)    │
    │  firmware/ (Zephyr)           POSIX 공유 메모리 MMIO │
    └─────────────────────────────────────────────────────┘
```

### 컴포넌트별 역할

| 컴포넌트 | 디렉토리 | 언어 | 역할 |
|----------|---------|------|------|
| Zephyr 펌웨어 | `firmware/` | C + Zephyr | 디바이스 사이드 ETL FSM, VirtIO transport |
| Linux 커널 드라이버 | `kernel/` | C (Linux) | 호스트 사이드 virtio 마스터 드라이버, io_uring URING_CMD |
| MMIO 시뮬레이터 | `sim/hw-model/` | C++20 | FPGA MMIO 시뮬레이터 — firmware + kernel 전체를 대체 |
| C++ userlib | `runtime/userlib/` | C++20 | ioctl / mmap / io_uring 래퍼 (실 HW 경로) |
| C++ appframework | `runtime/appframework/` | C++20 | DevicePool, CircuitBreaker, SessionManager |
| gRPC 서버 | `server/` | C++20 | HwipService · ManagementService · TelemetryService |
| Python SDK | `sdk/` | Python | grpcio 클라이언트 (DeepspanClient) |
| HWIP accel 플러그인 | `hwip/accel/plugin/` | C++20 | AccelPlugin — SHM MMIO Submitter (.so) |

---

## 실행 경로: HW vs Sim

### HW 경로 (실제 FPGA/ASIC)

```
sdk/ (Python)
    │ gRPC binary
server/ (C++20)
    │ dlopen libhwip_accel.so
hwip/accel/plugin/ AccelPlugin
    │ ioctl / io_uring URING_CMD
kernel/ (Linux kmod: /dev/hwipN)
    │ VirtIO virtqueue (PCIe)
firmware/ (Zephyr on FPGA)
    │ MMIO 레지스터
FPGA/ASIC 하드웨어
```

### Sim 경로 (firmware + kernel 대체)

```
sdk/ (Python)
    │ gRPC binary
server/ (C++20)
    │ dlopen libhwip_accel.so
hwip/accel/plugin/ AccelPlugin
    │ POSIX shm_open("/deepspan_hwip_N") + atomic CTRL.START polling
sim/hw-model/ (C++20)       ← firmware + kernel 역할 전담
    │ 메모리 내 MMIO 레지스터 시뮬레이션 (100 µs poll loop)
hwip/accel/hw-model/ accel opcode 핸들러
```

`sim/hw-model`은 `firmware`와 `kernel` 쌍 전체를 대체한다.
동일한 `server/`가 두 경로를 모두 지원하며 경로 전환은 설정(플러그인 .so)으로만 결정된다.

---

## Submitter 인터페이스

`server/`는 `deepspan::server::Submitter` 인터페이스 하나로 HWIP 플러그인을 추상화한다.

```cpp
// server/include/deepspan/server/submitter.hpp
class Submitter {
public:
    virtual SubmitResult submit(uint32_t opcode,
                                std::vector<uint8_t> data) = 0;
    virtual int device_state() const = 0;
    virtual std::string_view device_id() const = 0;
};
```

플러그인(`hwip/accel/plugin/`)은 이 인터페이스만 구현하면 서버에 등록된다.
서버는 시작 시 `--hwip-plugin <path>.so`를 `dlopen`하며, `.so` 안의 정적 `AccelRegistrar` 객체가
`HwipRegistry::register_type("accel", factory_fn)` 을 자동 호출한다.

---

## SHM MMIO 통신 프로토콜

플러그인(AccelPlugin)과 hw-model(HwModelServer) 사이의 통신 계약:

```
SHM name:   /deepspan_hwip_<device_index>   (예: /deepspan_hwip_0)
SHM size:   4096 bytes (1 page)

Offset 0x000 ~ 0x1FF: RegMap (512 bytes)
  0x000: ctrl          (bit1 = CTRL.START)
  0x004: status        (bit0 = STATUS.READY)
  0x008: irq_status    (bit0 = IRQ.DONE)
  0x010: version       (HW_VERSION read-only)
  0x100: cmd_opcode
  0x104: cmd_arg0
  0x108: cmd_arg1
  0x110: result_status
  0x114: result_data0
  0x118: result_data1

Offset 0x200 ~ 0x231: ShmStats (telemetry)
  +0:  cmd_count         uint64   (hw-model 처리 커맨드 수)
  +8:  start_time_sec    uint64   (hw-model 시작 시각, Unix epoch)
  +16: last_opcode       uint32
  +20: last_result_status uint32
  +24: fw_cmd_count      uint64   (firmware_sim 커맨드 수)

Submit 프로토콜 (AccelPlugin → HwModelServer):
  1) cmd_opcode/arg0/arg1 쓰기 (relaxed)
  2) __atomic_or_fetch(&ctrl, CTRL_START, RELEASE)
  3) while (__atomic_load_n(&ctrl, ACQUIRE) & CTRL_START) usleep(100)
  4) result_data0/1 읽기 (acquire)
```

---

## hwip.yaml 단일 원천 및 코드 생성 파이프라인

레지스터 맵과 opcode는 `hwip/accel/hwip.yaml` 하나에 정의된다.
`deepspan-codegen`이 이를 읽어 6개 레이어 아티팩트를 동시에 생성한다.

```
hwip/accel/hwip.yaml
    │
    ▼ deepspan-codegen (codegen/)
    ├── gen/kernel/deepspan_accel.h         C (커널 · 펌웨어 공용)
    ├── gen/firmware/deepspan_accel/        Zephyr opcode dispatch
    ├── gen/sim/deepspan_accel/ops.hpp      C++20 hw-model 열거형 + RegOffsets
    ├── gen/rpc/accel.hpp                   C++20 RPC opcode 매핑
    ├── gen/proto/deepspan_accel/v1/        Protobuf 서비스 정의
    └── gen/sdk/deepspan_accel/models.py    Python Pydantic v2 모델
```

재생성:
```bash
cd codegen && uv run deepspan-codegen --hwip hwip/accel/hwip.yaml --out hwip/accel/gen
```

생성된 아티팩트는 커밋되어 레포에 포함된다.

---

## 신규 HWIP 추가 방법

```bash
# 1. accel을 템플릿으로 복사
cp -r hwip/accel/ hwip/crypto/

# 2. hwip.yaml 편집 (레지스터 맵, opcode 정의)
vi hwip/crypto/hwip.yaml

# 3. 코드 생성
cd codegen && uv run deepspan-codegen --hwip hwip/crypto/hwip.yaml --out hwip/crypto/gen

# 4. AccelPlugin 참조하여 CryptoPlugin 구현
vi hwip/crypto/plugin/crypto_plugin.cpp

# 5. CMakePresets.json에 preset 추가
#   { "name": "dev-crypto", "inherits": "dev",
#     "cacheVariables": { "DEEPSPAN_BUILD_HWIP": "ON", "HWIP_TYPES": "crypto" } }
```

---

## CMake 빌드 구조

```
CMakeLists.txt (루트)
├── sim/hw-model/          — POSIX shm MMIO 시뮬레이터 (deepspan_hw_model)
├── runtime/userlib/       — io_uring 래퍼
├── runtime/appframework/  — DevicePool · CircuitBreaker
├── server/                — C++20 gRPC 서버 (deepspan-server)
└── hwip/${type}/          — HWIP_TYPES에 포함된 각 type마다 추가 (DEEPSPAN_BUILD_HWIP=ON)
    └── hwip/accel/        — hw-model ops + plugin .so + E2E tests
```

| Preset | 설명 |
|--------|------|
| `dev` | userspace C++ 전체, 테스트 ON — HWIP 없음 |
| `dev-submodule` | `dev` + third_party를 git submodule로 참조 |
| `dev-hwip` | `dev` + HWIP accel 플러그인 — **기본값** (`DEEPSPAN_DEFAULT_PRESET`) |
| `dev-multi-hwip` | `dev` + 복수 HWIP (`HWIP_TYPES=accel,codec`) |
| `dev-crc32` | `dev` + CRC32 HWIP (`HWIP_TYPES=crc32`) |
| `asan-ubsan` | Debug + `-fsanitize=address,undefined`, halt on first error |
| `sim` | 시뮬레이션 최적화 (firmware 포함) |
| `release` | 최적화, 테스트 OFF, install 활성화 |
| `arm64-cross` | ARM64 크로스 컴파일 |
| `coverage` | gcov 커버리지 |

---

> 최종 업데이트: 2026-04-18 — C++20 통일 (hw-model 포함), ASan+UBSan preset 도입, `HWIP_TYPE` → `HWIP_TYPES` 마이그레이션, 포트 `8080` 기준.
