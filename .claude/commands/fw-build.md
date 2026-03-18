---
description: Zephyr firmware를 native_sim/native/64 타겟으로 빌드하고 twister 테스트 실행
allowed-tools: Bash(west:*), Bash(bash:*), Bash(cat:*), Bash(ls:*)
---

## Context

- West workspace: !`ls /home/choih/works/ih-scratch/.west/config 2>/dev/null && echo "west OK" || echo "west NOT FOUND"`
- Zephyr base: !`echo ${ZEPHYR_BASE:-not set}`
- Existing firmware binary: !`ls /home/choih/works/ih-scratch/deepspan/build/firmware/app/zephyr/zephyr.exe 2>/dev/null || echo "not built"`
- firmware/app structure: !`ls /home/choih/works/ih-scratch/deepspan/firmware/app/`

## Your task

Zephyr firmware를 빌드하고 테스트하세요.

### 환경 설정

west workspace root는 `/home/choih/works/ih-scratch/` (`.west/` 위치)
```bash
export ZEPHYR_TOOLCHAIN_VARIANT=host
WEST_TOPDIR=$(west topdir 2>/dev/null || echo "/home/choih/works/ih-scratch")
ZEPHYR_EXTRA_MODULES="${WEST_TOPDIR}/deepspan/firmware"
```

### 빌드 명령

```bash
cd /home/choih/works/ih-scratch

# firmware/app 빌드
west build -b native_sim/native/64 deepspan/firmware/app \
  --build-dir deepspan/build/firmware/app \
  -- -DZEPHYR_EXTRA_MODULES="${WEST_TOPDIR}/deepspan/firmware"

# 생성 확인
ls deepspan/build/firmware/app/zephyr/zephyr.exe
```

### 테스트 실행 (twister)

```bash
cd /home/choih/works/ih-scratch

west twister \
  --platform native_sim/native/64 \
  -T deepspan/firmware/tests \
  --build-only
```

**주의**: twister에 `--` cmake 인자 전달 금지 (런타임 인자로 잘못 전달됨)

### 결과 확인
1. 빌드 성공: `zephyr.exe` 생성
2. twister: `PASSED X/X` 확인
3. 실패 시: `twister-out/` 로그 분석

### 빌드 실패 일반 원인
- `CONFIG_ZTEST_NEW_API` 오류 → `prj.conf`에서 제거
- `.west` 못찾음 → workspace root 확인
- ETL/CIB 헤더 없음 → `ZEPHYR_EXTRA_MODULES` 확인
- `std::uint64_t` 오류 → `native_sim.conf`에 `CONFIG_DEEPSPAN_USE_CIB=n` 확인
