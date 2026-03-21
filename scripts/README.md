# Deepspan Scripts

개발 라이프사이클을 따르는 두 개의 통합 CLI로 구성됩니다.

| CLI | 대상 | 위치 |
|-----|------|------|
| `dev.sh` | 플랫폼 전체 (모든 레이어) | `scripts/dev.sh` |
| `hwip.sh` | HWIP 서브시스템 전용 | `hwip/scripts/hwip.sh` |

공유 헬퍼 함수(색상, 로깅, 테스트 카운터, `wait_port` 등)는 `scripts/lib.sh`에 있으며, `hwip/scripts/lib.sh`가 이를 sourcing합니다.

---

## dev.sh — 플랫폼 개발 CLI

```
./scripts/dev.sh <command> [options]
```

### 라이프사이클 순서

```
setup → gen → build → test → validate
                           ↗
                     check (전체 CI 게이트)
```

### 명령어 상세

#### `setup` — 툴체인 설치 및 환경 검증

```bash
./scripts/dev.sh setup                        # 모든 레이어 설치 + 검증
./scripts/dev.sh setup --skip l2/firmware     # 느린 Zephyr SDK 다운로드 건너뜀
./scripts/dev.sh setup --layers l4/server,l6/sdk   # 특정 레이어만
./scripts/dev.sh setup --hooks                # git pre-commit 훅 설치 포함
./scripts/dev.sh setup --verify-only          # 설치 없이 검증만
```

옵션 | 설명
-----|-----
`--layers L1,L2` | 콤마 구분 레이어 목록으로 범위 한정
`--skip L1` | 특정 레이어 건너뜀 (firmware는 다운로드가 오래 걸림)
`--hooks` | `.githooks/`를 git hooks 경로로 설정
`--verify-only` | 설치 단계 없이 현재 환경 검증만 수행

사용 가능한 레이어: `l3/hw-model`, `l2/firmware`, `l2/kernel`, `l3/userlib`, `l3/appframework`, `l4/server`, `l6/sdk`

---

#### `gen` — 코드 생성

hwip.yaml로부터 HWIP 레이어 아티팩트를 생성합니다 (`deepspan-codegen`).

```bash
./scripts/dev.sh gen                   # 모든 HWIP 코드젠
./scripts/dev.sh gen --hwip accel      # 특정 HWIP 타입만
./scripts/dev.sh gen --check           # Dry-run: 생성 파일이 최신인지 확인 (CI용)
```

**출력 위치:**
- HWIP 아티팩트: `hwip/<type>/gen/`

---

#### `build` — 레이어 빌드

모든 레이어를 빌드하고 결과 테이블을 출력합니다. 로그는 `build/logs/`에 저장됩니다.

```bash
./scripts/dev.sh build                         # 모든 레이어 빌드
./scripts/dev.sh build --skip l2/firmware,l2/kernel  # 느린 레이어 제외
./scripts/dev.sh build --layers l4/server
```

빌드 순서 (의존성 우선): `l3/hw-model` → `l2/kernel` → `l3/userlib` → `l3/appframework` → `l2/firmware` → `l4/server` → `l6/sdk`

---

#### `test` — 풀스택 시뮬레이션 테스트

시뮬레이션 모드로 전체 스택을 시작하고 SDK hello-world 테스트를 실행합니다.

```bash
./scripts/dev.sh test            # 빌드 + 전체 시뮬레이션 실행
./scripts/dev.sh test --no-build # 기존 바이너리 사용 (빌드 건너뜀)
./scripts/dev.sh test --hwip     # HWIP 통합 테스트로 라우팅 (hwip.sh test)
```

시작 순서: `hw-model` → `firmware_sim` → `Zephyr` (존재 시) → `accel-server` → SDK hello-world

환경 변수로 오버라이드:
- `SERVER_ADDR` — 서버 주소 (기본: `:8080`)
- `HW_MODEL_SHM` — POSIX shm 이름 (기본: `deepspan-sim`)

---

#### `validate` — HWIP 아티팩트 검증

생성된 HWIP 아티팩트에 대해 검사를 수행합니다 (`hwip.sh validate`로 위임).

```bash
./scripts/dev.sh validate               # 모든 HWIP 검증
./scripts/dev.sh validate --hwip accel  # 단일 HWIP
./scripts/dev.sh validate --fix         # stale 코드젠 자동 수정
./scripts/dev.sh validate --skip-syntax # C/C++ 문법 검사 건너뜀
```

---

#### `check` — 전체 CI 게이트

```bash
./scripts/dev.sh check                     # build → test → validate
./scripts/dev.sh check --skip l2/firmware  # 느린 레이어 제외
```

CI에서 사용하는 단일 진입점입니다. 모든 단계가 성공해야 exit 0을 반환합니다.

---

## hwip.sh — HWIP 개발 CLI

```
./hwip/scripts/hwip.sh <command> [options]
```

### 라이프사이클 순서

```
setup → gen → build → validate → test
                              ↗
                        check (전체 CI 게이트)
```

### 명령어 상세

#### `setup` — HWIP 개발 환경 설정

```bash
./hwip/scripts/hwip.sh setup                 # deepspan-codegen 설치 + 코드젠 실행
./hwip/scripts/hwip.sh setup --skip-codegen  # 툴 설치만, 코드젠 건너뜀
```

`deepspan-codegen`을 `uv sync`로 설치합니다.

---

#### `gen` — HWIP 코드 생성

```bash
./hwip/scripts/hwip.sh gen                   # 모든 HWIP
./hwip/scripts/hwip.sh gen --hwip accel      # 특정 HWIP만
./hwip/scripts/hwip.sh gen --check           # Dry-run: 스테일 여부 확인
```

---

#### `build` — C++ 빌드

```bash
./hwip/scripts/hwip.sh build
```

빌드 대상: `deepspan-hw-model`, `deepspan-server`, `accel-plugin` (→ `build/bin/`)

---

#### `validate` — 아티팩트 검증

| # | 검사 | 도구 |
|---|------|------|
| 1 | Codegen stale check | `deepspan-codegen --dry-run` (diff) |
| 2 | C kernel header 문법 | `gcc -fsyntax-only` |
| 3 | C++ hw_model header 문법 | `g++ -fsyntax-only -std=c++17` |
| 4 | Python 문법 | `python3 -m py_compile` |
| 5 | Proto lint | `buf lint` |
| 6 | codegen 단위 테스트 | `pytest codegen/tests/ -q` |

```bash
./hwip/scripts/hwip.sh validate                  # 모든 HWIP
./hwip/scripts/hwip.sh validate --hwip accel     # 단일 HWIP
./hwip/scripts/hwip.sh validate --fix            # 자동 수정 가능 항목 수정
./hwip/scripts/hwip.sh validate --skip-syntax    # C/C++ 문법 검사 건너뜀
```

---

#### `test` — 통합 테스트

```bash
./hwip/scripts/hwip.sh test                      # hw-model + server + SDK E2E
./hwip/scripts/hwip.sh test --stub               # stub 모드 (하드웨어 불필요)
```

---

#### `check` — 전체 HWIP CI 게이트

```bash
./hwip/scripts/hwip.sh check   # build → validate → test (stub 모드)
```

---

## 빠른 참조

```bash
# 신규 개발자 온보딩
uv sync
./scripts/dev.sh setup --hooks

# 코드 수정 후 검증
./scripts/dev.sh gen --check          # 생성 파일 최신 여부
./scripts/dev.sh build --skip l2/firmware,l2/kernel

# 풀스택 테스트
./scripts/dev.sh test

# CI (전체 게이트)
./scripts/dev.sh check

# HWIP 개발
./hwip/scripts/hwip.sh setup
./hwip/scripts/hwip.sh gen
./hwip/scripts/hwip.sh validate --fix
./hwip/scripts/hwip.sh test --stub
./hwip/scripts/hwip.sh check
```
