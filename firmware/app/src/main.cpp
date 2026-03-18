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
#else
    LOG_INF("Deepspan firmware ready (simulation mode)");

    while (true) {
        k_sleep(K_MSEC(100));
    }
#endif

    return 0;
}
