// SPDX-License-Identifier: Apache-2.0
// accel_plugin.hpp — C++20 Submitter for the accel HWIP type
#pragma once

#include "deepspan/server/submitter.hpp"

#include <string>
#include <string_view>

namespace deepspan::hwip::accel {

/// Concrete Submitter for the accel HWIP type.
///
/// Communicates with the hw-model (or real hardware) via shared memory.
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
    std::string device_id_;
    int device_index_{0};
    // TODO: shared-memory handle (ShmClient) for actual HW communication.
};

}  // namespace deepspan::hwip::accel
