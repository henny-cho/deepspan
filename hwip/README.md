# deepspan-hwip

FPGA/ASIC Hardware IP(HWIP) 플러그인 모음. `deepspan` 플랫폼 코어 위에서 동작하며,
하드웨어 레지스터 맵과 커맨드 집합을 `hwip.yaml` 하나로 정의하면 6개 언어 레이어(C, C++, Go, Python, proto, firmware)의 코드가 자동 생성된다.

```
deepspan-hwip/
├── accel/              Accelerator HWIP (echo · process · status)
│   ├── hwip.yaml       단일 진실 원천 (레지스터 맵 + opcode 정의)
│   ├── gen/            자동 생성 아티팩트 (커밋됨)
│   │   ├── l1-kernel/  C 커널/펌웨어 헤더
│   │   ├── l2-firmware/ Zephyr dispatch 헤더
│   │   ├── l3-cpp/     C++17 hw-model ops
│   │   ├── l4-rpc/     Go opcodes (gofmt)
│   │   ├── l5-proto/   Protobuf 정의
│   │   └── l6-sdk/     Python Pydantic 모델
│   └── l4-plugin/      Go Submitter 구현 (ConnectRPC 플러그인)
├── shared/             크로스 HWIP 공통 테스트 유틸
├── scripts/            setup-dev.sh · codegen.sh · validate.sh
├── go.work             Go 단일 워크스페이스 (accel/l4-plugin + deepspan/l4-server + l5-gen)
└── west.yml            Zephyr West manifest (deepspan @ v0.3.0 고정)
```

---

## deepspan과의 관계

deepspan-hwip는 deepspan에 **단방향으로 의존**한다. deepspan은 deepspan-hwip를 모른다.

```
deepspan-hwip/
│
│  accel/l4-plugin/shmclient.go
│  └── implements ──────────────────────────────────────────────────┐
│                                                                    │
│  accel/hw-model/   (CMake)                                         │
│  └── links ─────────────── Deepspan::deepspan-appframework        │
│                             Deepspan::deepspan-userlib             │
│                                                                    │
└──────────────────────────── deepspan/l4-server/pkg/hwip.Submitter ◄──┘
                               (Tier-1 stable interface)
```

의존하는 Tier-1 인터페이스만 사용한다 (deepspan `STABLE_API.md` 기준):

| 계층 | 의존 대상 |
|---|---|
| Go | `github.com/myorg/deepspan/l4-server/pkg/hwip.Submitter` |
| C++ | `Deepspan::deepspan-appframework`, `Deepspan::deepspan-userlib` |
| Python | `deepspan.client.HwipExtension` |
| Firmware | `deepspan/l2-firmware/` (West 경유) |

---

## 디렉토리 레이아웃 및 경로 구조

두 repo는 **같은 레벨에 있을 필요가 없다.** deepspan-hwip를 클론하고 West를 실행하면 deepspan이 **내부**에 체크아웃된다.

```
ih-scratch/                  ← West topdir (.west 생성 위치)
├── .west/
├── deepspan-hwip/           ← 클론 위치 (manifest repo)
│   ├── accel/
│   │   ├── hwip.yaml        ← 단일 진실 원천
│   │   ├── gen/             ← 자동 생성 (커밋됨)
│   │   └── l4-plugin/go.mod
│   ├── shared/testutils/
│   ├── go.work              ← ./accel/l4-plugin, ../deepspan/l4-server 연결
│   └── west.yml             ← self: path: deepspan-hwip
└── deepspan/                ← west update 가 여기 체크아웃 (@ v0.3.0)
    ├── l4-server/pkg/hwip/  ← Go Tier-1 인터페이스
    ├── l5-gen/go/           ← platform RPC stubs
    └── tools/deepspan-codegen/
```

> **핵심**: `west init -l deepspan-hwip`를 **ih-scratch 디렉토리 안**에서 실행하면
> `.west`가 ih-scratch에 생성된다 (`west init -l`은 manifest repo의 부모를 topdir로 고정).
> `self: path: deepspan-hwip`로 manifest repo 위치를 명시한다.
> `deepspan`은 sibling으로 체크아웃되어 `go.work`의 `../deepspan/l4-server` 경로와 일치한다.

---

## 빠른 시작

### 사전 요건

| 도구 | 버전 | 용도 |
|---|---|---|
| Git | 2.x | - |
| West | 1.x | Zephyr/firmware 의존성 관리 |
| Go | 1.26+ | accel/l4-plugin 빌드 |
| CMake | 3.25+ | C++ hw-model 빌드 |
| Ninja | - | CMake 빌드 백엔드 |
| Python | 3.11+ | deepspan-codegen, SDK |
| buf | 1.34+ | proto → Go/Python stubs (Stage 2) |
| gcc / g++ | - | C/C++ 문법 검증 |

### 1. 저장소 클론 및 플랫폼 셋업

```bash
git clone https://github.com/myorg/deepspan-hwip
cd deepspan-hwip

# deepspan 플랫폼 체크아웃 + 아티팩트 다운로드 (원커맨드)
./scripts/setup-dev.sh
```

`setup-dev.sh`가 수행하는 작업:

1. `deepspan-codegen` 설치 (`deepspan/tools/deepspan-codegen/`)
2. 각 HWIP의 `hwip.yaml` → `gen/` 자동 생성 (Stage 1)
3. deepspan 플랫폼 C++ 라이브러리 다운로드 (`/opt/deepspan-platform/`)
   - 기본: GitHub Releases에서 tarball 다운로드
   - 소스 빌드 원할 경우: `--source-build` 옵션
4. `west init -l deepspan-hwip` (ih-scratch에서 실행) + `west update` (Zephyr 펌웨어 의존성)

### 2. Go 개발

```bash
# go.work가 accel/l4-plugin과 deepspan/l4-server, l5-gen/go 를 단일 워크스페이스로 연결
go build ./accel/l4-plugin/...
go test  ./accel/l4-plugin/...
```

### 3. C++ hw-model 빌드

```bash
cmake --preset accel-dev   # deepspan 소스 기준 (./deepspan/build/release)
cmake --build --preset accel-dev -j$(nproc)
ctest --preset accel-dev
```

### 4. 검증

```bash
# 생성 아티팩트 전체 검증 (7개 체크)
./scripts/validate.sh

# 특정 HWIP만
./scripts/validate.sh --hwip accel

# stale 자동 수정
./scripts/validate.sh --fix
```

---

## hwip.yaml — 단일 진실 원천

모든 하드웨어 정의는 `<hwip>/hwip.yaml` 하나에서 시작한다.

```yaml
# accel/hwip.yaml
hwip:
  name: accel
  version: "1.0.0"
  namespace: deepspan_accel

platform_registers:
  total_size: 0x200
  control_bank:
    - { name: ctrl, offset: 0x000, access: rw,
        bits: [{name: RESET, pos: 0}, {name: START, pos: 1}] }
  command_bank:
    - { name: cmd_opcode, offset: 0x100, access: wo }
    - { name: cmd_arg0,   offset: 0x104, access: wo }
  result_bank:
    - { name: result_data0, offset: 0x114, access: ro }

operations:
  - name: echo
    opcode: 0x0001           # HW 레지스터 와이어 값
    proto_enum_value: 1      # proto3 enum 값 (0은 UNSPECIFIED 예약)
    doc: "Echo arg0/arg1 back — latency test"
    request:
      fields: [{name: arg0, type: u32}, {name: arg1, type: u32}]
    response:
      fields: [{name: data0, type: u32, maps_to: result_data0}]
```

### 코드 생성 파이프라인

```
accel/hwip.yaml
      │
      ▼ Stage 1: deepspan-codegen
      ├── accel/gen/l1-kernel/deepspan_accel.h          C (kernel · firmware)
      ├── accel/gen/l2-firmware/deepspan_accel/dispatch.h  Zephyr
      ├── accel/gen/l3-cpp/deepspan_accel/ops.hpp       C++17 hw-model
      ├── accel/gen/l4-rpc/deepspan_accel/opcodes.go    Go opcodes (gofmt)
      ├── accel/gen/l5-proto/deepspan_accel/v1/device.proto
      └── accel/gen/l6-sdk/deepspan_accel/models.py     Python (Pydantic v2)
              │
              ▼ Stage 2: buf generate
              accel/gen/go/      Go ConnectRPC stubs
              accel/gen/python/  Python protobuf stubs
```

생성 파일은 git에 커밋된다. IDE(clangd · gopls · pyright)가 즉시 인덱싱하고, CI에서 stale 여부를 검사한다.

```bash
# 재생성
./scripts/codegen.sh             # 전체 (Stage 1 + 2)
./scripts/codegen.sh --stage 1   # Stage 1만
./scripts/codegen.sh --check     # stale 검사 (CI용, 변경 있으면 exit 1)
```

---

## 생성 아티팩트 예시 (accel)

### C 커널 헤더 (`gen/l1-kernel/deepspan_accel.h`)

```c
/* AUTO-GENERATED — DO NOT EDIT */
#define DEEPSPAN_ACCEL_OP_ECHO        0x0001U
#define DEEPSPAN_ACCEL_REG_CMD_OPCODE 0x0100U
#define DEEPSPAN_ACCEL_CTRL_START     (1U << 1)

#define DEEPSPAN_ACCEL_IS_VALID_OP(op) ( \
    (op) == 0x0001U || \
    (op) == 0x0002U || \
    (op) == 0x0003U)

struct deepspan_accel_echo_req { __u32 arg0; __u32 arg1; };
struct deepspan_accel_echo_resp { __u32 data0; __u32 data1; };
```

### C++ hw-model (`gen/l3-cpp/deepspan_accel/ops.hpp`)

```cpp
// AUTO-GENERATED — DO NOT EDIT
namespace deepspan::accel {

enum class AccelOp : uint32_t {
    ECHO = 0x0001U, PROCESS = 0x0002U, STATUS = 0x0003U,
};
struct RegOffsets {
    static constexpr uint32_t CMD_OPCODE = 0x0100U;
    static constexpr uint32_t RESULT_DATA0 = 0x0114U;
};
struct CtrlBits {
    static constexpr uint32_t START = (1U << 1);
    static constexpr uint32_t RESET = (1U << 0);
};
}
```

### Go opcodes (`gen/l4-rpc/deepspan_accel/opcodes.go`)

```go
// AUTO-GENERATED — DO NOT EDIT
package accelserver

const (
    OpEcho    uint32 = 0x0001
    OpProcess uint32 = 0x0002
    OpStatus  uint32 = 0x0003
)

func AccelOpToHwOpcode(protoOp int32) (uint32, bool) { /* ... */ }
func ValidateOpcode(op uint32) bool                  { /* ... */ }
```

### Proto3 (`gen/l5-proto/deepspan_accel/v1/device.proto`)

```proto
// AUTO-GENERATED — DO NOT EDIT
enum AccelOp {
    ACCEL_OP_UNSPECIFIED = 0;  // auto-inserted
    ACCEL_OP_ECHO        = 1;  // hw_opcode: 0x0001
    ACCEL_OP_PROCESS     = 2;
    ACCEL_OP_STATUS      = 3;
}
service AccelHwipService {
    rpc Echo(EchoRequest) returns (EchoResponse);
    rpc Process(ProcessRequest) returns (ProcessResponse);
    rpc Status(StatusRequest) returns (StatusResponse);
}
```

### Python SDK (`gen/l6-sdk/deepspan_accel/models.py`)

```python
# AUTO-GENERATED — DO NOT EDIT
class AccelOp(IntEnum):
    ECHO = 0x1; PROCESS = 0x2; STATUS = 0x3

class EchoRequest(BaseModel):
    arg0: int = Field(default=0, ge=0, lt=2**32)
    arg1: int = Field(default=0, ge=0, lt=2**32)

class AccelClient:
    hwip_type: str = "accel"
    def echo(self, arg0=0, arg1=0, timeout_ms=0) -> EchoResponse: ...
```

---

## 신규 HWIP 추가

`accel`을 템플릿으로 새 HWIP 타입(예: `crypto`)을 추가하는 절차:

```bash
# 1. accel 디렉토리 복사
cp -r accel/ crypto/

# 2. hwip.yaml 수정 (레지스터 맵, opcode만 변경)
vi crypto/hwip.yaml

# 3. 코드 생성
deepspan-codegen --descriptor crypto/hwip.yaml --out crypto/gen

# 4. Submitter 구현 (유일하게 손으로 작성하는 파일)
vi crypto/l4-plugin/shmclient.go   # hwip.Submitter 인터페이스 구현

# 5. go.work에 2줄 추가
#   use ./crypto/l4-plugin

# 6. CMakePresets.json에 preset 추가
#   { "name": "crypto-dev", "cacheVariables": { "HWIP_TYPE": "crypto" } }

# 7. CI 파일 추가 (5줄)
cp .github/workflows/ci-accel.yml .github/workflows/ci-codec.yml
# hwip-type: accel → crypto 로 변경
```

---

## CI

| 워크플로우 | 트리거 | 내용 |
|---|---|---|
| `ci-accel.yml` | accel/** push/PR | cpp · firmware · go-test (deepspan `_reusable/` 호출) |
| `ci-validate.yml` | hwip.yaml · gen/** 변경 | codegen stale · Go fmt/vet · Python 문법 · buf lint |
| `ci-all.yml` | deepspan 릴리스 트리거 | 전체 HWIP 매트릭스 |

### CI 권장 사용 (`ci-accel.yml` 예시)

```yaml
jobs:
  cpp:
    uses: myorg/deepspan/.github/workflows/_reusable/hwip-cpp.yml@main
    with:
      hwip-type: accel
      platform-ref: ${{ inputs.platform_ref || 'latest' }}
```

각 HWIP CI는 30줄 미만이다. 공통 로직은 deepspan의 `_reusable/` 워크플로우가 관리한다.

---

## validate.sh 체크 목록

```bash
./scripts/validate.sh [--hwip <type>] [--skip-syntax] [--fix]
```

| # | 체크 | 도구 |
|---|---|---|
| 1 | gen/ stale 감지 | deepspan-codegen (임시 출력과 diff) |
| 2 | C 커널 헤더 문법 | `gcc -fsyntax-only -std=gnu11` |
| 3 | C++ l3-cpp 헤더 문법 | `g++ -fsyntax-only -std=c++17` |
| 4 | Go 포맷 | `gofmt -l` |
| 5 | Go vet | `go vet` (GOWORK=off 격리 모듈) |
| 6 | Python 문법 | `python3 -m py_compile` |
| 7 | Proto lint | `buf lint` |

`--fix` 플래그로 stale gen/ 재생성과 gofmt 자동 적용이 가능하다.

---

## 공유 테스트 유틸 (`shared/testutils`)

```go
import "github.com/myorg/deepspan-hwip/shared/testutils"

// StubSubmitter: opcode를 data0에 에코하는 최소 구현
stub := &testutils.StubSubmitter{HwipTypeName: "accel"}

// SubmitterInfo 인터페이스 구현 여부 및 타입 검증
testutils.AssertSubmitterInfo(t, mySubmitter, "accel")
```

---

## 관련 저장소

| 저장소 | 역할 |
|---|---|
| [`deepspan`](https://github.com/myorg/deepspan) | 플랫폼 코어 (Tier-1 stable API 정의) |
| [`deepspan-hwip`](https://github.com/myorg/deepspan-hwip) | HWIP 플러그인 모음 (이 저장소) |

deepspan Tier-1 인터페이스 전체 목록은 [`deepspan/STABLE_API.md`](https://github.com/myorg/deepspan/blob/main/STABLE_API.md) 참조.
