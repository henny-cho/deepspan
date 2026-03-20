# Deepspan Architecture

멀티레이어 SW 스택의 레이어 간 의존 관계, 실행 경로, 인터페이스 경계를 설명한다.

---

## 레이어 의존 관계

```
  [Python SDK]              l6/sdk
       │ ConnectRPC (HTTP/2)
  [Go Server]               l4/server
       │ CGo
  [C++ appframework]        l3/appframework
       │
  [C++ userlib]             l3/userlib
       │
    ┌──┴──────────────────────────────────────────────────┐
    │  HW 경로 (실제 하드웨어)      Sim 경로 (시뮬레이션)      │
    │  l2/kernel (Linux kmod)       l3/hw-model (C++)         │
    │  l2/firmware (Zephyr)         POSIX 공유 메모리 MMIO sim │
    └─────────────────────────────────────────────────────┘
       │
  [HWIP plugin]             hwip/accel/l4-plugin · hwip.Submitter
```

### 레이어별 역할

| 레이어 | 디렉토리 | 언어 | 역할 |
|--------|---------|------|------|
| L2 | `l2/firmware` | C++20 + Zephyr | 디바이스 사이드 ETL FSM, VirtIO transport |
| L2 | `l2/kernel` | C (Linux) | 호스트 사이드 virtio 마스터 드라이버, io_uring |
| L3 | `l3/hw-model` | C++17 | FPGA MMIO 시뮬레이터 — `l2` 전체를 대체 |
| L3 | `l3/userlib` | C++23 | ioctl / mmap / io_uring 래퍼 (실 HW 경로) |
| L3 | `l3/appframework` | C++23 | DevicePool, CircuitBreaker, SessionManager |
| L4 | `l4/server` | Go | ConnectRPC 서버, hwip.Submitter 디스패치 |
| L4 | `l4/mgmt-daemon` | Go | OpenAMP 관리 데몬 |
| L5 | `l5/proto` | Protobuf | API 정의 |
| L5 | `l5/gen` | Go + Python | buf 생성 ConnectRPC 스텁 |
| L6 | `l6/sdk` | Python | Pydantic v2 클라이언트 |
| HWIP | `hwip/accel` | Go + C++ | Accelerator HWIP 플러그인 |

---

## 실행 경로: HW vs Sim

### HW 경로 (실제 FPGA/ASIC)

```
l6/sdk (Python)
    │ HTTP/2 ConnectRPC
l4/server (Go)
    │ CGo
l3/appframework → l3/userlib
    │ ioctl / io_uring URING_CMD
l2/kernel (Linux kmod: /dev/hwipN)
    │ VirtIO virtqueue (PCIe)
l2/firmware (Zephyr on FPGA)
    │ MMIO 레지스터
FPGA/ASIC 하드웨어
```

### Sim 경로 (l2 대체)

```
l6/sdk (Python)
    │ HTTP/2 ConnectRPC
l4/server (Go)
    │ CGo
l3/appframework → l3/userlib
    │ POSIX 공유 메모리 (shm_open)
l3/hw-model (C++)          ← l2/kernel + l2/firmware 역할 전담
    │ 메모리 내 MMIO 레지스터 시뮬레이션
hwip/accel ShmClient
```

`l3/hw-model`은 `l2/firmware`와 `l2/kernel` 쌍 전체를 대체한다.
동일한 `l4/server`가 두 경로를 모두 지원하며 경로 전환은 설정으로만 결정된다.

---

## hwip.Submitter 인터페이스

`l4/server`는 `pkg/hwip.Submitter` 인터페이스 하나로 HWIP 플러그인을 추상화한다.

```go
// l4/server/pkg/hwip/submitter.go
type Submitter interface {
    Info() SubmitterInfo           // HWIP 타입 메타데이터
    Submit(ctx context.Context, req *SubmitRequest) (*SubmitResponse, error)
    Close() error
}
```

HWIP 플러그인(`hwip/accel/l4-plugin`)은 이 인터페이스만 구현하면 서버에 등록된다.
서버는 플러그인 타입을 알 필요 없이 Submitter를 통해 HW 요청을 디스패치한다.

---

## hwip.yaml 단일 원천 및 코드 생성 파이프라인

레지스터 맵과 opcode는 `hwip/accel/hwip.yaml` 하나에 정의된다.
`deepspan-codegen`이 이를 읽어 6개 레이어 아티팩트를 동시에 생성한다.

```
hwip/accel/hwip.yaml
    │
    ▼ Stage 1: deepspan-codegen (tools/deepspan-codegen)
    ├── gen/l1-kernel/deepspan_accel.h          C (커널 · 펌웨어 공용)
    ├── gen/l2-firmware/deepspan_accel/dispatch.h  Zephyr opcode dispatch
    ├── gen/l3-cpp/deepspan_accel/ops.hpp        C++17 hw-model 열거형 + ops
    ├── gen/l4-rpc/deepspan_accel/opcodes.go     Go opcode 상수
    ├── gen/l5-proto/deepspan_accel/v1/device.proto  Protobuf 서비스 정의
    └── gen/l6-sdk/deepspan_accel/models.py      Python Pydantic v2 모델
            │
            ▼ Stage 2: buf generate (buf.yaml / buf.gen.yaml)
            gen/go/      Go ConnectRPC 스텁 (서버 + 클라이언트)
            gen/python/  Python protobuf 스텁
```

재생성:
```bash
./scripts/codegen.sh --hwip          # Stage 1 + 2
./scripts/codegen.sh --hwip --check  # stale 검사 (CI용)
```

생성된 아티팩트는 커밋되어 레포에 포함된다.
`ci-codegen.yml`이 매 push마다 stale 여부를 검증한다.

---

## Go 모듈 구조

루트 `go.work`가 7개 Go 모듈을 단일 워크스페이스로 묶는다.
`replace` 지시자 없이 monorepo 내 cross-module 참조가 가능하다.

```
go.work
├── use ./l5/gen/go              github.com/myorg/deepspan/l5/gen
├── use ./l4/mgmt-daemon         github.com/myorg/deepspan/l4/mgmt-daemon
├── use ./l4/server              github.com/myorg/deepspan/l4/server
├── use ./hwip/accel/gen/go      github.com/myorg/deepspan/hwip/accel/gen/go
├── use ./hwip/accel/l4-plugin   github.com/myorg/deepspan/hwip/accel/l4-plugin
├── use ./hwip/shared/testutils  github.com/myorg/deepspan/hwip/shared/testutils
└── use ./hwip/demo              github.com/myorg/deepspan/hwip/demo
```

> **주의:** hwip go.mod의 `v0.0.0-00010101000000-000000000000` 버전은 `replace` 지시자가 필수다.
> go.work `use()` 만으로는 Go의 버전 유효성 검사를 통과하지 못한다.

---

## 신규 HWIP 추가 방법

```bash
# 1. accel을 템플릿으로 복사
cp -r hwip/accel/ hwip/crypto/

# 2. hwip.yaml 편집 (레지스터 맵, opcode 정의)
vi hwip/crypto/hwip.yaml

# 3. 코드 생성 (Stage 1 + 2)
./scripts/codegen.sh --hwip crypto

# 4. hwip.Submitter 구현
vi hwip/crypto/l4-plugin/cryptoservice.go

# 5. go.work에 새 모듈 추가
go work use ./hwip/crypto/l4-plugin
go work use ./hwip/crypto/gen/go

# 6. CMakePresets.json에 preset 추가
#   { "name": "dev-crypto", "inherits": "dev",
#     "cacheVariables": { "DEEPSPAN_BUILD_HWIP": "ON", "HWIP_TYPE": "crypto" } }

# 7. l4/server에 플러그인 등록 (서버 초기화 코드)
#   server.RegisterSubmitter(crypto.NewSubmitter(...))
```

---

## CMake 빌드 구조

```
CMakeLists.txt (루트)
├── l3/hw-model/          — POSIX shm MMIO 시뮬레이터
├── l3/userlib/           — io_uring 래퍼
├── l3/appframework/      — DevicePool · CircuitBreaker
└── hwip/${HWIP_TYPE}/    — DEEPSPAN_BUILD_HWIP=ON 시 추가
    └── hwip/accel/       — C++ hw-model ops (gen/l3-cpp 활용)
```

| Preset | 설명 |
|--------|------|
| `dev` | userspace C++ 전체, 테스트 ON |
| `dev-hwip` | dev + HWIP accel C++ 플러그인 |
| `sim` | 시뮬레이션 최적화 |
| `release` | 최적화, 테스트 OFF |
| `arm64-cross` | ARM64 크로스 컴파일 |
| `coverage` | gcov 커버리지 |

---

> 최종 업데이트: 2026-03-20
