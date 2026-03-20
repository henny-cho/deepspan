// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024 Deepspan Project Authors
//
// error.hpp — Error codes for the deepspan userlib layer.

#pragma once

#include <string_view>

namespace deepspan::userlib {

/// Error codes returned by deepspan userlib operations.
enum class Error {
    /// The kernel driver's UAPI version is older than DEEPSPAN_UAPI_VERSION_MIN.
    UnsupportedKernelVersion,

    /// ::open() on the device path failed (e.g. device not present, permission denied).
    DeviceOpenFailed,

    /// io_uring_queue_init() failed.
    IouringSetupFailed,

    /// Submission to io_uring or ioctl submit failed.
    SubmitFailed,

    /// Operation timed out.
    Timeout,

    /// Generic errno-based I/O error.
    IoError,
};

/// Returns a human-readable name for \p e.  The returned view is a string
/// literal and remains valid for the lifetime of the program.
std::string_view to_string(Error e) noexcept;

} // namespace deepspan::userlib
