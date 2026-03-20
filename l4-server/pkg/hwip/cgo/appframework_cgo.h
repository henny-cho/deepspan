/*
 * SPDX-License-Identifier: Apache-2.0
 * appframework_cgo.h — C API shim exposing SessionManager to Go CGo.
 *
 * All functions use C linkage so CGo can call them without name mangling.
 * The opaque handle (void*) holds a heap-allocated SessionManager.
 */
#ifndef APPFRAMEWORK_CGO_H
#define APPFRAMEWORK_CGO_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * deepspan_cgo_result — result returned from deepspan_session_submit().
 * @status:    0 = success, negative = errno from io_uring / kernel
 * @result_lo: result_data0 (lower 32 bits of firmware result)
 * @result_hi: result_data1 (upper 32 bits of firmware result)
 * @err_code:  0 = ok; 1 = circuit open; 2 = no device; 3 = io error
 */
typedef struct {
    int32_t  status;
    uint32_t result_lo;
    uint32_t result_hi;
    int      err_code;
} deepspan_cgo_result;

/**
 * deepspan_session_create() — create a SessionManager for the given devices.
 *
 * @paths:       array of device path strings (e.g. {"/dev/hwip0"})
 * @n_paths:     number of elements in @paths
 * @queue_depth: io_uring queue depth per device (0 = default 64)
 *
 * Returns an opaque handle, or NULL on failure (e.g. device open failed).
 * The caller must call deepspan_session_destroy() when done.
 */
void* deepspan_session_create(const char** paths, int n_paths,
                               unsigned int queue_depth);

/**
 * deepspan_session_destroy() — destroy a SessionManager handle.
 * @handle: handle returned by deepspan_session_create(); no-op if NULL.
 */
void deepspan_session_destroy(void* handle);

/**
 * deepspan_session_submit() — submit a command synchronously.
 *
 * Calls SessionManager::execute() which routes through DevicePool +
 * CircuitBreaker, then calls AsyncClient::submit_and_wait().
 *
 * @handle:     handle from deepspan_session_create()
 * @opcode:     HWIP command opcode (DEEPSPAN_OP_*)
 * @arg0:       first command argument (packed into payload bytes 0-3 LE)
 * @arg1:       second command argument (packed into payload bytes 4-7 LE)
 * @timeout_ms: timeout in milliseconds (0 = kernel default)
 */
deepspan_cgo_result deepspan_session_submit(void*        handle,
                                             uint32_t     opcode,
                                             uint32_t     arg0,
                                             uint32_t     arg1,
                                             uint32_t     timeout_ms);

/**
 * deepspan_session_circuit_state() — query current CircuitBreaker state.
 * Returns: 0=Closed, 1=Open, 2=HalfOpen
 */
int deepspan_session_circuit_state(void* handle);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* APPFRAMEWORK_CGO_H */
