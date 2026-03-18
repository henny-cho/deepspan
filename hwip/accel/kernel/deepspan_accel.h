/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
/*
 * hwip/accel/kernel/deepspan_accel.h
 *
 * Plugin-side entry point.  The canonical header lives in the kernel UAPI
 * tree at kernel/include/uapi/linux/deepspan_accel.h and is the version
 * installed alongside the kernel module.  This file re-exports it so that
 * accel plugin code can use a self-contained path.
 *
 * Usage in firmware / driver code within the accel plugin:
 *   #include "deepspan_accel.h"   (within hwip/accel/)
 *
 * Usage in userlib / appframework / server:
 *   #include <linux/deepspan_accel.h>   (via DEEPSPAN_KERNEL_UAPI_DIR)
 */

#ifndef _HWIP_ACCEL_DEEPSPAN_ACCEL_H
#define _HWIP_ACCEL_DEEPSPAN_ACCEL_H

/* Accel command opcodes (deepspan_req.opcode) */
#define DEEPSPAN_ACCEL_OP_ECHO    0x0001  /* echo (for testing) */
#define DEEPSPAN_ACCEL_OP_PROCESS 0x0002  /* data processing */
#define DEEPSPAN_ACCEL_OP_STATUS  0x0003  /* device status query */

#endif /* _HWIP_ACCEL_DEEPSPAN_ACCEL_H */
