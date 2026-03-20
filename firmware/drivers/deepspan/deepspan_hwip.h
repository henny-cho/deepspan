/*
 * SPDX-License-Identifier: Apache-2.0
 * deepspan_hwip.h — Public API for the Deepspan HWIP driver.
 *
 * Implemented by:
 *   deepspan_hwip.c     — production MMIO driver (DTS reg address)
 *   deepspan_hwip_sim.c — native_sim driver (POSIX shm mmap)
 */

#ifndef DEEPSPAN_HWIP_H
#define DEEPSPAN_HWIP_H

#include <zephyr/device.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Submit a command to the HWIP and wait for completion.
 *
 * Writes opcode/arg0/arg1 to the RegMap command registers, sets CTRL.START,
 * and blocks until the command completes (ISR or poll thread gives cmd_done sem).
 *
 * @param dev         HWIP device
 * @param opcode      Command opcode (HWIP_OP_*)
 * @param arg0        Command argument 0
 * @param arg1        Command argument 1
 * @param timeout_ms  Timeout in ms; 0 = use default (5000ms)
 * @param[out] result_status  Result status register value
 * @param[out] result_data0   Result data register 0
 * @param[out] result_data1   Result data register 1
 *
 * @retval 0        Command completed successfully
 * @retval -ETIMEDOUT  Timeout waiting for completion
 * @retval -EIO     Device not available
 */
int deepspan_hwip_submit_cmd(const struct device *dev,
			     uint32_t opcode,
			     uint32_t arg0,
			     uint32_t arg1,
			     uint32_t timeout_ms,
			     uint32_t *result_status,
			     uint32_t *result_data0,
			     uint32_t *result_data1);

/**
 * @brief Read the HW version register.
 * @return version word (0x00MMNNPP) or 0 on error
 */
uint32_t deepspan_hwip_version(const struct device *dev);

#ifdef CONFIG_DEEPSPAN_HWIP_DRIVER_SIM
/**
 * @brief Get the singleton native_sim HWIP device.
 * Only available when CONFIG_DEEPSPAN_HWIP_DRIVER_SIM=y.
 */
const struct device *deepspan_hwip_sim_device(void);
#endif

#ifdef __cplusplus
}
#endif

#endif /* DEEPSPAN_HWIP_H */
