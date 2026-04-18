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
setup → gen → build → lint → test → validate
                                   ↗
                             check (전체 CI 게이트)
```

### 명령어 상세

#### `setup` — 툴체인 설치 및 환경 검증

```bash
./scripts/dev.sh setup                                # 모든 레이어 설치 + 검증
./scripts/dev.sh setup --skip firmware                # 느린 Zephyr SDK 다운로드 건너뜀
./scripts/dev.sh setup --layers server,sdk            # 특정 레이어만
./scripts/dev.sh setup --hooks                        # git pre-commit 훅 설치 포함
./scripts/dev.sh setup --lint-tools                   # clang-tidy 설치 포함
./scripts/dev.sh setup --verify-only                  # 설치 없이 검증만
```

| 옵션 | 설명 |
|-----|-----|
| `--layers L1,L2` | 콤마 구분 레이어 목록으로 범위 한정 |
| `--skip L1` | 특정 레이어 건너뜀 (firmware는 Zephyr SDK 다운로드가 오래 걸림) |
| `--hooks` | `.githooks/`를 git hooks 경로로 설정 |
| `--lint-tools` | `clang-tidy` 추가 설치 |
| `--verify-only` | 설치 단계 없이 현재 환경 검증만 수행 |

**사용 가능한 레이어** (`scripts/dev.sh` `ALL_LAYERS` 참조):
`sim/hw-model`, `firmware`, `kernel`, `runtime/userlib`, `runtime/appframework`, `sdk`

> `server`는 별도 레이어 setup 스크립트를 두지 않고, 공통 C++ 빌드 의존성(apt) 단계에서 다뤄집니다.

---

#### `gen` — 코드 생성

hwip.yaml로부터 HWIP 레이어 아티팩트를, `api/proto/`로부터 Python gRPC 스텁을 생성합니다.

```bash
./scripts/dev.sh gen                     # 모든 HWIP 코드젠 + Python 프로토 스텁
./scripts/dev.sh gen --hwip accel        # 특정 HWIP 타입만
./scripts/dev.sh gen --skip-hwip         # HWIP 코드젠 단계 건너뜀
./scripts/dev.sh gen --check             # Dry-run: 생성 파일이 최신인지 확인 (CI용)
```

**출력 위치**:
- HWIP 아티팩트: `hwip/<type>/gen/{kernel,firmware,sim,rpc,proto,sdk}/`
- Python gRPC 스텁: `sdk/src/deepspan/_proto/`

---

#### `build` — CMake 빌드

CMake 프리셋 기반 단일 커맨드. `build/<preset>/` 아래에 구성/빌드합니다. `ccache`가 PATH에 있으면 자동 사용됩니다.

```bash
./scripts/dev.sh build                           # dev-hwip 프리셋 (기본)
./scripts/dev.sh build --preset dev              # HWIP 없는 빠른 빌드
./scripts/dev.sh build --preset dev-crc32        # CRC32 HWIP만
./scripts/dev.sh build --preset release          # 릴리스 (tests OFF)
./scripts/dev.sh build --preset asan-ubsan       # ASan + UBSan
./scripts/dev.sh build --clean                   # 빌드 디렉토리 삭제 후 재빌드

./scripts/dev.sh build clean                     # 현재 프리셋 빌드 디렉토리 삭제
./scripts/dev.sh build clean --preset dev-hwip   # 특정 프리셋 삭제
./scripts/dev.sh build clean --all               # 모든 build/* 삭제
```

프리셋은 `CMakePresets.json` 참조: `dev`, `dev-submodule`, `sim`, `release`, `coverage`, `dev-hwip`, `dev-multi-hwip`, `dev-crc32`, `asan-ubsan`, `arm64-cross`.

**기본 preset 오버라이드**: `DEEPSPAN_DEFAULT_PRESET=dev` 환경 변수로 모든 서브커맨드의 기본값을 일괄 변경할 수 있습니다.

---

#### `lint` — C++ 정적 분석

```bash
./scripts/dev.sh lint                    # 경고만 출력 (exit 0)
./scripts/dev.sh lint --strict           # 경고 시 exit 1
./scripts/dev.sh lint --preset dev-hwip  # 특정 프리셋의 compile_commands.json 사용
```

사전 조건: `clang-tidy` 설치 (`dev.sh setup --lint-tools`) + 해당 프리셋으로 빌드 완료.

---

#### `test` — 풀스택 시뮬레이션 테스트

시뮬레이션 모드로 전체 스택을 시작하고 SDK E2E 테스트를 실행합니다.

```bash
./scripts/dev.sh test                    # 기본 preset 빌드 + 시뮬레이션 실행
./scripts/dev.sh test --no-build         # 기존 바이너리 사용 (빌드 건너뜀)
./scripts/dev.sh test --preset dev-crc32 # CRC32 HWIP로 전환 (crc32_test.py 실행)
```

시작 순서: `hw-model` → `Zephyr firmware_sim` (존재 시) → `deepspan-server` (HWIP 플러그인 로드) → SDK E2E 스크립트.

환경 변수:
- `SERVER_ADDR` — gRPC listen 주소 (기본: `0.0.0.0:8080`)

프리셋별 자동 선택:
- `dev-crc32` → `sdk/examples/crc32_test.py`, 디바이스 `crc32/0`
- 그 외 → `sdk/examples/hello.py`, 디바이스 `accel/0`

테스트 성공 후 서비스는 계속 실행되며, `Ctrl-C`로 종료할 때까지 대기합니다.

---

#### `validate` — HWIP 아티팩트 검증

생성된 HWIP 아티팩트에 대해 5단계 검사를 수행합니다 (`hwip.sh validate`로 위임).

```bash
./scripts/dev.sh validate                # 모든 HWIP 검증
./scripts/dev.sh validate --hwip accel   # 단일 HWIP
./scripts/dev.sh validate --fix          # stale 코드젠 자동 수정
./scripts/dev.sh validate --skip-syntax  # C/C++ 문법 검사 건너뜀
```

---

#### `check` — 전체 CI 게이트

```bash
./scripts/dev.sh check                       # 기본 (dev 프리셋)
./scripts/dev.sh check --preset dev-hwip     # HWIP 포함
```

순서: `build` → `ctest` → `validate`. 모든 단계 성공 시 exit 0.

---

## hwip.sh — HWIP 개발 CLI

```
./hwip/scripts/hwip.sh <command> [options]
```

### 라이프사이클 순서

```
setup → gen → build → validate → test
                              ↗
                        check (전체 HWIP CI 게이트)
```

### 명령어 상세

#### `setup` — HWIP 개발 환경 설정

```bash
./hwip/scripts/hwip.sh setup                 # deepspan-codegen 설치 + 모든 HWIP 코드젠
./hwip/scripts/hwip.sh setup --skip-codegen  # 툴 설치만, 코드젠 건너뜀
```

`deepspan-codegen`을 `uv tool install` 또는 `pip install`로 설치합니다. `gcc`, `g++`, `cmake`, `python3`는 사전 설치 필요.

---

#### `gen` — HWIP 코드 생성

```bash
./hwip/scripts/hwip.sh gen                   # 모든 HWIP
./hwip/scripts/hwip.sh gen --hwip accel      # 특정 HWIP만
./hwip/scripts/hwip.sh gen --all-hwip        # 모든 HWIP 명시적 지정
./hwip/scripts/hwip.sh gen --check           # Dry-run: 스테일 여부 확인
```

---

#### `build` — CMake 빌드

```bash
./hwip/scripts/hwip.sh build                           # dev-hwip 프리셋 전체
./hwip/scripts/hwip.sh build --preset dev-crc32        # 특정 프리셋
./hwip/scripts/hwip.sh build --target hwip_accel       # 특정 타겟만
```

---

#### `validate` — 아티팩트 검증

| # | 검사 | 도구 |
|---|------|------|
| 1 | Codegen stale check | `deepspan-codegen` + `diff` |
| 2 | C kernel header 문법 | `gcc -fsyntax-only -std=gnu11` |
| 3 | C++20 gen/sim + gen/rpc 헤더 문법 | `g++ -fsyntax-only -std=c++20` |
| 4 | Python 문법 | `python3 -m py_compile` |
| 5 | Proto lint | `buf lint` (설치 시) |

```bash
./hwip/scripts/hwip.sh validate                  # 모든 HWIP
./hwip/scripts/hwip.sh validate --hwip accel     # 단일 HWIP
./hwip/scripts/hwip.sh validate --fix            # 스테일 코드젠 자동 재생성
./hwip/scripts/hwip.sh validate --skip-syntax    # C/C++ 문법 검사 건너뜀
```

---

#### `demo` — Python 멀티 HWIP 데모

```bash
./hwip/scripts/hwip.sh demo                      # localhost:8080
./hwip/scripts/hwip.sh demo --addr host:9090     # 커스텀 주소
```

`deepspan-server`가 별도로 실행 중이어야 합니다.

---

#### `test` — 통합 테스트

```bash
./hwip/scripts/hwip.sh test                      # ctest + Python 스모크 테스트
./hwip/scripts/hwip.sh test --preset dev-hwip    # 특정 프리셋
./hwip/scripts/hwip.sh test --port 9090          # 서버 포트 오버라이드
```

---

#### `check` — 전체 HWIP CI 게이트

```bash
./hwip/scripts/hwip.sh check                     # build → validate → lint → test
./hwip/scripts/hwip.sh check --preset dev-crc32  # 특정 프리셋
```

---

## 빠른 참조

```bash
# 신규 개발자 온보딩
./scripts/dev.sh setup --hooks --lint-tools

# 코드 수정 후 검증
./scripts/dev.sh gen --check              # 생성 파일 최신 여부
./scripts/dev.sh build --preset dev       # 빠른 빌드 (HWIP/firmware 제외)
./scripts/dev.sh lint --strict

# 풀스택 테스트
./scripts/dev.sh test                     # 기본 (accel HWIP)
./scripts/dev.sh test --preset dev-crc32  # CRC32 HWIP

# CI (전체 게이트)
./scripts/dev.sh check --preset dev-hwip

# HWIP 개발
./hwip/scripts/hwip.sh setup
./hwip/scripts/hwip.sh gen
./hwip/scripts/hwip.sh validate --fix
./hwip/scripts/hwip.sh check
```
