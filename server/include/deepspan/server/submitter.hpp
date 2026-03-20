// SPDX-License-Identifier: Apache-2.0
// submitter.hpp — Plugin interface for HWIP Submitter
//
// Each HWIP type implements this interface and registers a factory via
// HwipRegistry::register_type(). The server routes SubmitRequest RPCs
// to the appropriate Submitter based on device_id prefix.
#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace deepspan::server {

/// A single submitted request result.
struct SubmitResult {
    std::string request_id;
    std::vector<uint8_t> response_data;
};

/// Device information returned by ListDevices.
struct DeviceInfo {
    std::string device_id;  ///< e.g. "accel/0", "codec/1"
    int state{0};           ///< maps to proto DeviceState enum
};

/// Abstract interface that each HWIP plugin must implement.
///
/// Each concrete Submitter is created per device_id by the factory registered
/// with HwipRegistry::register_type(). Implementations are free to maintain
/// per-instance state (shared memory handle, session, etc.).
class Submitter {
public:
    virtual ~Submitter() = default;

    /// Submit a synchronous request to the hardware.
    /// @param opcode   HW wire opcode (from gen/rpc/<hwip>.hpp)
    /// @param data     Raw payload bytes
    /// @returns        SubmitResult on success; throws std::runtime_error on failure
    virtual SubmitResult submit(uint32_t opcode, std::vector<uint8_t> data) = 0;

    /// Return current device state (0 = unspecified, 1 = ready, 2 = busy, ...).
    virtual int device_state() const = 0;

    /// Return the device_id this instance handles.
    virtual std::string_view device_id() const = 0;

    // Non-copyable, non-movable (factory always returns unique_ptr).
    Submitter(const Submitter&) = delete;
    Submitter& operator=(const Submitter&) = delete;

protected:
    Submitter() = default;
};

}  // namespace deepspan::server
