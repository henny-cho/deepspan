# Deepspan

멀티레이어 SW 스택: FPGA/ASIC HW IP를 시뮬레이션부터 실제 하드웨어까지 동일한 코드로 동작시키는 풀스택 플랫폼.

---

## 아키텍처 개요

```
  [Python SDK]          uv / PyPI
       │
  [Go Server]           ConnectRPC (gRPC + REST + gRPC-Web)
       │
  [userlib / appframework]  C++23 · io_uring · CircuitBreaker · SessionManager
       │
  [Linux Kernel Driver] virtio master · io_uring · /dev/hwip*
       │
  [Zephyr Firmware]     C++20 · ETL · native_sim / ARM
       │
  [hw-model]            C++17 · POSIX shm + eventfd · MMIO 시뮬레이터
```

| 레이어 | 디렉토리 | 언어 | 설명 |
|--------|---------|------|------|
| L3 | `l3-hw-model` | C++17 | FPGA 레지스터 MMIO 시뮬레이터 |
| L2 | `l2-firmware` | C++20 + Zephyr | ETL FSM · VirtIO transport · native_sim |
| L2 | `l2-kernel` | C (Linux) | virtio master 드라이버 · io_uring · 다중 디바이스 |
| L3 | `l3-userlib` | C++23 | ioctl / mmap / io_uring 래퍼 |
| L3 | `l3-appframework` | C++23 | DevicePool · CircuitBreaker · SessionManager |
| L4 | `l4-server` | Go | ConnectRPC 서버 · Protobuf |
| L5 | `l5-proto` / `l5-gen` | Protobuf / Go+Python | API 정의 및 생성 스텁 |
| L6 | `l6-sdk` | Python | Pydantic v2 클라이언트 |

---

## 빠른 시작

### 사전 요구사항

```bash
sudo apt install -y cmake ninja-build gcc python3 python3-pip
pip3 install --user west natsort
```

### 1. West 워크스페이스 초기화

```bash
mkdir deepspan-ws && cd deepspan-ws
west init -m https://github.com/myorg/deepspan --mr main
west update
```

### 2. 펌웨어 빌드 (hardware 불필요 — native_sim)

```bash
cd deepspan/
ZEPHYR_TOOLCHAIN_VARIANT=host \
west build -b native_sim/native/64 l2-firmware/app \
    -- -DZEPHYR_EXTRA_MODULES=$(pwd)/l2-firmware
./build/zephyr/zephyr.exe   # 직접 실행
```

### 3. 펌웨어 테스트

```bash
cd deepspan/
ZEPHYR_TOOLCHAIN_VARIANT=host \
west twister --platform native_sim/native/64 -T l2-firmware/tests
# 예상: 2 of 2 test cases passed (100.00%)
```

### 4. C++ 레이어 빌드 및 테스트

```bash
cd deepspan/l3-appframework/
cmake -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build
ctest --test-dir build --output-on-failure
```

### 5. Go 서버 빌드

```bash
cd deepspan/l4-server/
buf generate        # Protobuf → Go 코드 생성
go build -o bin/deepspan-server ./cmd/server/
```

### 전체 스택 한번에 검증

```bash
cd deepspan/

# 모든 레이어 순서대로 빌드 + 테스트
./scripts/verify-build.sh

# 특정 레이어만
./scripts/verify-build.sh --layers userlib,appframework,server

# 느린 레이어 제외
./scripts/verify-build.sh --skip kernel,firmware
```

---

## 디렉터리 구조

```
deepspan/
├── l2-firmware/            L2: Zephyr 펌웨어
│   ├── app/                메인 앱 (native_sim / ARM)
│   │   ├── src/main.cpp
│   │   ├── prj.conf
│   │   └── boards/native_sim.conf
│   ├── lib/
│   │   └── transport/      VirtIO transport 라이브러리
│   ├── drivers/            Zephyr 드라이버
│   ├── tests/
│   │   └── test_fsm/       ETL FSM 단위 테스트 (ztest)
│   ├── Kconfig
│   └── zephyr/module.yml   West 모듈 정의
├── l2-kernel/              L2: Linux 커널 드라이버
├── l3-hw-model/            L3: MMIO HW 시뮬레이터
├── l3-userlib/             L3: C++ 유저 공간 라이브러리
├── l3-appframework/        L3: C++ 애플리케이션 프레임워크
│   ├── include/
│   │   └── deepspan/appframework/
│   │       ├── circuit_breaker.hpp
│   │       ├── device_pool.hpp
│   │       └── session_manager.hpp
│   ├── src/
│   └── tests/unit/         GoogleTest 단위 테스트
├── l4-server/              L4: Go ConnectRPC 서버
├── l4-mgmt-daemon/         L4: Go OpenAMP 관리 데몬
├── l5-proto/               L5: Protobuf 정의
├── l5-gen/                 L5: 생성된 Go/Python 스텁
│   ├── go/                 Go ConnectRPC stubs
│   └── python/             Python protobuf stubs
├── l6-sdk/                 L6: Python SDK
├── third_party/            외부 의존성 (googletest, etl, spdlog)
├── tools/                  개발 도구 (deepspan-codegen)
└── west.yml                West 매니페스트 (Zephyr 4.3.0, ETL, CIB v1.7.0, OpenAMP)
```

---

## 핵심 설계 결정

- **펌웨어 네이티브 빌드**: `native_sim/native/64` 타겟으로 실제 하드웨어 없이 빌드·테스트 가능. `ZEPHYR_TOOLCHAIN_VARIANT=host`만 설정하면 Zephyr SDK 불필요.
- **CIB native_sim 비활성화**: CIB v1.7.0은 `std::uint64_t`를 사용하나 Zephyr freestanding 모드에서 사용 불가. `boards/native_sim.conf`에서 비활성화하고 ARM 타겟에서만 활성화.
- **ZEPHYR_EXTRA_MODULES**: `firmware/zephyr/module.yml`이 저장소 루트가 아닌 하위 디렉터리에 있으므로 `west build` 시 `-DZEPHYR_EXTRA_MODULES=$(pwd)/firmware` 필요. `west twister`에는 전달하지 않음 (test binary의 runtime 인자로 오인됨).
- **AppFramework**: `SessionManager`가 `DevicePool` + `CircuitBreaker`를 결합. 연속 실패 시 CB가 Open 상태로 전환하여 device를 자동 차단.

---

## CI/CD

| 워크플로우 | 트리거 | 내용 |
|-----------|--------|------|
| `ci-firmware.yml` | `firmware/**`, `west.yml` | native_sim 빌드 + twister 테스트 |
| `ci-cpp.yml` | `l3-hw-model/**`, `l3-userlib/**`, `l3-appframework/**` | CMake 빌드 + ctest (dev / dev-submodule 프리셋) |
| `ci-go.yml` | `l4-mgmt-daemon/**`, `l4-server/**`, `l5-gen/go/**`, `go.work` | go build + go test -race + golangci-lint |
| `ci-kernel.yml` | `l2-kernel/**` | out-of-tree 커널 모듈 컴파일 체크 |
| `ci-python.yml` | `l6-sdk/**` | uv sync + pytest |

---

## 스크립트

| 스크립트 | 설명 |
|---------|------|
| `scripts/verify-build.sh` | 전체 레이어 빌드 검증 (커밋 전 sanity check) |
| `scripts/codegen.sh` | Protobuf → Go/Python 스텁 생성 (`buf generate` 래퍼) |
| `firmware/scripts/build.sh` | 펌웨어 빌드 + twister 테스트 |
| `<layer>/scripts/build.sh` | 레이어별 빌드 + 단위 테스트 |
| `<layer>/scripts/setup-dev.sh` | 레이어별 개발 환경 초기 설치 |
| `<layer>/scripts/verify-setup.sh` | 개발 환경 설치 확인 |

→ 상세 사용법: [빌드 시스템 문서](../doc/build/build-system.md#빌드-스크립트-레퍼런스)

---

## 문서

전체 설계 문서: [`../doc/`](../doc/README.md)

### 시작하기
- [시작하기 가이드](../doc/guides/getting-started.md) — 환경 설정, 레이어별 첫 빌드, 트러블슈팅

### 아키텍처
- [아키텍처 개요](../doc/architecture/overview.md) — 전체 스택 설계 철학, 계층 구조
- [통신 프로토콜](../doc/architecture/communication-protocols.md) — MMIO/virtio/io_uring 계층 간 통신

### 빌드 & 패키징
- [빌드 시스템](../doc/build/build-system.md) — CMake Presets, West manifest, Go modules, uv, **스크립트 레퍼런스**
- [디렉터리 구조](../doc/build/directory-structure.md) — 파일 배치 규칙
- [패키징](../doc/build/packaging.md) — 외부 프로젝트 import 방법 (Conan / submodule)

### 레이어 설계
- [Zephyr 펌웨어](../doc/layers/zephyr-firmware.md) — ETL FSM, CIB, VirtIO transport, native_sim
- [userlib & appframework](../doc/layers/userlib-appframework.md) — io_uring, DevicePool, CircuitBreaker, SessionManager
- [Go 서버 & Python SDK](../doc/layers/server-client.md) — ConnectRPC, Protobuf, buf

### 운영
- [CI/CD](../doc/ops/cicd.md) — GitHub Actions 파이프라인 전략
- [테스팅](../doc/ops/testing.md) — 3단계 테스트 전략

---

> 최종 업데이트: 2026-03-20 — L-레이어 디렉토리 구조로 전면 개편 (l2-firmware, l3-hw-model, l4-server, l5-gen, l6-sdk 등)
