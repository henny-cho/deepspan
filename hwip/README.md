# hwip/

FPGA/ASIC Hardware IP(HWIP) 플러그인 모음.
`deepspan` 플랫폼 코어 위에서 동작하며, 하드웨어 레지스터 맵과 커맨드 집합을
`hwip.yaml` 하나로 정의하면 6개 레이어(C kernel, C firmware, C++ hw-model, C++ RPC, proto, Python SDK)의
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
│   │   ├── kernel/     C 커널/펌웨어 헤더 (deepspan_accel.h)
│   │   ├── firmware/   Zephyr dispatch 헤더
│   │   ├── sim/        C++20 hw-model ops (ops.hpp)
│   │   ├── rpc/        C++ RPC opcodes (accel.hpp)
│   │   ├── proto/      Protobuf 정의 (device.proto)
│   │   └── sdk/        Python Pydantic 모델 (models.py)
│   ├── plugin/         C++ AccelPlugin (SHM submit/poll)
│   ├── hw-model/       C++ hw-model 시뮬레이터
│   └── CMakeLists.txt  C++ 빌드
└── scripts/            hwip.sh · lib.sh
```

---

## 빠른 시작

```bash
cd deepspan

# 환경 설정 (Python venv + deepspan-codegen)
uv sync

# 코드 생성 (모든 HWIP 대상)
./scripts/dev.sh gen
# 또는 단일 HWIP
./scripts/dev.sh gen --hwip accel

# HWIP 플러그인 포함 C++ 빌드 (hw-model + server + plugin)
./scripts/dev.sh build --preset dev-hwip
ctest --preset dev-hwip

# 또는 HWIP 전용 CLI로 풀 스택 검증
./hwip/scripts/hwip.sh check
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
      encoding: fixed_args
      fields: [{name: arg0, type: u32}, {name: arg1, type: u32}]
    response:
      fields: [{name: data0, type: u32, maps_to: result_data0}]
```

### 코드 생성 파이프라인

```
hwip.yaml
    │
    ▼ deepspan-codegen (Python, uv run)
    ├── gen/kernel/deepspan_accel.h              C (kernel · firmware)
    ├── gen/firmware/deepspan_accel/dispatch.h   Zephyr
    ├── gen/sim/deepspan_accel/ops.hpp           C++20 hw-model
    ├── gen/rpc/accel.hpp                        C++ RPC opcodes
    ├── gen/proto/deepspan_accel/v1/device.proto Protobuf
    └── gen/sdk/deepspan_accel/models.py         Python (Pydantic v2)
```

```bash
# 재생성 (권장: dev.sh 경유)
./scripts/dev.sh gen --hwip accel

# 또는 직접 호출
uv run deepspan-codegen --descriptor hwip/accel/hwip.yaml --out hwip/accel/gen

# 특정 레이어만
uv run deepspan-codegen --descriptor hwip/accel/hwip.yaml --out hwip/accel/gen --target sdk

# CI용 stale 검사 (재생성하지 않고 diff만 확인)
./scripts/dev.sh gen --check
```

---

## 신규 HWIP 추가

```bash
# 1. _template을 기반으로 복사 (또는 accel을 참고)
cp -r hwip/_template/ hwip/crypto/

# 2. hwip.yaml 수정 (레지스터 맵, opcode)
vi hwip/crypto/hwip.yaml

# 3. 코드 생성
./scripts/dev.sh gen --hwip crypto

# 4. C++ AccelPlugin을 참고해 CryptoPlugin 구현
vi hwip/crypto/plugin/crypto_plugin.cpp

# 5. CMakePresets.json에 preset 추가
#    { "name": "dev-crypto", "inherits": "dev",
#      "cacheVariables": {
#        "DEEPSPAN_BUILD_HWIP": "ON",
#        "DEEPSPAN_BUILD_SERVER": "ON",
#        "HWIP_TYPES": "crypto"
#      } }

# 6. 빌드 + 검증
./scripts/dev.sh build --preset dev-crypto
./hwip/scripts/hwip.sh validate --hwip crypto
```

---

## validate 체크 목록 (`./hwip/scripts/hwip.sh validate`)

| # | 체크 | 도구 |
|---|---|---|
| 1 | gen/ stale 감지 | deepspan-codegen 재실행 + diff |
| 2 | C 커널 헤더 문법 | `gcc -fsyntax-only -std=gnu11` |
| 3 | C++20 gen/sim + gen/rpc 헤더 문법 | `g++ -fsyntax-only -std=c++20` |
| 4 | Python 문법 | `python3 -m py_compile` |
| 5 | Proto lint | `buf lint` (설치 시) |

codegen 단위 테스트(`pytest`)는 별도로 `ci-codegen.yml`에서 실행합니다.
