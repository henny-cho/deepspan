---
description: 실행 중인 hw-model의 레지스터 상태, 명령 카운터, firmware_sim 연동 현황 출력
allowed-tools: Bash(curl:*), Bash(pgrep:*)
---

## Context

- Running processes: !`pgrep -a "deepspan-hw-model\|deepspan-firmware-sim\|deepspan-server" 2>/dev/null || echo "none running"`
- Raw hw-stats API: !`curl -sf http://localhost:8080/api/hw-stats 2>/dev/null || echo "server not reachable"`

## Your task

hw-model의 현재 상태를 읽어서 포맷된 리포트로 출력하세요.

### 출력 형식

서버가 응답하는 경우:
```
╔══════════════════════════════════════╗
║  Deepspan HW-Model Status            ║
╠══════════════════════════════════════╣
║  version      : 0x00010000  (v1.0.0) ║
║  capabilities : DMA  IRQ  MULTI      ║
║  status       : READY                ║
║  uptime       : 42s                  ║
╠══════════════════════════════════════╣
║  hw cmd_count : 125                  ║
║  fw cmd_count : 125                  ║
║  last opcode  : 0x00000001 (ECHO)    ║
║  result_data0 : 0xDEAD007C           ║
║  result_data1 : 0x0000007C           ║
╠══════════════════════════════════════╣
║  monitor URL  : http://localhost:8080/monitor ║
╚══════════════════════════════════════╝
```

서버가 없는 경우:
- 실행 방법 안내: `cd deepspan && bash scripts/run-sim.sh --no-build`

shm은 있지만 server가 없는 경우:
- `/dev/shm/deepspan-sim` 직접 읽기 시도 (Python으로 파싱)

### 추가 분석
- hw_cmd_count와 fw_cmd_count가 크게 다를 경우 (> 5 차이): 동기화 문제 경고
- status가 BUSY인 경우: 명령 처리 중 (정상)
- status가 ERROR인 경우: hw-model 이상 경고
