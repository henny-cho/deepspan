---
description: verify-build.sh 실행 후 FAIL 레이어 자동 분석 및 수정 제안
allowed-tools: Bash(bash:*), Bash(cat:*), Bash(grep:*)
---

## Context

- verify-build.sh exists: !`ls /home/choih/works/ih-scratch/deepspan/scripts/verify-build.sh`
- Current directory: !`pwd`

## Your task

Deepspan 전체 레이어 빌드를 검증하고 실패 항목을 분석하세요.

### 절차

1. **실행**:
   ```bash
   cd /home/choih/works/ih-scratch/deepspan
   bash scripts/verify-build.sh 2>&1
   ```

2. **결과 파싱**:
   - `PASS` / `FAIL` / `SKIP` 집계
   - FAIL 레이어 식별

3. **FAIL 레이어 분석** (각 FAIL에 대해):
   - 에러 메시지 전체 읽기
   - 원인 파악: 의존성 누락 / 컴파일 오류 / 테스트 실패 / 환경 문제
   - 수정 방법 제시

4. **출력 형식**:
```
## verify-build 결과

| 레이어 | 결과 | 비고 |
|--------|------|------|
| hw-model | ✅ PASS | |
| firmware | ❌ FAIL | west not found |
...

**요약**: PASS X / FAIL Y / SKIP Z

## FAIL 분석

### firmware
- **원인**: ...
- **수정**: ...
```

5. **수정 가능한 항목**은 바로 수정할지 물어보세요.

### 주의사항
- firmware는 west/Zephyr SDK 없으면 SKIP 처리됨 (정상)
- `ZEPHYR_TOOLCHAIN_VARIANT=host` 필요
- C++ 빌드: CMakePresets.json `dev` preset 사용 (cmake --preset dev)
