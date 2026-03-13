// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024 Deepspan Project Authors
//
// device.hpp — RAII handle for a /dev/hwipN device file descriptor.

#pragma once

#include <cstdint>
#include <expected>
#include <string_view>

// Forward-declare the kernel UAPI types so that callers only need this header.
// The full definitions come from <linux/deepspan.h> which is included in the
// translation units that implement this interface.
struct deepspan_req;
struct deepspan_result;

#include "error.hpp"

namespace deepspan::userlib {

/// RAII wrapper around a file descriptor opened on a Deepspan HWIP device
/// (e.g. /dev/hwip0).
///
/// DeepspanDevice is non-copyable and movable.  The destructor closes the
/// underlying file descriptor.
class DeepspanDevice {
public:
    /// Open the device at \p device_path (e.g. "/dev/hwip0") and negotiate
    /// the UAPI version with the kernel driver.
    ///
    /// Errors:
    ///   - Error::DeviceOpenFailed          if ::open() fails
    ///   - Error::UnsupportedKernelVersion  if the driver UAPI version is
    ///                                      below DEEPSPAN_UAPI_VERSION_MIN
    ///   - Error::IoError                   if the version ioctl fails
    static std::expected<DeepspanDevice, Error> open(std::string_view device_path);

    /// Closes the file descriptor.
    ~DeepspanDevice();

    // Non-copyable.
    DeepspanDevice(const DeepspanDevice&)            = delete;
    DeepspanDevice& operator=(const DeepspanDevice&) = delete;

    // Movable.
    DeepspanDevice(DeepspanDevice&&) noexcept;
    DeepspanDevice& operator=(DeepspanDevice&&) noexcept;

    /// Returns the raw file descriptor.  -1 if the object was moved from.
    [[nodiscard]] int fd() const noexcept { return fd_; }

    /// Returns the UAPI version reported by the kernel driver.
    [[nodiscard]] uint32_t kernel_uapi_version() const noexcept {
        return kernel_uapi_version_;
    }

    /// Synchronous ioctl submit fallback (DEEPSPAN_IOC_SUBMIT).
    ///
    /// Use this when io_uring is unavailable or for simple one-shot calls.
    /// Errors:
    ///   - Error::SubmitFailed  if the ioctl returns an error
    std::expected<deepspan_result, Error> submit_sync(const deepspan_req& req);

private:
    explicit DeepspanDevice(int fd, uint32_t uapi_ver) noexcept;

    int      fd_{-1};
    uint32_t kernel_uapi_version_{0};
};

} // namespace deepspan::userlib
