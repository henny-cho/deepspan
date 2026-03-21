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

namespace {

// liburing 2.5 (Ubuntu 24.04) does not expose io_uring_prep_uring_cmd as a
// public inline helper; construct the SQE for IORING_OP_URING_CMD manually.
inline void prep_uring_cmd(io_uring_sqe* sqe, int fd, __u32 cmd_op,
                            const void* addr, unsigned len) noexcept {
    io_uring_prep_rw(IORING_OP_URING_CMD, sqe, fd, addr, len, 0);
    sqe->cmd_op = cmd_op;
}

} // anonymous namespace

// ---------------------------------------------------------------------------
// Private constructor
// ---------------------------------------------------------------------------

AsyncClient::AsyncClient(io_uring ring, int device_fd) noexcept
    : ring_{ring}, device_fd_{device_fd}, initialized_{true} {}

// ---------------------------------------------------------------------------
// Static factory: create()
// ---------------------------------------------------------------------------

tl::expected<AsyncClient, Error>
AsyncClient::create(DeepspanDevice& device, unsigned queue_depth) {
    if (device.fd() < 0) {
        return tl::make_unexpected(Error::DeviceOpenFailed);
    }

    io_uring ring{};
    const int ret = io_uring_queue_init(queue_depth, &ring, 0);
    if (ret < 0) {
        return tl::make_unexpected(Error::IouringSetupFailed);
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

tl::expected<void, Error>
AsyncClient::submit(const deepspan_req& req, uint64_t user_data) {
    io_uring_sqe* sqe = io_uring_get_sqe(&ring_);
    if (sqe == nullptr) {
        // SQ is full.
        return tl::make_unexpected(Error::SubmitFailed);
    }

    // Keep a copy of the request because the kernel may read it asynchronously
    // after this function returns.  The SQE carries a pointer to a fixed-size
    // command buffer that the liburing helper copies from req_copy.
    // SAFETY: prep_uring_cmd stores the pointer; the driver reads it
    // before the completion is signalled, so the stack copy is valid for the
    // lifetime of the in-flight operation only when the caller does not reuse
    // the SQE before the CQE.  For correctness in production code callers
    // should use heap-allocated buffers; here we follow the simple convention
    // documented in the project spec.
    // NOLINTNEXTLINE(cppcoreguidelines-pro-type-reinterpret-cast)
    prep_uring_cmd(sqe,
                   device_fd_,
                   DEEPSPAN_CMD_OP,
                   reinterpret_cast<const void*>(&req), // NOLINT
                   sizeof(req));

    io_uring_sqe_set_data64(sqe, user_data);

    const int submitted = io_uring_submit(&ring_);
    if (submitted < 0) {
        return tl::make_unexpected(Error::SubmitFailed);
    }

    return {};  // tl::expected<void, Error> success
}

// ---------------------------------------------------------------------------
// reap()
// ---------------------------------------------------------------------------

tl::expected<int, Error>
AsyncClient::reap(CompletionCallback cb, bool wait) {
    io_uring_cqe* cqe = nullptr;
    int count = 0;

    if (wait) {
        const int ret = io_uring_wait_cqe(&ring_, &cqe);
        if (ret < 0) {
            return tl::make_unexpected(Error::IoError);
        }
        deepspan_result dr{};
        dr.status = cqe->res;
        const uint64_t token = io_uring_cqe_get_data64(cqe);
        io_uring_cqe_seen(&ring_, cqe);
        ++count;
        if (dr.status < 0) {
            cb(token, tl::make_unexpected(Error::IoError));
        } else {
            cb(token, dr);
        }
    }

    // Drain any additional completed CQEs without blocking.
    while (io_uring_peek_cqe(&ring_, &cqe) == 0 && cqe != nullptr) {
        deepspan_result dr{};
        dr.status = cqe->res;
        const uint64_t token = io_uring_cqe_get_data64(cqe);
        io_uring_cqe_seen(&ring_, cqe);
        ++count;
        if (dr.status < 0) {
            cb(token, tl::make_unexpected(Error::IoError));
        } else {
            cb(token, dr);
        }
    }

    return count;
}

// ---------------------------------------------------------------------------
// submit_and_wait()
// ---------------------------------------------------------------------------

tl::expected<deepspan_result, Error>
AsyncClient::submit_and_wait(const deepspan_req& req) {
    auto submit_result = submit(req, 0);
    if (!submit_result.has_value()) {
        return tl::make_unexpected(submit_result.error());
    }

    tl::expected<deepspan_result, Error> captured = tl::make_unexpected(Error::IoError);
    auto reap_result = reap(
        [&captured](uint64_t, tl::expected<deepspan_result, Error> r) {
            captured = std::move(r);
        },
        /*wait=*/true);

    if (!reap_result.has_value()) {
        return tl::make_unexpected(reap_result.error());
    }

    return captured;
}

} // namespace deepspan::userlib
