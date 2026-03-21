// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "deepspan/server/submitter.hpp"

#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

namespace deepspan::hwip::crc32 {

/// CRC32 HWIP plugin — implements the Submitter interface over POSIX shm MMIO.
///
/// SHM layout (4 KiB page shared with hw-model / Zephyr native_sim):
///   0x000–0x1FF  RegMap   (platform control/command/result registers)
///   0x200–0x21F  ShmStats (command counter, timestamps)
///   0x300–0xEFF  DMA buf  (kShmDmaOffset, max kShmDmaMaxLen bytes)
///
/// For the COMPUTE opcode (dma_bytes encoding) the plugin writes the input
/// data to the DMA buffer area before asserting CTRL.START.  arg0 carries
/// the byte length; the hw-model reads the buffer and returns the CRC32.
class Crc32Plugin final : public deepspan::server::Submitter {
public:
    explicit Crc32Plugin(std::string_view device_id);
    ~Crc32Plugin() override;

    deepspan::server::SubmitResult
    submit(uint32_t opcode, std::vector<uint8_t> data) override;

    int device_state() const override;
    std::string_view device_id() const override { return device_id_; }

private:
    static constexpr size_t   kShmSize     = 4096u;
    static constexpr uint32_t kShmDmaOffset = 0x300u;   // after RegMap+ShmStats
    static constexpr uint32_t kShmDmaMaxLen = 0xC00u;   // 3072 bytes

    std::string device_id_;
    int         device_index_;
    int         shm_fd_{-1};
    void*       shm_base_{nullptr};
    mutable std::mutex submit_mutex_;
};

}  // namespace deepspan::hwip::crc32
