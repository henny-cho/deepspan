# Deepspan

멀티레이어 SW 스택: FPGA/ASIC HW IP를 시뮬레이션부터 실제 하드웨어까지 동일한 코드로 동작시키는 풀스택 플랫폼.

---

## 아키텍처 개요

```
  [Python SDK]          l6/sdk · uv / PyPI
       │
  [Go Server]           l4/server · ConnectRPC (gRPC + REST + gRPC-Web)
       │
  [C++ userlib / appframework]  l3/userlib + l3/appframework · C++23 · io_uring
       │
    ┌──┴──────────────────────────────────────────────┐
    │  HW path                   Sim path             │
    │  l2/kernel (Linux kmod)    l3/hw-model (C++)    │
    │  l2/firmware (Zephyr)      POSIX shm MMIO sim   │
    └─────────────────────────────────────────────────┘
       │
  [HWIP plugin]         hwip/accel/l4-plugin · hwip.Submitter 인터페이스
```

| 레이어 | 디렉토리 | 언어 | 설명 |
|--------|---------|------|------|
| L2 | `l2/firmware` | C++20 + Zephyr | ETL FSM · VirtIO transport · native_sim |
| L2 | `l2/kernel` | C (Linux) | virtio master 드라이버 · io_uring · 다중 디바이스 |
| L3 | `l3/hw-model` | C++17 | FPGA 레지스터 MMIO 시뮬레이터 (l2 전체 대체) |
| L3 | `l3/userlib` | C++23 | ioctl / mmap / io_uring 래퍼 |
| L3 | `l3/appframework` | C++23 | DevicePool · CircuitBreaker · SessionManager |
| L4 | `l4/server` | Go | ConnectRPC 서버 · Protobuf |
| L4 | `l4/mgmt-daemon` | Go | OpenAMP 관리 데몬 |
| L5 | `l5/proto` / `l5/gen` | Protobuf / Go+Python | API 정의 및 생성 스텁 |
| L6 | `l6/sdk` | Python | Pydantic v2 클라이언트 |
| HWIP | `hwip/accel` | Go + C++ | Accelerator HWIP 플러그인 |

자세한 레이어 간 의존 관계: [ARCHITECTURE.md](ARCHITECTURE.md)

---

## 빠른 시작

### 사전 요구사항

```bash
sudo apt install -y cmake ninja-build gcc g++ python3 python3-pip
pip3 install --user west
```

Go 1.26+: <https://go.dev/dl/>

### 1. 전체 개발 환경 설치

```bash
./scripts/setup-all.sh                  # 전체
./scripts/setup-all.sh --skip l2/firmware  # 펌웨어 제외 (빠름)
```

### 2. 빌드 검증

```bash
./scripts/verify-build.sh                       # 모든 레이어
./scripts/verify-build.sh --layers l4/server    # 특정 레이어
./scripts/verify-build.sh --skip l2/firmware,l2/kernel
```

### 3. 시뮬레이션 실행

```bash
./scripts/run-sim.sh            # 전체 스택 빌드 + 실행
./scripts/run-sim.sh --no-build # 이미 빌드된 바이너리 사용
```

### 4. 펌웨어 빌드 (native_sim)

```bash
west build -b native_sim/native/64 l2/firmware/app
./build/l2/firmware/app/zephyr/zephyr.exe
```

### 5. C++ 레이어 빌드

```bash
cmake --preset dev          # userspace C++ (hw-model 포함)
cmake --build --preset dev -j$(nproc)
ctest --preset dev

cmake --preset dev-hwip     # + HWIP accel C++ 플러그인
cmake --build --preset dev-hwip -j$(nproc)
```

### 6. Go 서버 빌드

```bash
cd l4/server && go build ./cmd/server/
cd hwip/demo && go build ./cmd/server/   # HWIP 포함 데모 서버
```

### 7. 전체 gate 검증

```bash
./scripts/gate.sh build      # 레이어별 빌드
./scripts/gate.sh lint       # Go 전체 모듈 lint
./scripts/gate.sh test       # 풀스택 시뮬레이션 테스트
./scripts/gate.sh validate   # HWIP gen/ 아티팩트 검증
```

---

## 디렉터리 구조

```
deepspan/
├── l2/
│   ├── firmware/           Zephyr 펌웨어 (device-side)
│   └── kernel/             Linux 커널 드라이버 (host-side)
├── l3/
│   ├── hw-model/           MMIO 시뮬레이터 (l2 전체 대체)
│   ├── userlib/            C++ io_uring 래퍼
│   └── appframework/       DevicePool · CircuitBreaker
├── l4/
│   ├── server/             Go ConnectRPC 서버
│   └── mgmt-daemon/        Go OpenAMP 데몬
├── l5/
│   ├── proto/              Protobuf 정의
│   └── gen/                생성된 Go/Python 스텁
│       ├── go/
│       └── python/
├── l6/
│   └── sdk/                Python SDK
├── hwip/                   HWIP 플러그인 모음
│   ├── accel/              Accelerator HWIP
│   │   ├── hwip.yaml       단일 진실 원천
│   │   ├── gen/            자동 생성 아티팩트
│   │   └── l4-plugin/      Go Submitter 구현
│   ├── demo/               풀스택 데모 서버 + 클라이언트
│   └── shared/             공통 테스트 유틸
├── tools/
│   └── deepspan-codegen/   HWIP 코드 생성기 (Python)
├── scripts/                빌드·검증·시뮬레이션 스크립트
├── third_party/            googletest, etl, spdlog
├── go.work                 Go 워크스페이스 (7개 모듈)
├── CMakeLists.txt
├── CMakePresets.json        dev, dev-hwip, release, ...
└── west.yml                Zephyr West 매니페스트
```

---

## CMake Presets

| Preset | 설명 |
|--------|------|
| `dev` | userspace C++ 전체 (hw-model 포함), 테스트 ON |
| `dev-submodule` | third_party를 git submodule로 참조 |
| `dev-hwip` | dev + HWIP accel C++ 플러그인 (`DEEPSPAN_BUILD_HWIP=ON`) |
| `sim` | 시뮬레이션 최적화 빌드 |
| `release` | 최적화, 테스트 OFF |
| `arm64-cross` | ARM64 크로스 컴파일 |
| `coverage` | gcov 커버리지 |

---

## CI/CD

| 워크플로우 | 트리거 | 내용 |
|-----------|--------|------|
| `ci-firmware.yml` | `l2/firmware/**` | native_sim 빌드 + twister |
| `ci-cpp.yml` | `l3/**`, `CMakeLists.txt` | CMake dev/dev-submodule 빌드 + ctest |
| `ci-go.yml` | `l4/**`, `l5/gen/go/**`, `hwip/**/go` | go build + go test -race + golangci-lint |
| `ci-kernel.yml` | `l2/kernel/**` | out-of-tree 모듈 컴파일 체크 |
| `ci-python.yml` | `l6/sdk/**` | pytest |
| `ci-codegen.yml` | `tools/deepspan-codegen/**`, `hwip/**/hwip.yaml` | codegen TDD + hwip 아티팩트 stale 검증 |
| `hwip-cpp.yml` | `hwip/**`, `CMakeLists.txt` | dev-hwip preset 빌드 + ctest |
| `hwip-go.yml` | `hwip/**`, `go.work` | hwip Go 빌드 + 테스트 |

---

## 핵심 설계 결정

- **시뮬레이션 / HW 이중 경로**: `l3/hw-model`이 `l2/firmware + l2/kernel` 쌍을 대체. 동일한 `l4/server`가 두 경로 모두 지원.
- **hwip.Submitter 인터페이스**: HWIP 플러그인은 `pkg/hwip.Submitter`만 구현하면 서버에 등록. `go.work`로 monorepo 내 모든 Go 모듈이 단일 워크스페이스.
- **hwip.yaml 단일 원천**: 레지스터 맵과 opcode를 `hwip.yaml` 하나에 정의 → `deepspan-codegen`으로 C/C++/Go/Python/Proto/Firmware 6개 레이어 동시 생성.
- **펌웨어 네이티브 빌드**: `native_sim/native/64` 타겟으로 실제 하드웨어 없이 빌드·테스트.

---

> 최종 업데이트: 2026-03-20 — 모노레포 통합 (deepspan-hwip → hwip/), 레이어 그룹화 (l2-firmware → l2/firmware)
