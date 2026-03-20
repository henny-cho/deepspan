/*
 * SPDX-License-Identifier: Apache-2.0
 * deepspan_hwip_sim.c — Deepspan HWIP driver for Zephyr native_sim.
 *
 * Instead of a DTS register address, this driver opens the hw-model POSIX
 * shared memory (/dev/shm/<name>), mmaps the RegMap region, and drives the
 * same register protocol as the production driver.
 *
 * Completion notification: a background Zephyr thread polls the IRQ_STATUS
 * register every 1 ms (hw-model sets IRQ_DONE when a command finishes).
 *
 * Build: enabled by CONFIG_DEEPSPAN_HWIP_DRIVER_SIM=y (native_sim only).
 */

#include "deepspan_hwip.h"

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/logging/log.h>

/* POSIX APIs — available on native_sim via CONFIG_POSIX_API=y */
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdatomic.h>
#include <errno.h>

LOG_MODULE_REGISTER(deepspan_hwip_sim, CONFIG_DEEPSPAN_LOG_LEVEL);

/* ── RegMap offsets (must match reg_map.hpp) ──────────────────────────── */
#define REG_CTRL          0x000
#define REG_STATUS        0x004
#define REG_IRQ_STATUS    0x008
#define REG_IRQ_ENABLE    0x00C
#define REG_VERSION       0x010
#define REG_CMD_OPCODE    0x100
#define REG_CMD_ARG0      0x104
#define REG_CMD_ARG1      0x108
#define REG_CMD_FLAGS     0x10C
#define REG_RESULT_STATUS 0x110
#define REG_RESULT_DATA0  0x114
#define REG_RESULT_DATA1  0x118

#define CTRL_START   (UINT32_C(1) << 1)
#define IRQ_DONE     (UINT32_C(1) << 0)
#define STATUS_READY (UINT32_C(1) << 0)

#define SHM_MMAP_SIZE    4096
#define SHM_OPEN_RETRIES 50   /* 50 × 100 ms = 5 s */

/* ── Driver data ─────────────────────────────────────────────────────── */
struct hwip_sim_data {
	void          *shm_base;
	struct k_sem   cmd_done;
	uint32_t       last_status;
	uint32_t       last_result0;
	uint32_t       last_result1;
};

static struct hwip_sim_data g_data;

#define POLL_STACK_SIZE 1024
K_THREAD_STACK_DEFINE(g_poll_stack, POLL_STACK_SIZE);
static struct k_thread g_poll_thread;

/* ── Register helpers (atomic loads/stores) ──────────────────────────── */
static inline uint32_t reg_read(const void *base, uint32_t off)
{
	return atomic_load_explicit(
		(volatile atomic_uint *)((const char *)base + off),
		memory_order_acquire);
}

static inline void reg_write(void *base, uint32_t off, uint32_t val)
{
	atomic_store_explicit(
		(volatile atomic_uint *)((char *)base + off),
		val, memory_order_release);
}

static inline void reg_or(void *base, uint32_t off, uint32_t bits)
{
	atomic_fetch_or_explicit(
		(volatile atomic_uint *)((char *)base + off),
		bits, memory_order_acq_rel);
}

/* ── IRQ poll thread ─────────────────────────────────────────────────── */
static void poll_thread_fn(void *arg1, void *arg2, void *arg3)
{
	struct hwip_sim_data *data = arg1;
	ARG_UNUSED(arg2);
	ARG_UNUSED(arg3);

	LOG_DBG("poll thread started");

	while (1) {
		uint32_t irq_st = reg_read(data->shm_base, REG_IRQ_STATUS);
		if (irq_st & IRQ_DONE) {
			data->last_status  = reg_read(data->shm_base, REG_RESULT_STATUS);
			data->last_result0 = reg_read(data->shm_base, REG_RESULT_DATA0);
			data->last_result1 = reg_read(data->shm_base, REG_RESULT_DATA1);
			/* W1C: write-1-to-clear IRQ */
			reg_write(data->shm_base, REG_IRQ_STATUS, IRQ_DONE);
			k_sem_give(&data->cmd_done);
		}
		k_sleep(K_MSEC(1));
	}
}

/* ── Driver init ─────────────────────────────────────────────────────── */
static int hwip_sim_init(const struct device *dev)
{
	struct hwip_sim_data *data = dev->data;

	/* shm name: env var > Kconfig default */
	const char *shm_name = getenv("DEEPSPAN_SHM_NAME");
	if (!shm_name || shm_name[0] == '\0') {
		shm_name = CONFIG_DEEPSPAN_HWIP_SIM_SHM_NAME;
	}

	char shm_path[80];
	snprintf(shm_path, sizeof(shm_path), "/%s", shm_name);

	/* Retry loop: hw-model may start slightly later */
	int fd = -1;

	for (int i = 0; i < SHM_OPEN_RETRIES && fd < 0; i++) {
		fd = shm_open(shm_path, O_RDWR, 0);
		if (fd < 0) {
			if (i == 0) {
				LOG_INF("waiting for hw-model shm %s ...", shm_path);
			}
			k_sleep(K_MSEC(100));
		}
	}

	if (fd < 0) {
		LOG_ERR("shm_open(%s) failed: %d — is hw-model running?",
			shm_path, errno);
		return -EIO;
	}

	data->shm_base = mmap(NULL, SHM_MMAP_SIZE,
			      PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	close(fd);

	if (data->shm_base == MAP_FAILED) {
		LOG_ERR("mmap failed: %d", errno);
		data->shm_base = NULL;
		return -EIO;
	}

	uint32_t ver = reg_read(data->shm_base, REG_VERSION);
	LOG_INF("connected to hw-model  shm=%s  hw_version=0x%08x",
		shm_name, ver);

	/* Enable IRQ_DONE */
	reg_write(data->shm_base, REG_IRQ_ENABLE, IRQ_DONE);

	k_sem_init(&data->cmd_done, 0, 1);

	k_thread_create(&g_poll_thread, g_poll_stack,
			K_THREAD_STACK_SIZEOF(g_poll_stack),
			poll_thread_fn, data, NULL, NULL,
			K_PRIO_COOP(7), 0, K_NO_WAIT);
	k_thread_name_set(&g_poll_thread, "hwip_sim_poll");

	return 0;
}

/* ── Static device instance ──────────────────────────────────────────── */
DEVICE_DEFINE(deepspan_hwip0, "deepspan_hwip0",
	      hwip_sim_init, NULL,
	      &g_data, NULL,
	      POST_KERNEL, 50, NULL);

/* ── Public accessor ─────────────────────────────────────────────────── */
const struct device *deepspan_hwip_sim_device(void)
{
	return DEVICE_GET(deepspan_hwip0);
}

/* ── API implementation ──────────────────────────────────────────────── */
int deepspan_hwip_submit_cmd(const struct device *dev,
			     uint32_t opcode,
			     uint32_t arg0,
			     uint32_t arg1,
			     uint32_t timeout_ms,
			     uint32_t *result_status,
			     uint32_t *result_data0,
			     uint32_t *result_data1)
{
	struct hwip_sim_data *data = dev->data;

	if (!data->shm_base) {
		return -EIO;
	}

	if (timeout_ms == 0) {
		timeout_ms = 5000;
	}

	/* Write command registers */
	reg_write(data->shm_base, REG_CMD_OPCODE, opcode);
	reg_write(data->shm_base, REG_CMD_ARG0,   arg0);
	reg_write(data->shm_base, REG_CMD_ARG1,   arg1);
	reg_write(data->shm_base, REG_CMD_FLAGS,   0);

	/* Set CTRL.START */
	reg_or(data->shm_base, REG_CTRL, CTRL_START);

	/* Wait for IRQ (poll thread gives sem when IRQ_DONE is set) */
	int ret = k_sem_take(&data->cmd_done, K_MSEC(timeout_ms));
	if (ret == -EAGAIN) {
		LOG_WRN("SubmitCmd timeout (%u ms) opcode=0x%02x", timeout_ms, opcode);
		return -ETIMEDOUT;
	}

	if (result_status) {
		*result_status = data->last_status;
	}
	if (result_data0) {
		*result_data0 = data->last_result0;
	}
	if (result_data1) {
		*result_data1 = data->last_result1;
	}
	return 0;
}

uint32_t deepspan_hwip_version(const struct device *dev)
{
	const struct hwip_sim_data *data = dev->data;

	if (!data->shm_base) {
		return 0;
	}
	return reg_read(data->shm_base, REG_VERSION);
}
