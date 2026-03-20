/*
 * deepspan_hwip.c - HWIP Zephyr driver (C only, no C++ allowed)
 *
 * Follows the Zephyr driver model:
 *   - device_api struct
 *   - Device instantiation via DTS binding
 *   - ISR handler (MMIO IRQ or eventfd)
 *
 * This file is intentionally written in C only.
 * Zephyr driver layer convention: the drivers/ directory is C only.
 */

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/logging/log.h>
#include <zephyr/irq.h>

LOG_MODULE_REGISTER(deepspan_hwip, CONFIG_DEEPSPAN_LOG_LEVEL);

/* DTS node label: &deepspan_hwip0 */
#define DT_DRV_COMPAT deepspan_hwip

struct deepspan_hwip_config {
    uintptr_t reg_base;  /* MMIO register base address */
    uint32_t  reg_size;
    int       irq_num;
};

struct deepspan_hwip_data {
    struct k_sem cmd_done;
    uint32_t     last_status;
    uint32_t     last_result0;
    uint32_t     last_result1;
};

/* CTRL register offsets (same as reg_map.hpp) */
#define HWIP_REG_CTRL          0x000
#define HWIP_REG_STATUS        0x004
#define HWIP_REG_IRQ_STATUS    0x008
#define HWIP_REG_IRQ_ENABLE    0x00C
#define HWIP_REG_VERSION       0x010
#define HWIP_REG_CMD_OPCODE    0x100
#define HWIP_REG_CMD_ARG0      0x104
#define HWIP_REG_CMD_ARG1      0x108
#define HWIP_REG_RESULT_STATUS 0x110
#define HWIP_REG_RESULT_DATA0  0x114
#define HWIP_REG_RESULT_DATA1  0x118

#define CTRL_START  BIT(1)
#define IRQ_DONE    BIT(0)

static inline uint32_t hwip_read(const struct deepspan_hwip_config *cfg,
                                  uint32_t offset)
{
    return *((volatile uint32_t *)(cfg->reg_base + offset));
}

static inline void hwip_write(const struct deepspan_hwip_config *cfg,
                               uint32_t offset, uint32_t val)
{
    *((volatile uint32_t *)(cfg->reg_base + offset)) = val;
}

static void deepspan_hwip_isr(const struct device *dev)
{
    const struct deepspan_hwip_config *cfg = dev->config;
    struct deepspan_hwip_data *data = dev->data;

    uint32_t irq_st = hwip_read(cfg, HWIP_REG_IRQ_STATUS);
    if (irq_st & IRQ_DONE) {
        data->last_status  = hwip_read(cfg, HWIP_REG_RESULT_STATUS);
        data->last_result0 = hwip_read(cfg, HWIP_REG_RESULT_DATA0);
        data->last_result1 = hwip_read(cfg, HWIP_REG_RESULT_DATA1);
        /* W1C: write-1-to-clear */
        hwip_write(cfg, HWIP_REG_IRQ_STATUS, IRQ_DONE);
        k_sem_give(&data->cmd_done);
    }
}

static int deepspan_hwip_init(const struct device *dev)
{
    const struct deepspan_hwip_config *cfg = dev->config;
    struct deepspan_hwip_data *data = dev->data;

    k_sem_init(&data->cmd_done, 0, 1);

    /* Enable IRQ */
    hwip_write(cfg, HWIP_REG_IRQ_ENABLE, IRQ_DONE);

    LOG_INF("deepspan HWIP initialized, version=0x%08x",
            hwip_read(cfg, HWIP_REG_VERSION));
    return 0;
}

/* DTS-based device instantiation */
#define DEEPSPAN_HWIP_INIT(n)                                          \
    static struct deepspan_hwip_data deepspan_hwip_data_##n;           \
    static const struct deepspan_hwip_config deepspan_hwip_cfg_##n = { \
        .reg_base = DT_INST_REG_ADDR(n),                               \
        .reg_size = DT_INST_REG_SIZE(n),                               \
        .irq_num  = DT_INST_IRQN(n),                                   \
    };                                                                  \
    DEVICE_DT_INST_DEFINE(n,                                           \
        deepspan_hwip_init, NULL,                                       \
        &deepspan_hwip_data_##n,                                        \
        &deepspan_hwip_cfg_##n,                                         \
        POST_KERNEL, 50, NULL);

DT_INST_FOREACH_STATUS_OKAY(DEEPSPAN_HWIP_INIT)
