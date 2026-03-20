// SPDX-License-Identifier: Apache-2.0
// accel_plugin.hpp — C++20 Submitter for the accel HWIP type
#pragma once

#include "deepspan/server/submitter.hpp"

#include <cstddef>
#include <mutex>
#include <string>
#include <string_view>

namespace deepspan::hwip::accel {

/// Concrete Submitter for the accel HWIP type.
///
/// Communicates with the hw-model (or real hardware) via POSIX shared memory.
/// Each instance is created per device_id by AccelRegistrar.
class AccelPlugin final : public deepspan::server::Submitter {
public:
    explicit AccelPlugin(std::string_view device_id);
    ~AccelPlugin() override;

    deepspan::server::SubmitResult
    submit(uint32_t opcode, std::vector<uint8_t> data) override;

    int device_state() const override;

    std::string_view device_id() const override { return device_id_; }

private:
    static constexpr size_t kShmSize = 4096u;  ///< Total SHM size (1 page)

    std::string device_id_;
    int         device_index_{0};
    int         shm_fd_{-1};       ///< File descriptor from shm_open()
    void*       shm_base_{nullptr}; ///< mmap'd register base
    mutable std::mutex submit_mutex_;  ///< Serialises concurrent submits
};

}  // namespace deepspan::hwip::accel
