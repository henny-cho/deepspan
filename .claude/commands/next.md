---
description: 현재 TODO/stub 스캔 후 Phase 계획과 대조하여 다음 작업 제안
allowed-tools: Bash(grep:*), Bash(find:*), Bash(cat:*), Bash(git:*)
---

## Context

- TODO/stub summary: !`grep -rn "TODO\|FIXME\|stub\|Stub" /home/choih/works/ih-scratch/deepspan --include="*.go" --include="*.cpp" --include="*.hpp" --include="*.py" --include="*.c" -l 2>/dev/null | grep -v "build/" | grep -v ".git/" | while read f; do echo "$f: $(grep -c 'TODO\|FIXME\|stub\|Stub' $f)"; done`
- Recent git log: !`git -C /home/choih/works/ih-scratch/deepspan log --oneline -5`
- Modified/untracked: !`git -C /home/choih/works/ih-scratch/deepspan status --short`

## Phase 계획 (참고)

### Phase 1 — 시뮬레이션 스택 완성
- **1-1** Firmware native_sim MMIO 드라이버 (`firmware/app/src/hw_sim_driver.cpp`)
  - shm_open + mmap으로 hw-model shm 연결, ECHO 명령 전송 루프
- **1-2** mgmt-daemon sim pipe transport (GetFirmwareInfo 500 해소)
  - Unix pipe 기반 stub 응답 반환
- **1-3** server SubmitRequest shm 연결 (Go에서 RegMap 쓰기)

### Phase 2 — 커널 + userlib 연결
- **2-1** 커널 virtio probe 완성 (`kernel/drivers/deepspan/deepspan_virtio.c`)
- **2-2** userlib io_uring AsyncClient submit()/drain() 완성
- **2-3** appframework DevicePool 실제 연결

### Phase 3 — 전체 경로 통합
- **3-1** server HwipService CGo 브릿지
- **3-2** QEMU virtio-mmio 환경 지원

## Your task

현재 codebase 상태를 Phase 계획과 대조하여 **지금 바로 시작할 수 있는 가장 작은 작업**을 제안하세요.

### 분석 절차

1. 각 Phase 1 항목의 진행 상태 확인 (해당 파일 존재 여부, TODO 유무)
2. 의존성 확인 (선행 작업이 완료됐는지)
3. 작업 크기 추정 (새 파일 몇 개, 수정 몇 줄)

### 출력 형식

```
## 다음 작업 추천

### 1순위: [작업명] (Phase X-Y)
- **이유**: 왜 지금 이 작업인가
- **파일**: 생성/수정할 파일 목록
- **예상 범위**: 대략적인 변경 크기
- **검증 방법**: 어떻게 동작 확인하는가

### 2순위: [작업명]
...

### 건너뛸 항목
- [항목]: [이유]
```

바로 시작하시겠습니까? 라고 물어보세요.
