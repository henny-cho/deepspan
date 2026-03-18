/**
 * @file main.cpp
 * @brief Deepspan firmware entry point
 *
 * Components are connected at compile time via the CIB nexus.
 * Services start zero-cost with no runtime registration.
 */

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/version.h>

#if CONFIG_DEEPSPAN_TRANSPORT_VIRTIO
#include "deepspan/transport/virtio_transport.hpp"
#endif

#if CONFIG_DEEPSPAN_HWIP_DRIVER_SIM
#include "deepspan_hwip.h"
#endif

LOG_MODULE_REGISTER(deepspan_main, CONFIG_DEEPSPAN_LOG_LEVEL);

int main(void)
{
    LOG_INF("Deepspan firmware starting (Zephyr %s)", KERNEL_VERSION_STRING);

#if CONFIG_DEEPSPAN_TRANSPORT_VIRTIO
    /* TODO: CIB nexus initialization (automatic component wiring)
     * cib::nexus<AppConfig>::init(); */

    static deepspan::transport::DefaultTransport g_transport;
    /* TODO: g_transport.init(SHM_BASE, SHM_SIZE); */

    LOG_INF("Deepspan firmware ready (VirtIO transport)");

    while (true) {
        g_transport.poll();
        k_sleep(K_MSEC(1));
    }

#elif CONFIG_DEEPSPAN_HWIP_DRIVER_SIM
    LOG_INF("Deepspan firmware ready (HWIP sim driver)");

    const struct device *hwip = deepspan_hwip_sim_device();

    if (!device_is_ready(hwip)) {
        LOG_ERR("HWIP sim device not ready — is hw-model running?");
        return -1;
    }

    LOG_INF("HWIP hw_version=0x%08x", deepspan_hwip_version(hwip));

    uint32_t seq = 0;

    /* Periodic ECHO loop: send ECHO (opcode=0x01) every 2 seconds */
    while (true) {
        uint32_t result_status = 0;
        uint32_t result_data0  = 0;
        uint32_t result_data1  = 0;

        int ret = deepspan_hwip_submit_cmd(
            hwip,
            /*opcode=*/0x01,      /* HWIP_OP_ECHO */
            /*arg0=*/seq,
            /*arg1=*/~seq,
            /*timeout_ms=*/3000,
            &result_status, &result_data0, &result_data1
        );

        if (ret == 0) {
            LOG_INF("ECHO #%u ok  status=0x%08x  data0=0x%08x  data1=0x%08x",
                    seq, result_status, result_data0, result_data1);
        } else {
            LOG_WRN("ECHO #%u failed: %d", seq, ret);
        }

        seq++;
        k_sleep(K_MSEC(2000));
    }

#else
    LOG_INF("Deepspan firmware ready (simulation mode — no transport)");

    while (true) {
        k_sleep(K_MSEC(100));
    }
#endif

    return 0;
}
