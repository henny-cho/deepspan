/**
 * @file main.cpp
 * @brief Deepspan firmware entry point
 *
 * Components are connected at compile time via the CIB nexus.
 * Services start zero-cost with no runtime registration.
 */

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

// CIB & ETL
#include <cib/cib.hpp>

// Deepspan components
#include "deepspan/transport/virtio_transport.hpp"

LOG_MODULE_REGISTER(deepspan_main, CONFIG_DEEPSPAN_LOG_LEVEL);

namespace {

// Default VirtioTransport instance (compile-time parameters)
deepspan::transport::DefaultTransport g_transport;

} // anonymous namespace

int main(void)
{
    LOG_INF("Deepspan firmware starting (Zephyr %s)", KERNEL_VERSION_STRING);

    // TODO: CIB nexus initialization (automatic component wiring)
    // cib::nexus<AppConfig>::init();

    // TODO: Transport initialization (set platform-specific shm address)
    // g_transport.init(SHM_BASE, SHM_SIZE);

    LOG_INF("Deepspan firmware ready");

    // Zephyr event loop (handled by threads/workqueue)
    while (true) {
        g_transport.poll();
        k_sleep(K_MSEC(1));
    }

    return 0;
}
