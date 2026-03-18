/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
/*
 * deepspan_codec.h - Deepspan codec HWIP opcode definitions
 *
 * Skeleton for codec HWIP type.  Include after <linux/deepspan.h>.
 */

#ifndef _UAPI_LINUX_DEEPSPAN_CODEC_H
#define _UAPI_LINUX_DEEPSPAN_CODEC_H

#include <linux/deepspan.h>

/* Codec command opcodes (deepspan_req.opcode) */
#define DEEPSPAN_CODEC_OP_ENCODE 0x0001  /* encode a data buffer */
#define DEEPSPAN_CODEC_OP_DECODE 0x0002  /* decode a data buffer */
#define DEEPSPAN_CODEC_OP_STATUS 0x0003  /* device status query */

#endif /* _UAPI_LINUX_DEEPSPAN_CODEC_H */
