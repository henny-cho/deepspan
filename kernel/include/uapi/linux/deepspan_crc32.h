/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
/*
 * deepspan_crc32.h — Deepspan CRC32 HWIP UAPI header
 *
 * Opcode definitions for the CRC32 HWIP type, shared between:
 *   - kernel driver  (deepspan_crc32_shash.c)
 *   - userspace      (via AF_ALG: alg name "crc32-deepspan")
 */

#ifndef _UAPI_LINUX_DEEPSPAN_CRC32_H
#define _UAPI_LINUX_DEEPSPAN_CRC32_H

#include <linux/types.h>

/* ── Opcode values (match hwip/crc32/hwip.yaml) ─────────────────────────── */

/** Compute CRC32 over a byte stream (IEEE 802.3 poly 0xEDB88320). */
#define DEEPSPAN_CRC32_OP_COMPUTE   0x0001U

/** Return the active CRC32 polynomial (default 0xEDB88320). */
#define DEEPSPAN_CRC32_OP_GET_POLY  0x0002U

/* ── Register offsets (match gen/kernel/deepspan_crc32.h) ───────────────── */

#define DEEPSPAN_CRC32_REG_CTRL          0x0000U
#define DEEPSPAN_CRC32_REG_STATUS        0x0004U
#define DEEPSPAN_CRC32_REG_CMD_OPCODE    0x0100U
#define DEEPSPAN_CRC32_REG_CMD_ARG0      0x0104U  /* data length */
#define DEEPSPAN_CRC32_REG_RESULT_STATUS 0x0110U
#define DEEPSPAN_CRC32_REG_RESULT_DATA0  0x0114U  /* CRC32 checksum */

/* ── Request / result structures ────────────────────────────────────────── */

/**
 * struct deepspan_crc32_compute_req - COMPUTE request payload
 * @data:     Input byte stream (variable length)
 * @data_len: Length of @data in bytes
 */
struct deepspan_crc32_compute_req {
	__u8  data[3072];
	__u32 data_len;
};

/**
 * struct deepspan_crc32_compute_resp - COMPUTE result
 * @checksum: CRC32 checksum of the input data
 */
struct deepspan_crc32_compute_resp {
	__u32 checksum;
};

#endif /* _UAPI_LINUX_DEEPSPAN_CRC32_H */
