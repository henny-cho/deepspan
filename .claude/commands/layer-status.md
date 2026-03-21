---
description: 각 레이어의 구현 완성도, TODO/stub 개수, 빌드 상태를 테이블로 출력
allowed-tools: Bash(grep:*), Bash(find:*), Bash(ls:*), Bash(git:*)
---

## Context

- TODO/stub locations: !`grep -rn "TODO\|FIXME\|stub\|Stub\|placeholder\|not implemented" /home/choih/works/ih-scratch/deepspan --include="*.cpp" --include="*.hpp" --include="*.py" --include="*.c" --include="*.h" -l 2>/dev/null | grep -v "build/" | grep -v ".git/"`
- Binary existence: !`ls /home/choih/works/ih-scratch/deepspan/build/bin/deepspan-hw-model /home/choih/works/ih-scratch/deepspan/build/bin/deepspan-firmware-sim /home/choih/works/ih-scratch/deepspan/build/bin/deepspan-server /home/choih/works/ih-scratch/deepspan/build/firmware/app/zephyr/zephyr.exe 2>&1`
- Recent commits: !`git -C /home/choih/works/ih-scratch/deepspan log --oneline -10`
- Untracked/modified files: !`git -C /home/choih/works/ih-scratch/deepspan status --short`

## Your task

Deepspan 멀티레이어 스택의 현재 구현 상태를 분석하여 보고하세요.

### 각 레이어별로 확인할 항목

레이어 목록: `hw-model`, `firmware`, `kernel`, `userlib`, `appframework`, `server`, `sdk`

각 레이어에 대해:
1. 소스 파일 구조 파악 (핵심 파일만)
2. TODO/FIXME/stub 개수 카운트
3. 빌드 바이너리 존재 여부
4. 테스트 파일 존재 여부

### 출력 형식

다음 형식의 마크다운 테이블로 출력하세요:

```
| 레이어 | 상태 | TODO/stub | 바이너리 | 테스트 | 핵심 미완성 항목 |
|--------|------|-----------|---------|--------|-----------------|
| hw-model | ✅ 완성 | 0 | ✅ | ✅ | — |
| firmware | ⚠️ 진행중 | 2 | ✅ | ✅ | MMIO 드라이버 |
...
```

상태 아이콘:
- ✅ 완성: 주요 기능 구현, 빌드 통과
- ⚠️ 진행중: 골격 있으나 stub/TODO 다수
- ❌ 미착수: 파일만 있고 구현 없음

마지막에 **"지금 바로 작업 가능한 항목"** 1-3개를 제안하세요.
