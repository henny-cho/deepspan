# Deepspan

멀티레이어 SW 스택: FPGA/ASIC HW IP를 시뮬레이션부터 실제 하드웨어까지 동일한 코드로 동작시키는 풀스택 플랫폼.

---

## 아키텍처 개요

```
  [Python SDK]          sdk/  · grpcio
       │ gRPC (binary)
  [C++20 gRPC Server]   server/  · C++20
       │
  [C++ appframework]    runtime/appframework/
       │
  [C++ userlib]         runtime/userlib/  · io_uring
       │
    ┌──┴──────────────────────────────────────────────┐
    │  HW 경로 (실제 FPGA)           Sim 경로          │
    │  kernel/ (Linux virtio)       sim/hw-model/     │
    │  firmware/ (Zephyr)           POSIX shm MMIO    │
    └─────────────────────────────────────────────────┘
       │
  [HWIP plugin]         hwip/accel/plugin/  · Submitter 인터페이스
```

| 컴포넌트 | 디렉토리 | 언어 | 설명 |
|----------|---------|------|------|
| Zephyr 펌웨어 | `firmware/` | C + Zephyr | ETL FSM · VirtIO transport · native_sim |
| Linux 커널 드라이버 | `kernel/` | C (Linux) | virtio master 드라이버 · io_uring · 다중 디바이스 |
| MMIO 시뮬레이터 | `sim/hw-model/` | C++20 | FPGA 레지스터 MMIO 시뮬레이터 (firmware + kernel 대체) |
| C++ userlib | `runtime/userlib/` | C++20 | ioctl / mmap / io_uring 래퍼 |
| C++ appframework | `runtime/appframework/` | C++20 | DevicePool · CircuitBreaker · SessionManager |
| gRPC 서버 | `server/` | C++20 | gRPC 서버 · Protobuf · dlopen 플러그인 로더 |
| Python SDK | `sdk/` | Python | grpcio 클라이언트 |
| HWIP accel 플러그인 | `hwip/accel/plugin/` | C++20 | AccelPlugin SHM Submitter |

자세한 레이어 간 의존 관계: [ARCHITECTURE.md](ARCHITECTURE.md)

---

## 빠른 시작

### 사전 요구사항

```bash
sudo apt install -y cmake ninja-build gcc g++ python3 python3-pip pipx \
     libgrpc++-dev libprotobuf-dev protobuf-compiler-grpc \
     libspdlog-dev liburing-dev libgtest-dev \
     clang-tidy ccache
pipx install west
```

또는 한 번에:

```bash
./scripts/dev.sh setup --hooks --lint-tools
```

### 1. 빌드

```bash
# 기본 preset (dev-hwip: userspace + HWIP accel plugin + server)
./scripts/dev.sh build
./scripts/dev.sh test              # 풀스택 시뮬레이션 + SDK E2E

# 또는 cmake 직접
cmake --preset dev-hwip
cmake --build --preset dev-hwip -j$(nproc)
ctest --preset dev-hwip
```

`DEEPSPAN_DEFAULT_PRESET` 환경 변수로 모든 서브커맨드의 기본 preset을 일괄 변경할 수 있습니다. 예: `export DEEPSPAN_DEFAULT_PRESET=dev` → HWIP 없는 빠른 빌드.

### 2. 시뮬레이션 실행 (Sim 경로)

```bash
# 1. hw-model 실행 (SHM 생성 + poll loop)
build/dev-hwip/sim/hw-model/deepspan-hw-model &

# 2. gRPC 서버 실행 (플러그인 로드)
build/dev-hwip/server/deepspan-server \
  --addr 0.0.0.0:8080 \
  --hwip-plugin build/dev-hwip/hwip/accel/plugin/libhwip_accel.so &

# 3. Python SDK로 검증
cd sdk && uv run python -c "
from deepspan import DeepspanClient
c = DeepspanClient('localhost:8080')
print(c.list_devices())          # [DeviceInfo(id='accel/0', state=READY)]
rid = c.submit_request('accel/0', opcode=0x0001)
print(rid)                       # SubmitResult with ECHO response
"
```

### 3. 펌웨어 빌드 (native_sim)

```bash
west build -b native_sim/native/64 firmware/app
./build/firmware/app/zephyr/zephyr.exe
```

### 4. 전체 ctest

```bash
ctest --preset dev-hwip -R accel   # accel E2E integration tests
ctest --preset dev                  # hw-model + userlib + server unit tests
```

---

## 디렉터리 구조

```
deepspan/
├── firmware/           Zephyr 펌웨어 (device-side)
├── kernel/             Linux 커널 드라이버 (host-side)
├── sim/
│   └── hw-model/       MMIO 시뮬레이터 (firmware + kernel 전체 대체)
├── runtime/
│   ├── userlib/        C++20 io_uring 래퍼
│   └── appframework/   DevicePool · CircuitBreaker · SessionManager
├── server/             C++20 gRPC 서버 (HwipService · MgmtService · TelemetryService)
├── sdk/                Python grpcio SDK
├── hwip/               HWIP 플러그인 모음
│   └── accel/
│       ├── hwip.yaml       단일 진실 원천 (레지스터 맵 + opcode)
│       ├── gen/            deepspan-codegen 자동 생성 아티팩트
│       ├── hw-model/       accel opcode 핸들러 (hw-model 플러그인)
│       ├── plugin/         AccelPlugin (.so) — SHM Submitter
│       └── tests/          E2E 통합 테스트
├── api/proto/          Protobuf 서비스 정의
├── codegen/            deepspan-codegen (Python · pytest TDD)
├── scripts/            `dev.sh` · `lib.sh` · `tmux-crc32.sh`
├── third_party/        googletest, spdlog, etl, nlohmann_json, tl-expected
├── CMakeLists.txt
├── CMakePresets.json   dev, dev-hwip, dev-crc32, asan-ubsan, release, ...
└── west.yml            Zephyr West 매니페스트 (zephyr, etl, openamp, ...)
```

---

## CMake Presets

| Preset | 설명 |
|--------|------|
| `dev` | userspace C++ 전체 (hw-model 포함), 테스트 ON — **HWIP 없음** |
| `dev-submodule` | third_party를 git submodule로 참조 |
| `dev-hwip` | dev + HWIP accel C++ 플러그인 (`DEEPSPAN_BUILD_HWIP=ON`) — **기본값** |
| `dev-multi-hwip` | dev + 복수 HWIP 플러그인 동시 빌드 (`HWIP_TYPES=accel,codec`) |
| `dev-crc32` | dev + CRC32 HWIP 플러그인 (`HWIP_TYPES=crc32`) |
| `asan-ubsan` | Debug + `-fsanitize=address,undefined`, halt on first error |
| `sim` | 시뮬레이션 최적화 빌드 (firmware 포함) |
| `release` | 최적화, 테스트 OFF, install 활성화 |
| `arm64-cross` | ARM64 크로스 컴파일 |
| `coverage` | gcov 커버리지 |

전체 목록은 `CMakePresets.json` 참조.

---

## CI/CD

| 워크플로우 | 트리거 | 내용 |
|-----------|--------|------|
| `ci-cpp.yml` | `hwip/**`, `runtime/**`, `sim/**`, `server/**`, `api/proto/**`, `CMakeLists.txt`, `CMakePresets.json` | 4-preset 매트릭스 빌드 + ctest, clang-tidy strict (dev-hwip), ASan+UBSan gating |
| `ci-firmware.yml` | `firmware/**`, `hwip/accel/firmware/**`, `west.yml` | native_sim 빌드 + twister |
| `ci-kernel.yml` | `kernel/**` | out-of-tree 모듈 컴파일 체크 |
| `ci-python.yml` | `sdk/**`, `api/proto/**`, `codegen/**`, `hwip/**/hwip.yaml` | pytest (Python 3.11/3.12 매트릭스) |
| `ci-codegen.yml` | `codegen/**`, `hwip/**/hwip.yaml` | pytest + ruff + 실제 hwip.yaml stale 검증 |
| `release.yml` | main push | release-please → 태그 · GitHub Release · PyPI (SDK) · platform tarball |

모든 CI 워크플로는 `permissions: { contents: read }` + `concurrency:` 그룹 + `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true`로 하드닝되어 있습니다. C++ 빌드는 ccache (800 MB, preset별 버킷)로 캐시됩니다.

Dependabot(`.github/dependabot.yml`)이 github-actions / pip(sdk, codegen)을 주간 업데이트합니다. 코드 소유권: `.github/CODEOWNERS`.

---

## 핵심 설계 결정

- **Sim / HW 이중 경로**: `sim/hw-model`이 `firmware + kernel` 쌍을 대체. 동일한 `server/`가 두 경로 모두 지원.
- **Submitter 인터페이스**: HWIP 플러그인은 `deepspan::server::Submitter`만 구현하면 서버에 dlopen 등록. 서버는 플러그인 타입을 알 필요 없음.
- **hwip.yaml 단일 원천**: 레지스터 맵과 opcode를 `hwip.yaml` 하나에 정의 → `deepspan-codegen`으로 C/C++/Python/Proto 6개 레이어 동시 생성.
- **SHM MMIO 프로토콜**: plugin ↔ hw-model 간 통신은 POSIX shm + atomic CTRL.START 폴링 (µs 수준 레이턴시).
- **펌웨어 네이티브 빌드**: `native_sim/native/64` 타겟으로 실제 하드웨어 없이 빌드·테스트.

---

> 최종 업데이트: 2026-04-18 — 빌드/CI 전면 점검: ASan+UBSan gating, clang-tidy CI, Dependabot, ccache CMake 라우팅, `DEEPSPAN_DEFAULT_PRESET` 도입
