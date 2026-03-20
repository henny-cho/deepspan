// SPDX-License-Identifier: Apache-2.0
// plugin.hpp — Submitter template for a new HWIP type (C++20)
//
// 1. Copy hwip/_template/ to hwip/<your-name>/
// 2. Replace "mychip" / "Mychip" / "MYCHIP" with your HWIP name.
// 3. Implement submit() and device_state() in plugin.cpp.
// 4. Build: cmake --build build --target hwip_mychip
#pragma once

#include "deepspan/server/submitter.hpp"

#include <string>
#include <string_view>

namespace deepspan::hwip::mychip {

class MychipPlugin final : public deepspan::server::Submitter {
public:
    explicit MychipPlugin(std::string_view device_id);
    ~MychipPlugin() override;

    deepspan::server::SubmitResult
    submit(uint32_t opcode, std::vector<uint8_t> data) override;

    int device_state() const override;

    std::string_view device_id() const override { return device_id_; }

private:
    std::string device_id_;
    int device_index_{0};
    // TODO: add your hardware handle (shared memory, file descriptor, etc.)
};

}  // namespace deepspan::hwip::mychip
