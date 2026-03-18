/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
/*
 * deepspan_accel.h - Deepspan acceleration HWIP opcode definitions
 *
 * Include after <linux/deepspan.h> for accel-specific opcodes.
 * These opcodes are passed as deepspan_req.opcode.
 */

#ifndef _UAPI_LINUX_DEEPSPAN_ACCEL_H
#define _UAPI_LINUX_DEEPSPAN_ACCEL_H

#include <linux/deepspan.h>

/* Accel command opcodes (deepspan_req.opcode) */
#define DEEPSPAN_ACCEL_OP_ECHO    0x0001  /* echo (for testing) */
#define DEEPSPAN_ACCEL_OP_PROCESS 0x0002  /* data processing */
#define DEEPSPAN_ACCEL_OP_STATUS  0x0003  /* device status query */

#endif /* _UAPI_LINUX_DEEPSPAN_ACCEL_H */
