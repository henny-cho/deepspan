// SPDX-License-Identifier: Apache-2.0
#include "crc32_plugin.hpp"

#include <spdlog/spdlog.h>

#include <algorithm>
#include <charconv>
#include <cstring>
#include <mutex>
#include <stdexcept>

#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <deepspan_crc32/ops.hpp>

namespace deepspan::hwip::crc32 {

namespace {
/// Parse device index from "crc32/<N>" → N.  Returns -1 on error.
int parse_index(std::string_view device_id) {
    auto slash = device_id.rfind('/');
    if (slash == std::string_view::npos) return -1;
    auto idx_str = device_id.substr(slash + 1);
    int idx = -1;
    auto [ptr, ec] = std::from_chars(
        idx_str.data(), idx_str.data() + idx_str.size(), idx);
    return (ec == std::errc{}) ? idx : -1;
}
}  // namespace

Crc32Plugin::Crc32Plugin(std::string_view device_id)
    : device_id_{device_id}
    , device_index_{parse_index(device_id)}
{
    if (device_index_ < 0) {
        throw std::invalid_argument{
            "Crc32Plugin: bad device_id: " + std::string{device_id}};
    }

    std::string shm_name = "/deepspan_hwip_" + std::to_string(device_index_);

    shm_fd_ = shm_open(shm_name.c_str(), O_RDWR, 0);
    if (shm_fd_ < 0) {
        spdlog::debug("Crc32Plugin: shm {} not found (no device at index {})",
                      shm_name, device_index_);
        return;  // benign — signals "no device" to the registry
    }

    shm_base_ = mmap(nullptr, kShmSize,
                     PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd_, 0);
    if (shm_base_ == MAP_FAILED) {
        close(shm_fd_);
        shm_fd_   = -1;
        shm_base_ = nullptr;
        throw std::runtime_error{
            "Crc32Plugin: mmap failed for " + shm_name};
    }

    spdlog::debug("Crc32Plugin: connected to {} for {}", shm_name, device_id_);
}

Crc32Plugin::~Crc32Plugin() {
    if (shm_base_ && shm_base_ != MAP_FAILED) {
        munmap(shm_base_, kShmSize);
        shm_base_ = nullptr;
    }
    if (shm_fd_ >= 0) {
        close(shm_fd_);
        shm_fd_ = -1;
    }
    spdlog::debug("Crc32Plugin: destroyed for {}", device_id_);
}

deepspan::server::SubmitResult
Crc32Plugin::submit(uint32_t opcode, std::vector<uint8_t> data) {
    spdlog::debug("Crc32Plugin::submit opcode=0x{:04X} data_len={} dev={}",
                  opcode, data.size(), device_id_);

    if (!shm_base_) {
        throw std::runtime_error{
            "Crc32Plugin: SHM not mapped for " + device_id_};
    }

    std::lock_guard lock{submit_mutex_};

    auto* base        = static_cast<char*>(shm_base_);
    auto* ctrl_reg    = reinterpret_cast<uint32_t*>(
        base + deepspan::crc32::RegOffsets::CTRL);
    auto* opcode_reg  = reinterpret_cast<uint32_t*>(
        base + deepspan::crc32::RegOffsets::CMD_OPCODE);
    auto* arg0_reg    = reinterpret_cast<uint32_t*>(
        base + deepspan::crc32::RegOffsets::CMD_ARG0);
    auto* arg1_reg    = reinterpret_cast<uint32_t*>(
        base + deepspan::crc32::RegOffsets::CMD_ARG1);
    auto* result0_reg = reinterpret_cast<uint32_t*>(
        base + deepspan::crc32::RegOffsets::RESULT_DATA0);
    auto* result1_reg = reinterpret_cast<uint32_t*>(
        base + deepspan::crc32::RegOffsets::RESULT_DATA1);

    uint32_t arg0 = 0u, arg1 = 0u;

    using deepspan::crc32::Crc32Op;
    if (static_cast<Crc32Op>(opcode) == Crc32Op::COMPUTE) {
        // dma_bytes encoding: write data to SHM DMA buffer, pass length in arg0.
        uint32_t len = static_cast<uint32_t>(
            std::min(data.size(), static_cast<size_t>(kShmDmaMaxLen)));
        if (len > 0u) {
            std::memcpy(base + kShmDmaOffset, data.data(), len);
        }
        arg0 = len;
        arg1 = 0u;
    } else {
        // fixed_args encoding: extract arg0/arg1 from payload.
        if (data.size() >= 4u) std::memcpy(&arg0, data.data(),     4u);
        if (data.size() >= 8u) std::memcpy(&arg1, data.data() + 4, 4u);
    }

    // 1. Write command registers (relaxed — ordering enforced by START release).
    __atomic_store_n(opcode_reg, opcode, __ATOMIC_RELAXED);
    __atomic_store_n(arg0_reg,   arg0,   __ATOMIC_RELAXED);
    __atomic_store_n(arg1_reg,   arg1,   __ATOMIC_RELAXED);

    // 2. Set CTRL.START with release semantics.
    __atomic_or_fetch(ctrl_reg,
                      deepspan::crc32::CtrlBits::START,
                      __ATOMIC_RELEASE);

    // 3. Poll until hw-model clears CTRL.START (acquire — makes result visible).
    constexpr int kMaxPolls = 50'000;  // 50 000 × 100 µs = 5 s timeout
    bool done = false;
    for (int i = 0; i < kMaxPolls; ++i) {
        uint32_t ctrl = __atomic_load_n(ctrl_reg, __ATOMIC_ACQUIRE);
        if (!(ctrl & deepspan::crc32::CtrlBits::START)) {
            done = true;
            break;
        }
        usleep(100);  // 100 µs
    }
    if (!done) {
        throw std::runtime_error{
            "Crc32Plugin: submit timeout for " + device_id_};
    }

    // 4. Read result registers.
    uint32_t r0 = __atomic_load_n(result0_reg, __ATOMIC_ACQUIRE);
    uint32_t r1 = __atomic_load_n(result1_reg, __ATOMIC_ACQUIRE);

    // Pack into response_data (8 bytes, little-endian).
    deepspan::server::SubmitResult result;
    result.request_id = device_id_ + "-" + std::to_string(opcode);
    result.response_data.resize(8u);
    std::memcpy(result.response_data.data(),     &r0, 4u);
    std::memcpy(result.response_data.data() + 4, &r1, 4u);
    return result;
}

int Crc32Plugin::device_state() const {
    if (!shm_base_) return -1;

    auto* base       = static_cast<char*>(shm_base_);
    auto* status_reg = reinterpret_cast<uint32_t*>(
        base + deepspan::crc32::RegOffsets::STATUS);
    uint32_t status = __atomic_load_n(status_reg, __ATOMIC_ACQUIRE);
    return (status & deepspan::crc32::StatusBits::READY) ? 2 : 1;
}

}  // namespace deepspan::hwip::crc32
