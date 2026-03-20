// SPDX-License-Identifier: Apache-2.0
// mgmt_service.cpp — ManagementService: sim path reads SHM stats directly.
//
// Sim path: opens /deepspan_hwip_<N> shared memory and drives control
// registers or reads stats.  HW path (OpenAMP RPMsg) is reserved for
// a future integration pass.
#include "mgmt_service.hpp"

#include <spdlog/spdlog.h>
#include <charconv>
#include <cstring>
#include <ctime>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

namespace deepspan::server {

namespace {

// SHM layout constants — must stay in sync with sim/hw-model/include/deepspan/hw_model/reg_map.hpp
constexpr size_t   kShmTotalSize   = 4096u;
constexpr uint32_t kRegVersion     = 0x010u;  ///< HW version (read-only)
constexpr uint32_t kRegCtrl        = 0x000u;  ///< Control register
constexpr uint32_t kCtrlResetBit   = (1u << 0); ///< Soft reset bit
constexpr size_t   kShmStatsOffset = 0x200u;   ///< ShmStats area start

struct ShmStatsView {
    volatile uint64_t cmd_count;
    volatile uint64_t start_time_sec;
    volatile uint32_t last_opcode;
    volatile uint32_t last_result_status;
    volatile uint64_t fw_cmd_count;
};

/// Parse device index from e.g. "accel/0" → 0, returns -1 on error.
int parse_device_index(std::string_view device_id) {
    auto slash = device_id.rfind('/');
    if (slash == std::string_view::npos) return -1;
    auto sub = device_id.substr(slash + 1);
    int idx = -1;
    auto [ptr, ec] = std::from_chars(sub.data(), sub.data() + sub.size(), idx);
    return (ec == std::errc{}) ? idx : -1;
}

/// RAII helper: opens, mmaps and unmaps the device SHM for the sim path.
struct ShmView {
    void* base{nullptr};
    int   fd{-1};

    explicit ShmView(int device_index) {
        std::string name = "/deepspan_hwip_" + std::to_string(device_index);
        fd = shm_open(name.c_str(), O_RDWR, 0);
        if (fd < 0) return;
        base = mmap(nullptr, kShmTotalSize,
                    PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        if (base == MAP_FAILED) {
            base = nullptr;
            close(fd);
            fd = -1;
        }
    }

    ~ShmView() {
        if (base && base != MAP_FAILED) munmap(base, kShmTotalSize);
        if (fd >= 0) close(fd);
    }

    bool ok() const { return base != nullptr; }

    const ShmStatsView* stats() const {
        return reinterpret_cast<const ShmStatsView*>(
            static_cast<const char*>(base) + kShmStatsOffset);
    }

    volatile uint32_t* reg(uint32_t off) const {
        return reinterpret_cast<volatile uint32_t*>(
            static_cast<char*>(base) + off);
    }

    ShmView(const ShmView&)            = delete;
    ShmView& operator=(const ShmView&) = delete;
};

}  // namespace

MgmtServiceImpl::MgmtServiceImpl() {
    spdlog::info("MgmtServiceImpl: initialised (sim transport — SHM stats)");
}

MgmtServiceImpl::~MgmtServiceImpl() {
    spdlog::info("MgmtServiceImpl: shutting down");
}

grpc::Status MgmtServiceImpl::GetFirmwareInfo(
    grpc::ServerContext* /*ctx*/,
    const deepspan::v1::GetFirmwareInfoRequest* req,
    deepspan::v1::GetFirmwareInfoResponse* resp) {
    spdlog::debug("GetFirmwareInfo: device_id={}", req->device_id());

    int idx = parse_device_index(req->device_id());
    ShmView shm(idx);

    if (!shm.ok()) {
        // hw-model not running — return stub values.
        resp->set_fw_version("0.0.0-stub");
        resp->set_build_date("1970-01-01");
        resp->set_protocol_version(1);
        return grpc::Status::OK;
    }

    // Read HW version register: 0x00010000 → "1.0.0-sim"
    uint32_t hw_ver = __atomic_load_n(shm.reg(kRegVersion), __ATOMIC_ACQUIRE);
    uint32_t major  = (hw_ver >> 16) & 0xFFu;
    uint32_t minor  = (hw_ver >>  8) & 0xFFu;
    uint32_t patch  =  hw_ver        & 0xFFu;
    resp->set_fw_version(std::to_string(major) + "." +
                         std::to_string(minor) + "." +
                         std::to_string(patch) + "-sim");

    // Derive build date from hw-model start_time_sec.
    uint64_t start_sec = __atomic_load_n(&shm.stats()->start_time_sec,
                                         __ATOMIC_ACQUIRE);
    if (start_sec > 0) {
        std::time_t t = static_cast<std::time_t>(start_sec);
        char buf[16];
        std::strftime(buf, sizeof(buf), "%Y-%m-%d", std::gmtime(&t));
        resp->set_build_date(buf);
    } else {
        resp->set_build_date("1970-01-01");
    }
    resp->set_protocol_version(1);
    return grpc::Status::OK;
}

grpc::Status MgmtServiceImpl::ResetDevice(
    grpc::ServerContext* /*ctx*/,
    const deepspan::v1::ResetDeviceRequest* req,
    deepspan::v1::ResetDeviceResponse* resp) {
    spdlog::info("ResetDevice: device_id={} force={}",
                 req->device_id(), req->force());

    int idx = parse_device_index(req->device_id());
    ShmView shm(idx);

    if (!shm.ok()) {
        resp->set_success(false);
        resp->set_message("hw-model SHM not available");
        return grpc::Status::OK;
    }

    // Set CTRL.RESET bit — hw-model will acknowledge and clear it.
    __atomic_or_fetch(shm.reg(kRegCtrl), kCtrlResetBit, __ATOMIC_RELEASE);
    resp->set_success(true);
    return grpc::Status::OK;
}

grpc::Status MgmtServiceImpl::PushConfig(
    grpc::ServerContext* /*ctx*/,
    const deepspan::v1::PushConfigRequest* req,
    deepspan::v1::PushConfigResponse* resp) {
    spdlog::info("PushConfig: device_id={} keys={}",
                 req->device_id(), req->config_size());
    resp->set_success(true);
    return grpc::Status::OK;
}

grpc::Status MgmtServiceImpl::GetConsolePath(
    grpc::ServerContext* /*ctx*/,
    const deepspan::v1::GetConsolePathRequest* req,
    deepspan::v1::GetConsolePathResponse* resp) {
    spdlog::debug("GetConsolePath: device_id={}", req->device_id());
    // Sim path: no real console PTY.
    resp->set_pty_path("/dev/null");
    return grpc::Status::OK;
}

}  // namespace deepspan::server
