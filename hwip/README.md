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
│   │   ├── sim/        C++17 hw-model ops (ops.hpp)
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

# 코드 생성
source .venv/bin/activate
python -m deepspan_codegen -d hwip/accel/hwip.yaml -o hwip/accel/gen

# C++ 빌드 (hw-model + server + plugin)
cmake --preset dev
cmake --build --preset dev -j$(nproc)
ctest --preset dev
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
    ├── gen/sim/deepspan_accel/ops.hpp           C++17 hw-model
    ├── gen/rpc/accel.hpp                        C++ RPC opcodes
    ├── gen/proto/deepspan_accel/v1/device.proto Protobuf
    └── gen/sdk/deepspan_accel/models.py         Python (Pydantic v2)
```

```bash
# 재생성
source .venv/bin/activate
python -m deepspan_codegen -d hwip/accel/hwip.yaml -o hwip/accel/gen

# 특정 타겟만
python -m deepspan_codegen -d hwip/accel/hwip.yaml -o hwip/accel/gen --target python
```

---

## 신규 HWIP 추가

```bash
# 1. accel을 템플릿으로 복사
cp -r hwip/accel/ hwip/crypto/

# 2. hwip.yaml 수정 (레지스터 맵, opcode)
vi hwip/crypto/hwip.yaml

# 3. 코드 생성
python -m deepspan_codegen -d hwip/crypto/hwip.yaml -o hwip/crypto/gen

# 4. C++ AccelPlugin을 참고해 CryptoPlugin 구현
vi hwip/crypto/plugin/crypto_plugin.cpp

# 5. CMakePresets.json에 preset 추가
```

---

## validate 체크 목록

| # | 체크 | 도구 |
|---|---|---|
| 1 | gen/ stale 감지 | deepspan-codegen --dry-run + diff |
| 2 | C 커널 헤더 문법 | `gcc -fsyntax-only -std=gnu11` |
| 3 | C++ hw_model 헤더 문법 | `g++ -fsyntax-only -std=c++17` |
| 4 | Python 문법 | `python3 -m py_compile` |
| 5 | Proto lint | `buf lint` |
| 6 | codegen 단위 테스트 | `pytest codegen/tests/ -q` |
