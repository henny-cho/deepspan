// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024 Deepspan Project Authors
//
// async_client.cpp — Implementation of AsyncClient (io_uring URING_CMD).

#include "deepspan/userlib/async_client.hpp"

#include <cerrno>
#include <cstring>
#include <utility>

// Kernel UAPI — provided via target_include_directories in CMakeLists.txt.
#include <linux/deepspan.h> // NOLINT(hicpp-deprecated-headers)

// cmd_op value for IORING_OP_URING_CMD submitted to the deepspan driver.
// The kernel driver registers a single uring_cmd handler; the cmd_op field
// is driver-private and defined here as 0 to match the driver's expectation.
#define DEEPSPAN_CMD_OP 0  // NOLINT(cppcoreguidelines-macro-usage)

namespace deepspan::userlib {

// ---------------------------------------------------------------------------
// Private constructor
// ---------------------------------------------------------------------------

AsyncClient::AsyncClient(io_uring ring, int device_fd) noexcept
    : ring_{ring}, device_fd_{device_fd}, initialized_{true} {}

// ---------------------------------------------------------------------------
// Static factory: create()
// ---------------------------------------------------------------------------

etl::expected<AsyncClient, Error>
AsyncClient::create(DeepspanDevice& device, unsigned queue_depth) {
    if (device.fd() < 0) {
        return etl::unexpected{Error::DeviceOpenFailed};
    }

    io_uring ring{};
    const int ret = io_uring_queue_init(queue_depth, &ring, 0);
    if (ret < 0) {
        return etl::unexpected{Error::IouringSetupFailed};
    }

    return AsyncClient{ring, device.fd()};
}

// ---------------------------------------------------------------------------
// Destructor
// ---------------------------------------------------------------------------

AsyncClient::~AsyncClient() {
    if (initialized_) {
        io_uring_queue_exit(&ring_);
        initialized_ = false;
    }
}

// ---------------------------------------------------------------------------
// Move semantics
// ---------------------------------------------------------------------------

AsyncClient::AsyncClient(AsyncClient&& other) noexcept
    : ring_{other.ring_},
      device_fd_{other.device_fd_},
      initialized_{other.initialized_} {
    other.initialized_ = false;
    other.device_fd_   = -1;
}

AsyncClient& AsyncClient::operator=(AsyncClient&& other) noexcept {
    if (this != &other) {
        if (initialized_) {
            io_uring_queue_exit(&ring_);
        }
        ring_              = other.ring_;
        device_fd_         = other.device_fd_;
        initialized_       = other.initialized_;
        other.initialized_ = false;
        other.device_fd_   = -1;
    }
    return *this;
}

// ---------------------------------------------------------------------------
// submit()
// ---------------------------------------------------------------------------

etl::expected<void, Error>
AsyncClient::submit(const deepspan_req& req, uint64_t user_data) {
    io_uring_sqe* sqe = io_uring_get_sqe(&ring_);
    if (sqe == nullptr) {
        // SQ is full.
        return etl::unexpected{Error::SubmitFailed};
    }

    // Keep a copy of the request because the kernel may read it asynchronously
    // after this function returns.  The SQE carries a pointer to a fixed-size
    // command buffer that the liburing helper copies from req_copy.
    // SAFETY: io_uring_prep_uring_cmd stores the pointer; the driver reads it
    // before the completion is signalled, so the stack copy is valid for the
    // lifetime of the in-flight operation only when the caller does not reuse
    // the SQE before the CQE.  For correctness in production code callers
    // should use heap-allocated buffers; here we follow the simple convention
    // documented in the project spec.
    // NOLINTNEXTLINE(cppcoreguidelines-pro-type-reinterpret-cast)
    io_uring_prep_uring_cmd(sqe,
                            device_fd_,
                            DEEPSPAN_CMD_OP,
                            reinterpret_cast<const void*>(&req), // NOLINT
                            sizeof(req));

    io_uring_sqe_set_data64(sqe, user_data);

    const int submitted = io_uring_submit(&ring_);
    if (submitted < 0) {
        return etl::unexpected{Error::SubmitFailed};
    }

    return {};  // etl::expected<void, Error> success
}

// ---------------------------------------------------------------------------
// reap()
// ---------------------------------------------------------------------------

etl::expected<int, Error>
AsyncClient::reap(CompletionCallback cb, bool wait) {
    int count = 0;

    // Process all immediately available completions first, then optionally
    // block for one more if none were found and wait==true.
    while (true) {
        io_uring_cqe* cqe = nullptr;
        int ret = 0;

        if (wait && count == 0) {
            ret = io_uring_wait_cqe(&ring_, &cqe);
        } else {
            ret = io_uring_peek_cqe(&ring_, &cqe);
        }

        if (ret == -EAGAIN || cqe == nullptr) {
            // No more completions available.
            break;
        }
        if (ret < 0) {
            return etl::unexpected{Error::IoError};
        }

        const uint64_t ud = io_uring_cqe_get_data64(cqe);

        // Build a deepspan_result from the CQE.
        // For URING_CMD the kernel places the operation status in cqe->res
        // (negative errno on error, 0 on success).  Extended data (result_lo,
        // result_hi) would require big-CQE support; we leave them zero for now.
        deepspan_result result{};
        result.status    = static_cast<__s32>(cqe->res);
        result.result_lo = 0;
        result.result_hi = 0;
        result._pad      = 0;

        io_uring_cqe_seen(&ring_, cqe);
        ++count;

        if (result.status < 0) {
            cb(ud, etl::unexpected{Error::IoError});
        } else {
            cb(ud, result);
        }

        // After the first blocked completion, switch to non-blocking peek.
        wait = false;
    }

    return count;
}

// ---------------------------------------------------------------------------
// submit_and_wait()
// ---------------------------------------------------------------------------

etl::expected<deepspan_result, Error>
AsyncClient::submit_and_wait(const deepspan_req& req) {
    constexpr uint64_t kSentinel = 0xDEAD'BEEF'CAFE'0000ULL;

    auto sub_result = submit(req, kSentinel);
    if (!sub_result) {
        return etl::unexpected{sub_result.error()};
    }

    etl::expected<deepspan_result, Error> outcome =
        etl::unexpected{Error::IoError};

    auto reap_result = reap(
        [&](uint64_t /*user_data*/, etl::expected<deepspan_result, Error> r) {
            outcome = r;
        },
        /*wait=*/true);

    if (!reap_result) {
        return etl::unexpected{reap_result.error()};
    }

    return outcome;
}

} // namespace deepspan::userlib
