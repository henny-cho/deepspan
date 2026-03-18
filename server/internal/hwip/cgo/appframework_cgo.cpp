// SPDX-License-Identifier: Apache-2.0
/*
 * appframework_cgo.cpp — C++ implementation of the CGo shim for SessionManager.
 *
 * Each exported function has C linkage (extern "C") so CGo can call it.
 *
 * Flow for deepspan_session_submit():
 *   1. Build deepspan_req with opcode + [arg0, arg1] payload
 *   2. Call SessionManager::execute([&](AsyncClient& c){ c.submit_and_wait(req) })
 *   3. Pack the deepspan_result into deepspan_cgo_result and return it
 */

#include "appframework_cgo.h"

#include <deepspan/appframework/session_manager.hpp>
#include <deepspan/userlib/async_client.hpp>
#include <linux/deepspan.h>      // deepspan_req, deepspan_result, DEEPSPAN_OP_*

#include <cstring>
#include <memory>
#include <string>
#include <vector>

/* ── Error codes (must match cgo_client.go cgoErr* constants) ──── */
static constexpr int CGO_OK         = 0;
static constexpr int CGO_CIRCUIT    = 1;  // circuit breaker open
static constexpr int CGO_NO_DEVICE  = 2;  // no available device in pool
static constexpr int CGO_IO_ERROR   = 3;  // io_uring / kernel error

/* ── Opaque handle ──────────────────────────────────────────────── */

struct SessionHandle {
    deepspan::appframework::SessionManager mgr;

    explicit SessionHandle(deepspan::appframework::SessionManager&& m)
        : mgr(std::move(m)) {}
};

/* ── Helpers ────────────────────────────────────────────────────── */

static deepspan_cgo_result make_err(int code) noexcept {
    return {0, 0, 0, code};
}

/* ── C API implementation ───────────────────────────────────────── */

extern "C" {

void* deepspan_session_create(const char** paths, int n_paths,
                               unsigned int queue_depth)
{
    if (!paths || n_paths <= 0) {
        return nullptr;
    }

    deepspan::appframework::SessionManager::Config cfg;
    cfg.uring_queue_depth = (queue_depth > 0) ? queue_depth : 64u;
    cfg.device_paths.reserve(static_cast<std::size_t>(n_paths));
    for (int i = 0; i < n_paths; ++i) {
        if (paths[i]) {
            cfg.device_paths.emplace_back(paths[i]);
        }
    }

    cfg.cb_config.failure_threshold = 5;
    cfg.cb_config.success_threshold = 2;
    cfg.cb_config.open_duration     = std::chrono::milliseconds(5000);
    cfg.cb_config.name              = "hwip-cgo";

    auto result = deepspan::appframework::SessionManager::create(std::move(cfg));
    if (!result.has_value()) {
        return nullptr;
    }

    try {
        return new SessionHandle(std::move(result.value()));
    } catch (...) {
        return nullptr;
    }
}

void deepspan_session_destroy(void* handle)
{
    delete static_cast<SessionHandle*>(handle);
}

deepspan_cgo_result deepspan_session_submit(void*        handle,
                                             uint32_t     opcode,
                                             uint32_t     arg0,
                                             uint32_t     arg1,
                                             uint32_t     timeout_ms)
{
    if (!handle) {
        return make_err(CGO_NO_DEVICE);
    }
    auto* h = static_cast<SessionHandle*>(handle);

    /* Pack arg0, arg1 as little-endian payload (matches deepspan_iouring.c) */
    struct [[gnu::packed]] payload_t {
        uint32_t arg0;
        uint32_t arg1;
    } payload = { arg0, arg1 };

    deepspan_req req{};
    req.opcode     = opcode;
    req.flags      = 0;
    req.data_ptr   = reinterpret_cast<uint64_t>(&payload);
    req.data_len   = static_cast<uint32_t>(sizeof(payload));
    req.timeout_ms = timeout_ms;

    deepspan_cgo_result out{};

    auto exec_result = h->mgr.execute(
        [&](deepspan::userlib::AsyncClient& client) -> bool {
            auto res = client.submit_and_wait(req);
            if (!res.has_value()) {
                out = make_err(CGO_IO_ERROR);
                return false;  // record failure in CircuitBreaker
            }
            out.status    = res->status;
            out.result_lo = res->result_lo;
            out.result_hi = res->result_hi;
            out.err_code  = CGO_OK;
            return (res->status == 0);
        });

    if (!exec_result.has_value()) {
        /* execute() returned error — circuit is open or no device */
        if (out.err_code == CGO_OK) {
            out = make_err(CGO_CIRCUIT);
        }
    }

    return out;
}

int deepspan_session_circuit_state(void* handle)
{
    if (!handle) return 1; /* treat NULL as OPEN */
    auto* h = static_cast<SessionHandle*>(handle);
    return static_cast<int>(h->mgr.circuit_state());
}

} /* extern "C" */
