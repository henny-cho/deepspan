/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
/*
 * deepspan.h - Deepspan HWIP UAPI header
 *
 * This header is the contract shared between the kernel and userspace.
 * Used in userlib as #include <linux/deepspan.h>.
 * ABI compatibility: runtime version negotiation via DEEPSPAN_UAPI_VERSION.
 */

#ifndef _UAPI_LINUX_DEEPSPAN_H
#define _UAPI_LINUX_DEEPSPAN_H

#include <linux/types.h>
#include <linux/ioctl.h>

/* UAPI version: used by userlib for runtime compatibility check */
#define DEEPSPAN_UAPI_VERSION     1
#define DEEPSPAN_UAPI_VERSION_MIN 1

/* ioctl magic */
#define DEEPSPAN_IOC_MAGIC  'D'

/**
 * struct deepspan_req - io_uring command request structure
 * @opcode:     command type — hwip-specific (e.g. DEEPSPAN_ACCEL_OP_* from <linux/deepspan_accel.h>)
 * @flags:      request flags
 * @data_ptr:   userspace data buffer pointer
 * @data_len:   data buffer size (bytes)
 * @timeout_ms: timeout (0 = default 5000ms)
 */
struct deepspan_req {
    __u32 opcode;
    __u32 flags;
    __u64 data_ptr;
    __u32 data_len;
    __u32 timeout_ms;
};

/**
 * struct deepspan_result - io_uring command result
 * @status:    0 = success, negative = errno
 * @result_lo: result data lower 32 bits
 * @result_hi: result data upper 32 bits
 */
struct deepspan_result {
    __s32 status;
    __u32 result_lo;
    __u32 result_hi;
    __u32 _pad;
};

/*
 * Command opcodes are hwip-type specific.
 * Include the appropriate hwip header for opcode definitions:
 *   #include <linux/deepspan_accel.h>   -- acceleration HWIP
 *   #include <linux/deepspan_codec.h>   -- codec HWIP
 */

/* ioctl: query UAPI version */
#define DEEPSPAN_IOC_GET_VERSION  _IOR(DEEPSPAN_IOC_MAGIC, 1, __u32)

/* ioctl: synchronous request submission (fallback when not using io_uring) */
#define DEEPSPAN_IOC_SUBMIT \
    _IOWR(DEEPSPAN_IOC_MAGIC, 2, struct deepspan_req)

#endif /* _UAPI_LINUX_DEEPSPAN_H */
