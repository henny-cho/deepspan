# hwip/

FPGA/ASIC Hardware IP(HWIP) 플러그인 모음.
`deepspan` 플랫폼 코어 위에서 동작하며, 하드웨어 레지스터 맵과 커맨드 집합을
`hwip.yaml` 하나로 정의하면 6개 언어 레이어(C, C++, Go, Python, proto, firmware)의
코드가 자동 생성된다.

> **이전 standalone 레포**: `deepspan-hwip` 독립 레포는 모노레포 통합으로 폐기.
> 이 디렉토리(`deepspan/hwip/`)가 해당 레포의 후속 위치다.

---

## 디렉토리 구조

```
deepspan/hwip/
├── accel/              Accelerator HWIP (echo · process · status)
│   ├── hwip.yaml       단일 진실 원천 (레지스터 맵 + opcode 정의)
│   ├── gen/            자동 생성 아티팩트 (커밋됨)
│   │   ├── l1-kernel/  C 커널/펌웨어 헤더
│   │   ├── l2-firmware/ Zephyr dispatch 헤더
│   │   ├── l3-cpp/     C++17 hw-model ops
│   │   ├── l4-rpc/     Go opcodes (deepspan-codegen 생성)
│   │   ├── l5-proto/   Protobuf 정의
│   │   ├── l6-sdk/     Python Pydantic 모델
│   │   └── go/         Go ConnectRPC stubs (buf 생성)
│   ├── l4-plugin/      Go Submitter 구현 (ConnectRPC 플러그인)
│   └── CMakeLists.txt  C++ hw-model 빌드
├── demo/               full-stack demo server + client (Go)
├── shared/             크로스 HWIP 공통 테스트 유틸
├── scripts/            setup-dev.sh · validate.sh · gate.sh
├── buf.yaml            buf 설정 (proto lint)
└── buf.gen.yaml        buf codegen 설정 (Go/Python stubs)
```

---

## Go 모듈 경로

| 디렉토리 | Go 모듈 |
|---|---|
| `hwip/accel/gen/go` | `github.com/myorg/deepspan/hwip/accel/gen/go` |
| `hwip/accel/l4-plugin` | `github.com/myorg/deepspan/hwip/accel/l4-plugin` |
| `hwip/shared/testutils` | `github.com/myorg/deepspan/hwip/shared/testutils` |
| `hwip/demo` | `github.com/myorg/deepspan/hwip/demo` |

모든 모듈은 루트 `go.work`에 포함되어 별도 `replace` 없이 빌드 가능.

---

## 빠른 시작 (모노레포)

```bash
# 루트에서 전체 환경 설정
cd deepspan
./scripts/setup-all.sh

# HWIP 개발 환경만 (deepspan-codegen + codegen 실행)
./hwip/scripts/setup-dev.sh

# Go 빌드 및 테스트
go build ./hwip/...
go test  ./hwip/accel/l4-plugin/... ./hwip/demo/...

# C++ HWIP 포함 빌드
cmake --preset dev-hwip
cmake --build --preset dev-hwip -j$(nproc)
ctest --preset dev-hwip

# 생성 아티팩트 검증 (7개 체크)
./hwip/scripts/validate.sh
```

---

## hwip.yaml — 단일 진실 원천

```yaml
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
  result_bank:
    - { name: result_data0, offset: 0x114, access: ro }

operations:
  - name: echo
    opcode: 0x0001
    proto_enum_value: 1
    doc: "Echo arg0/arg1 back — latency test"
    request:
      fields: [{name: arg0, type: u32}, {name: arg1, type: u32}]
    response:
      fields: [{name: data0, type: u32}]
```

### 코드 생성 파이프라인

```
hwip.yaml
    │
    ▼ Stage 1: deepspan-codegen
    ├── gen/l1-kernel/deepspan_accel.h          C (kernel · firmware)
    ├── gen/l2-firmware/deepspan_accel/dispatch.h  Zephyr
    ├── gen/l3-cpp/deepspan_accel/ops.hpp       C++17 hw-model
    ├── gen/l4-rpc/deepspan_accel/opcodes.go    Go opcodes
    ├── gen/l5-proto/deepspan_accel/v1/device.proto
    └── gen/l6-sdk/deepspan_accel/models.py     Python (Pydantic v2)
            │
            ▼ Stage 2: buf generate
            gen/go/      Go ConnectRPC stubs
            gen/python/  Python protobuf stubs
```

```bash
# 재생성 (루트에서)
./scripts/codegen.sh --hwip          # Stage 1 + 2
./scripts/codegen.sh --hwip --check  # stale 검사 (CI용)
```

---

## 신규 HWIP 추가

```bash
# 1. accel을 템플릿으로 복사
cp -r hwip/accel/ hwip/crypto/

# 2. hwip.yaml 수정 (레지스터 맵, opcode)
vi hwip/crypto/hwip.yaml

# 3. 코드 생성
deepspan-codegen --descriptor hwip/crypto/hwip.yaml --out hwip/crypto/gen

# 4. Submitter 구현
vi hwip/crypto/l4-plugin/shmclient.go  # hwip.Submitter 인터페이스 구현

# 5. go.work에 추가
#   use ./hwip/crypto/l4-plugin

# 6. CMakePresets.json에 preset 추가
#   { "name": "dev-crypto", "inherits": "dev",
#     "cacheVariables": { "DEEPSPAN_BUILD_HWIP": "ON", "HWIP_TYPE": "crypto" } }
```

---

## validate.sh 체크 목록

| # | 체크 | 도구 |
|---|---|---|
| 1 | gen/ stale 감지 | deepspan-codegen (임시 출력과 diff) |
| 2 | C 커널 헤더 문법 | `gcc -fsyntax-only -std=gnu11` |
| 3 | C++ hw_model 헤더 문법 | `g++ -fsyntax-only -std=c++17` |
| 4 | Go 포맷 | `gofmt -l` |
| 5 | Go vet | `go vet` |
| 6 | Python 문법 | `python3 -m py_compile` |
| 7 | Proto lint | `buf lint` |

```bash
./hwip/scripts/validate.sh [--hwip accel] [--fix]
```

---

## 공유 테스트 유틸 (`shared/testutils`)

```go
import "github.com/myorg/deepspan/hwip/shared/testutils"

stub := &testutils.StubSubmitter{HwipTypeName: "accel"}
testutils.AssertSubmitterInfo(t, mySubmitter, "accel")
```
