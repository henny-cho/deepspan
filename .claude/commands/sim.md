---
description: 전체 시뮬레이션 스택 시작 및 검증 (hw-model, firmware_sim, mgmt-daemon, server, SDK)
allowed-tools: Bash(scripts/run-sim.sh:*), Bash(lsof:*), Bash(pkill:*), Bash(curl:*), Bash(cat:*)
---

## Context

- Deepspan root: /home/choih/works/ih-scratch/deepspan
- Current port usage: !`lsof -i :8080 -t 2>/dev/null | head -3 && lsof -i :8081 -t 2>/dev/null | head -3 || echo "ports free"`
- Running deepspan processes: !`pgrep -a "deepspan|mgmt-daemon|zephyr.exe" 2>/dev/null || echo "none"`
- Binary status: !`ls -1 /home/choih/works/ih-scratch/deepspan/hw-model/build/deepspan-hw-model /home/choih/works/ih-scratch/deepspan/hw-model/build/deepspan-firmware-sim /home/choih/works/ih-scratch/deepspan/build/bin/deepspan-server /home/choih/works/ih-scratch/deepspan/build/bin/mgmt-daemon 2>&1`

## Your task

전체 Deepspan 시뮬레이션 스택을 시작하고 검증하세요.

### 절차

1. **기존 프로세스 정리**: 포트 8080/8081 점유 프로세스 및 기존 deepspan 프로세스 종료
2. **바이너리 확인**: hw-model, firmware_sim, mgmt-daemon, server 바이너리 존재 여부 확인
   - 없으면 `scripts/run-sim.sh` (빌드 포함) 실행
   - 있으면 `scripts/run-sim.sh --no-build` 실행
3. **실행**: `cd /home/choih/works/ih-scratch/deepspan && bash scripts/run-sim.sh [--no-build]`
4. **결과 확인**:
   - PASSED 메시지 확인
   - hw_cmd_count / fw_cmd_count 증가 확인
   - `http://localhost:8080/monitor` URL 출력
5. **실패 시**: 해당 레이어 로그(`build/logs/*.log`) 읽어서 원인 분석 후 수정 제안

### 주의사항
- 스크립트가 "Press Ctrl-C" 상태로 대기 중이면 백그라운드에서 계속 실행 중인 것이 정상
- hw-model이 없으면 firmware_sim도 동작하지 않음 (shm 의존)
- Python은 `.venv/bin/python` 우선 사용
