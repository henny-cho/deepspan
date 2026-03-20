// SPDX-License-Identifier: Apache-2.0
#include "accel_plugin.hpp"

#include <spdlog/spdlog.h>
#include <stdexcept>
#include <charconv>
#include <cstring>
#include <mutex>

#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <deepspan_accel/ops.hpp>

namespace deepspan::hwip::accel {

namespace {
/// Parse device index from "accel/<N>" → N.  Returns -1 on error.
int parse_index(std::string_view device_id) {
    auto slash = device_id.rfind('/');
    if (slash == std::string_view::npos) return -1;
    auto idx_str = device_id.substr(slash + 1);
    int idx = -1;
    auto [ptr, ec] = std::from_chars(idx_str.data(),
                                     idx_str.data() + idx_str.size(), idx);
    return (ec == std::errc{}) ? idx : -1;
}
}  // namespace

AccelPlugin::AccelPlugin(std::string_view device_id)
    : device_id_{device_id},
      device_index_{parse_index(device_id)} {
    if (device_index_ < 0) {
        throw std::invalid_argument{"AccelPlugin: bad device_id: " +
                                    std::string{device_id}};
    }

    // Open shared-memory segment created by the hw-model for this device index.
    std::string shm_name = "/deepspan_hwip_" + std::to_string(device_index_);

    // Single attempt — no retry.  The hw-model must already be running when
    // the plugin is first used for enumeration.  Non-existent SHM signals
    // "no device at this index" to the registry (device_state returns -1).
    shm_fd_ = shm_open(shm_name.c_str(), O_RDWR, 0);
    if (shm_fd_ < 0) {
        // Leave shm_base_ = nullptr; device_state() will return -1 to stop
        // enumeration at this index.
        spdlog::debug("AccelPlugin: shm {} not found (no device at index {})",
                      shm_name, device_index_);
        return;  // benign — not an error for enumeration
    }

    shm_base_ = mmap(nullptr, kShmSize,
                     PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd_, 0);
    if (shm_base_ == MAP_FAILED) {
        close(shm_fd_);
        shm_fd_   = -1;
        shm_base_ = nullptr;
        throw std::runtime_error{"AccelPlugin: mmap failed for " + shm_name};
    }

    spdlog::debug("AccelPlugin: connected to {} for {}", shm_name, device_id_);
}

AccelPlugin::~AccelPlugin() {
    if (shm_base_ && shm_base_ != MAP_FAILED) {
        munmap(shm_base_, kShmSize);
        shm_base_ = nullptr;
    }
    if (shm_fd_ >= 0) {
        close(shm_fd_);
        shm_fd_ = -1;
    }
    spdlog::debug("AccelPlugin: destroyed for {}", device_id_);
}

deepspan::server::SubmitResult
AccelPlugin::submit(uint32_t opcode, std::vector<uint8_t> data) {
    spdlog::debug("AccelPlugin::submit opcode=0x{:04X} data_len={} dev={}",
                  opcode, data.size(), device_id_);

    if (!shm_base_) {
        throw std::runtime_error{"AccelPlugin: SHM not mapped for " + device_id_};
    }

    std::lock_guard lock{submit_mutex_};

    auto* base = static_cast<char*>(shm_base_);
    auto* ctrl_reg    = reinterpret_cast<uint32_t*>(base + deepspan::accel::RegOffsets::CTRL);
    auto* opcode_reg  = reinterpret_cast<uint32_t*>(base + deepspan::accel::RegOffsets::CMD_OPCODE);
    auto* arg0_reg    = reinterpret_cast<uint32_t*>(base + deepspan::accel::RegOffsets::CMD_ARG0);
    auto* arg1_reg    = reinterpret_cast<uint32_t*>(base + deepspan::accel::RegOffsets::CMD_ARG1);
    auto* result0_reg = reinterpret_cast<uint32_t*>(base + deepspan::accel::RegOffsets::RESULT_DATA0);
    auto* result1_reg = reinterpret_cast<uint32_t*>(base + deepspan::accel::RegOffsets::RESULT_DATA1);

    // Extract arg0/arg1 from payload bytes (little-endian uint32 each).
    uint32_t arg0 = 0, arg1 = 0;
    if (data.size() >= 4) std::memcpy(&arg0, data.data(),     4);
    if (data.size() >= 8) std::memcpy(&arg1, data.data() + 4, 4);

    // 1. Write command registers (relaxed — ordering enforced by START release below).
    __atomic_store_n(opcode_reg, opcode, __ATOMIC_RELAXED);
    __atomic_store_n(arg0_reg,   arg0,   __ATOMIC_RELAXED);
    __atomic_store_n(arg1_reg,   arg1,   __ATOMIC_RELAXED);

    // 2. Set CTRL.START with release semantics so the hw-model sees the cmd regs.
    __atomic_or_fetch(ctrl_reg,
                      deepspan::accel::CtrlBits::START,
                      __ATOMIC_RELEASE);

    // 3. Poll until hw-model clears CTRL.START (acquire — makes result regs visible).
    constexpr int kMaxPolls = 50'000;  // 50 000 × 100 µs = 5 s
    bool done = false;
    for (int i = 0; i < kMaxPolls; ++i) {
        uint32_t ctrl = __atomic_load_n(ctrl_reg, __ATOMIC_ACQUIRE);
        if (!(ctrl & deepspan::accel::CtrlBits::START)) {
            done = true;
            break;
        }
        usleep(100);  // 100 µs
    }
    if (!done) {
        throw std::runtime_error{"AccelPlugin: submit timeout for " + device_id_};
    }

    // 4. Read result registers.
    uint32_t r0 = __atomic_load_n(result0_reg, __ATOMIC_ACQUIRE);
    uint32_t r1 = __atomic_load_n(result1_reg, __ATOMIC_ACQUIRE);

    // Pack result into response_data (8 bytes, little-endian).
    deepspan::server::SubmitResult result;
    result.request_id = device_id_ + "-" + std::to_string(opcode);
    result.response_data.resize(8);
    std::memcpy(result.response_data.data(),     &r0, 4);
    std::memcpy(result.response_data.data() + 4, &r1, 4);
    return result;
}

int AccelPlugin::device_state() const {
    if (!shm_base_) return -1;

    // Cast away const for the atomic load — we only read the register.
    auto* base       = static_cast<char*>(shm_base_);
    auto* status_reg = reinterpret_cast<uint32_t*>(
        base + deepspan::accel::RegOffsets::STATUS);
    uint32_t status = __atomic_load_n(status_reg, __ATOMIC_ACQUIRE);
    // Return proto DeviceState values: DEVICE_STATE_READY=2, DEVICE_STATE_INITIALIZING=1
    return (status & deepspan::accel::StatusBits::READY) ? 2 : 1;
}

}  // namespace deepspan::hwip::accel
