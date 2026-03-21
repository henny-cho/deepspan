---
description: deepspan-codegen 실행, 생성 파일 diff 확인, 변경 시 커밋 제안
allowed-tools: Bash(bash:*), Bash(git:*), Bash(cat:*), Bash(ls:*), Bash(python:*)
---

## Context

- codegen tool: !`python -m deepspan_codegen --help 2>/dev/null | head -5 || echo "deepspan_codegen not found — run: uv sync"`
- uv sync status: !`ls /home/choih/works/ih-scratch/deepspan/.venv/bin/activate 2>/dev/null && echo "venv exists" || echo "venv missing"`
- current gen diff: !`git -C /home/choih/works/ih-scratch/deepspan diff --stat hwip/accel/gen/ 2>/dev/null`
- hwip.yaml files: !`find /home/choih/works/ih-scratch/deepspan/hwip -name "hwip.yaml" 2>/dev/null`

## Your task

deepspan-codegen을 실행하고 생성 파일을 검증하세요.

### 절차

1. **환경 확인**:
   - `.venv` 존재 여부 확인
   - 없으면 `uv sync` 실행

2. **실행**:
   ```bash
   cd /home/choih/works/ih-scratch/deepspan
   source .venv/bin/activate
   python -m deepspan_codegen -d hwip/accel/hwip.yaml -o hwip/accel/gen
   ```

3. **변경 확인**:
   ```bash
   git diff --stat hwip/accel/gen/
   git diff hwip/accel/gen/
   ```

4. **결과 분류**:
   - 변경 없음: "gen 코드가 hwip.yaml과 동기화됨" 출력
   - 변경 있음:
     - 변경 내용 요약 (어떤 타겟이 바뀌었는지)
     - 커밋 여부 물어보기

5. **커밋 시** (`build(codegen): regenerate accel artifacts` 형식 사용):
   ```bash
   git add hwip/accel/gen/
   git commit -m "build(codegen): regenerate accel artifacts"
   ```

### 생성 타겟 목록

| 타겟 | 출력 경로 | 용도 |
|------|-----------|------|
| `kernel` | `gen/kernel/deepspan_accel.h` | C 커널/펌웨어 헤더 |
| `firmware` | `gen/firmware/deepspan_accel/dispatch.h` | Zephyr dispatch |
| `hw_model` | `gen/sim/deepspan_accel/ops.hpp` | C++ hw-model ops |
| `rpc` | `gen/rpc/accel.hpp` | C++ RPC opcodes |
| `proto` | `gen/proto/deepspan_accel/v1/device.proto` | Protobuf 정의 |
| `python` | `gen/sdk/deepspan_accel/models.py` | Python Pydantic SDK |

### 주의사항
- `gen/` 아래 파일은 `# AUTO-GENERATED` 헤더 — 직접 수정 금지
- `hwip.yaml`을 수정한 경우 반드시 재생성 후 커밋
- Python SDK 변경 시 `sdk/tests/` 재실행: `python -m pytest codegen/tests/ sdk/tests/ --import-mode=importlib -q`
