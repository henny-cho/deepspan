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

| 레이어 | 언어 | 설명 |
|--------|------|------|
| `hw-model` | C++17 | FPGA 레지스터 MMIO 시뮬레이터 |
| `firmware` | C++20 + Zephyr | ETL FSM · VirtIO transport · native_sim |
| `kernel` | C (Linux) | virtio master 드라이버 · io_uring · 다중 디바이스 |
| `userlib` | C++23 | ioctl / mmap / io_uring 래퍼 |
| `appframework` | C++23 | DevicePool · CircuitBreaker · SessionManager |
| `server` | Go | ConnectRPC 서버 · Protobuf |
| `sdk` | Python | Pydantic v2 클라이언트 |

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
west build -b native_sim/native/64 firmware/app \
    -- -DZEPHYR_EXTRA_MODULES=$(pwd)/firmware
./build/zephyr/zephyr.exe   # 직접 실행
```

### 3. 펌웨어 테스트

```bash
cd deepspan/
ZEPHYR_TOOLCHAIN_VARIANT=host \
west twister --platform native_sim/native/64 -T firmware/tests
# 예상: 2 of 2 test cases passed (100.00%)
```

### 4. C++ 레이어 빌드 및 테스트

```bash
cd deepspan/appframework/
cmake -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build
ctest --test-dir build --output-on-failure
```

### 5. Go 서버 빌드

```bash
cd deepspan/server/
buf generate        # Protobuf → Go 코드 생성
go build -o bin/deepspan-server ./cmd/server/
```

---

## 디렉터리 구조

```
deepspan/
├── firmware/               Zephyr 펌웨어
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
├── appframework/           C++ 애플리케이션 프레임워크
│   ├── include/
│   │   └── deepspan/appframework/
│   │       ├── circuit_breaker.hpp
│   │       ├── device_pool.hpp
│   │       └── session_manager.hpp
│   ├── src/
│   └── tests/unit/         GoogleTest 단위 테스트
├── userlib/                C++ 유저 공간 라이브러리
├── hw-model/               MMIO HW 시뮬레이터
├── kernel/                 Linux 커널 드라이버
├── server/                 Go ConnectRPC 서버
├── sdk/                    Python SDK
├── proto/                  Protobuf 정의
├── third_party/            외부 의존성 (googletest, etl, spdlog)
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
| `ci-firmware.yml` | `firmware/**`, `west.yml` push/PR | native_sim 빌드 + twister 테스트 |

---

## 문서

전체 설계 문서: [`../doc/`](../doc/README.md)

- [아키텍처 개요](../doc/architecture/overview.md)
- [시작하기](../doc/guides/getting-started.md)
- [Zephyr 펌웨어 레이어](../doc/layers/zephyr-firmware.md)
- [CI/CD](../doc/ops/cicd.md)

---

> 최종 업데이트: 2026-03-18
