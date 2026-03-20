// SPDX-License-Identifier: Apache-2.0
// plugin.cpp — Submitter implementation skeleton
// Replace "mychip" / "Mychip" with your HWIP name.
#include "plugin.hpp"

#include <spdlog/spdlog.h>
#include <stdexcept>
#include <charconv>

namespace deepspan::hwip::mychip {

namespace {
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

MychipPlugin::MychipPlugin(std::string_view device_id)
    : device_id_{device_id},
      device_index_{parse_index(device_id)} {
    if (device_index_ < 0)
        throw std::invalid_argument{"MychipPlugin: bad device_id: " +
                                    std::string{device_id}};
    // TODO: open hardware handle.
}

MychipPlugin::~MychipPlugin() {
    // TODO: close hardware handle.
}

deepspan::server::SubmitResult
MychipPlugin::submit(uint32_t opcode, std::vector<uint8_t> data) {
    spdlog::debug("MychipPlugin::submit opcode=0x{:04X} dev={}", opcode, device_id_);
    // TODO: implement hardware communication.
    deepspan::server::SubmitResult result;
    result.request_id = device_id_ + "-" + std::to_string(opcode);
    return result;
}

int MychipPlugin::device_state() const {
    // Return 1 (READY) for valid indices; -1 signals end of device list.
    return (device_index_ < 1) ? 1 : -1;
}

}  // namespace deepspan::hwip::mychip
