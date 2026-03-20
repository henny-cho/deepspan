// SPDX-License-Identifier: Apache-2.0
#include "accel_plugin.hpp"

#include <spdlog/spdlog.h>
#include <stdexcept>
#include <charconv>

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
    spdlog::debug("AccelPlugin: constructed for {}", device_id_);
    // TODO: open shared-memory segment for device_index_.
}

AccelPlugin::~AccelPlugin() {
    spdlog::debug("AccelPlugin: destroyed for {}", device_id_);
    // TODO: close shared-memory handle.
}

deepspan::server::SubmitResult
AccelPlugin::submit(uint32_t opcode, std::vector<uint8_t> data) {
    spdlog::debug("AccelPlugin::submit opcode=0x{:04X} data_len={} dev={}",
                  opcode, data.size(), device_id_);
    // TODO: write to SHM ring buffer and wait for completion.
    // Stub: echo opcode back as 4-byte little-endian response.
    deepspan::server::SubmitResult result;
    result.request_id = device_id_ + "-" + std::to_string(opcode);
    result.response_data = {
        static_cast<uint8_t>(opcode & 0xFF),
        static_cast<uint8_t>((opcode >> 8) & 0xFF),
        static_cast<uint8_t>((opcode >> 16) & 0xFF),
        static_cast<uint8_t>((opcode >> 24) & 0xFF),
    };
    return result;
}

int AccelPlugin::device_state() const {
    // TODO: query SHM status word.
    // Stub: index 0 and 1 are always READY (1); anything else signals end.
    return (device_index_ < 2) ? 1 : -1;
}

}  // namespace deepspan::hwip::accel
