// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024 Deepspan Project Authors
//
// async_client.hpp — io_uring URING_CMD based async client for Deepspan HWIP.

#pragma once

#include <cstdint>
#include "tl/expected.hpp"
#include <functional>

#include <liburing.h>

#include "device.hpp"
#include "error.hpp"

// Forward-declare the kernel UAPI types (full definitions in <linux/deepspan.h>).
struct deepspan_req;
struct deepspan_result;

namespace deepspan::userlib {

/// Completion callback type.
///
/// Arguments:
///   uint64_t                               — the user_data token supplied to submit()
///   tl::expected<deepspan_result, Error>  — result or error
using CompletionCallback =
    std::function<void(uint64_t, tl::expected<deepspan_result, Error>)>;

/// io_uring based async client for Deepspan HWIP operations.
///
/// Uses IORING_OP_URING_CMD so that the kernel driver handles each SQE
/// directly without a syscall round-trip per request.
///
/// AsyncClient is non-copyable and movable.
class AsyncClient {
public:
    /// Create an AsyncClient backed by \p device.
    ///
    /// \param device       An already-opened DeepspanDevice.  The device must
    ///                     outlive this AsyncClient.
    /// \param queue_depth  Number of SQE/CQE slots in the io_uring (default 64).
    ///
    /// Errors:
    ///   - Error::IouringSetupFailed  if io_uring_queue_init() fails
    static tl::expected<AsyncClient, Error> create(DeepspanDevice& device,
                                                    unsigned queue_depth = 64);

    /// Tears down the io_uring and releases kernel resources.
    ~AsyncClient();

    // Non-copyable.
    AsyncClient(const AsyncClient&)            = delete;
    AsyncClient& operator=(const AsyncClient&) = delete;

    // Movable.
    AsyncClient(AsyncClient&&) noexcept;
    AsyncClient& operator=(AsyncClient&&) noexcept;

    /// Enqueue an async request.
    ///
    /// \param req       The request descriptor.
    /// \param user_data Opaque token delivered to the CompletionCallback.
    ///
    /// Errors:
    ///   - Error::SubmitFailed  if no SQE slot is available or io_uring_submit fails
    tl::expected<void, Error> submit(const deepspan_req& req, uint64_t user_data);

    /// Harvest completed requests and invoke \p cb for each one.
    ///
    /// \param cb    Callback invoked for every completed CQE.
    /// \param wait  If true, block until at least one completion is available.
    ///
    /// \returns The number of completions processed, or an Error.
    tl::expected<int, Error> reap(CompletionCallback cb, bool wait = false);

    /// Convenience wrapper: submit one request and block until it completes.
    ///
    /// Errors: any error from submit() or reap().
    tl::expected<deepspan_result, Error> submit_and_wait(const deepspan_req& req);

private:
    explicit AsyncClient(io_uring ring, int device_fd) noexcept;

    io_uring ring_{};
    int      device_fd_{-1};
    bool     initialized_{false};
};

} // namespace deepspan::userlib
