/*
 * deepspan_accel_hwip.c - Acceleration HWIP Zephyr driver
 *
 * Accel-specific variant of the deepspan HWIP driver.
 * Follows Zephyr driver model (C only, no C++ allowed in drivers/).
 *
 * Register layout is defined in hwip/accel/hw-model/include/deepspan_accel/reg_map.hpp
 * and mirrors the generic deepspan RegMap with accel-specific command semantics.
 */

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/logging/log.h>
#include <zephyr/irq.h>

LOG_MODULE_REGISTER(deepspan_accel_hwip, CONFIG_DEEPSPAN_LOG_LEVEL);

#define DT_DRV_COMPAT deepspan_accel_hwip

/* Accel opcode definitions */
#define DEEPSPAN_ACCEL_OP_ECHO    0x0001
#define DEEPSPAN_ACCEL_OP_PROCESS 0x0002
#define DEEPSPAN_ACCEL_OP_STATUS  0x0003

/* Register offsets (match reg_map.hpp and generic driver) */
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

struct deepspan_accel_config {
    uintptr_t reg_base;
    uint32_t  reg_size;
    int       irq_num;
};

struct deepspan_accel_data {
    struct k_sem cmd_done;
    uint32_t     last_status;
    uint32_t     last_result0;
    uint32_t     last_result1;
};

static inline uint32_t accel_read(const struct deepspan_accel_config *cfg,
                                   uint32_t offset)
{
    return *((volatile uint32_t *)(cfg->reg_base + offset));
}

static inline void accel_write(const struct deepspan_accel_config *cfg,
                                uint32_t offset, uint32_t val)
{
    *((volatile uint32_t *)(cfg->reg_base + offset)) = val;
}

static void deepspan_accel_isr(const struct device *dev)
{
    const struct deepspan_accel_config *cfg = dev->config;
    struct deepspan_accel_data *data = dev->data;

    uint32_t irq_st = accel_read(cfg, HWIP_REG_IRQ_STATUS);
    if (irq_st & IRQ_DONE) {
        data->last_status  = accel_read(cfg, HWIP_REG_RESULT_STATUS);
        data->last_result0 = accel_read(cfg, HWIP_REG_RESULT_DATA0);
        data->last_result1 = accel_read(cfg, HWIP_REG_RESULT_DATA1);
        accel_write(cfg, HWIP_REG_IRQ_STATUS, IRQ_DONE); /* W1C */
        k_sem_give(&data->cmd_done);
    }
}

static int deepspan_accel_init(const struct device *dev)
{
    const struct deepspan_accel_config *cfg = dev->config;
    struct deepspan_accel_data *data = dev->data;

    k_sem_init(&data->cmd_done, 0, 1);
    accel_write(cfg, HWIP_REG_IRQ_ENABLE, IRQ_DONE);

    LOG_INF("deepspan accel HWIP initialized, version=0x%08x",
            accel_read(cfg, HWIP_REG_VERSION));
    return 0;
}

#define DEEPSPAN_ACCEL_HWIP_INIT(n)                                              \
    static struct deepspan_accel_data deepspan_accel_data_##n;                   \
    static const struct deepspan_accel_config deepspan_accel_cfg_##n = {         \
        .reg_base = DT_INST_REG_ADDR(n),                                         \
        .reg_size = DT_INST_REG_SIZE(n),                                         \
        .irq_num  = DT_INST_IRQN(n),                                             \
    };                                                                            \
    DEVICE_DT_INST_DEFINE(n,                                                     \
        deepspan_accel_init, NULL,                                                \
        &deepspan_accel_data_##n,                                                 \
        &deepspan_accel_cfg_##n,                                                  \
        POST_KERNEL, 50, NULL);

DT_INST_FOREACH_STATUS_OKAY(DEEPSPAN_ACCEL_HWIP_INIT)
