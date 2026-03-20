// SPDX-License-Identifier: Apache-2.0
// telemetry_service.cpp — TelemetryService: sim path reads SHM stats directly.
#include "telemetry_service.hpp"

#include <spdlog/spdlog.h>
#include <charconv>
#include <ctime>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

namespace deepspan::server {

namespace {

// SHM layout constants — must stay in sync with sim/hw-model/include/deepspan/hw_model/reg_map.hpp
constexpr size_t kShmTotalSize   = 4096u;
constexpr size_t kShmStatsOffset = 0x200u;

struct ShmStatsView {
    volatile uint64_t cmd_count;
    volatile uint64_t start_time_sec;
    volatile uint32_t last_opcode;
    volatile uint32_t last_result_status;
    volatile uint64_t fw_cmd_count;
};

int parse_device_index(std::string_view device_id) {
    auto slash = device_id.rfind('/');
    if (slash == std::string_view::npos) return -1;
    auto sub = device_id.substr(slash + 1);
    int idx = -1;
    auto [ptr, ec] = std::from_chars(sub.data(), sub.data() + sub.size(), idx);
    return (ec == std::errc{}) ? idx : -1;
}

}  // namespace

grpc::Status TelemetryServiceImpl::GetTelemetry(
    grpc::ServerContext* /*ctx*/,
    const deepspan::v1::GetTelemetryRequest* req,
    deepspan::v1::GetTelemetryResponse* resp) {
    spdlog::debug("GetTelemetry: device_id={}", req->device_id());

    auto* snap = resp->mutable_snapshot();
    snap->set_device_id(req->device_id());

    // Populate timestamp with current wall-clock time.
    {
        auto now_sec = static_cast<int64_t>(std::time(nullptr));
        snap->mutable_timestamp()->set_seconds(now_sec);
        snap->mutable_timestamp()->set_nanos(0);
    }

    int idx = parse_device_index(req->device_id());
    std::string shm_name = "/deepspan_hwip_" + std::to_string(idx);

    int fd = (idx >= 0) ? shm_open(shm_name.c_str(), O_RDONLY, 0) : -1;
    if (fd < 0) {
        // hw-model not running — return zero-filled metrics.
        return grpc::Status::OK;
    }

    void* base = mmap(nullptr, kShmTotalSize, PROT_READ, MAP_SHARED, fd, 0);
    close(fd);
    if (base == MAP_FAILED) {
        return grpc::Status::OK;
    }

    const auto* stats = reinterpret_cast<const ShmStatsView*>(
        static_cast<const char*>(base) + kShmStatsOffset);

    uint64_t cmd_count    = __atomic_load_n(&stats->cmd_count,       __ATOMIC_ACQUIRE);
    uint64_t start_sec    = __atomic_load_n(&stats->start_time_sec,  __ATOMIC_ACQUIRE);
    uint64_t fw_cmd_count = __atomic_load_n(&stats->fw_cmd_count,    __ATOMIC_ACQUIRE);

    uint64_t now_sec   = static_cast<uint64_t>(std::time(nullptr));
    uint64_t uptime_ms = (start_sec > 0 && now_sec >= start_sec)
                         ? (now_sec - start_sec) * 1000u
                         : 0u;

    // FirmwareTelemetry: uptime derived from SHM start_time_sec.
    auto* fw = snap->mutable_firmware();
    fw->set_uptime_ms(static_cast<uint32_t>(
        uptime_ms > UINT32_MAX ? UINT32_MAX : uptime_ms));

    // KernelTelemetry: use hw-model cmd_count as irq_count proxy,
    // fw_cmd_count as a pending-cmd indicator.
    auto* kern = snap->mutable_kernel();
    kern->set_irq_count(cmd_count);
    kern->set_pending_cmds(static_cast<uint32_t>(fw_cmd_count & UINT32_MAX));

    munmap(base, kShmTotalSize);
    return grpc::Status::OK;
}

}  // namespace deepspan::server
