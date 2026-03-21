// SPDX-License-Identifier: GPL-2.0
/*
 * deepspan_crc32_shash.c — Linux Crypto API shash bridge for Deepspan CRC32 HW
 *
 * Registers "crc32-deepspan" as a synchronous hash (shash) algorithm with the
 * Linux Crypto subsystem.  Once registered, any userspace application can use
 * the hardware CRC32 engine via the AF_ALG socket interface without modifying
 * its source code — the same pattern used by:
 *   - drivers/crypto/stm32/stm32-crc32.c  (STM32 SoC CRC32 engine)
 *   - arch/x86/crypto/crc32c-intel_glue.c (Intel SSE4.2 CRC32C)
 *   - arch/arm64/crypto/crc32-arm64.c     (ARM64 hardware CRC32)
 *
 * AF_ALG usage example (userspace — no source changes needed):
 *
 *   struct sockaddr_alg sa = {
 *       .salg_family = AF_ALG,
 *       .salg_type   = "hash",
 *       .salg_name   = "crc32-deepspan",
 *   };
 *   int afd = socket(AF_ALG, SOCK_SEQPACKET, 0);
 *   bind(afd, (struct sockaddr *)&sa, sizeof(sa));
 *   int fd = accept(afd, NULL, 0);
 *   send(fd, data, len, MSG_MORE);
 *   read(fd, &checksum, 4);   // FPGA CRC32 result
 *
 * Registration:
 *   Enabled by CONFIG_DEEPSPAN_CRC32_SHASH=y.
 *   Priority 200 (same as STM32/Intel hardware drivers) — preferred over
 *   the generic software fallback (priority 100).
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/crypto.h>
#include <crypto/hash.h>
#include <crypto/internal/hash.h>
#include <linux/crc32.h>

#include "deepspan_priv.h"

/* ── Algorithm constants ─────────────────────────────────────────────────── */

#define DEEPSPAN_CRC32_DIGESTSIZE  4    /* 32-bit checksum */
#define DEEPSPAN_CRC32_BLOCKSIZE   1    /* byte-granular input */
#define DEEPSPAN_CRC32_PRIORITY  200    /* prefer over generic SW (100) */

/* IEEE 802.3 / Ethernet CRC32 polynomial (reflected, LSB-first). */
#define CRC32_POLY_IEEE 0xEDB88320U

/* ── Per-request state ───────────────────────────────────────────────────── */

struct deepspan_crc32_ctx {
	u32 crc;   /* running checksum, initialised to 0xFFFFFFFF */
};

/* ── shash callbacks ─────────────────────────────────────────────────────── */

static int deepspan_crc32_init(struct shash_desc *desc)
{
	struct deepspan_crc32_ctx *ctx = shash_desc_ctx(desc);

	ctx->crc = 0xFFFFFFFFU;
	return 0;
}

/*
 * deepspan_crc32_update — feed data bytes to the CRC32 engine.
 *
 * In a production implementation this would DMA the data to the FPGA
 * CRC32 hardware block via the deepspan virtio channel.  For the skeleton
 * we delegate to the kernel's crc32() helper (same polynomial, same result)
 * to keep the layer boundary correct while the virtio DMA path is being wired.
 *
 * TODO: replace with DMA submission via deepspan_uring_cmd_issue() once the
 *       HW path is validated end-to-end in simulation.
 */
static int deepspan_crc32_update(struct shash_desc *desc,
				  const u8 *data, unsigned int len)
{
	struct deepspan_crc32_ctx *ctx = shash_desc_ctx(desc);

	/*
	 * crc32() from <linux/crc32.h> uses the same IEEE 802.3 polynomial
	 * (0xEDB88320) and produces the same result as the Deepspan CRC32 HW.
	 * The initial value is passed in and the running CRC is accumulated.
	 */
	ctx->crc = crc32(ctx->crc, data, len);
	return 0;
}

static int deepspan_crc32_final(struct shash_desc *desc, u8 *out)
{
	struct deepspan_crc32_ctx *ctx = shash_desc_ctx(desc);
	u32 checksum = ctx->crc ^ 0xFFFFFFFFU;  /* final XOR */

	put_unaligned_le32(checksum, out);
	return 0;
}

static int deepspan_crc32_finup(struct shash_desc *desc,
				 const u8 *data, unsigned int len, u8 *out)
{
	deepspan_crc32_update(desc, data, len);
	return deepspan_crc32_final(desc, out);
}

static int deepspan_crc32_digest(struct shash_desc *desc,
				  const u8 *data, unsigned int len, u8 *out)
{
	deepspan_crc32_init(desc);
	return deepspan_crc32_finup(desc, data, len, out);
}

/* ── Algorithm descriptor ────────────────────────────────────────────────── */

static struct shash_alg deepspan_crc32_alg = {
	.digestsize  = DEEPSPAN_CRC32_DIGESTSIZE,
	.init        = deepspan_crc32_init,
	.update      = deepspan_crc32_update,
	.final       = deepspan_crc32_final,
	.finup       = deepspan_crc32_finup,
	.digest      = deepspan_crc32_digest,
	.descsize    = sizeof(struct deepspan_crc32_ctx),
	.base = {
		.cra_name         = "crc32",
		.cra_driver_name  = "crc32-deepspan",
		.cra_priority     = DEEPSPAN_CRC32_PRIORITY,
		.cra_flags        = CRYPTO_ALG_OPTIONAL_KEY,
		.cra_blocksize    = DEEPSPAN_CRC32_BLOCKSIZE,
		.cra_module       = THIS_MODULE,
	},
};

/* ── Module lifecycle ────────────────────────────────────────────────────── */

static int __init deepspan_crc32_mod_init(void)
{
	int ret = crypto_register_shash(&deepspan_crc32_alg);

	if (ret)
		pr_err("deepspan-crc32: failed to register shash: %d\n", ret);
	else
		pr_info("deepspan-crc32: registered 'crc32-deepspan' "
			"(priority %d) via Linux Crypto API\n",
			DEEPSPAN_CRC32_PRIORITY);
	return ret;
}

static void __exit deepspan_crc32_mod_exit(void)
{
	crypto_unregister_shash(&deepspan_crc32_alg);
	pr_info("deepspan-crc32: unregistered 'crc32-deepspan'\n");
}

module_init(deepspan_crc32_mod_init);
module_exit(deepspan_crc32_mod_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Deepspan Project");
MODULE_DESCRIPTION("Deepspan CRC32 hardware engine — Linux Crypto API shash bridge");
MODULE_ALIAS_CRYPTO("crc32");
MODULE_ALIAS_CRYPTO("crc32-deepspan");
