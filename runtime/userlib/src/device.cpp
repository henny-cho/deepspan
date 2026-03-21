// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024 Deepspan Project Authors
//
// device.cpp — Implementation of DeepspanDevice.

#include "deepspan/userlib/device.hpp"

#include <cerrno>
#include <cstring>
#include <string>
#include <utility>

// POSIX / Linux headers
#include <fcntl.h>      // O_RDWR, O_CLOEXEC
#include <sys/ioctl.h>
#include <unistd.h>     // close()

// Kernel UAPI — provided via target_include_directories in CMakeLists.txt
// (deepspan/kernel/include/uapi is on the include path, so the file is found
// as <linux/deepspan.h>).
#include <linux/deepspan.h> // NOLINT(hicpp-deprecated-headers)

namespace deepspan::userlib {

// ---------------------------------------------------------------------------
// Private constructor
// ---------------------------------------------------------------------------

DeepspanDevice::DeepspanDevice(int fd, uint32_t uapi_ver) noexcept
    : fd_{fd}, kernel_uapi_version_{uapi_ver} {}

// ---------------------------------------------------------------------------
// Static factory: open()
// ---------------------------------------------------------------------------

tl::expected<DeepspanDevice, Error>
DeepspanDevice::open(std::string_view device_path) {
    // Build a null-terminated path for the C API.
    // std::string guarantees null termination.
    const std::string path{device_path};

    // NOLINTNEXTLINE(cppcoreguidelines-pro-type-vararg)
    const int fd = ::open(path.c_str(), O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        return tl::make_unexpected(Error::DeviceOpenFailed);
    }

    // Query the kernel driver UAPI version.
    __u32 ver = 0; // NOLINT(google-runtime-int)
    // NOLINTNEXTLINE(cppcoreguidelines-pro-type-vararg)
    if (::ioctl(fd, DEEPSPAN_IOC_GET_VERSION, &ver) < 0) {
        ::close(fd);
        return tl::make_unexpected(Error::IoError);
    }

    if (ver < DEEPSPAN_UAPI_VERSION_MIN) {
        ::close(fd);
        return tl::make_unexpected(Error::UnsupportedKernelVersion);
    }

    return DeepspanDevice{fd, static_cast<uint32_t>(ver)};
}

// ---------------------------------------------------------------------------
// Destructor
// ---------------------------------------------------------------------------

DeepspanDevice::~DeepspanDevice() {
    if (fd_ >= 0) {
        ::close(fd_);
        fd_ = -1;
    }
}

// ---------------------------------------------------------------------------
// Move semantics
// ---------------------------------------------------------------------------

DeepspanDevice::DeepspanDevice(DeepspanDevice&& other) noexcept
    : fd_{other.fd_}, kernel_uapi_version_{other.kernel_uapi_version_} {
    other.fd_ = -1;
    other.kernel_uapi_version_ = 0;
}

DeepspanDevice& DeepspanDevice::operator=(DeepspanDevice&& other) noexcept {
    if (this != &other) {
        if (fd_ >= 0) {
            ::close(fd_);
        }
        fd_                    = other.fd_;
        kernel_uapi_version_   = other.kernel_uapi_version_;
        other.fd_              = -1;
        other.kernel_uapi_version_ = 0;
    }
    return *this;
}

// ---------------------------------------------------------------------------
// submit_sync() — synchronous ioctl fallback
// ---------------------------------------------------------------------------

tl::expected<deepspan_result, Error>
DeepspanDevice::submit_sync(const deepspan_req& req) {
    // Make a mutable copy: the ioctl is IOWR and the kernel may write
    // the result back into the same buffer.  deepspan_result is piggybacked
    // by the driver into the extended ioctl result area; we use a local
    // deepspan_result to receive it.
    deepspan_req req_copy = req;
    deepspan_result result{};

    // The DEEPSPAN_IOC_SUBMIT ioctl writes the result into the request
    // structure on return (driver convention: the result fields follow the
    // request in memory for the extended ioctl path).  We read ioctl(2)
    // return value as the status.
    // NOLINTNEXTLINE(cppcoreguidelines-pro-type-vararg)
    const int ret = ::ioctl(fd_, DEEPSPAN_IOC_SUBMIT, &req_copy);
    if (ret < 0) {
        return tl::make_unexpected(Error::SubmitFailed);
    }

    // The kernel driver returns the result status in the ioctl return value
    // (ret == 0 on success).  Extended result data is not available through
    // the synchronous ioctl path, so we synthesize a minimal deepspan_result.
    result.status    = static_cast<__s32>(ret);
    result.result_lo = 0;
    result.result_hi = 0;
    result._pad      = 0;

    return result;
}

} // namespace deepspan::userlib
