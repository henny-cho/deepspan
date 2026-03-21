# deepspan Stable API Reference

This document defines the stability guarantees for deepspan interfaces, organized
into three tiers. HWIP plugin authors should only depend on **Tier 1** interfaces.

---

## Tier 1 — Stable (SemVer-protected, no breaking changes without major version bump)

### C++ plugin interface (`deepspan::server`)

HWIP 플러그인이 구현해야 하는 핵심 인터페이스.
헤더 경로: `server/include/deepspan/server/`

| Symbol | Header | Notes |
|---|---|---|
| `Submitter` | `deepspan/server/submitter.hpp` | 플러그인이 상속받는 순수 가상 기반 클래스 |
| `Submitter::submit()` | same | `(uint32_t opcode, vector<uint8_t> data) → SubmitResult` |
| `Submitter::device_state()` | same | proto `DeviceState` 정수 반환 |
| `Submitter::device_id()` | same | 담당 device_id 반환 |
| `SubmitResult` | `deepspan/server/submitter.hpp` | `request_id`, `response_data` |
| `DeviceInfo` | `deepspan/server/submitter.hpp` | `device_id`, `state` |
| `SubmitterFactory` | `deepspan/server/registry.hpp` | `std::function<unique_ptr<Submitter>(string_view)>` |
| `HwipRegistry::instance()` | `deepspan/server/registry.hpp` | 싱글톤 접근 |
| `HwipRegistry::register_type()` | same | 플러그인 `.so` dlopen 시 자동 호출 |
| `HwipRegistry::unregister_type()` | same | dlclose 시 Registrar 소멸자에서 호출 |

### CMake targets (`find_package(DeepspanPlatform)`)

| Target | Header | Notes |
|---|---|---|
| `Deepspan::deepspan-appframework` | `deepspan/appframework/session_manager.hpp` | 세션 관리, DevicePool, CircuitBreaker |
| `Deepspan::deepspan-userlib` | `deepspan/userlib/device.hpp` | C++20 `DeepspanDevice` RAII 핸들, io_uring 클라이언트 |

### CMake functions (`include(DeepspanHwip)`)

| Function | Notes |
|---|---|
| `deepspan_hwip_plugin()` | HWIP 플러그인 SHARED 라이브러리 타겟 생성 (`NAME`, `HWIP_TYPE`, `SOURCES` 필수) |
| `deepspan_hwip_codegen()` | `hwip.yaml` → 6개 타겟 코드 생성 커스텀 타겟 추가 (`HWIP_TYPE`, `DESCRIPTOR`, `OUT_DIR`) |
| `deepspan_hwip_target()` | `deepspan_hwip_plugin()` 의 하위 호환 alias |

### Protobuf / gRPC

proto 파일 경로: `api/proto/deepspan/v1/`

#### `HwipService` (`device.proto`)

| RPC / Message | Notes |
|---|---|
| `rpc ListDevices` | 등록된 모든 HWIP 디바이스 목록 반환 |
| `rpc GetDeviceStatus` | 단일 디바이스 상태 조회 |
| `rpc SubmitRequest` | HWIP 커맨드 제출 (동기) |
| `rpc StreamEvents` | 서버 사이드 스트리밍 이벤트 구독 |
| `DeviceInfo` | `device_id`, `device_path`, `state`, `uapi_version`, `fw_version` |
| `DeviceState` | 열거형: `INITIALIZING=1`, `READY=2`, `RUNNING=3`, `ERROR=4`, `RESETTING=5` |
| `SubmitRequestRequest` | `device_id`, `opcode`, `payload`, `timeout_ms`, `flags` |
| `SubmitRequestResponse` | `request_id`, `status`, `result`, `latency` |
| `DeviceEvent` | `device_id`, `event_type`, `data`, `timestamp`, `severity` |
| `EventType` | `STATE_CHANGE=1`, `ERROR=2`, `TELEMETRY=3`, `FW_LOG=4` |

#### `ManagementService` (`management.proto`)

| RPC / Message | Notes |
|---|---|
| `rpc GetFirmwareInfo` | 펌웨어 버전/기능 조회 |
| `rpc ResetDevice` | 펌웨어 리셋 (`force=true` = 즉시 강제) |
| `rpc PushConfig` | 런타임 설정 Zephyr 전송 (rpmsg-config 채널) |
| `rpc GetConsolePath` | OpenAMP proxy PTY 경로 반환 (`/dev/pts/N`) |

#### `TelemetryService` (`telemetry.proto`)

| RPC / Message | Notes |
|---|---|
| `rpc GetTelemetry` | 텔레메트리 스냅샷 단발 조회 |
| `rpc StreamTelemetry` | 실시간 텔레메트리 스트리밍 (`interval_ms`) |
| `TelemetrySnapshot` | `firmware` (cpu/heap/uptime), `kernel` (irq/dma/vq) |

### Linux UAPI

| Header | Symbol | Notes |
|---|---|---|
| `linux/deepspan.h` | `struct deepspan_req` | `opcode`, `flags`, `data_ptr`, `data_len`, `timeout_ms` |
| `linux/deepspan.h` | `struct deepspan_result` | `status`, `result_lo`, `result_hi` |
| `linux/deepspan.h` | `DEEPSPAN_IOC_GET_VERSION` | UAPI 버전 조회 ioctl |
| `linux/deepspan.h` | `DEEPSPAN_IOC_SUBMIT` | 동기 요청 제출 ioctl (io_uring 미사용 시 fallback) |
| `linux/deepspan.h` | `DEEPSPAN_UAPI_VERSION` | 현재 버전: `1` |
| `linux/deepspan_accel.h` | `DEEPSPAN_ACCEL_OP_*` | accel HWIP 전용 opcode 상수 (codegen 생성본의 진실 원천) |

### Python SDK

| Symbol | Module | Notes |
|---|---|---|
| `DeepspanClient` | `deepspan.client` | gRPC 채널 관리, context manager (`with` 지원) |
| `DeepspanClient.list_devices()` | same | `→ list[DeviceInfo]` |
| `DeepspanClient.get_device_status()` | same | `(device_id) → DeviceInfo` |
| `DeepspanClient.submit_request()` | same | `(device_id, opcode, data=b"") → bytes` |
| `DeepspanClient.get_firmware_info()` | same | `(device_id) → FirmwareInfo` |
| `DeepspanClient.reset_device()` | same | `(device_id, force=False) → bool` |
| `DeepspanClient.push_config()` | same | `(device_id, config: dict) → list[str]` (거부된 키) |
| `DeepspanClient.get_console_path()` | same | `(device_id) → str` PTY 경로 |
| `DeepspanClient.get_telemetry()` | same | `(device_id) → TelemetrySnapshot` |
| `DeepspanClient.register_extension()` | same | HWIP 확장 객체 등록 |
| `HwipExtension` | `deepspan.client` | `Protocol` — HWIP 확장 타입 프로토콜 (`hwip_type`, `attach()`) |
| `DeviceInfo` | `deepspan.models` | `device_id`, `state: DeviceState` |
| `DeviceState` | `deepspan.models` | `IntEnum`: `INITIALIZING=1` … `RESETTING=5` |
| `FirmwareInfo` | `deepspan.models` | `fw_version`, `build_date`, `protocol_version`, `features` |
| `TelemetrySnapshot` | `deepspan.models` | `device_id`, `uptime_ms`, `irq_count` |

---

## Tier 2 — Deprecated (will emit warnings before removal)

| Symbol | Tier 1 replacement | Removal milestone |
|---|---|---|
| `deepspan_hwip_target()` (CMake) | `deepspan_hwip_plugin()` | v2.0.0 |

---

## Tier 3 — Internal (no stability guarantee)

Anything under these paths may change or disappear without notice:

- `server/src/` — gRPC 서버 구현 내부
- `firmware/lib/` — Zephyr 펌웨어 라이브러리 내부
- `sim/hw-model/` — 시뮬레이터 내부
- `runtime/appframework/src/`, `runtime/userlib/src/` — 런타임 구현 내부
- `hwip/*/gen/` — codegen 생성 파일 (hwip.yaml 변경 시 자동 재생성)
- `codegen/gen/` — codegen 테스트 픽스처
- `sdk/src/deepspan/_proto/` — 내부 gRPC 스텁 (사용자 직접 임포트 금지)

---

## Versioning policy

deepspan follows [Semantic Versioning 2.0.0](https://semver.org/).

- **Patch** releases (0.x.**y**): bug fixes only, no API changes.
- **Minor** releases (0.**x**.0): new Tier 1 symbols added; existing symbols unchanged.
- **Major** releases (**x**.0.0): breaking changes allowed; Tier 2 symbols removed.

HWIP plugins should pin `deepspan` to a **minor** version range:
```
# west.yml
revision: v0.3.0   # SHA or tag — never branch: main
```

---

*최종 업데이트: 2026-03-21 — Go/ConnectRPC → C++ gRPC 전환 반영*
